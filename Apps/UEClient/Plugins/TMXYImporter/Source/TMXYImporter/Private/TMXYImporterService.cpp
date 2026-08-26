#include "TMXYImporterService.h"

#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "TMXYGltfImporter.h"
#include "TMXYTerrainImporter.h"
#include "TMXYTextureImporter.h"

#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include "Windows/HideWindowsPlatformTypes.h"

#include <bcrypt.h>
#endif

namespace
{
constexpr TCHAR GoldenRoot[] = TEXT("/Game/TMXY/Golden");
constexpr TCHAR GoldenMap[] = TEXT("/Game/TMXY/Golden/Maps/TMXYGoldenTestMap");
constexpr TCHAR GoldenMapRelativePath[] =
    TEXT("Apps/UEClient/Content/TMXY/Golden/Maps/TMXYGoldenTestMap.umap");

bool IsSafeRelativePath(const FString& path)
{
    if (path.IsEmpty() || !FPaths::IsRelative(path) || path.Contains(TEXT("\\")) ||
        path.Contains(TEXT(":")) || path.StartsWith(TEXT("/")) || path.EndsWith(TEXT("/")) ||
        path.Contains(TEXT("//")))
    {
        return false;
    }
    TArray<FString> segments;
    path.ParseIntoArray(segments, TEXT("/"), false);
    return !segments.Contains(TEXT("..")) && !segments.Contains(TEXT("."));
}

FTMXYImportItemResult MakeFailure(const FTMXYImportRequest& request, const TCHAR* errorCode)
{
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("failed");
    result.ErrorCode = errorCode;
    return result;
}

bool HashBytes(const TArray<uint8>& bytes, FString& digest)
{
#if PLATFORM_WINDOWS
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    TArray<uint8> object;
    TArray<uint8> result;
    ULONG objectSize = 0;
    ULONG bytesWritten = 0;
    bool succeeded =
        BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0;
    succeeded = succeeded && BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                                               reinterpret_cast<PUCHAR>(&objectSize),
                                               sizeof(objectSize), &bytesWritten, 0) >= 0;
    if (succeeded)
    {
        object.SetNumUninitialized(static_cast<int32>(objectSize));
        result.SetNumUninitialized(32);
        succeeded =
            BCryptCreateHash(algorithm, &hash, object.GetData(), objectSize, nullptr, 0, 0) >= 0 &&
            BCryptHashData(hash, const_cast<PUCHAR>(bytes.GetData()),
                           static_cast<ULONG>(bytes.Num()), 0) >= 0 &&
            BCryptFinishHash(hash, result.GetData(), static_cast<ULONG>(result.Num()), 0) >= 0;
    }
    if (hash != nullptr)
    {
        BCryptDestroyHash(hash);
    }
    if (algorithm != nullptr)
    {
        BCryptCloseAlgorithmProvider(algorithm, 0);
    }
    if (!succeeded)
    {
        return false;
    }
    digest.Reset(64);
    for (const uint8 value : result)
    {
        digest += FString::Printf(TEXT("%02x"), value);
    }
    return true;
#else
    static_cast<void>(bytes);
    static_cast<void>(digest);
    return false;
#endif
}

TSharedRef<FJsonObject> MakeGoldenPackage(const FString& contentSha256)
{
    TSharedRef<FJsonObject> package = MakeShared<FJsonObject>();
    package->SetStringField(TEXT("package_name"), GoldenMap);
    package->SetStringField(TEXT("class_name"), TEXT("World"));
    package->SetStringField(TEXT("content_sha256"), contentSha256);
    return package;
}

TSharedRef<FJsonObject> MakeSnapshot(const TCHAR* phase, const FString& mapSha256)
{
    TSharedRef<FJsonObject> snapshot = MakeShared<FJsonObject>();
    snapshot->SetStringField(TEXT("phase"), phase);
    snapshot->SetArrayField(TEXT("packages"),
                            {MakeShared<FJsonValueObject>(MakeGoldenPackage(mapSha256))});
    snapshot->SetNumberField(TEXT("map_count"), 1);
    snapshot->SetNumberField(TEXT("imported_asset_count"), 0);
    return snapshot;
}
} // namespace

FTMXYImporterService::FTMXYImporterService(FString rebuildRoot)
    : RebuildRoot(FPaths::ConvertRelativePathToFull(MoveTemp(rebuildRoot)))
{
    FPaths::NormalizeDirectoryName(RebuildRoot);
    RegisterImporter(MakeShared<FTMXYTextureImporter>(RebuildRoot));
    RegisterImporter(MakeShared<FTMXYGltfImporter>(RebuildRoot));
    RegisterImporter(MakeShared<FTMXYTerrainImporter>(RebuildRoot));
}

bool FTMXYImporterService::RegisterImporter(const TSharedRef<ITMXYAssetImporter>& importer)
{
    const FName formatId = importer->GetFormatId();
    if (formatId.IsNone() || Importers.Contains(formatId))
    {
        return false;
    }
    Importers.Add(formatId, importer);
    return true;
}

int32 FTMXYImporterService::GetRegisteredImporterCount() const
{
    return Importers.Num();
}

bool FTMXYImporterService::ResolveRepositoryPath(const FString& relativePath,
                                                 FString& resolvedPath) const
{
    if (!IsSafeRelativePath(relativePath))
    {
        return false;
    }
    resolvedPath = FPaths::ConvertRelativePathToFull(FPaths::Combine(RebuildRoot, relativePath));
    FPaths::NormalizeFilename(resolvedPath);
    FString rootPrefix = RebuildRoot;
    FPaths::NormalizeFilename(rootPrefix);
    rootPrefix += TEXT("/");
    return resolvedPath.StartsWith(rootPrefix, ESearchCase::IgnoreCase);
}

FTMXYImportItemResult
FTMXYImporterService::ValidateManifest(const FTMXYImportRequest& request) const
{
    if (request.Mode != ETMXYImportMode::ValidateOnly)
    {
        return MakeFailure(request, TEXT("unsupported-mode"));
    }
    FString manifestPath;
    if (!ResolveRepositoryPath(request.RelativeManifestPath, manifestPath))
    {
        return MakeFailure(request, TEXT("unsafe-manifest-path"));
    }

    TArray<uint8> manifestBytes;
    FString manifestText;
    if (!FFileHelper::LoadFileToArray(manifestBytes, *manifestPath) ||
        !FFileHelper::LoadFileToString(manifestText, *manifestPath))
    {
        return MakeFailure(request, TEXT("manifest-read-failed"));
    }
    FString manifestSha256;
    if (!HashBytes(manifestBytes, manifestSha256))
    {
        return MakeFailure(request, TEXT("manifest-hash-failed"));
    }

    TSharedPtr<FJsonObject> manifest;
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(manifestText);
    if (!FJsonSerializer::Deserialize(reader, manifest) || !manifest.IsValid())
    {
        return MakeFailure(request, TEXT("manifest-json-invalid"));
    }

    FString schema;
    FString version;
    double schemaVersion = 0.0;
    const TArray<TSharedPtr<FJsonValue>>* sources = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* artifacts = nullptr;
    if (!manifest->TryGetStringField(TEXT("schema"), schema) ||
        schema != TEXT("tmxy.asset.interchange") ||
        !manifest->TryGetNumberField(TEXT("schema_version"), schemaVersion) ||
        schemaVersion != 1.0 || !manifest->TryGetStringField(TEXT("format_version"), version) ||
        version != TEXT("1.0.0") || !manifest->TryGetArrayField(TEXT("source_inputs"), sources) ||
        !manifest->TryGetArrayField(TEXT("artifacts"), artifacts))
    {
        return MakeFailure(request, TEXT("manifest-contract-mismatch"));
    }

    TSet<FString> sourceIds;
    for (const TSharedPtr<FJsonValue>& value : *sources)
    {
        const TSharedPtr<FJsonObject> source = value.IsValid() ? value->AsObject() : nullptr;
        FString id;
        FString path;
        if (!source.IsValid() || !source->TryGetStringField(TEXT("id"), id) || id.IsEmpty() ||
            sourceIds.Contains(id) || !source->TryGetStringField(TEXT("relative_path"), path) ||
            !IsSafeRelativePath(path))
        {
            return MakeFailure(request, TEXT("source-entry-invalid"));
        }
        sourceIds.Add(id);
    }

    TSet<FString> artifactIds;
    for (const TSharedPtr<FJsonValue>& value : *artifacts)
    {
        const TSharedPtr<FJsonObject> artifact = value.IsValid() ? value->AsObject() : nullptr;
        FString id;
        FString path;
        FString formatId;
        if (!artifact.IsValid() || !artifact->TryGetStringField(TEXT("id"), id) || id.IsEmpty() ||
            artifactIds.Contains(id) || !artifact->TryGetStringField(TEXT("relative_path"), path) ||
            !IsSafeRelativePath(path) ||
            !artifact->TryGetStringField(TEXT("format_id"), formatId) || formatId.IsEmpty())
        {
            return MakeFailure(request, TEXT("artifact-entry-invalid"));
        }
        artifactIds.Add(id);
    }

    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("validated");
    result.ManifestSha256 = manifestSha256;
    result.SourceCount = sources->Num();
    result.ArtifactCount = artifacts->Num();
    result.bSucceeded = true;
    return result;
}

FTMXYImportBatchResult
FTMXYImporterService::ValidateBatch(const TArray<FTMXYImportRequest>& requests) const
{
    FTMXYImportBatchResult batch;
    batch.Items.Reserve(requests.Num());
    for (const FTMXYImportRequest& request : requests)
    {
        FTMXYImportItemResult result = ValidateManifest(request);
        result.bSucceeded ? ++batch.SucceededCount : ++batch.FailedCount;
        batch.Items.Add(MoveTemp(result));
    }
    return batch;
}

bool FTMXYImporterService::ResolveArtifactFormat(const FTMXYImportRequest& request,
                                                 const FString& artifactId, FName& formatId,
                                                 FString& error) const
{
    FString manifestPath;
    if (!ResolveRepositoryPath(request.RelativeManifestPath, manifestPath))
    {
        error = TEXT("unsafe-manifest-path");
        return false;
    }
    FString manifestText;
    TSharedPtr<FJsonObject> manifest;
    if (!FFileHelper::LoadFileToString(manifestText, *manifestPath))
    {
        error = TEXT("manifest-read-failed");
        return false;
    }
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(manifestText);
    const TArray<TSharedPtr<FJsonValue>>* artifacts = nullptr;
    if (!FJsonSerializer::Deserialize(reader, manifest) || !manifest.IsValid() ||
        !manifest->TryGetArrayField(TEXT("artifacts"), artifacts))
    {
        error = TEXT("manifest-json-invalid");
        return false;
    }
    for (const TSharedPtr<FJsonValue>& value : *artifacts)
    {
        const TSharedPtr<FJsonObject> artifact = value.IsValid() ? value->AsObject() : nullptr;
        FString candidateId;
        FString candidateFormat;
        if (artifact.IsValid() && artifact->TryGetStringField(TEXT("id"), candidateId) &&
            candidateId == artifactId &&
            artifact->TryGetStringField(TEXT("format_id"), candidateFormat) &&
            !candidateFormat.IsEmpty())
        {
            formatId = FName(candidateFormat);
            return true;
        }
    }
    error = TEXT("artifact-not-found");
    return false;
}

FTMXYImportItemResult FTMXYImporterService::ImportArtifact(const FTMXYImportRequest& request,
                                                           const FString& artifactId) const
{
    FName formatId;
    FString error;
    if (request.Mode == ETMXYImportMode::ValidateOnly || artifactId.IsEmpty() ||
        !ResolveArtifactFormat(request, artifactId, formatId, error))
    {
        return MakeFailure(request, request.Mode == ETMXYImportMode::ValidateOnly
                                        ? TEXT("unsupported-mode")
                                    : error.IsEmpty() ? TEXT("artifact-id-invalid")
                                                      : *error);
    }
    const TSharedRef<ITMXYAssetImporter>* importer = Importers.Find(formatId);
    if (importer == nullptr)
    {
        return MakeFailure(request, TEXT("format-importer-not-registered"));
    }
    return (*importer)->ImportArtifact(request, artifactId);
}

FTMXYReimportDecision
FTMXYImporterService::EvaluateReimport(const FTMXYReimportRequest& request) const
{
    if (!request.PackageName.StartsWith(FString(GoldenRoot) + TEXT("/")) ||
        !IsSafeRelativePath(request.RelativeManifestPath) || request.ArtifactId.IsEmpty())
    {
        return {false, TEXT("reimport-request-outside-golden-boundary")};
    }
    const TSharedRef<ITMXYAssetImporter>* importer = Importers.Find(request.FormatId);
    if (importer == nullptr)
    {
        return {false, TEXT("format-importer-not-registered")};
    }
    return (*importer)->EvaluateReimport(request);
}

FTMXYImportItemResult FTMXYImporterService::Reimport(const FTMXYReimportRequest& request) const
{
    const FTMXYReimportDecision decision = EvaluateReimport(request);
    if (!decision.bCanReimport)
    {
        FTMXYImportRequest failureRequest;
        failureRequest.RequestId = request.ArtifactId;
        failureRequest.RelativeManifestPath = request.RelativeManifestPath;
        FTMXYImportItemResult failure = MakeFailure(failureRequest, TEXT("reimport-rejected"));
        failure.ErrorCode = decision.Reason;
        return failure;
    }
    return Importers.FindChecked(request.FormatId)->Reimport(request);
}

bool FTMXYImporterService::WriteGoldenReport(const FTMXYImportBatchResult& batch,
                                             const FString& relativeManifestPath,
                                             const FString& outputPath, FString& error) const
{
    FString manifestPath;
    if (!ResolveRepositoryPath(relativeManifestPath, manifestPath))
    {
        error = TEXT("unsafe-manifest-path");
        return false;
    }
    FString mapPath;
    if (!ResolveRepositoryPath(GoldenMapRelativePath, mapPath))
    {
        error = TEXT("golden-map-path-invalid");
        return false;
    }
    TArray<uint8> mapBytes;
    FString mapSha256;
    if (!FFileHelper::LoadFileToArray(mapBytes, *mapPath) || !HashBytes(mapBytes, mapSha256))
    {
        error = TEXT("golden-map-hash-failed");
        return false;
    }

    TSharedRef<FJsonObject> report = MakeShared<FJsonObject>();
    report->SetStringField(TEXT("schema"), TEXT("tmxy.ue.golden-import-report"));
    report->SetNumberField(TEXT("schema_version"), 1);
    report->SetStringField(TEXT("report_version"), TEXT("1.0.0"));
    report->SetStringField(TEXT("run_id"), TEXT("p1-21-manifest-batch"));
    report->SetStringField(TEXT("golden_root"), GoldenRoot);
    report->SetStringField(TEXT("golden_map"), GoldenMap);
    report->SetStringField(TEXT("interchange_manifest"), relativeManifestPath);
    report->SetStringField(TEXT("import_mode"), TEXT("validate-only"));
    report->SetObjectField(TEXT("before_import"), MakeSnapshot(TEXT("before-import"), mapSha256));
    report->SetObjectField(TEXT("after_import"), MakeSnapshot(TEXT("after-import"), mapSha256));

    TSharedRef<FJsonObject> outcome = MakeShared<FJsonObject>();
    outcome->SetStringField(TEXT("status"),
                            batch.FailedCount == 0 ? TEXT("passed") : TEXT("failed"));
    outcome->SetNumberField(TEXT("imported_asset_count"), batch.ImportedAssetCount);
    outcome->SetArrayField(
        TEXT("warnings"),
        {MakeShared<FJsonValueString>(TEXT("P1-21 validates manifests without creating assets."))});
    TArray<TSharedPtr<FJsonValue>> errors;
    for (const FTMXYImportItemResult& item : batch.Items)
    {
        if (!item.bSucceeded)
        {
            errors.Add(MakeShared<FJsonValueString>(item.RequestId + TEXT(":") + item.ErrorCode));
        }
    }
    outcome->SetArrayField(TEXT("errors"), errors);
    report->SetObjectField(TEXT("outcome"), outcome);

    FString serialized;
    const TSharedRef<TJsonWriter<>> writer = TJsonWriterFactory<>::Create(&serialized);
    if (!FJsonSerializer::Serialize(report, writer))
    {
        error = TEXT("report-serialization-failed");
        return false;
    }
    serialized.ReplaceInline(TEXT("\r\n"), TEXT("\n"));
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(outputPath), true);
    if (!FFileHelper::SaveStringToFile(serialized + TEXT("\n"), *outputPath,
                                       FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))
    {
        error = TEXT("report-write-failed");
        return false;
    }
    return true;
}
