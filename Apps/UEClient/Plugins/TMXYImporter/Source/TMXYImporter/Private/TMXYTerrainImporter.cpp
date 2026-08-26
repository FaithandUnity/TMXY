#include "TMXYTerrainImporter.h"

#include "Engine/StaticMesh.h"
#include "MeshDescription.h"
#include "MeshDescriptionBuilder.h"
#include "Misc/PackageName.h"
#include "StaticMeshAttributes.h"
#include "TMXYTerrainDecoder.h"
#include "TMXYTerrainManifest.h"
#include "UObject/MetaData.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"

namespace
{
constexpr TCHAR TerrainRoot[] = TEXT("/Game/TMXY/Golden/Terrain/");
constexpr TCHAR ManifestHashKey[] = TEXT("TMXY.ManifestSha256");
constexpr TCHAR ImporterVersionKey[] = TEXT("TMXY.TerrainImporterVersion");
constexpr TCHAR FixtureIdKey[] = TEXT("TMXY.Terrain.FixtureId");
constexpr TCHAR TileOriginKey[] = TEXT("TMXY.Terrain.TileOriginCm");
constexpr TCHAR ScaleKey[] = TEXT("TMXY.Terrain.CellSpacingCm");
constexpr TCHAR EdgePolicyKey[] = TEXT("TMXY.Terrain.EdgePolicy");
constexpr TCHAR ImporterVersion[] = TEXT("1.0.0");

FTMXYImportItemResult MakeFailure(const FTMXYImportRequest& request, const FString& error)
{
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("failed");
    result.ErrorCode = error;
    return result;
}

FString ObjectPath(const FString& packageName)
{
    return packageName + TEXT(".") + FPackageName::GetLongPackageAssetName(packageName);
}

FVector ExpectedPosition(const int32 vertexIndex, const FTMXYTerrainImportSpec& spec,
                         const FTMXYDecodedTerrainTile& decoded)
{
    const int32 x = vertexIndex % spec.EdgeVertexCount;
    const int32 y = vertexIndex / spec.EdgeVertexCount;
    return FVector(static_cast<double>(x) * spec.CellSpacingCentimeters,
                   static_cast<double>(y) * spec.CellSpacingCentimeters,
                   static_cast<double>(decoded.Heights[vertexIndex]) *
                       spec.CentimetersPerSourceUnit * spec.SourceUnitsPerCell);
}

FMeshDescription BuildMeshDescription(const FTMXYTerrainImportSpec& spec,
                                      const FTMXYDecodedTerrainTile& decoded)
{
    FMeshDescription description;
    FStaticMeshAttributes attributes(description);
    attributes.Register();
    FMeshDescriptionBuilder builder;
    builder.SetMeshDescription(&description);
    builder.SetNumUVLayers(1);
    builder.ReserveNewVertices(decoded.Heights.Num());
    TArray<FVertexID> vertices;
    vertices.Reserve(decoded.Heights.Num());
    for (int32 index = 0; index < decoded.Heights.Num(); ++index)
    {
        vertices.Add(builder.AppendVertex(ExpectedPosition(index, spec, decoded)));
    }
    const FPolygonGroupID group = builder.AppendPolygonGroup(TEXT("TerrainLayerWeights"));
    const auto appendTriangle = [&](const int32 first, const int32 second, const int32 third)
    {
        const int32 indices[3]{first, second, third};
        FVertexInstanceID instances[3];
        for (int32 corner = 0; corner < 3; ++corner)
        {
            const int32 index = indices[corner];
            instances[corner] = builder.AppendInstance(vertices[index]);
            builder.SetInstanceNormal(instances[corner], FVector::UpVector);
            const int32 x = index % spec.EdgeVertexCount;
            const int32 y = index / spec.EdgeVertexCount;
            builder.SetInstanceUV(instances[corner],
                                  FVector2D(static_cast<double>(x) / spec.CellsPerAxis,
                                            static_cast<double>(y) / spec.CellsPerAxis),
                                  0);
            const FColor weights = decoded.LayerWeights[index];
            builder.SetInstanceColor(instances[corner],
                                     FVector4f(static_cast<float>(weights.R) / 255.0F,
                                               static_cast<float>(weights.G) / 255.0F,
                                               static_cast<float>(weights.B) / 255.0F,
                                               static_cast<float>(weights.A) / 255.0F));
        }
        builder.AppendTriangle(instances[0], instances[1], instances[2], group);
    };
    for (int32 y = 0; y < spec.CellsPerAxis; ++y)
    {
        for (int32 x = 0; x < spec.CellsPerAxis; ++x)
        {
            const int32 topLeft = y * spec.EdgeVertexCount + x;
            const int32 topRight = topLeft + 1;
            const int32 bottomLeft = topLeft + spec.EdgeVertexCount;
            const int32 bottomRight = bottomLeft + 1;
            appendTriangle(topLeft, topRight, bottomRight);
            appendTriangle(topLeft, bottomRight, bottomLeft);
        }
    }
    return description;
}

bool NearlyEqual(const FVector& first, const FVector& second)
{
    return first.Equals(second, 0.05);
}

FString ExpectedOrigin(const FTMXYTerrainTileSpec& tile, const FTMXYTerrainImportSpec& spec)
{
    return FString::Printf(TEXT("%.0f,%.0f,0"), tile.TileX * spec.ZoneSizeCentimeters,
                           tile.TileY * spec.ZoneSizeCentimeters);
}

bool AssetMatches(const UStaticMesh& mesh, const FTMXYTerrainTileSpec& tile,
                  const FTMXYTerrainImportSpec& spec, const FTMXYDecodedTerrainTile& decoded)
{
    UPackage* package = mesh.GetPackage();
    FMetaData* metadata = package != nullptr ? &package->GetMetaData() : nullptr;
    const FMeshDescription* description = mesh.GetMeshDescription(0);
    if (metadata == nullptr || description == nullptr ||
        metadata->GetValue(&mesh, ManifestHashKey) != spec.ManifestSha256 ||
        metadata->GetValue(&mesh, ImporterVersionKey) != ImporterVersion ||
        metadata->GetValue(&mesh, FixtureIdKey) != tile.FixtureId ||
        metadata->GetValue(&mesh, TileOriginKey) != ExpectedOrigin(tile, spec) ||
        metadata->GetValue(&mesh, ScaleKey) != TEXT("400") ||
        metadata->GetValue(&mesh, EdgePolicyKey) != TEXT("preserve-source-differences") ||
        description->Vertices().Num() != tile.ExpectedVertexCount ||
        mesh.GetNumTriangles(0) != tile.ExpectedTriangleCount || mesh.GetNumSections(0) != 1 ||
        mesh.GetNumUVChannels(0) != 1 || mesh.GetStaticMaterials().Num() != 1)
    {
        return false;
    }
    const FBox bounds = mesh.GetBounds().GetBox();
    const FVector expectedMinimum(
        0.0, 0.0, decoded.MinimumHeight * spec.CentimetersPerSourceUnit * spec.SourceUnitsPerCell);
    const FVector expectedMaximum(spec.ZoneSizeCentimeters, spec.ZoneSizeCentimeters,
                                  decoded.MaximumHeight * spec.CentimetersPerSourceUnit *
                                      spec.SourceUnitsPerCell);
    return NearlyEqual(bounds.Min, expectedMinimum) && NearlyEqual(bounds.Max, expectedMaximum);
}

bool PreflightPackages(const FTMXYTerrainImportSpec& spec,
                       const TArray<FTMXYDecodedTerrainTile>& decodedTiles, FString& error)
{
    for (int32 index = 0; index < spec.Tiles.Num(); ++index)
    {
        UStaticMesh* existing =
            LoadObject<UStaticMesh>(nullptr, *ObjectPath(spec.Tiles[index].PackageName));
        if (existing != nullptr &&
            !AssetMatches(*existing, spec.Tiles[index], spec, decodedTiles[index]))
        {
            error = TEXT("terrain-existing-asset-mismatch");
            return false;
        }
    }
    return true;
}

UStaticMesh* SaveTerrainMesh(const FTMXYTerrainTileSpec& tile, const FTMXYTerrainImportSpec& spec,
                             const FTMXYDecodedTerrainTile& decoded, FString& error)
{
    UStaticMesh* mesh = LoadObject<UStaticMesh>(nullptr, *ObjectPath(tile.PackageName));
    if (mesh != nullptr)
    {
        return mesh;
    }
    const FString assetName = FPackageName::GetLongPackageAssetName(tile.PackageName);
    UPackage* package = CreatePackage(*tile.PackageName);
    package->FullyLoad();
    mesh = NewObject<UStaticMesh>(package, *assetName, RF_Public | RF_Standalone);
    mesh->SetNumSourceModels(1);
    FMeshBuildSettings& buildSettings = mesh->GetSourceModel(0).BuildSettings;
    buildSettings.bRecomputeNormals = true;
    buildSettings.bRecomputeTangents = true;
    buildSettings.bUseMikkTSpace = true;
    buildSettings.bGenerateLightmapUVs = false;
    buildSettings.bRemoveDegenerates = false;
    mesh->SetLightMapCoordinateIndex(0);
    const FName materialName(TEXT("TerrainLayerWeights"));
    mesh->GetStaticMaterials().Emplace(nullptr, materialName, materialName);
    FMeshDescription description = BuildMeshDescription(spec, decoded);
    TArray<const FMeshDescription*> descriptions{&description};
    UStaticMesh::FBuildMeshDescriptionsParams params;
    params.bUseHashAsGuid = true;
    params.bCommitMeshDescription = true;
    params.bFastBuild = false;
    params.bBuildSimpleCollision = false;
    params.bAllowCpuAccess = false;
    if (!mesh->BuildFromMeshDescriptions(descriptions, params))
    {
        error = TEXT("terrain-static-mesh-build-failed");
        return nullptr;
    }
    FMetaData& metadata = package->GetMetaData();
    metadata.SetValue(mesh, ManifestHashKey, *spec.ManifestSha256);
    metadata.SetValue(mesh, ImporterVersionKey, ImporterVersion);
    metadata.SetValue(mesh, FixtureIdKey, *tile.FixtureId);
    metadata.SetValue(mesh, TileOriginKey, *ExpectedOrigin(tile, spec));
    metadata.SetValue(mesh, ScaleKey, TEXT("400"));
    metadata.SetValue(mesh, EdgePolicyKey, TEXT("preserve-source-differences"));
    mesh->PostEditChange();
    mesh->MarkPackageDirty();
    const FString filename = FPackageName::LongPackageNameToFilename(
        tile.PackageName, FPackageName::GetAssetPackageExtension());
    FSavePackageArgs saveArgs;
    saveArgs.TopLevelFlags = RF_Public | RF_Standalone;
    saveArgs.SaveFlags = SAVE_None;
    if (!UPackage::SavePackage(package, mesh, *filename, saveArgs))
    {
        error = TEXT("terrain-package-save-failed");
        return nullptr;
    }
    return mesh;
}

bool ImportTerrainMeshes(const FTMXYTerrainImportSpec& spec, FString& error)
{
    TArray<FTMXYDecodedTerrainTile> decodedTiles;
    decodedTiles.SetNum(spec.Tiles.Num());
    for (int32 index = 0; index < spec.Tiles.Num(); ++index)
    {
        if (!DecodeTMXYTerrainTile(spec.Tiles[index], decodedTiles[index], error))
        {
            return false;
        }
    }
    if (!PreflightPackages(spec, decodedTiles, error))
    {
        return false;
    }
    for (int32 index = 0; index < spec.Tiles.Num(); ++index)
    {
        if (SaveTerrainMesh(spec.Tiles[index], spec, decodedTiles[index], error) == nullptr)
        {
            return false;
        }
    }
    return true;
}
} // namespace

FTMXYTerrainImporter::FTMXYTerrainImporter(FString rebuildRoot)
    : RebuildRoot(FPaths::ConvertRelativePathToFull(MoveTemp(rebuildRoot)))
{
    FPaths::NormalizeDirectoryName(RebuildRoot);
}

FName FTMXYTerrainImporter::GetFormatId() const
{
    return TEXT("tmxy.terrain.height-f32le");
}

FTMXYImportItemResult FTMXYTerrainImporter::ImportArtifact(const FTMXYImportRequest& request,
                                                           const FString& artifactId)
{
    FTMXYTerrainImportSpec spec;
    FString error;
    if (!ReadTMXYTerrainSpec(RebuildRoot, request, artifactId, spec, error) ||
        !ImportTerrainMeshes(spec, error))
    {
        return MakeFailure(request, error);
    }
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("imported");
    result.ManifestSha256 = spec.ManifestSha256;
    result.OutputPackageName = spec.Tiles[0].PackageName;
    result.SourceCount = 1;
    result.ArtifactCount = 12;
    result.ImportedAssetCount = spec.Tiles.Num();
    result.bSucceeded = true;
    return result;
}

FTMXYReimportDecision
FTMXYTerrainImporter::EvaluateReimport(const FTMXYReimportRequest& request) const
{
    if (request.FormatId != GetFormatId() || !request.PackageName.StartsWith(TerrainRoot))
    {
        return {false, TEXT("terrain-reimport-boundary-invalid")};
    }
    const FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                           ETMXYImportMode::SingleFixture};
    FTMXYTerrainImportSpec spec;
    FString error;
    if (!ReadTMXYTerrainSpec(RebuildRoot, importRequest, request.ArtifactId, spec, error))
    {
        return {false, error};
    }
    for (const FTMXYTerrainTileSpec& tile : spec.Tiles)
    {
        if (tile.PackageName == request.PackageName)
        {
            return {true, TEXT("terrain-reimport-supported")};
        }
    }
    return {false, TEXT("terrain-reimport-target-mismatch")};
}

FTMXYImportItemResult FTMXYTerrainImporter::Reimport(const FTMXYReimportRequest& request)
{
    const FTMXYReimportDecision decision = EvaluateReimport(request);
    const FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                           ETMXYImportMode::SingleFixture};
    return decision.bCanReimport ? ImportArtifact(importRequest, request.ArtifactId)
                                 : MakeFailure(importRequest, decision.Reason);
}
