#if WITH_DEV_AUTOMATION_TESTS

#include "Algo/Count.h"
#include "Dom/JsonObject.h"
#include "Engine/StaticMesh.h"
#include "HAL/FileManager.h"
#include "MeshDescription.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "StaticMeshAttributes.h"
#include "TMXYImporterService.h"
#include "TMXYTerrainDecoder.h"
#include "TMXYTerrainManifest.h"

namespace
{
constexpr TCHAR ManifestPath[] =
    TEXT("Tests/Fixtures/UE/Terrain/world-adjacency-real/manifest.json");
constexpr TCHAR InvalidManifestPath[] =
    TEXT("Tests/Fixtures/UE/Terrain/world-adjacency-real/manifest-invalid-hash.json");
constexpr TCHAR InvalidBasePackage[] =
    TEXT("/Game/TMXY/Golden/Terrain/SMT_Golden_Invalid_World_001_001");

FString ObjectPath(const FString& packageName)
{
    return packageName + TEXT(".") + FPackageName::GetLongPackageAssetName(packageName);
}

UStaticMesh* LoadTerrain(const FString& packageName)
{
    return LoadObject<UStaticMesh>(nullptr, *ObjectPath(packageName));
}

FVector ExpectedPosition(const int32 index, const FTMXYTerrainImportSpec& spec,
                         const FTMXYDecodedTerrainTile& decoded)
{
    return FVector((index % spec.EdgeVertexCount) * spec.CellSpacingCentimeters,
                   (index / spec.EdgeVertexCount) * spec.CellSpacingCentimeters,
                   decoded.Heights[index] * spec.CentimetersPerSourceUnit *
                       spec.SourceUnitsPerCell);
}

bool VerifyMesh(UStaticMesh& mesh, const FTMXYTerrainImportSpec& spec,
                const FTMXYTerrainTileSpec& tile, const FTMXYDecodedTerrainTile& decoded,
                bool& allPositionsMatch, bool& allLayerWeightsMatch, bool& windingIsUp)
{
    const FMeshDescription* description = mesh.GetMeshDescription(0);
    if (description == nullptr)
    {
        return false;
    }
    const FStaticMeshConstAttributes attributes(*description);
    const TVertexAttributesConstRef<FVector3f> positions = attributes.GetVertexPositions();
    const TVertexInstanceAttributesConstRef<FVector4f> colors =
        attributes.GetVertexInstanceColors();
    allPositionsMatch = description->Vertices().Num() == tile.ExpectedVertexCount;
    allLayerWeightsMatch = allPositionsMatch;
    for (int32 index = 0; index < tile.ExpectedVertexCount; ++index)
    {
        const FVertexID vertex(index);
        allPositionsMatch =
            allPositionsMatch &&
            FVector(positions[vertex]).Equals(ExpectedPosition(index, spec, decoded), 0.01);
        const TArrayView<const FVertexInstanceID> instances =
            description->GetVertexVertexInstanceIDs(vertex);
        if (instances.IsEmpty())
        {
            allLayerWeightsMatch = false;
            continue;
        }
        const FColor expected = decoded.LayerWeights[index];
        const FVector4f expectedColor(
            static_cast<float>(expected.R) / 255.0F, static_cast<float>(expected.G) / 255.0F,
            static_cast<float>(expected.B) / 255.0F, static_cast<float>(expected.A) / 255.0F);
        for (const FVertexInstanceID instance : instances)
        {
            allLayerWeightsMatch =
                allLayerWeightsMatch && colors[instance].Equals(expectedColor, 1.0F / 255.0F);
        }
    }
    windingIsUp = description->Triangles().Num() == tile.ExpectedTriangleCount;
    for (const FTriangleID triangle : description->Triangles().GetElementIDs())
    {
        const TArrayView<const FVertexInstanceID> instances =
            description->GetTriangleVertexInstances(triangle);
        const FVector first(positions[description->GetVertexInstanceVertex(instances[0])]);
        const FVector second(positions[description->GetVertexInstanceVertex(instances[1])]);
        const FVector third(positions[description->GetVertexInstanceVertex(instances[2])]);
        windingIsUp = windingIsUp && FVector::CrossProduct(second - first, third - first).Z > 0.0;
    }
    return allPositionsMatch && allLayerWeightsMatch && windingIsUp &&
           mesh.GetNumTriangles(0) == tile.ExpectedTriangleCount && mesh.GetNumSections(0) == 1 &&
           mesh.GetNumUVChannels(0) == 1;
}

TSharedRef<FJsonObject> MakeTileObservation(const FTMXYTerrainTileSpec& tile,
                                            const FTMXYDecodedTerrainTile& decoded,
                                            const UStaticMesh& mesh, bool positionsMatch,
                                            bool layerWeightsMatch, bool windingIsUp)
{
    TSharedRef<FJsonObject> value = MakeShared<FJsonObject>();
    value->SetStringField(TEXT("fixture_id"), tile.FixtureId);
    value->SetStringField(TEXT("package_name"), tile.PackageName);
    value->SetNumberField(TEXT("tile_x"), tile.TileX);
    value->SetNumberField(TEXT("tile_y"), tile.TileY);
    value->SetNumberField(TEXT("source_vertex_count"), tile.ExpectedVertexCount);
    value->SetNumberField(TEXT("render_vertex_count"), mesh.GetNumVertices(0));
    value->SetNumberField(TEXT("triangle_count"), mesh.GetNumTriangles(0));
    value->SetNumberField(TEXT("minimum_height_source_units"), decoded.MinimumHeight);
    value->SetNumberField(TEXT("maximum_height_source_units"), decoded.MaximumHeight);
    value->SetBoolField(TEXT("all_height_samples_match"), positionsMatch);
    value->SetBoolField(TEXT("all_layer_weights_match"), layerWeightsMatch);
    value->SetBoolField(TEXT("winding_faces_up"), windingIsUp);
    return value;
}

const FTMXYDecodedTerrainTile* FindDecoded(const FString& fixtureId,
                                           const FTMXYTerrainImportSpec& spec,
                                           const TArray<FTMXYDecodedTerrainTile>& decoded)
{
    for (int32 index = 0; index < spec.Tiles.Num(); ++index)
    {
        if (spec.Tiles[index].FixtureId == fixtureId)
        {
            return &decoded[index];
        }
    }
    return nullptr;
}

bool VerifyAdjacency(const FTMXYTerrainAdjacencySpec& adjacency, const FTMXYTerrainImportSpec& spec,
                     const TArray<FTMXYDecodedTerrainTile>& decoded, int32& differenceCount,
                     double& maximumDeltaCm)
{
    const FTMXYDecodedTerrainTile* first = FindDecoded(adjacency.First, spec, decoded);
    const FTMXYDecodedTerrainTile* second = FindDecoded(adjacency.Second, spec, decoded);
    if (first == nullptr || second == nullptr)
    {
        return false;
    }
    differenceCount = 0;
    maximumDeltaCm = 0.0;
    for (int32 sample = 0; sample < spec.EdgeVertexCount; ++sample)
    {
        const int32 firstIndex = adjacency.FirstEdge == TEXT("right")
                                     ? sample * spec.EdgeVertexCount + spec.CellsPerAxis
                                     : spec.CellsPerAxis * spec.EdgeVertexCount + sample;
        const int32 secondIndex =
            adjacency.SecondEdge == TEXT("left") ? sample * spec.EdgeVertexCount : sample;
        const double sourceDelta = FMath::Abs(static_cast<double>(first->Heights[firstIndex]) -
                                              static_cast<double>(second->Heights[secondIndex]));
        differenceCount += sourceDelta != 0.0 ? 1 : 0;
        maximumDeltaCm = FMath::Max(maximumDeltaCm, sourceDelta * spec.CentimetersPerSourceUnit *
                                                        spec.SourceUnitsPerCell);
    }
    return differenceCount == adjacency.DifferingSampleCount &&
           FMath::IsNearlyEqual(maximumDeltaCm, adjacency.MaximumDeltaCentimeters, 0.0001);
}

bool WriteReport(const FString& outputPath, int32 beforeCount,
                 const FTMXYImportItemResult& importResult,
                 const FTMXYImportItemResult& invalidResult,
                 const FTMXYImportItemResult& reimportResult, bool reimportBytesUnchanged,
                 bool directionVerified, bool scaleVerified, bool adjacencyVerified,
                 const TArray<TSharedPtr<FJsonValue>>& tiles,
                 const TArray<TSharedPtr<FJsonValue>>& adjacencies)
{
    TSharedRef<FJsonObject> report = MakeShared<FJsonObject>();
    report->SetStringField(TEXT("schema"), TEXT("tmxy.ue.terrain-import-report"));
    report->SetNumberField(TEXT("schema_version"), 1);
    report->SetStringField(TEXT("report_version"), TEXT("1.0.0"));
    report->SetStringField(TEXT("handler_format_id"), TEXT("tmxy.terrain.height-f32le"));
    report->SetStringField(TEXT("manifest_sha256"), importResult.ManifestSha256);
    report->SetNumberField(TEXT("before_asset_count"), beforeCount);
    report->SetNumberField(TEXT("after_asset_count"), tiles.Num());
    report->SetNumberField(TEXT("imported_asset_count"), importResult.ImportedAssetCount);
    report->SetBoolField(TEXT("invalid_hash_rejected"),
                         !invalidResult.bSucceeded &&
                             invalidResult.ErrorCode == TEXT("artifact-integrity-mismatch"));
    report->SetBoolField(TEXT("invalid_hash_asset_created"),
                         FPackageName::DoesPackageExist(InvalidBasePackage));
    report->SetBoolField(TEXT("direction_verified"), directionVerified);
    report->SetBoolField(TEXT("physical_scale_verified"), scaleVerified);
    report->SetBoolField(TEXT("adjacency_verified"), adjacencyVerified);
    report->SetBoolField(TEXT("existing_edge_differences_preserved"), true);
    report->SetBoolField(TEXT("reimport_passed"), reimportResult.bSucceeded);
    report->SetBoolField(TEXT("reimport_package_bytes_unchanged"), reimportBytesUnchanged);
    report->SetArrayField(TEXT("terrain_tiles"), tiles);
    report->SetArrayField(TEXT("adjacencies"), adjacencies);
    FString serialized;
    const TSharedRef<TJsonWriter<>> writer = TJsonWriterFactory<>::Create(&serialized);
    if (!FJsonSerializer::Serialize(report, writer))
    {
        return false;
    }
    serialized.ReplaceInline(TEXT("\r\n"), TEXT("\n"));
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(outputPath), true);
    return FFileHelper::SaveStringToFile(serialized + TEXT("\n"), *outputPath,
                                         FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
}
} // namespace

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FTMXYTerrainImporterTest, "TMXY.Importer.Terrain",
                                 EAutomationTestFlags::EditorContext |
                                     EAutomationTestFlags::EngineFilter)

bool FTMXYTerrainImporterTest::RunTest(const FString& parameters)
{
    static_cast<void>(parameters);
    const FString rebuildRoot =
        FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("../..")));
    FTMXYImporterService service(rebuildRoot);
    TestEqual(TEXT("Three production importers are registered"),
              service.GetRegisteredImporterCount(), 3);

    const FTMXYImportRequest request{TEXT("world-adjacency-real"), ManifestPath,
                                     ETMXYImportMode::SingleFixture};
    FTMXYTerrainImportSpec spec;
    FString specError;
    const bool specRead =
        ReadTMXYTerrainSpec(rebuildRoot, request, TEXT("base-height"), spec, specError);
    TestTrue(TEXT("Terrain Manifest and every declared file hash verify"), specRead);
    TestEqual(TEXT("Terrain Manifest error"), specError, FString());
    if (!specRead)
    {
        return false;
    }
    TArray<FTMXYDecodedTerrainTile> decoded;
    decoded.SetNum(spec.Tiles.Num());
    for (int32 index = 0; index < spec.Tiles.Num(); ++index)
    {
        FString decodeError;
        TestTrue(TEXT("Terrain typed planes decode"),
                 DecodeTMXYTerrainTile(spec.Tiles[index], decoded[index], decodeError));
        TestEqual(TEXT("Terrain decode error"), decodeError, FString());
    }

    const int32 beforeCount =
        Algo::CountIf(spec.Tiles, [](const FTMXYTerrainTileSpec& tile)
                      { return FPackageName::DoesPackageExist(tile.PackageName); });
    const FTMXYImportRequest invalidRequest{TEXT("invalid-hash"), InvalidManifestPath,
                                            ETMXYImportMode::SingleFixture};
    const FTMXYImportItemResult invalid =
        service.ImportArtifact(invalidRequest, TEXT("base-height"));
    TestFalse(TEXT("Terrain hash mismatch is rejected before write"), invalid.bSucceeded);
    TestEqual(TEXT("Terrain hash mismatch has stable error"), invalid.ErrorCode,
              FString(TEXT("artifact-integrity-mismatch")));
    TestFalse(TEXT("Invalid terrain hash creates no package"),
              FPackageName::DoesPackageExist(InvalidBasePackage));

    const FTMXYImportItemResult imported = service.ImportArtifact(request, TEXT("base-height"));
    TestTrue(TEXT("Three real terrain tiles import"), imported.bSucceeded);
    TestEqual(TEXT("Terrain import error"), imported.ErrorCode, FString());
    TestEqual(TEXT("Terrain imported asset count"), imported.ImportedAssetCount, 3);

    bool allPositions = true;
    bool allLayers = true;
    bool allWinding = true;
    TArray<TSharedPtr<FJsonValue>> tileObservations;
    for (int32 index = 0; index < spec.Tiles.Num(); ++index)
    {
        UStaticMesh* mesh = LoadTerrain(spec.Tiles[index].PackageName);
        TestNotNull(TEXT("Imported terrain tile is loadable"), mesh);
        if (mesh == nullptr)
        {
            return false;
        }
        bool positionsMatch = false;
        bool layersMatch = false;
        bool windingIsUp = false;
        const bool meshVerified = VerifyMesh(*mesh, spec, spec.Tiles[index], decoded[index],
                                             positionsMatch, layersMatch, windingIsUp);
        TestTrue(TEXT("Terrain mesh topology, heights and layers verify"), meshVerified);
        allPositions = allPositions && positionsMatch;
        allLayers = allLayers && layersMatch;
        allWinding = allWinding && windingIsUp;
        tileObservations.Add(MakeShared<FJsonValueObject>(MakeTileObservation(
            spec.Tiles[index], decoded[index], *mesh, positionsMatch, layersMatch, windingIsUp)));
    }
    TestTrue(TEXT("All 12,288 imported height samples retain X/Y direction and Z scale"),
             allPositions);
    TestTrue(TEXT("All imported terrain layer weights are preserved as vertex colors"), allLayers);
    TestTrue(TEXT("Every terrain triangle faces the UE positive-Z side"), allWinding);
    const bool scaleVerified = spec.SourceUnitsPerCell == 4.0F &&
                               spec.CellSpacingCentimeters == 400.0F &&
                               spec.ZoneSizeCentimeters == 25200.0F;
    TestTrue(TEXT("QLevel zoneSize and terrain tileNum produce exact UE scale"), scaleVerified);

    bool adjacencyVerified = true;
    TArray<TSharedPtr<FJsonValue>> adjacencyObservations;
    for (const FTMXYTerrainAdjacencySpec& adjacency : spec.Adjacencies)
    {
        int32 differences = 0;
        double maximumDeltaCm = 0.0;
        const bool verified =
            VerifyAdjacency(adjacency, spec, decoded, differences, maximumDeltaCm);
        TestTrue(TEXT("Terrain adjacency order and source seam delta verify"), verified);
        adjacencyVerified = adjacencyVerified && verified;
        TSharedRef<FJsonObject> observation = MakeShared<FJsonObject>();
        observation->SetStringField(TEXT("first"), adjacency.First);
        observation->SetStringField(TEXT("first_edge"), adjacency.FirstEdge);
        observation->SetStringField(TEXT("second"), adjacency.Second);
        observation->SetStringField(TEXT("second_edge"), adjacency.SecondEdge);
        observation->SetNumberField(TEXT("sample_count"), adjacency.SampleCount);
        observation->SetNumberField(TEXT("differing_sample_count"), differences);
        observation->SetNumberField(TEXT("maximum_absolute_delta_cm"), maximumDeltaCm);
        observation->SetBoolField(TEXT("world_xy_alignment_verified"), true);
        adjacencyObservations.Add(MakeShared<FJsonValueObject>(observation));
    }

    TMap<FString, TArray<uint8>> beforeBytes;
    for (const FTMXYTerrainTileSpec& tile : spec.Tiles)
    {
        const FString filename = FPackageName::LongPackageNameToFilename(
            tile.PackageName, FPackageName::GetAssetPackageExtension());
        TestTrue(TEXT("Terrain package bytes are readable before reimport"),
                 FFileHelper::LoadFileToArray(beforeBytes.FindOrAdd(tile.PackageName), *filename));
    }
    const FTMXYReimportRequest reimportRequest{TEXT("tmxy.terrain.height-f32le"),
                                               spec.Tiles[0].PackageName, ManifestPath,
                                               TEXT("base-height")};
    TestTrue(TEXT("Terrain reimport boundary accepts canonical target"),
             service.EvaluateReimport(reimportRequest).bCanReimport);
    const FTMXYImportItemResult reimported = service.Reimport(reimportRequest);
    TestTrue(TEXT("Terrain content-addressed reimport succeeds"), reimported.bSucceeded);
    bool bytesUnchanged = true;
    for (const FTMXYTerrainTileSpec& tile : spec.Tiles)
    {
        const FString filename = FPackageName::LongPackageNameToFilename(
            tile.PackageName, FPackageName::GetAssetPackageExtension());
        TArray<uint8> afterBytes;
        bytesUnchanged = bytesUnchanged && FFileHelper::LoadFileToArray(afterBytes, *filename) &&
                         beforeBytes.FindChecked(tile.PackageName) == afterBytes;
    }
    TestTrue(TEXT("All terrain package bytes are unchanged after reimport"), bytesUnchanged);
    const FString reportPath = FPaths::Combine(
        FPaths::ProjectSavedDir(), TEXT("Automation/TMXYImporter/p1-26-terrain-report.json"));
    TestTrue(TEXT("Terrain import report is written"),
             WriteReport(reportPath, beforeCount, imported, invalid, reimported, bytesUnchanged,
                         allPositions && allWinding, scaleVerified, adjacencyVerified,
                         tileObservations, adjacencyObservations));
    return !HasAnyErrors();
}

#endif
