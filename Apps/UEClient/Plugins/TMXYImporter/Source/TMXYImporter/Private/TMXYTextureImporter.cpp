#include "TMXYTextureImporter.h"

#include "Dom/JsonObject.h"
#include "Engine/Texture2D.h"
#include "HAL/FileManager.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "TMXYDdsDecoder.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"

#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include "Windows/HideWindowsPlatformTypes.h"

#include <bcrypt.h>
#endif

namespace
{
constexpr TCHAR TextureRoot[] = TEXT("/Game/TMXY/Golden/Textures/");

struct FTextureImportSpec
{
    FString ManifestSha256;
    FString ArtifactPath;
    FString ArtifactRelativePath;
    FString ArtifactSha256;
    FString PackageName;
    FString LegacyFormat;
    FString AlphaCoverage;
    int32 Width = 0;
    int32 Height = 0;
    int32 MipCount = 0;
    bool bSrgb = false;
};

FTMXYImportItemResult MakeFailure(const FTMXYImportRequest& request, const FString& error)
{
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("failed");
    result.ErrorCode = error;
    return result;
}

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

bool ResolveBundleFile(const FString& manifestPath, const FString& relativePath,
                       FString& resolvedPath)
{
    if (!IsSafeRelativePath(relativePath))
    {
        return false;
    }
    FString bundleRoot = FPaths::ConvertRelativePathToFull(FPaths::GetPath(manifestPath));
    FPaths::NormalizeDirectoryName(bundleRoot);
    resolvedPath = FPaths::ConvertRelativePathToFull(FPaths::Combine(bundleRoot, relativePath));
    FPaths::NormalizeFilename(resolvedPath);
    return resolvedPath.StartsWith(bundleRoot + TEXT("/"), ESearchCase::IgnoreCase);
}

bool VerifyFileContract(const FString& manifestPath, const TSharedPtr<FJsonObject>& entry,
                        FString& resolvedPath, FString& error)
{
    FString relativePath;
    FString expectedHash;
    double expectedBytes = -1.0;
    if (!entry.IsValid() || !entry->TryGetStringField(TEXT("relative_path"), relativePath) ||
        !entry->TryGetStringField(TEXT("sha256"), expectedHash) || expectedHash.Len() != 64 ||
        !entry->TryGetNumberField(TEXT("bytes"), expectedBytes) || expectedBytes < 0.0 ||
        !ResolveBundleFile(manifestPath, relativePath, resolvedPath))
    {
        error = TEXT("file-contract-invalid");
        return false;
    }
    TArray<uint8> bytes;
    FString actualHash;
    if (!FFileHelper::LoadFileToArray(bytes, *resolvedPath))
    {
        error = TEXT("artifact-read-failed");
        return false;
    }
    if (bytes.Num() != static_cast<int64>(expectedBytes) || !HashBytes(bytes, actualHash) ||
        actualHash != expectedHash)
    {
        error = TEXT("artifact-integrity-mismatch");
        return false;
    }
    return true;
}

bool ReadImportSettings(const TSharedPtr<FJsonObject>& manifest, FTextureImportSpec& spec,
                        FString& error)
{
    const TSharedPtr<FJsonObject>* extensions = nullptr;
    const TSharedPtr<FJsonObject>* settings = nullptr;
    double width = 0.0;
    double height = 0.0;
    double mips = 0.0;
    if (!manifest->TryGetObjectField(TEXT("extensions"), extensions) ||
        !(*extensions)->TryGetObjectField(TEXT("org.tmxy.ue-import"), settings) ||
        !(*settings)->TryGetStringField(TEXT("package_name"), spec.PackageName) ||
        !spec.PackageName.StartsWith(TextureRoot) ||
        !FPackageName::IsValidLongPackageName(spec.PackageName) ||
        !(*settings)->TryGetBoolField(TEXT("srgb"), spec.bSrgb) ||
        !(*settings)->TryGetStringField(TEXT("expected_format"), spec.LegacyFormat) ||
        !(*settings)->TryGetStringField(TEXT("expected_alpha_coverage"), spec.AlphaCoverage) ||
        !(*settings)->TryGetNumberField(TEXT("expected_width"), width) ||
        !(*settings)->TryGetNumberField(TEXT("expected_height"), height) ||
        !(*settings)->TryGetNumberField(TEXT("expected_mips"), mips) || width < 1.0 ||
        height < 1.0 || mips < 1.0)
    {
        error = TEXT("texture-import-settings-invalid");
        return false;
    }
    spec.Width = static_cast<int32>(width);
    spec.Height = static_cast<int32>(height);
    spec.MipCount = static_cast<int32>(mips);
    return true;
}

bool ReadTextureSpec(const FString& rebuildRoot, const FTMXYImportRequest& request,
                     const FString& artifactId, FTextureImportSpec& spec, FString& error)
{
    if (request.Mode != ETMXYImportMode::SingleFixture ||
        !IsSafeRelativePath(request.RelativeManifestPath))
    {
        error = TEXT("unsupported-mode");
        return false;
    }
    FString manifestPath = FPaths::ConvertRelativePathToFull(
        FPaths::Combine(rebuildRoot, request.RelativeManifestPath));
    FPaths::NormalizeFilename(manifestPath);
    FString rootPrefix = rebuildRoot;
    FPaths::NormalizeFilename(rootPrefix);
    if (!manifestPath.StartsWith(rootPrefix + TEXT("/"), ESearchCase::IgnoreCase))
    {
        error = TEXT("unsafe-manifest-path");
        return false;
    }
    TArray<uint8> manifestBytes;
    FString manifestText;
    TSharedPtr<FJsonObject> manifest;
    if (!FFileHelper::LoadFileToArray(manifestBytes, *manifestPath) ||
        !FFileHelper::LoadFileToString(manifestText, *manifestPath) ||
        !HashBytes(manifestBytes, spec.ManifestSha256))
    {
        error = TEXT("manifest-read-failed");
        return false;
    }
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(manifestText);
    FString schema;
    FString version;
    FString assetKind;
    const TArray<TSharedPtr<FJsonValue>>* artifacts = nullptr;
    if (!FJsonSerializer::Deserialize(reader, manifest) || !manifest.IsValid() ||
        !manifest->TryGetStringField(TEXT("schema"), schema) ||
        schema != TEXT("tmxy.asset.interchange") ||
        !manifest->TryGetStringField(TEXT("format_version"), version) || version != TEXT("1.0.0") ||
        !manifest->TryGetStringField(TEXT("asset_kind"), assetKind) ||
        (assetKind != TEXT("texture") && assetKind != TEXT("ui_texture")) ||
        !manifest->TryGetArrayField(TEXT("artifacts"), artifacts) ||
        !ReadImportSettings(manifest, spec, error))
    {
        if (error.IsEmpty())
        {
            error = TEXT("texture-manifest-invalid");
        }
        return false;
    }
    for (const TSharedPtr<FJsonValue>& value : *artifacts)
    {
        const TSharedPtr<FJsonObject> artifact = value.IsValid() ? value->AsObject() : nullptr;
        FString id;
        FString format;
        FString authority;
        FString resolved;
        if (!artifact.IsValid() || !artifact->TryGetStringField(TEXT("id"), id) ||
            !artifact->TryGetStringField(TEXT("format_id"), format) ||
            !artifact->TryGetStringField(TEXT("authority"), authority) ||
            !VerifyFileContract(manifestPath, artifact, resolved, error))
        {
            return false;
        }
        if (id == artifactId)
        {
            if (format != TEXT("microsoft.dds") || authority != TEXT("authoritative-interchange"))
            {
                error = TEXT("texture-artifact-not-authoritative-dds");
                return false;
            }
            artifact->TryGetStringField(TEXT("relative_path"), spec.ArtifactRelativePath);
            artifact->TryGetStringField(TEXT("sha256"), spec.ArtifactSha256);
            spec.ArtifactPath = MoveTemp(resolved);
        }
    }
    if (spec.ArtifactPath.IsEmpty())
    {
        error = TEXT("artifact-not-found");
        return false;
    }
    return true;
}

bool SourceMatches(UTexture2D& texture, const FTMXYDecodedDds& decoded)
{
    if (texture.Source.GetSizeX() != decoded.Width || texture.Source.GetSizeY() != decoded.Height ||
        texture.Source.GetNumSlices() != 1 || texture.Source.GetNumMips() != decoded.MipCount ||
        texture.Source.GetFormat() != TSF_BGRA8)
    {
        return false;
    }

    int64 sourceOffset = 0;
    int32 mipWidth = decoded.Width;
    int32 mipHeight = decoded.Height;
    for (int32 mipIndex = 0; mipIndex < decoded.MipCount; ++mipIndex)
    {
        const int64 mipSize = static_cast<int64>(mipWidth) * mipHeight * 4;
        TArray64<uint8> existingMip;
        if (!texture.Source.GetMipData(existingMip, mipIndex) || existingMip.Num() != mipSize ||
            sourceOffset + mipSize > decoded.Bgra8MipData.Num() ||
            FMemory::Memcmp(existingMip.GetData(), decoded.Bgra8MipData.GetData() + sourceOffset,
                            mipSize) != 0)
        {
            return false;
        }
        sourceOffset += mipSize;
        mipWidth = FMath::Max(1, mipWidth / 2);
        mipHeight = FMath::Max(1, mipHeight / 2);
    }
    return sourceOffset == decoded.Bgra8MipData.Num();
}

UTexture2D* ImportDds(const FTextureImportSpec& spec, FString& error)
{
    TArray<uint8> ddsBytes;
    FTMXYDecodedDds decoded;
    if (!FFileHelper::LoadFileToArray(ddsBytes, *spec.ArtifactPath) ||
        !DecodeTMXYDds(ddsBytes, decoded, error))
    {
        return nullptr;
    }
    if (decoded.Width != spec.Width || decoded.Height != spec.Height ||
        decoded.MipCount != spec.MipCount || decoded.LegacyFormat != spec.LegacyFormat)
    {
        error = TEXT("dds-observed-dimensions-mismatch");
        return nullptr;
    }
    const FString assetName = FPackageName::GetLongPackageAssetName(spec.PackageName);
    const FString objectPath = spec.PackageName + TEXT(".") + assetName;
    UTexture2D* texture = LoadObject<UTexture2D>(nullptr, *objectPath);
    const bool existed = texture != nullptr;
    UPackage* package =
        texture != nullptr ? texture->GetPackage() : CreatePackage(*spec.PackageName);
    package->FullyLoad();
    if (texture == nullptr)
    {
        texture = NewObject<UTexture2D>(package, *assetName, RF_Public | RF_Standalone);
    }
    const bool compressionNoAlpha = spec.AlphaCoverage == TEXT("opaque");
    if (existed && texture->SRGB == spec.bSrgb &&
        texture->CompressionNoAlpha == compressionNoAlpha &&
        texture->MipGenSettings == TMGS_LeaveExistingMips && SourceMatches(*texture, decoded))
    {
        return texture;
    }

    texture->Modify();
    texture->Source.Init(decoded.Width, decoded.Height, 1, decoded.MipCount, TSF_BGRA8,
                         decoded.Bgra8MipData.GetData());
    texture->SRGB = spec.bSrgb;
    texture->CompressionNoAlpha = compressionNoAlpha;
    texture->MipGenSettings = TMGS_LeaveExistingMips;
    texture->PostEditChange();
    texture->MarkPackageDirty();
    const FString filename = FPackageName::LongPackageNameToFilename(
        spec.PackageName, FPackageName::GetAssetPackageExtension());
    FSavePackageArgs saveArgs;
    saveArgs.TopLevelFlags = RF_Public | RF_Standalone;
    saveArgs.SaveFlags = SAVE_None;
    if (!UPackage::SavePackage(texture->GetPackage(), texture, *filename, saveArgs))
    {
        error = TEXT("texture-package-save-failed");
        return nullptr;
    }
    return texture;
}
} // namespace

FTMXYTextureImporter::FTMXYTextureImporter(FString rebuildRoot)
    : RebuildRoot(FPaths::ConvertRelativePathToFull(MoveTemp(rebuildRoot)))
{
    FPaths::NormalizeDirectoryName(RebuildRoot);
}

FName FTMXYTextureImporter::GetFormatId() const
{
    return TEXT("microsoft.dds");
}

FTMXYImportItemResult FTMXYTextureImporter::ImportArtifact(const FTMXYImportRequest& request,
                                                           const FString& artifactId)
{
    FTextureImportSpec spec;
    FString error;
    if (!ReadTextureSpec(RebuildRoot, request, artifactId, spec, error))
    {
        return MakeFailure(request, error);
    }
    UTexture2D* texture = ImportDds(spec, error);
    if (texture == nullptr)
    {
        return MakeFailure(request, error);
    }
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("imported");
    result.ManifestSha256 = spec.ManifestSha256;
    result.OutputPackageName = spec.PackageName;
    result.ArtifactCount = 1;
    result.ImportedAssetCount = 1;
    result.bSucceeded = true;
    return result;
}

FTMXYReimportDecision
FTMXYTextureImporter::EvaluateReimport(const FTMXYReimportRequest& request) const
{
    if (request.FormatId != GetFormatId() || !request.PackageName.StartsWith(TextureRoot))
    {
        return {false, TEXT("texture-reimport-boundary-invalid")};
    }
    FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                     ETMXYImportMode::SingleFixture};
    FTextureImportSpec spec;
    FString error;
    if (!ReadTextureSpec(RebuildRoot, importRequest, request.ArtifactId, spec, error) ||
        spec.PackageName != request.PackageName)
    {
        return {false, error.IsEmpty() ? TEXT("texture-reimport-target-mismatch") : error};
    }
    return {true, TEXT("texture-reimport-supported")};
}

FTMXYImportItemResult FTMXYTextureImporter::Reimport(const FTMXYReimportRequest& request)
{
    const FTMXYReimportDecision decision = EvaluateReimport(request);
    if (!decision.bCanReimport)
    {
        FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                         ETMXYImportMode::SingleFixture};
        return MakeFailure(importRequest, decision.Reason);
    }
    FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                     ETMXYImportMode::SingleFixture};
    return ImportArtifact(importRequest, request.ArtifactId);
}
