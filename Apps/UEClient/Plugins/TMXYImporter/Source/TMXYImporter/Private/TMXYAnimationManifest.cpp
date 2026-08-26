#include "TMXYAnimationManifest.h"

#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include "Windows/HideWindowsPlatformTypes.h"

#include <bcrypt.h>
#endif

namespace
{
constexpr TCHAR AnimationRoot[] = TEXT("/Game/TMXY/Golden/Animations/");
constexpr TCHAR SkeletonRoot[] = TEXT("/Game/TMXY/Golden/Skeletons/");
constexpr TCHAR SkeletalMeshRoot[] = TEXT("/Game/TMXY/Golden/SkeletalMeshes/");

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

bool ResolveUnder(const FString& root, const FString& relativePath, FString& resolvedPath)
{
    if (!IsSafeRelativePath(relativePath))
    {
        return false;
    }
    FString normalizedRoot = FPaths::ConvertRelativePathToFull(root);
    FPaths::NormalizeDirectoryName(normalizedRoot);
    resolvedPath = FPaths::ConvertRelativePathToFull(FPaths::Combine(normalizedRoot, relativePath));
    FPaths::NormalizeFilename(resolvedPath);
    return resolvedPath.StartsWith(normalizedRoot + TEXT("/"), ESearchCase::IgnoreCase);
}

bool VerifyFile(const FString& root, const FString& relativePath, const FString& expectedHash,
                FString& resolvedPath)
{
    TArray<uint8> bytes;
    FString hash;
    return expectedHash.Len() == 64 && ResolveUnder(root, relativePath, resolvedPath) &&
           FFileHelper::LoadFileToArray(bytes, *resolvedPath) && HashBytes(bytes, hash) &&
           hash == expectedHash;
}

bool VerifyBundleEntry(const FString& manifestPath, const TSharedPtr<FJsonObject>& entry,
                       FString& resolvedPath, FString& relativePath, FString& error)
{
    FString expectedHash;
    double expectedBytes = -1.0;
    const FString bundleRoot = FPaths::GetPath(manifestPath);
    if (!entry.IsValid() || !entry->TryGetStringField(TEXT("relative_path"), relativePath) ||
        !entry->TryGetStringField(TEXT("sha256"), expectedHash) ||
        !entry->TryGetNumberField(TEXT("bytes"), expectedBytes) || expectedBytes < 0.0 ||
        expectedBytes != FMath::FloorToDouble(expectedBytes) ||
        !VerifyFile(bundleRoot, relativePath, expectedHash, resolvedPath))
    {
        error = TEXT("artifact-integrity-mismatch");
        return false;
    }
    const int64 actualBytes = IFileManager::Get().FileSize(*resolvedPath);
    if (actualBytes != static_cast<int64>(expectedBytes))
    {
        error = TEXT("artifact-integrity-mismatch");
        return false;
    }
    return true;
}

bool ReadInt(const TSharedPtr<FJsonObject>& object, const TCHAR* field, int32& value,
             const bool allowZero = false)
{
    double number = 0.0;
    const double minimum = allowZero ? 0.0 : 1.0;
    if (!object.IsValid() || !object->TryGetNumberField(field, number) || number < minimum ||
        number > MAX_int32 || number != FMath::FloorToDouble(number))
    {
        return false;
    }
    value = static_cast<int32>(number);
    return true;
}

bool ReadFinite(const TSharedPtr<FJsonObject>& object, const TCHAR* field, double& value,
                const bool positive)
{
    return object.IsValid() && object->TryGetNumberField(field, value) && FMath::IsFinite(value) &&
           (positive ? value > 0.0 : value >= 0.0);
}

bool ReadClip(const TSharedPtr<FJsonObject>& object, FTMXYAnimationClipSpec& clip)
{
    return object.IsValid() && object->TryGetStringField(TEXT("source_name"), clip.SourceName) &&
           !clip.SourceName.IsEmpty() &&
           object->TryGetStringField(TEXT("package_name"), clip.PackageName) &&
           clip.PackageName.StartsWith(AnimationRoot) &&
           FPackageName::IsValidLongPackageName(clip.PackageName) &&
           ReadInt(object, TEXT("source_index"), clip.SourceIndex, true) &&
           ReadInt(object, TEXT("expected_frame_count"), clip.ExpectedFrameCount) &&
           clip.ExpectedFrameCount >= 2 &&
           ReadInt(object, TEXT("expected_track_count"), clip.ExpectedTrackCount) &&
           ReadFinite(object, TEXT("expected_sampled_duration_seconds"),
                      clip.ExpectedSampledDurationSeconds, true) &&
           ReadFinite(object, TEXT("expected_legacy_loop_period_seconds"),
                      clip.ExpectedLegacyLoopPeriodSeconds, true) &&
           object->TryGetBoolField(TEXT("legacy_self_loop"), clip.bLegacySelfLoop) &&
           object->TryGetBoolField(TEXT("expected_root_classified_moving"),
                                   clip.bExpectedRootMoving) &&
           ReadFinite(object, TEXT("expected_root_translation_distance_meters"),
                      clip.ExpectedRootTranslationDistanceMeters, false) &&
           ReadFinite(object, TEXT("expected_maximum_endpoint_translation_delta_meters"),
                      clip.ExpectedMaximumEndpointTranslationMeters, false) &&
           ReadFinite(object, TEXT("expected_maximum_endpoint_rotation_delta_degrees"),
                      clip.ExpectedMaximumEndpointRotationDegrees, false);
}

bool ReadSettings(const FString& rebuildRoot, const TSharedPtr<FJsonObject>& manifest,
                  FTMXYAnimationImportSpec& spec, FString& error)
{
    const TSharedPtr<FJsonObject>* extensions = nullptr;
    const TSharedPtr<FJsonObject>* settings = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* clips = nullptr;
    FString coordinateMapping;
    FString quaternionPolicy;
    FString rootMotionPolicy;
    FString resolvedSkeletonManifest;
    if (!manifest->TryGetObjectField(TEXT("extensions"), extensions) ||
        !(*extensions)->TryGetObjectField(TEXT("org.tmxy.ue-import"), settings) ||
        !(*settings)->TryGetStringField(TEXT("skeleton_package_name"), spec.SkeletonPackageName) ||
        !spec.SkeletonPackageName.StartsWith(SkeletonRoot) ||
        !FPackageName::IsValidLongPackageName(spec.SkeletonPackageName) ||
        !(*settings)->TryGetStringField(TEXT("skeletal_mesh_package_name"),
                                        spec.SkeletalMeshPackageName) ||
        !spec.SkeletalMeshPackageName.StartsWith(SkeletalMeshRoot) ||
        !FPackageName::IsValidLongPackageName(spec.SkeletalMeshPackageName) ||
        !(*settings)->TryGetStringField(TEXT("skeleton_manifest_path"),
                                        spec.SkeletonManifestPath) ||
        !(*settings)->TryGetStringField(TEXT("skeleton_manifest_sha256"),
                                        spec.SkeletonManifestSha256) ||
        !VerifyFile(rebuildRoot, spec.SkeletonManifestPath, spec.SkeletonManifestSha256,
                    resolvedSkeletonManifest) ||
        !ReadInt(*settings, TEXT("expected_bone_count"), spec.ExpectedBoneCount) ||
        !ReadInt(*settings, TEXT("sample_rate_numerator"), spec.SampleRateNumerator) ||
        !ReadInt(*settings, TEXT("sample_rate_denominator"), spec.SampleRateDenominator) ||
        spec.SampleRateNumerator != 30 || spec.SampleRateDenominator != 1 ||
        !(*settings)->TryGetStringField(TEXT("coordinate_mapping"), coordinateMapping) ||
        coordinateMapping != TEXT("gltf(y,z,x)-to-ue(x,y,z)-centimeters") ||
        !(*settings)->TryGetStringField(TEXT("quaternion_policy"), quaternionPolicy) ||
        quaternionPolicy != TEXT("normalized-adjacent-hemisphere-continuity") ||
        !(*settings)->TryGetStringField(TEXT("root_motion_policy"), rootMotionPolicy) ||
        rootMotionPolicy != TEXT("preserved-root-track-not-extracted") ||
        !(*settings)->TryGetArrayField(TEXT("clips"), clips) || clips->Num() != 3)
    {
        error = TEXT("animation-import-settings-invalid");
        return false;
    }
    TSet<FString> names;
    TSet<FString> packages;
    for (const TSharedPtr<FJsonValue>& value : *clips)
    {
        FTMXYAnimationClipSpec clip;
        if (!value.IsValid() || !ReadClip(value->AsObject(), clip) ||
            clip.ExpectedTrackCount != spec.ExpectedBoneCount || names.Contains(clip.SourceName) ||
            packages.Contains(clip.PackageName))
        {
            error = TEXT("animation-clip-settings-invalid");
            return false;
        }
        names.Add(clip.SourceName);
        packages.Add(clip.PackageName);
        spec.Clips.Add(MoveTemp(clip));
    }
    return true;
}

bool AssignArtifact(const FString& id, const FString& format, const FString& authority,
                    FString resolvedPath, FString relativePath, FTMXYAnimationImportSpec& spec,
                    FString& error)
{
    if (authority != TEXT("authoritative-interchange"))
    {
        error = TEXT("animation-artifact-authority-invalid");
        return false;
    }
    if (id == TEXT("animation-gltf") && format == TEXT("khronos.gltf-json"))
    {
        spec.GltfPath = MoveTemp(resolvedPath);
    }
    else if (id == TEXT("buffer") && format == TEXT("khronos.gltf-bin"))
    {
        spec.BufferPath = MoveTemp(resolvedPath);
        spec.BufferRelativePath = MoveTemp(relativePath);
    }
    else if (id == TEXT("metadata") && format == TEXT("tmxy.asset.metadata-json"))
    {
        spec.MetadataPath = MoveTemp(resolvedPath);
    }
    else
    {
        error = TEXT("animation-artifact-contract-invalid");
        return false;
    }
    return true;
}
} // namespace

bool ReadTMXYAnimationSpec(const FString& rebuildRoot, const FTMXYImportRequest& request,
                           const FString& artifactId, FTMXYAnimationImportSpec& spec,
                           FString& error)
{
    if (request.Mode != ETMXYImportMode::SingleFixture || artifactId != TEXT("animation-gltf") ||
        !IsSafeRelativePath(request.RelativeManifestPath))
    {
        error = TEXT("unsupported-mode-or-artifact");
        return false;
    }
    FString manifestPath;
    if (!ResolveUnder(rebuildRoot, request.RelativeManifestPath, manifestPath))
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
    const TArray<TSharedPtr<FJsonValue>>* sources = nullptr;
    if (!FJsonSerializer::Deserialize(reader, manifest) || !manifest.IsValid() ||
        !manifest->TryGetStringField(TEXT("schema"), schema) ||
        schema != TEXT("tmxy.asset.interchange") ||
        !manifest->TryGetStringField(TEXT("format_version"), version) || version != TEXT("1.0.0") ||
        !manifest->TryGetStringField(TEXT("asset_kind"), assetKind) ||
        assetKind != TEXT("animation_set") ||
        !manifest->TryGetArrayField(TEXT("source_inputs"), sources) || sources->Num() != 1 ||
        !manifest->TryGetArrayField(TEXT("artifacts"), artifacts) || artifacts->Num() != 3 ||
        !ReadSettings(rebuildRoot, manifest, spec, error))
    {
        if (error.IsEmpty())
        {
            error = TEXT("animation-manifest-invalid");
        }
        return false;
    }
    for (const TSharedPtr<FJsonValue>& value : *sources)
    {
        FString resolved;
        FString relative;
        if (!value.IsValid() ||
            !VerifyBundleEntry(manifestPath, value->AsObject(), resolved, relative, error))
        {
            return false;
        }
    }
    TSet<FString> ids;
    for (const TSharedPtr<FJsonValue>& value : *artifacts)
    {
        const TSharedPtr<FJsonObject> entry = value.IsValid() ? value->AsObject() : nullptr;
        FString id;
        FString format;
        FString authority;
        FString resolved;
        FString relative;
        if (!entry.IsValid() || !entry->TryGetStringField(TEXT("id"), id) || ids.Contains(id) ||
            !entry->TryGetStringField(TEXT("format_id"), format) ||
            !entry->TryGetStringField(TEXT("authority"), authority) ||
            !VerifyBundleEntry(manifestPath, entry, resolved, relative, error) ||
            !AssignArtifact(id, format, authority, MoveTemp(resolved), MoveTemp(relative), spec,
                            error))
        {
            return false;
        }
        ids.Add(id);
    }
    if (spec.GltfPath.IsEmpty() || spec.BufferPath.IsEmpty() || spec.MetadataPath.IsEmpty())
    {
        error = TEXT("animation-required-artifact-missing");
        return false;
    }
    return true;
}
