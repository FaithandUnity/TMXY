#if WITH_DEV_AUTOMATION_TESTS

#include "Animation/Skeleton.h"
#include "Dom/JsonObject.h"
#include "Engine/SkeletalMesh.h"
#include "HAL/FileManager.h"
#include "MeshDescription.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "ReferenceSkeleton.h"
#include "Rendering/SkeletalMeshLODModel.h"
#include "Rendering/SkeletalMeshModel.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "SkeletalMeshAttributes.h"
#include "TMXYImporterService.h"
#include "TMXYSkeletalGltfDecoder.h"

namespace
{
constexpr TCHAR ManifestPath[] =
    TEXT("Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/manifest.json");
constexpr TCHAR InvalidManifestPath[] =
    TEXT("Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/manifest-invalid-hash.json");
constexpr TCHAR MeshPackage[] = TEXT("/Game/TMXY/Golden/SkeletalMeshes/SK_Golden_Boy01_Default");
constexpr TCHAR SkeletonPackage[] = TEXT("/Game/TMXY/Golden/Skeletons/SKEL_Golden_Boy01");
constexpr TCHAR InvalidMeshPackage[] =
    TEXT("/Game/TMXY/Golden/SkeletalMeshes/SK_Golden_Invalid_Hash");
constexpr TCHAR InvalidSkeletonPackage[] =
    TEXT("/Game/TMXY/Golden/Skeletons/SKEL_Golden_Invalid_Hash");

FString ObjectPath(const FString& packageName)
{
    return packageName + TEXT(".") + FPackageName::GetLongPackageAssetName(packageName);
}

template <typename AssetType> AssetType* LoadAsset(const FString& packageName)
{
    return LoadObject<AssetType>(nullptr, *ObjectPath(packageName));
}

bool DecodeFixture(const FString& rebuildRoot, FTMXYDecodedSkeletalGltf& decoded, FString& error)
{
    const FString root =
        FPaths::Combine(rebuildRoot, TEXT("Tests/Fixtures/UE/SkeletalMesh/boy01-default-real"));
    FString text;
    TArray<uint8> buffer;
    return FFileHelper::LoadFileToString(text, *FPaths::Combine(root, TEXT("mesh.gltf"))) &&
           FFileHelper::LoadFileToArray(buffer, *FPaths::Combine(root, TEXT("mesh.bin"))) &&
           DecodeTMXYSkeletalGltf(text, buffer, TEXT("mesh.bin"), decoded, error);
}

int32 TriangleCount(const USkeletalMesh& mesh)
{
    const FSkeletalMeshModel* model = mesh.GetImportedModel();
    if (model == nullptr || model->LODModels.IsEmpty())
    {
        return 0;
    }
    int32 count = 0;
    for (const FSkelMeshSection& section : model->LODModels[0].Sections)
    {
        count += section.NumTriangles;
    }
    return count;
}

struct FWeightObservation
{
    bool bPassed = false;
    int32 WeightedVertexCount = 0;
    int32 MaximumInfluences = 0;
    float MaximumSumError = 0.0F;
};

FWeightObservation InspectWeights(const FMeshDescription& description, int32 boneCount)
{
    const FSkeletalMeshConstAttributes attributes(description);
    const TArray<FName> profiles = attributes.GetSkinWeightProfileNames();
    if (profiles.IsEmpty())
    {
        return {};
    }
    const FSkinWeightsVertexAttributesConstRef weights =
        attributes.GetVertexSkinWeights(profiles[0]);
    FWeightObservation observation;
    observation.bPassed = weights.IsValid();
    for (const FVertexID vertex : description.Vertices().GetElementIDs())
    {
        const FVertexBoneWeightsConst influences = weights.Get(vertex);
        float sum = 0.0F;
        observation.MaximumInfluences = FMath::Max(observation.MaximumInfluences, influences.Num());
        observation.bPassed &= influences.Num() >= 1 && influences.Num() <= 4;
        for (const UE::AnimationCore::FBoneWeight influence : influences)
        {
            sum += influence.GetWeight();
            observation.bPassed &=
                influence.GetBoneIndex() < boneCount && influence.GetWeight() > 0.0F;
        }
        const float sumError = FMath::Abs(sum - 1.0F);
        observation.MaximumSumError = FMath::Max(observation.MaximumSumError, sumError);
        observation.bPassed &= sumError <= 0.0001F;
        ++observation.WeightedVertexCount;
    }
    return observation;
}

bool VerifyBindPose(const FReferenceSkeleton& reference, const FTMXYDecodedSkeletalGltf& decoded,
                    float& maximumComponentMagnitude)
{
    if (reference.GetRawBoneNum() != decoded.Bones.Num())
    {
        return false;
    }
    bool passed = true;
    TArray<FTransform> components;
    components.Reserve(reference.GetRawBoneNum());
    for (int32 index = 0; index < reference.GetRawBoneNum(); ++index)
    {
        const FTransform& local = reference.GetRawRefBonePose()[index];
        const FTMXYSkeletalBone& expected = decoded.Bones[index];
        const double quaternionAlignment =
            FMath::Abs(local.GetRotation() | FQuat(expected.LocalRotation));
        passed &= reference.GetRawRefBoneInfo()[index].Name.ToString() == expected.Name &&
                  reference.GetRawParentIndex(index) == expected.ParentIndex &&
                  local.GetTranslation().Equals(FVector(expected.LocalTranslationCm), 0.05) &&
                  quaternionAlignment >= 0.9999 && local.GetScale3D().Equals(FVector::OneVector) &&
                  !local.ContainsNaN() && local.ToMatrixNoScale().Determinant() > 0.0;
        const int32 parent = reference.GetRawParentIndex(index);
        const FTransform component = parent == INDEX_NONE ? local : local * components[parent];
        components.Add(component);
        const FVector translation = component.GetTranslation();
        maximumComponentMagnitude =
            FMath::Max(maximumComponentMagnitude, static_cast<float>(translation.GetAbsMax()));
        passed &= !component.ContainsNaN() && component.ToMatrixNoScale().Determinant() > 0.0 &&
                  translation.GetAbsMax() < 100000.0;
    }
    return passed;
}

bool VerifyAttachmentPolicy(const USkeletalMesh& mesh, const USkeleton& skeleton)
{
    const FReferenceSkeleton& reference = mesh.GetRefSkeleton();
    const TCHAR* candidates[] = {TEXT("Bip01 Head"), TEXT("Bip01 L Hand"), TEXT("Bip01 R Hand")};
    bool candidatesExist = true;
    for (const TCHAR* candidate : candidates)
    {
        candidatesExist &= reference.FindBoneIndex(FName(candidate)) != INDEX_NONE;
    }
    return candidatesExist && mesh.GetMeshOnlySocketList().IsEmpty() && skeleton.Sockets.IsEmpty();
}

TArray<TSharedPtr<FJsonValue>> VectorArray(const FVector& vector)
{
    return {MakeShared<FJsonValueNumber>(vector.X), MakeShared<FJsonValueNumber>(vector.Y),
            MakeShared<FJsonValueNumber>(vector.Z)};
}

bool WriteReport(const FString& outputPath, const FTMXYImportItemResult& imported,
                 const FTMXYImportItemResult& invalid, const FTMXYImportItemResult& reimported,
                 const USkeletalMesh& mesh, const USkeleton& skeleton,
                 const FTMXYDecodedSkeletalGltf& decoded, const FWeightObservation& weights,
                 bool bindPosePassed, float maximumComponentMagnitude, bool attachmentPolicyPassed,
                 bool meshBytesUnchanged, bool skeletonBytesUnchanged)
{
    const FSkeletalMeshModel* model = mesh.GetImportedModel();
    const FBox bounds = mesh.GetBounds().GetBox();
    TSharedRef<FJsonObject> report = MakeShared<FJsonObject>();
    report->SetStringField(TEXT("schema"), TEXT("tmxy.ue.skeletal-mesh-import-report"));
    report->SetNumberField(TEXT("schema_version"), 1);
    report->SetStringField(TEXT("report_version"), TEXT("1.0.0"));
    report->SetStringField(TEXT("handler_format_id"), TEXT("khronos.gltf-json"));
    report->SetStringField(TEXT("fixture_id"), TEXT("boy01-default-real"));
    report->SetStringField(TEXT("manifest_path"), ManifestPath);
    report->SetStringField(TEXT("manifest_sha256"), imported.ManifestSha256);
    report->SetStringField(TEXT("skeletal_mesh_package"), MeshPackage);
    report->SetStringField(TEXT("skeleton_package"), SkeletonPackage);
    report->SetNumberField(TEXT("imported_asset_count"), imported.ImportedAssetCount);
    report->SetNumberField(TEXT("source_vertex_count"),
                           mesh.GetMeshDescription(0)->Vertices().Num());
    report->SetNumberField(TEXT("render_vertex_count"),
                           model != nullptr ? model->LODModels[0].NumVertices : 0);
    report->SetNumberField(TEXT("triangle_count"), TriangleCount(mesh));
    report->SetNumberField(TEXT("section_count"),
                           model != nullptr ? model->LODModels[0].Sections.Num() : 0);
    report->SetNumberField(TEXT("material_slot_count"), mesh.GetMaterials().Num());
    report->SetNumberField(TEXT("bone_count"), mesh.GetRefSkeleton().GetRawBoneNum());
    report->SetNumberField(TEXT("skeleton_bone_count"),
                           skeleton.GetReferenceSkeleton().GetRawBoneNum());
    report->SetStringField(TEXT("root_bone_name"), mesh.GetRefSkeleton().GetBoneName(0).ToString());
    report->SetNumberField(TEXT("weighted_vertex_count"), weights.WeightedVertexCount);
    report->SetNumberField(TEXT("maximum_active_influences"), weights.MaximumInfluences);
    report->SetNumberField(TEXT("maximum_weight_sum_error"), weights.MaximumSumError);
    report->SetBoolField(TEXT("weights_verified"), weights.bPassed);
    report->SetBoolField(TEXT("bind_pose_verified"), bindPosePassed);
    report->SetNumberField(TEXT("maximum_component_translation_cm"), maximumComponentMagnitude);
    report->SetBoolField(TEXT("inverse_bind_orientation_preserved"),
                         decoded.bInverseBindOrientationPreserved);
    report->SetBoolField(TEXT("attachment_policy_verified"), attachmentPolicyPassed);
    report->SetBoolField(TEXT("invalid_hash_rejected"),
                         !invalid.bSucceeded &&
                             invalid.ErrorCode == TEXT("artifact-integrity-mismatch"));
    report->SetBoolField(TEXT("invalid_hash_asset_created"),
                         FPackageName::DoesPackageExist(InvalidMeshPackage) ||
                             FPackageName::DoesPackageExist(InvalidSkeletonPackage));
    report->SetBoolField(TEXT("reimport_passed"), reimported.bSucceeded);
    report->SetBoolField(TEXT("reimport_mesh_bytes_unchanged"), meshBytesUnchanged);
    report->SetBoolField(TEXT("reimport_skeleton_bytes_unchanged"), skeletonBytesUnchanged);
    TSharedRef<FJsonObject> boundsJson = MakeShared<FJsonObject>();
    boundsJson->SetArrayField(TEXT("minimum"), VectorArray(bounds.Min));
    boundsJson->SetArrayField(TEXT("maximum"), VectorArray(bounds.Max));
    report->SetObjectField(TEXT("bounds_cm"), boundsJson);
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

bool ReadPackageBytes(const FString& packageName, TArray<uint8>& bytes)
{
    const FString filename = FPackageName::LongPackageNameToFilename(
        packageName, FPackageName::GetAssetPackageExtension());
    return FFileHelper::LoadFileToArray(bytes, *filename);
}
} // namespace

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FTMXYSkeletalMeshImporterTest, "TMXY.Importer.SkeletalMesh",
                                 EAutomationTestFlags::EditorContext |
                                     EAutomationTestFlags::EngineFilter)

bool FTMXYSkeletalMeshImporterTest::RunTest(const FString& parameters)
{
    static_cast<void>(parameters);
    const FString rebuildRoot =
        FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("../..")));
    FTMXYImporterService service(rebuildRoot);
    TestEqual(TEXT("glTF routing plus terrain keep three production format handlers"),
              service.GetRegisteredImporterCount(), 3);

    FTMXYDecodedSkeletalGltf decoded;
    FString decodeError;
    const bool decodedOk = DecodeFixture(rebuildRoot, decoded, decodeError);
    TestTrue(TEXT("Boy01 authoritative skinned glTF decodes"), decodedOk);
    TestEqual(TEXT("Boy01 glTF decode error"), decodeError, FString());
    if (!decodedOk)
    {
        return false;
    }
    TestTrue(TEXT("Inverse bind matrices preserve positive orientation"),
             decoded.bInverseBindOrientationPreserved);
    TestEqual(TEXT("Decoded Boy01 vertices"), decoded.Positions.Num(), 10338);
    TestEqual(TEXT("Decoded Boy01 bones"), decoded.Bones.Num(), 80);
    TestEqual(TEXT("Decoded Boy01 sections"), decoded.Primitives.Num(), 7);

    const FTMXYImportRequest invalidRequest{TEXT("boy01-invalid"), InvalidManifestPath,
                                            ETMXYImportMode::SingleFixture};
    const FTMXYImportItemResult invalid =
        service.ImportArtifact(invalidRequest, TEXT("render-gltf"));
    TestFalse(TEXT("Skeletal mesh artifact hash mismatch is rejected"), invalid.bSucceeded);
    TestEqual(TEXT("Skeletal mesh hash mismatch has stable error"), invalid.ErrorCode,
              FString(TEXT("artifact-integrity-mismatch")));
    TestFalse(TEXT("Invalid skeletal mesh creates no package"),
              FPackageName::DoesPackageExist(InvalidMeshPackage));
    TestFalse(TEXT("Invalid skeleton creates no package"),
              FPackageName::DoesPackageExist(InvalidSkeletonPackage));

    const FTMXYImportRequest request{TEXT("boy01-default-real"), ManifestPath,
                                     ETMXYImportMode::SingleFixture};
    const FTMXYImportItemResult imported = service.ImportArtifact(request, TEXT("render-gltf"));
    TestTrue(TEXT("Boy01 real skeletal mesh imports"), imported.bSucceeded);
    TestEqual(TEXT("Boy01 skeletal import error"), imported.ErrorCode, FString());
    TestEqual(TEXT("Skeletal import produces mesh and skeleton"), imported.ImportedAssetCount, 2);

    USkeletalMesh* mesh = LoadAsset<USkeletalMesh>(MeshPackage);
    USkeleton* skeleton = LoadAsset<USkeleton>(SkeletonPackage);
    TestNotNull(TEXT("Generated skeletal mesh is loadable"), mesh);
    TestNotNull(TEXT("Generated skeleton is loadable"), skeleton);
    if (mesh == nullptr || skeleton == nullptr)
    {
        return false;
    }
    const FMeshDescription* source = mesh->GetMeshDescription(0);
    const FSkeletalMeshModel* model = mesh->GetImportedModel();
    TestNotNull(TEXT("Skeletal mesh source description is retained"), source);
    TestNotNull(TEXT("Skeletal mesh imported model is retained"), model);
    if (source == nullptr || model == nullptr || model->LODModels.IsEmpty())
    {
        return false;
    }
    TestEqual(TEXT("Boy01 source vertex count"), source->Vertices().Num(), 10338);
    TestEqual(TEXT("Boy01 triangle count"), TriangleCount(*mesh), 8757);
    TestEqual(TEXT("Boy01 section count"), model->LODModels[0].Sections.Num(), 7);
    TestEqual(TEXT("Boy01 material slot count"), mesh->GetMaterials().Num(), 7);
    TestEqual(TEXT("Boy01 mesh bone count"), mesh->GetRefSkeleton().GetRawBoneNum(), 80);
    TestEqual(TEXT("Boy01 skeleton bone count"), skeleton->GetReferenceSkeleton().GetRawBoneNum(),
              80);
    TestEqual(TEXT("Boy01 root bone"), mesh->GetRefSkeleton().GetBoneName(0).ToString(),
              FString(TEXT("Bip01")));

    const FWeightObservation weights = InspectWeights(*source, 80);
    TestTrue(TEXT("All source vertices have normalized valid skin weights"), weights.bPassed);
    TestEqual(TEXT("Every source vertex is weighted"), weights.WeightedVertexCount, 10338);
    TestEqual(TEXT("Maximum active influences remains four"), weights.MaximumInfluences, 4);
    float maximumComponentMagnitude = 0.0F;
    const bool bindPosePassed =
        VerifyBindPose(mesh->GetRefSkeleton(), decoded, maximumComponentMagnitude);
    TestTrue(TEXT("Bone hierarchy and bind pose are finite and orientation-preserving"),
             bindPosePassed);
    const bool attachmentPolicyPassed = VerifyAttachmentPolicy(*mesh, *skeleton);
    TestTrue(TEXT("Bone-name attachment candidates exist without invented sockets"),
             attachmentPolicyPassed);
    const FBox bounds = mesh->GetBounds().GetBox();
    TestTrue(TEXT("Boy01 bounds are finite and non-exploding"),
             bounds.IsValid != 0 && bounds.Min.Equals(FVector(decoded.Bounds.Min), 0.05) &&
                 bounds.Max.Equals(FVector(decoded.Bounds.Max), 0.05));

    TArray<uint8> meshBefore;
    TArray<uint8> skeletonBefore;
    const bool beforeReadable = ReadPackageBytes(MeshPackage, meshBefore) &&
                                ReadPackageBytes(SkeletonPackage, skeletonBefore);
    TestTrue(TEXT("Skeletal packages are readable before reimport"), beforeReadable);
    const FTMXYReimportRequest reimportRequest{TEXT("khronos.gltf-json"), MeshPackage, ManifestPath,
                                               TEXT("render-gltf")};
    TestTrue(TEXT("Skeletal reimport accepts canonical target"),
             service.EvaluateReimport(reimportRequest).bCanReimport);
    const FTMXYImportItemResult reimported = service.Reimport(reimportRequest);
    TestTrue(TEXT("Skeletal reimport succeeds"), reimported.bSucceeded);
    TArray<uint8> meshAfter;
    TArray<uint8> skeletonAfter;
    const bool afterReadable = ReadPackageBytes(MeshPackage, meshAfter) &&
                               ReadPackageBytes(SkeletonPackage, skeletonAfter);
    TestTrue(TEXT("Skeletal packages are readable after reimport"), afterReadable);
    const bool meshBytesUnchanged = beforeReadable && afterReadable && meshBefore == meshAfter;
    const bool skeletonBytesUnchanged =
        beforeReadable && afterReadable && skeletonBefore == skeletonAfter;
    TestTrue(TEXT("Skeletal mesh reimport preserves package bytes"), meshBytesUnchanged);
    TestTrue(TEXT("Skeleton reimport preserves package bytes"), skeletonBytesUnchanged);

    const FString reportPath = FPaths::Combine(
        FPaths::ProjectSavedDir(), TEXT("Automation/TMXYImporter/p1-24-skeletal-mesh-report.json"));
    TestTrue(TEXT("Skeletal mesh import report is written"),
             WriteReport(reportPath, imported, invalid, reimported, *mesh, *skeleton, decoded,
                         weights, bindPosePassed, maximumComponentMagnitude, attachmentPolicyPassed,
                         meshBytesUnchanged, skeletonBytesUnchanged));
    return !HasAnyErrors();
}

#endif
