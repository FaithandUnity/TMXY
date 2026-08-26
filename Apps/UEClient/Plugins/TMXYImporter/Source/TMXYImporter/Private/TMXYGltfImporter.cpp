#include "TMXYGltfImporter.h"

#include "Dom/JsonObject.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "TMXYAnimationImporter.h"
#include "TMXYSkeletalMeshImporter.h"
#include "TMXYStaticMeshImporter.h"

namespace
{
constexpr TCHAR StaticMeshRoot[] = TEXT("/Game/TMXY/Golden/StaticMeshes/");
constexpr TCHAR SkeletalMeshRoot[] = TEXT("/Game/TMXY/Golden/SkeletalMeshes/");
constexpr TCHAR AnimationRoot[] = TEXT("/Game/TMXY/Golden/Animations/");

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

FTMXYImportItemResult MakeFailure(const FTMXYImportRequest& request, const FString& error)
{
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("failed");
    result.ErrorCode = error;
    return result;
}
} // namespace

FTMXYGltfImporter::FTMXYGltfImporter(FString rebuildRoot)
    : RebuildRoot(FPaths::ConvertRelativePathToFull(MoveTemp(rebuildRoot))),
      StaticMeshImporter(MakeShared<FTMXYStaticMeshImporter>(RebuildRoot)),
      SkeletalMeshImporter(MakeShared<FTMXYSkeletalMeshImporter>(RebuildRoot)),
      AnimationImporter(MakeShared<FTMXYAnimationImporter>(RebuildRoot))
{
    FPaths::NormalizeDirectoryName(RebuildRoot);
}

FName FTMXYGltfImporter::GetFormatId() const
{
    return TEXT("khronos.gltf-json");
}

ITMXYAssetImporter* FTMXYGltfImporter::ResolveManifestImporter(const FString& relativeManifestPath,
                                                               FString& error) const
{
    if (!IsSafeRelativePath(relativeManifestPath))
    {
        error = TEXT("unsafe-manifest-path");
        return nullptr;
    }
    FString path =
        FPaths::ConvertRelativePathToFull(FPaths::Combine(RebuildRoot, relativeManifestPath));
    FPaths::NormalizeFilename(path);
    if (!path.StartsWith(RebuildRoot + TEXT("/"), ESearchCase::IgnoreCase))
    {
        error = TEXT("unsafe-manifest-path");
        return nullptr;
    }
    FString text;
    TSharedPtr<FJsonObject> manifest;
    if (!FFileHelper::LoadFileToString(text, *path))
    {
        error = TEXT("manifest-read-failed");
        return nullptr;
    }
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(text);
    FString assetKind;
    if (!FJsonSerializer::Deserialize(reader, manifest) || !manifest.IsValid() ||
        !manifest->TryGetStringField(TEXT("asset_kind"), assetKind))
    {
        error = TEXT("manifest-json-invalid");
        return nullptr;
    }
    if (assetKind == TEXT("static_mesh"))
    {
        return &StaticMeshImporter.Get();
    }
    if (assetKind == TEXT("skeletal_mesh"))
    {
        return &SkeletalMeshImporter.Get();
    }
    if (assetKind == TEXT("animation_set"))
    {
        return &AnimationImporter.Get();
    }
    error = TEXT("gltf-asset-kind-unsupported");
    return nullptr;
}

ITMXYAssetImporter* FTMXYGltfImporter::ResolvePackageImporter(const FString& packageName) const
{
    if (packageName.StartsWith(StaticMeshRoot))
    {
        return &StaticMeshImporter.Get();
    }
    if (packageName.StartsWith(SkeletalMeshRoot))
    {
        return &SkeletalMeshImporter.Get();
    }
    if (packageName.StartsWith(AnimationRoot))
    {
        return &AnimationImporter.Get();
    }
    return nullptr;
}

FTMXYImportItemResult FTMXYGltfImporter::ImportArtifact(const FTMXYImportRequest& request,
                                                        const FString& artifactId)
{
    FString error;
    ITMXYAssetImporter* importer = ResolveManifestImporter(request.RelativeManifestPath, error);
    return importer == nullptr ? MakeFailure(request, error)
                               : importer->ImportArtifact(request, artifactId);
}

FTMXYReimportDecision FTMXYGltfImporter::EvaluateReimport(const FTMXYReimportRequest& request) const
{
    ITMXYAssetImporter* importer = ResolvePackageImporter(request.PackageName);
    return importer == nullptr ? FTMXYReimportDecision{false, TEXT("gltf-package-kind-unsupported")}
                               : importer->EvaluateReimport(request);
}

FTMXYImportItemResult FTMXYGltfImporter::Reimport(const FTMXYReimportRequest& request)
{
    ITMXYAssetImporter* importer = ResolvePackageImporter(request.PackageName);
    if (importer == nullptr)
    {
        FTMXYImportRequest failureRequest{request.ArtifactId, request.RelativeManifestPath,
                                          ETMXYImportMode::SingleFixture};
        return MakeFailure(failureRequest, TEXT("gltf-package-kind-unsupported"));
    }
    return importer->Reimport(request);
}
