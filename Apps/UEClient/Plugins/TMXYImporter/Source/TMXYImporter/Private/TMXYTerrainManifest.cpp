#include "TMXYTerrainManifest.h"

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
constexpr TCHAR TerrainRoot[] = TEXT("/Game/TMXY/Golden/Terrain/");

struct FVerifiedArtifact
{
    FString Path;
    FString FormatId;
    FString Authority;
};

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
    FString root = FPaths::ConvertRelativePathToFull(FPaths::GetPath(manifestPath));
    FPaths::NormalizeDirectoryName(root);
    resolvedPath = FPaths::ConvertRelativePathToFull(FPaths::Combine(root, relativePath));
    FPaths::NormalizeFilename(resolvedPath);
    return resolvedPath.StartsWith(root + TEXT("/"), ESearchCase::IgnoreCase);
}

bool VerifyFile(const FString& manifestPath, const TSharedPtr<FJsonObject>& entry,
                FString& resolvedPath, FString& error)
{
    FString relativePath;
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

bool ReadInteger(const TSharedPtr<FJsonObject>& object, const TCHAR* field, int32 minimum,
                 int32 maximum, int32& value)
{
    double number = 0.0;
    if (!object.IsValid() || !object->TryGetNumberField(field, number) || number < minimum ||
        number > maximum || number != FMath::FloorToDouble(number))
    {
        return false;
    }
    value = static_cast<int32>(number);
    return true;
}

bool ReadFiniteFloat(const TSharedPtr<FJsonObject>& object, const TCHAR* field, float& value)
{
    double number = 0.0;
    if (!object.IsValid() || !object->TryGetNumberField(field, number) ||
        !FMath::IsFinite(number) || number < -MAX_flt || number > MAX_flt)
    {
        return false;
    }
    value = static_cast<float>(number);
    return FMath::IsFinite(value);
}

bool ValidateArtifact(const FString& id, const FVerifiedArtifact& artifact)
{
    if (id.EndsWith(TEXT("-metadata")))
    {
        return artifact.FormatId == TEXT("tmxy.asset.metadata-json") &&
               artifact.Authority == TEXT("authoritative-interchange");
    }
    if (id.EndsWith(TEXT("-height")))
    {
        return artifact.FormatId == TEXT("tmxy.terrain.height-f32le") &&
               artifact.Authority == TEXT("authoritative-interchange");
    }
    if (id.EndsWith(TEXT("-layers")))
    {
        return artifact.FormatId == TEXT("tmxy.terrain.layers-rgba8") &&
               artifact.Authority == TEXT("authoritative-interchange");
    }
    return id.EndsWith(TEXT("-edges")) && artifact.FormatId == TEXT("text.csv-rfc4180") &&
           artifact.Authority == TEXT("review");
}

bool ReadTile(const TSharedPtr<FJsonObject>& value,
              const TMap<FString, FVerifiedArtifact>& artifacts, FTMXYTerrainTileSpec& tile,
              FString& error)
{
    FString metadataId;
    FString heightId;
    FString layerId;
    if (!value.IsValid() || !value->TryGetStringField(TEXT("fixture_id"), tile.FixtureId) ||
        !value->TryGetStringField(TEXT("package_name"), tile.PackageName) ||
        !tile.PackageName.StartsWith(TerrainRoot) ||
        !FPackageName::IsValidLongPackageName(tile.PackageName) ||
        !value->TryGetStringField(TEXT("metadata_artifact_id"), metadataId) ||
        !value->TryGetStringField(TEXT("height_artifact_id"), heightId) ||
        !value->TryGetStringField(TEXT("layer_artifact_id"), layerId) ||
        !ReadInteger(value, TEXT("tile_x"), 0, 999, tile.TileX) ||
        !ReadInteger(value, TEXT("tile_y"), 0, 999, tile.TileY) ||
        !ReadInteger(value, TEXT("expected_vertex_count"), 1, 1 << 20, tile.ExpectedVertexCount) ||
        !ReadInteger(value, TEXT("expected_triangle_count"), 1, 1 << 21,
                     tile.ExpectedTriangleCount) ||
        !ReadFiniteFloat(value, TEXT("expected_min_height_source_units"),
                         tile.ExpectedMinimumHeight) ||
        !ReadFiniteFloat(value, TEXT("expected_max_height_source_units"),
                         tile.ExpectedMaximumHeight) ||
        tile.ExpectedMinimumHeight > tile.ExpectedMaximumHeight ||
        !artifacts.Contains(metadataId) || !artifacts.Contains(heightId) ||
        !artifacts.Contains(layerId))
    {
        error = TEXT("terrain-tile-settings-invalid");
        return false;
    }
    tile.MetadataPath = artifacts.FindChecked(metadataId).Path;
    tile.HeightPath = artifacts.FindChecked(heightId).Path;
    tile.LayerPath = artifacts.FindChecked(layerId).Path;
    return true;
}

bool ReadAdjacency(const TSharedPtr<FJsonObject>& value, FTMXYTerrainAdjacencySpec& adjacency)
{
    double sourceDelta = -1.0;
    double centimeterDelta = -1.0;
    if (!value.IsValid() || !value->TryGetStringField(TEXT("first"), adjacency.First) ||
        !value->TryGetStringField(TEXT("first_edge"), adjacency.FirstEdge) ||
        !value->TryGetStringField(TEXT("second"), adjacency.Second) ||
        !value->TryGetStringField(TEXT("second_edge"), adjacency.SecondEdge) ||
        !ReadInteger(value, TEXT("sample_count"), 1, 4096, adjacency.SampleCount) ||
        !ReadInteger(value, TEXT("differing_sample_count"), 0, adjacency.SampleCount,
                     adjacency.DifferingSampleCount) ||
        !value->TryGetNumberField(TEXT("maximum_absolute_delta_source_units"), sourceDelta) ||
        !value->TryGetNumberField(TEXT("maximum_absolute_delta_cm"), centimeterDelta) ||
        !FMath::IsFinite(sourceDelta) || !FMath::IsFinite(centimeterDelta) || sourceDelta < 0.0 ||
        centimeterDelta < 0.0 ||
        !((adjacency.FirstEdge == TEXT("right") && adjacency.SecondEdge == TEXT("left")) ||
          (adjacency.FirstEdge == TEXT("bottom") && adjacency.SecondEdge == TEXT("top"))))
    {
        return false;
    }
    adjacency.MaximumDeltaSourceUnits = sourceDelta;
    adjacency.MaximumDeltaCentimeters = centimeterDelta;
    return true;
}
} // namespace

bool ReadTMXYTerrainSpec(const FString& rebuildRoot, const FTMXYImportRequest& request,
                         const FString& artifactId, FTMXYTerrainImportSpec& spec, FString& error)
{
    if (request.Mode != ETMXYImportMode::SingleFixture || artifactId != TEXT("base-height") ||
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
    const TArray<TSharedPtr<FJsonValue>>* sources = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* artifactValues = nullptr;
    if (!FJsonSerializer::Deserialize(reader, manifest) || !manifest.IsValid() ||
        !manifest->TryGetStringField(TEXT("schema"), schema) ||
        schema != TEXT("tmxy.asset.interchange") ||
        !manifest->TryGetStringField(TEXT("format_version"), version) || version != TEXT("1.0.0") ||
        !manifest->TryGetStringField(TEXT("asset_kind"), assetKind) ||
        assetKind != TEXT("terrain_tile") ||
        !manifest->TryGetArrayField(TEXT("source_inputs"), sources) || sources->Num() != 1 ||
        !manifest->TryGetArrayField(TEXT("artifacts"), artifactValues) ||
        artifactValues->Num() != 12)
    {
        error = TEXT("terrain-manifest-invalid");
        return false;
    }
    FString sourcePath;
    if (!VerifyFile(manifestPath, (*sources)[0]->AsObject(), sourcePath, error))
    {
        return false;
    }
    TMap<FString, FVerifiedArtifact> artifacts;
    for (const TSharedPtr<FJsonValue>& value : *artifactValues)
    {
        const TSharedPtr<FJsonObject> artifact = value.IsValid() ? value->AsObject() : nullptr;
        FString id;
        FVerifiedArtifact verified;
        if (!artifact.IsValid() || !artifact->TryGetStringField(TEXT("id"), id) || id.IsEmpty() ||
            artifacts.Contains(id) ||
            !artifact->TryGetStringField(TEXT("format_id"), verified.FormatId) ||
            !artifact->TryGetStringField(TEXT("authority"), verified.Authority) ||
            !VerifyFile(manifestPath, artifact, verified.Path, error) ||
            !ValidateArtifact(id, verified))
        {
            if (error.IsEmpty())
            {
                error = TEXT("terrain-artifact-contract-invalid");
            }
            return false;
        }
        artifacts.Add(id, MoveTemp(verified));
    }
    const TSharedPtr<FJsonObject>* extensions = nullptr;
    const TSharedPtr<FJsonObject>* settings = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* tileValues = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* adjacencyValues = nullptr;
    FString mapping;
    if (!manifest->TryGetObjectField(TEXT("extensions"), extensions) ||
        !(*extensions)->TryGetObjectField(TEXT("org.tmxy.ue-import"), settings) ||
        !(*settings)->TryGetStringField(TEXT("coordinate_mapping"), mapping) ||
        mapping != TEXT("legacy-x-forward-y-right-z-up-to-ue-x-forward-y-right-z-up") ||
        !ReadInteger(*settings, TEXT("edge_vertex_count"), 2, 1024, spec.EdgeVertexCount) ||
        !ReadInteger(*settings, TEXT("cells_per_axis"), 1, 1023, spec.CellsPerAxis) ||
        !ReadFiniteFloat(*settings, TEXT("source_units_per_cell"), spec.SourceUnitsPerCell) ||
        !ReadFiniteFloat(*settings, TEXT("centimeters_per_source_unit"),
                         spec.CentimetersPerSourceUnit) ||
        !ReadFiniteFloat(*settings, TEXT("cell_spacing_cm"), spec.CellSpacingCentimeters) ||
        !ReadFiniteFloat(*settings, TEXT("zone_size_cm"), spec.ZoneSizeCentimeters) ||
        !(*settings)->TryGetBoolField(TEXT("preserve_existing_edge_differences"),
                                      spec.bPreserveExistingEdgeDifferences) ||
        !spec.bPreserveExistingEdgeDifferences || spec.EdgeVertexCount != 64 ||
        spec.CellsPerAxis != 63 || spec.SourceUnitsPerCell != 4.0F ||
        spec.CentimetersPerSourceUnit != 100.0F || spec.CellSpacingCentimeters != 400.0F ||
        spec.ZoneSizeCentimeters != 25200.0F ||
        !(*settings)->TryGetArrayField(TEXT("tile_meshes"), tileValues) || tileValues->Num() != 3 ||
        !(*settings)->TryGetArrayField(TEXT("adjacency"), adjacencyValues) ||
        adjacencyValues->Num() != 2)
    {
        error = TEXT("terrain-import-settings-invalid");
        return false;
    }
    TSet<FString> fixtureIds;
    TSet<FString> packages;
    for (const TSharedPtr<FJsonValue>& value : *tileValues)
    {
        FTMXYTerrainTileSpec tile;
        if (!ReadTile(value.IsValid() ? value->AsObject() : nullptr, artifacts, tile, error) ||
            fixtureIds.Contains(tile.FixtureId) || packages.Contains(tile.PackageName) ||
            tile.ExpectedVertexCount != 4096 || tile.ExpectedTriangleCount != 7938)
        {
            if (error.IsEmpty())
            {
                error = TEXT("terrain-tile-contract-invalid");
            }
            return false;
        }
        fixtureIds.Add(tile.FixtureId);
        packages.Add(tile.PackageName);
        spec.Tiles.Add(MoveTemp(tile));
    }
    if (!fixtureIds.Contains(TEXT("base")) || !fixtureIds.Contains(TEXT("right")) ||
        !fixtureIds.Contains(TEXT("bottom")))
    {
        error = TEXT("terrain-fixture-set-invalid");
        return false;
    }
    for (const TSharedPtr<FJsonValue>& value : *adjacencyValues)
    {
        FTMXYTerrainAdjacencySpec adjacency;
        if (!ReadAdjacency(value.IsValid() ? value->AsObject() : nullptr, adjacency) ||
            !fixtureIds.Contains(adjacency.First) || !fixtureIds.Contains(adjacency.Second) ||
            adjacency.SampleCount != 64)
        {
            error = TEXT("terrain-adjacency-contract-invalid");
            return false;
        }
        spec.Adjacencies.Add(MoveTemp(adjacency));
    }
    return true;
}
