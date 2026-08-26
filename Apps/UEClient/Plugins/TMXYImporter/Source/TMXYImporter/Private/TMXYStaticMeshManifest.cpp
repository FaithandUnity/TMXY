#include "TMXYStaticMeshManifest.h"

#include "Dom/JsonObject.h"
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
constexpr TCHAR StaticMeshRoot[] = TEXT("/Game/TMXY/Golden/StaticMeshes/");

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

bool VerifyFile(const FString& manifestPath, const TSharedPtr<FJsonObject>& entry,
                FString& resolvedPath, FString& relativePath, FString& error)
{
    FString expectedHash;
    double expectedBytes = -1.0;
    if (!entry.IsValid() || !entry->TryGetStringField(TEXT("relative_path"), relativePath) ||
        !entry->TryGetStringField(TEXT("sha256"), expectedHash) || expectedHash.Len() != 64 ||
        !entry->TryGetNumberField(TEXT("bytes"), expectedBytes) || expectedBytes < 0.0 ||
        expectedBytes != FMath::FloorToDouble(expectedBytes) ||
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

bool ReadPositiveInt(const TSharedPtr<FJsonObject>& object, const TCHAR* field, int32& value)
{
    double number = 0.0;
    if (!object.IsValid() || !object->TryGetNumberField(field, number) || number < 1.0 ||
        number > MAX_int32 || number != FMath::FloorToDouble(number))
    {
        return false;
    }
    value = static_cast<int32>(number);
    return true;
}

bool ReadVector(const TSharedPtr<FJsonObject>& object, const TCHAR* field, FVector3f& vector)
{
    const TArray<TSharedPtr<FJsonValue>>* values = nullptr;
    if (!object.IsValid() || !object->TryGetArrayField(field, values) || values->Num() != 3)
    {
        return false;
    }
    double components[3]{};
    for (int32 index = 0; index < 3; ++index)
    {
        if (!(*values)[index].IsValid() || !(*values)[index]->TryGetNumber(components[index]) ||
            !FMath::IsFinite(components[index]))
        {
            return false;
        }
    }
    vector = FVector3f(static_cast<float>(components[0]), static_cast<float>(components[1]),
                       static_cast<float>(components[2]));
    return FMath::IsFinite(vector.X) && FMath::IsFinite(vector.Y) && FMath::IsFinite(vector.Z);
}

bool ReadSettings(const TSharedPtr<FJsonObject>& manifest, FTMXYStaticMeshImportSpec& spec,
                  FString& error)
{
    const TSharedPtr<FJsonObject>* extensions = nullptr;
    const TSharedPtr<FJsonObject>* settings = nullptr;
    const TSharedPtr<FJsonObject>* renderBounds = nullptr;
    const TSharedPtr<FJsonObject>* legacyBounds = nullptr;
    FString mapping;
    if (!manifest->TryGetObjectField(TEXT("extensions"), extensions) ||
        !(*extensions)->TryGetObjectField(TEXT("org.tmxy.ue-import"), settings) ||
        !(*settings)->TryGetStringField(TEXT("package_name"), spec.PackageName) ||
        !spec.PackageName.StartsWith(StaticMeshRoot) ||
        !FPackageName::IsValidLongPackageName(spec.PackageName) ||
        !ReadPositiveInt(*settings, TEXT("expected_vertex_count"), spec.ExpectedVertexCount) ||
        !ReadPositiveInt(*settings, TEXT("expected_triangle_count"), spec.ExpectedTriangleCount) ||
        !ReadPositiveInt(*settings, TEXT("expected_material_slot_count"),
                         spec.ExpectedMaterialSlotCount) ||
        !ReadPositiveInt(*settings, TEXT("expected_uv_channel_count"),
                         spec.ExpectedUvChannelCount) ||
        spec.ExpectedUvChannelCount > 2 ||
        !(*settings)->TryGetBoolField(TEXT("expected_use_light_map"), spec.bExpectedUseLightMap) ||
        !(*settings)->TryGetBoolField(TEXT("preserve_winding"), spec.bPreserveWinding) ||
        !(*settings)->TryGetBoolField(TEXT("recompute_tangents"), spec.bRecomputeTangents) ||
        !spec.bPreserveWinding || !spec.bRecomputeTangents ||
        !(*settings)->TryGetStringField(TEXT("coordinate_mapping"), mapping) ||
        mapping != TEXT("gltf(y,z,x)-to-ue(x,y,z)-centimeters") ||
        !(*settings)->TryGetObjectField(TEXT("expected_render_bounds_cm"), renderBounds) ||
        !ReadVector(*renderBounds, TEXT("minimum"), spec.ExpectedBoundsMinimum) ||
        !ReadVector(*renderBounds, TEXT("maximum"), spec.ExpectedBoundsMaximum) ||
        !(*settings)->TryGetObjectField(TEXT("expected_effective_legacy_bounds_cm"),
                                        legacyBounds) ||
        !ReadVector(*legacyBounds, TEXT("minimum"), spec.ExpectedLegacyBoundsMinimum) ||
        !ReadVector(*legacyBounds, TEXT("maximum"), spec.ExpectedLegacyBoundsMaximum))
    {
        error = TEXT("static-mesh-import-settings-invalid");
        return false;
    }
    return true;
}
} // namespace

bool ReadTMXYStaticMeshSpec(const FString& rebuildRoot, const FTMXYImportRequest& request,
                            const FString& artifactId, FTMXYStaticMeshImportSpec& spec,
                            FString& error)
{
    if (request.Mode != ETMXYImportMode::SingleFixture || artifactId != TEXT("render-gltf") ||
        !IsSafeRelativePath(request.RelativeManifestPath))
    {
        error = TEXT("unsupported-mode-or-artifact");
        return false;
    }
    FString normalizedRoot = rebuildRoot;
    FPaths::NormalizeDirectoryName(normalizedRoot);
    FString manifestPath = FPaths::ConvertRelativePathToFull(
        FPaths::Combine(normalizedRoot, request.RelativeManifestPath));
    FPaths::NormalizeFilename(manifestPath);
    if (!manifestPath.StartsWith(normalizedRoot + TEXT("/"), ESearchCase::IgnoreCase))
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
        assetKind != TEXT("static_mesh") ||
        !manifest->TryGetArrayField(TEXT("artifacts"), artifacts) ||
        !ReadSettings(manifest, spec, error))
    {
        if (error.IsEmpty())
        {
            error = TEXT("static-mesh-manifest-invalid");
        }
        return false;
    }

    for (const TSharedPtr<FJsonValue>& value : *artifacts)
    {
        const TSharedPtr<FJsonObject> artifact = value.IsValid() ? value->AsObject() : nullptr;
        FString id;
        FString format;
        FString authority;
        FString resolvedPath;
        FString relativePath;
        if (!artifact.IsValid() || !artifact->TryGetStringField(TEXT("id"), id) ||
            !artifact->TryGetStringField(TEXT("format_id"), format) ||
            !artifact->TryGetStringField(TEXT("authority"), authority) ||
            !VerifyFile(manifestPath, artifact, resolvedPath, relativePath, error))
        {
            return false;
        }
        if (id == TEXT("render-gltf"))
        {
            if (format != TEXT("khronos.gltf-json") ||
                authority != TEXT("authoritative-interchange"))
            {
                error = TEXT("static-mesh-artifact-not-authoritative-gltf");
                return false;
            }
            spec.GltfPath = MoveTemp(resolvedPath);
            artifact->TryGetStringField(TEXT("sha256"), spec.GltfSha256);
        }
        else if (id == TEXT("buffer"))
        {
            if (format != TEXT("khronos.gltf-bin") ||
                authority != TEXT("authoritative-interchange"))
            {
                error = TEXT("static-mesh-buffer-invalid");
                return false;
            }
            spec.BufferPath = MoveTemp(resolvedPath);
            spec.BufferRelativePath = MoveTemp(relativePath);
        }
        else if (id == TEXT("metadata"))
        {
            if (format != TEXT("tmxy.asset.metadata-json") ||
                authority != TEXT("authoritative-interchange"))
            {
                error = TEXT("static-mesh-metadata-invalid");
                return false;
            }
            spec.MetadataPath = MoveTemp(resolvedPath);
        }
    }
    if (spec.GltfPath.IsEmpty() || spec.BufferPath.IsEmpty() || spec.MetadataPath.IsEmpty())
    {
        error = TEXT("static-mesh-required-artifact-missing");
        return false;
    }
    return true;
}
