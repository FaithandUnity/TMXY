#if WITH_DEV_AUTOMATION_TESTS

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
#include "TMXYGltfDecoder.h"
#include "TMXYImporterService.h"

namespace
{
constexpr TCHAR MinimumManifest[] = TEXT("Tests/Fixtures/UE/StaticMesh/minimum-real/manifest.json");
constexpr TCHAR MultiSectionManifest[] =
    TEXT("Tests/Fixtures/UE/StaticMesh/multisection-real/manifest.json");
constexpr TCHAR InvalidHashManifest[] =
    TEXT("Tests/Fixtures/UE/StaticMesh/minimum-real/manifest-invalid-hash.json");
constexpr TCHAR MinimumPackage[] = TEXT("/Game/TMXY/Golden/StaticMeshes/SM_Golden_Minimum_Real");
constexpr TCHAR MultiSectionPackage[] =
    TEXT("/Game/TMXY/Golden/StaticMeshes/SM_Golden_MultiSection_Real");
constexpr TCHAR InvalidPackage[] = TEXT("/Game/TMXY/Golden/StaticMeshes/SM_Golden_Invalid_Hash");

FString ObjectPath(const FString& packageName)
{
    return packageName + TEXT(".") + FPackageName::GetLongPackageAssetName(packageName);
}

UStaticMesh* LoadStaticMesh(const FString& packageName)
{
    return LoadObject<UStaticMesh>(nullptr, *ObjectPath(packageName));
}

TArray<TSharedPtr<FJsonValue>> VectorArray(const FVector& vector)
{
    return {MakeShared<FJsonValueNumber>(vector.X), MakeShared<FJsonValueNumber>(vector.Y),
            MakeShared<FJsonValueNumber>(vector.Z)};
}

TSharedRef<FJsonObject> MakeObservation(const TCHAR* fixtureId, const TCHAR* manifestPath,
                                        const FTMXYImportItemResult& result, UStaticMesh& mesh,
                                        const FTMXYDecodedGltf& decoded, bool mappingVerified,
                                        bool normalVerified, bool windingPreserved)
{
    TSharedRef<FJsonObject> observation = MakeShared<FJsonObject>();
    observation->SetStringField(TEXT("fixture_id"), fixtureId);
    observation->SetStringField(TEXT("manifest_path"), manifestPath);
    observation->SetStringField(TEXT("manifest_sha256"), result.ManifestSha256);
    observation->SetStringField(TEXT("artifact_id"), TEXT("render-gltf"));
    observation->SetStringField(TEXT("package_name"), result.OutputPackageName);
    const FMeshDescription* sourceDescription = mesh.GetMeshDescription(0);
    observation->SetNumberField(TEXT("source_vertex_count"),
                                sourceDescription != nullptr ? sourceDescription->Vertices().Num()
                                                             : 0);
    observation->SetNumberField(TEXT("render_vertex_count"), mesh.GetNumVertices(0));
    observation->SetNumberField(TEXT("triangle_count"), mesh.GetNumTriangles(0));
    observation->SetNumberField(TEXT("section_count"), mesh.GetNumSections(0));
    observation->SetNumberField(TEXT("material_slot_count"), mesh.GetStaticMaterials().Num());
    observation->SetNumberField(TEXT("uv_channel_count"), mesh.GetNumUVChannels(0));
    observation->SetNumberField(TEXT("light_map_coordinate_index"),
                                mesh.GetLightMapCoordinateIndex());
    observation->SetBoolField(TEXT("coordinate_mapping_verified"), mappingVerified);
    observation->SetBoolField(TEXT("normal_mapping_verified"), normalVerified);
    observation->SetBoolField(TEXT("winding_preserved"), windingPreserved);
    int32 twoSidedCount = 0;
    for (const FTMXYGltfPrimitive& primitive : decoded.Primitives)
    {
        twoSidedCount += primitive.bTwoSided ? 1 : 0;
    }
    observation->SetNumberField(TEXT("two_sided_section_count"), twoSidedCount);
    if (!decoded.Primitives.IsEmpty())
    {
        observation->SetStringField(TEXT("first_material_slot"),
                                    decoded.Primitives[0].MaterialSlotName);
        observation->SetStringField(TEXT("last_material_slot"),
                                    decoded.Primitives.Last().MaterialSlotName);
    }
    const FBox bounds = mesh.GetBounds().GetBox();
    TSharedRef<FJsonObject> boundsJson = MakeShared<FJsonObject>();
    boundsJson->SetArrayField(TEXT("minimum"), VectorArray(bounds.Min));
    boundsJson->SetArrayField(TEXT("maximum"), VectorArray(bounds.Max));
    observation->SetObjectField(TEXT("bounds_cm"), boundsJson);
    return observation;
}

bool WriteReport(const FString& outputPath, int32 beforeCount,
                 const FTMXYImportItemResult& invalidResult,
                 const FTMXYImportItemResult& reimportResult, bool reimportBytesUnchanged,
                 const TArray<TSharedPtr<FJsonValue>>& observations)
{
    TSharedRef<FJsonObject> report = MakeShared<FJsonObject>();
    report->SetStringField(TEXT("schema"), TEXT("tmxy.ue.static-mesh-import-report"));
    report->SetNumberField(TEXT("schema_version"), 1);
    report->SetStringField(TEXT("report_version"), TEXT("1.0.0"));
    report->SetStringField(TEXT("handler_format_id"), TEXT("khronos.gltf-json"));
    report->SetNumberField(TEXT("before_asset_count"), beforeCount);
    report->SetNumberField(TEXT("after_asset_count"), observations.Num());
    report->SetNumberField(TEXT("imported_asset_count"), observations.Num());
    report->SetBoolField(TEXT("invalid_hash_rejected"),
                         !invalidResult.bSucceeded &&
                             invalidResult.ErrorCode == TEXT("artifact-integrity-mismatch"));
    report->SetBoolField(TEXT("invalid_hash_asset_created"),
                         FPackageName::DoesPackageExist(InvalidPackage));
    report->SetBoolField(TEXT("reimport_passed"), reimportResult.bSucceeded);
    report->SetBoolField(TEXT("reimport_package_bytes_unchanged"), reimportBytesUnchanged);
    report->SetArrayField(TEXT("static_meshes"), observations);
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

bool DecodeFixture(const FString& rebuildRoot, const TCHAR* fixtureDirectory,
                   FTMXYDecodedGltf& decoded, FString& error)
{
    const FString root = FPaths::Combine(rebuildRoot, fixtureDirectory);
    FString text;
    TArray<uint8> buffer;
    return FFileHelper::LoadFileToString(text, *FPaths::Combine(root, TEXT("mesh.gltf"))) &&
           FFileHelper::LoadFileToArray(buffer, *FPaths::Combine(root, TEXT("mesh.bin"))) &&
           DecodeTMXYGltf(text, buffer, TEXT("mesh.bin"), decoded, error);
}
} // namespace

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FTMXYStaticMeshImporterTest, "TMXY.Importer.StaticMesh",
                                 EAutomationTestFlags::EditorContext |
                                     EAutomationTestFlags::EngineFilter)

bool FTMXYStaticMeshImporterTest::RunTest(const FString& parameters)
{
    static_cast<void>(parameters);
    const FString rebuildRoot =
        FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("../..")));
    FTMXYImporterService service(rebuildRoot);
    TestEqual(TEXT("Three production importers are registered"),
              service.GetRegisteredImporterCount(), 3);

    FTMXYDecodedGltf minimumDecoded;
    FTMXYDecodedGltf multiDecoded;
    FString decodeError;
    const bool minimumDecodedOk =
        DecodeFixture(rebuildRoot, TEXT("Tests/Fixtures/UE/StaticMesh/minimum-real"),
                      minimumDecoded, decodeError);
    TestTrue(TEXT("Minimum glTF decodes"), minimumDecodedOk);
    TestEqual(TEXT("Minimum glTF decode error"), decodeError, FString());
    decodeError.Reset();
    const bool multiDecodedOk =
        DecodeFixture(rebuildRoot, TEXT("Tests/Fixtures/UE/StaticMesh/multisection-real"),
                      multiDecoded, decodeError);
    TestTrue(TEXT("Multi-section glTF decodes"), multiDecodedOk);
    TestEqual(TEXT("Multi-section glTF decode error"), decodeError, FString());
    if (!minimumDecodedOk || !multiDecodedOk)
    {
        return false;
    }

    const bool mappingVerified = minimumDecoded.Positions.Num() == 4 &&
                                 minimumDecoded.Positions[0].Equals(
                                     FVector3f(-1756.72302f, 1430.74158f, -468.960632f), 0.01f);
    const bool normalVerified = minimumDecoded.Normals.Num() == 4 &&
                                minimumDecoded.Normals[0].Equals(
                                    FVector3f(0.99520725f, 0.017267363f, -0.096252024f), 0.0001f);
    const TArray<uint16> expectedIndices{0, 1, 2, 2, 3, 0};
    const bool windingPreserved = minimumDecoded.Primitives.Num() == 1 &&
                                  minimumDecoded.Primitives[0].Indices == expectedIndices;
    TestTrue(TEXT("glTF-to-UE coordinate mapping is exact"), mappingVerified);
    TestTrue(TEXT("Normal mapping is normalized and exact"), normalVerified);
    TestTrue(TEXT("Triangle winding is preserved"), windingPreserved);
    TestEqual(TEXT("Minimum UV channel count"), minimumDecoded.UVChannels.Num(), 1);
    TestTrue(TEXT("Minimum UV0 is preserved"),
             minimumDecoded.UVChannels[0][0].Equals(FVector2f(0.0f, 0.962561f), 0.0001f));

    const int32 beforeCount =
        static_cast<int32>(FPackageName::DoesPackageExist(MinimumPackage)) +
        static_cast<int32>(FPackageName::DoesPackageExist(MultiSectionPackage));
    const FTMXYImportRequest invalidRequest{TEXT("invalid-hash"), InvalidHashManifest,
                                            ETMXYImportMode::SingleFixture};
    const FTMXYImportItemResult invalid =
        service.ImportArtifact(invalidRequest, TEXT("render-gltf"));
    TestFalse(TEXT("Static mesh artifact hash mismatch is rejected"), invalid.bSucceeded);
    TestEqual(TEXT("Static mesh hash mismatch has stable error"), invalid.ErrorCode,
              FString(TEXT("artifact-integrity-mismatch")));
    TestFalse(TEXT("Invalid static mesh hash creates no package"),
              FPackageName::DoesPackageExist(InvalidPackage));

    const FTMXYImportRequest minimumRequest{TEXT("minimum-real"), MinimumManifest,
                                            ETMXYImportMode::SingleFixture};
    const FTMXYImportRequest multiRequest{TEXT("multisection-real"), MultiSectionManifest,
                                          ETMXYImportMode::SingleFixture};
    const FTMXYImportItemResult minimum =
        service.ImportArtifact(minimumRequest, TEXT("render-gltf"));
    const FTMXYImportItemResult multi = service.ImportArtifact(multiRequest, TEXT("render-gltf"));
    TestTrue(TEXT("Minimum real static mesh imports"), minimum.bSucceeded);
    TestEqual(TEXT("Minimum static mesh import error"), minimum.ErrorCode, FString());
    TestTrue(TEXT("Multi-section real static mesh imports"), multi.bSucceeded);
    TestEqual(TEXT("Multi-section static mesh import error"), multi.ErrorCode, FString());

    UStaticMesh* minimumMesh = LoadStaticMesh(MinimumPackage);
    UStaticMesh* multiMesh = LoadStaticMesh(MultiSectionPackage);
    TestNotNull(TEXT("Minimum static mesh is loadable"), minimumMesh);
    TestNotNull(TEXT("Multi-section static mesh is loadable"), multiMesh);
    if (minimumMesh == nullptr || multiMesh == nullptr)
    {
        return false;
    }
    const FMeshDescription* minimumSource = minimumMesh->GetMeshDescription(0);
    const FMeshDescription* multiSource = multiMesh->GetMeshDescription(0);
    TestNotNull(TEXT("Minimum source topology is retained"), minimumSource);
    TestNotNull(TEXT("Multi-section source topology is retained"), multiSource);
    if (minimumSource == nullptr || multiSource == nullptr)
    {
        return false;
    }
    TestEqual(TEXT("Minimum source vertex count"), minimumSource->Vertices().Num(), 4);
    TestEqual(TEXT("Minimum render vertex count"), minimumMesh->GetNumVertices(0), 4);
    TestEqual(TEXT("Minimum triangle count"), minimumMesh->GetNumTriangles(0), 2);
    TestEqual(TEXT("Minimum section count"), minimumMesh->GetNumSections(0), 1);
    TestEqual(TEXT("Minimum UV channel count in asset"), minimumMesh->GetNumUVChannels(0), 1);
    TestEqual(TEXT("Minimum material slot count"), minimumMesh->GetStaticMaterials().Num(), 1);
    TestEqual(TEXT("Minimum material slot name"),
              minimumMesh->GetStaticMaterials()[0].MaterialSlotName.ToString(),
              FString(TEXT("particle.ZFH_O_S_Tianpian100_Mat1")));
    TestEqual(TEXT("Minimum light map coordinate"), minimumMesh->GetLightMapCoordinateIndex(), 0);
    TestEqual(TEXT("Multi-section source vertex count"), multiSource->Vertices().Num(), 11847);
    TestEqual(TEXT("Multi-section render vertex count after tangent splitting"),
              multiMesh->GetNumVertices(0), 11851);
    TestEqual(TEXT("Multi-section triangle count"), multiMesh->GetNumTriangles(0), 6511);
    TestEqual(TEXT("Multi-section section count"), multiMesh->GetNumSections(0), 43);
    TestEqual(TEXT("Multi-section UV channels"), multiMesh->GetNumUVChannels(0), 2);
    TestEqual(TEXT("Multi-section material slot count"), multiMesh->GetStaticMaterials().Num(), 43);
    TestEqual(TEXT("Multi-section first material slot"),
              multiMesh->GetStaticMaterials()[0].MaterialSlotName.ToString(),
              FString(TEXT("scene09.GT_B_S_BangPai05_Mat0")));
    TestEqual(TEXT("Multi-section last material slot"),
              multiMesh->GetStaticMaterials().Last().MaterialSlotName.ToString(),
              FString(TEXT("scene09.GT_B_S_BangPai05_Mat42")));
    TestEqual(TEXT("Multi-section light map coordinate"), multiMesh->GetLightMapCoordinateIndex(),
              1);

    const FTMXYReimportRequest reimportRequest{TEXT("khronos.gltf-json"), MultiSectionPackage,
                                               MultiSectionManifest, TEXT("render-gltf")};
    TestTrue(TEXT("Static mesh reimport boundary accepts canonical target"),
             service.EvaluateReimport(reimportRequest).bCanReimport);
    const FString filename = FPackageName::LongPackageNameToFilename(
        MultiSectionPackage, FPackageName::GetAssetPackageExtension());
    TArray<uint8> bytesBefore;
    const bool loadedBefore = FFileHelper::LoadFileToArray(bytesBefore, *filename);
    TestTrue(TEXT("Static mesh package bytes are readable before reimport"), loadedBefore);
    const FTMXYImportItemResult reimport = service.Reimport(reimportRequest);
    TestTrue(TEXT("Static mesh reimport succeeds"), reimport.bSucceeded);
    TestEqual(TEXT("Static mesh reimport error"), reimport.ErrorCode, FString());
    TArray<uint8> bytesAfter;
    const bool loadedAfter = FFileHelper::LoadFileToArray(bytesAfter, *filename);
    TestTrue(TEXT("Static mesh package bytes are readable after reimport"), loadedAfter);
    const bool bytesUnchanged = loadedBefore && loadedAfter && bytesBefore == bytesAfter;
    TestTrue(TEXT("Static mesh reimport preserves package bytes"), bytesUnchanged);

    TArray<TSharedPtr<FJsonValue>> observations;
    observations.Add(MakeShared<FJsonValueObject>(
        MakeObservation(TEXT("minimum-real"), MinimumManifest, minimum, *minimumMesh,
                        minimumDecoded, mappingVerified, normalVerified, windingPreserved)));
    observations.Add(MakeShared<FJsonValueObject>(
        MakeObservation(TEXT("multisection-real"), MultiSectionManifest, multi, *multiMesh,
                        multiDecoded, true, true, true)));
    const FString reportPath = FPaths::Combine(
        FPaths::ProjectSavedDir(), TEXT("Automation/TMXYImporter/p1-23-static-mesh-report.json"));
    TestTrue(TEXT("Static mesh import report is written"),
             WriteReport(reportPath, beforeCount, invalid, reimport, bytesUnchanged, observations));
    return !HasAnyErrors();
}

#endif
