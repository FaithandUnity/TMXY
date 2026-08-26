#include "TMXYSkeletalMeshImporter.h"

#include "Animation/Skeleton.h"
#include "BoneWeights.h"
#include "Dom/JsonObject.h"
#include "Engine/SkeletalMesh.h"
#include "MeshDescription.h"
#include "MeshDescriptionBuilder.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "ReferenceSkeleton.h"
#include "Rendering/SkeletalMeshLODModel.h"
#include "Rendering/SkeletalMeshModel.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "SkeletalMeshAttributes.h"
#include "StaticToSkeletalMeshConverter.h"
#include "TMXYSkeletalGltfDecoder.h"
#include "TMXYSkeletalMeshManifest.h"
#include "UObject/MetaData.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"

namespace
{
constexpr TCHAR SkeletalMeshRoot[] = TEXT("/Game/TMXY/Golden/SkeletalMeshes/");
constexpr TCHAR ManifestHashKey[] = TEXT("TMXY.ManifestSha256");
constexpr TCHAR ImporterVersionKey[] = TEXT("TMXY.SkeletalMeshImporterVersion");
constexpr TCHAR ImporterVersion[] = TEXT("1");

struct FImportedPair
{
    USkeletalMesh* Mesh = nullptr;
    USkeleton* Skeleton = nullptr;
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

bool ReadExactInt(const TSharedPtr<FJsonObject>& object, const TCHAR* field, int32& value,
                  bool allowZero = false)
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

bool NearlyEqual(const FVector3f& left, const FVector3f& right, float tolerance = 0.05F)
{
    return FMath::Abs(left.X - right.X) <= tolerance && FMath::Abs(left.Y - right.Y) <= tolerance &&
           FMath::Abs(left.Z - right.Z) <= tolerance;
}

int32 CountTriangles(const FTMXYDecodedSkeletalGltf& decoded)
{
    int32 count = 0;
    for (const FTMXYSkeletalPrimitive& primitive : decoded.Primitives)
    {
        count += primitive.Indices.Num() / 3;
    }
    return count;
}

bool ValidateMetadata(const FTMXYSkeletalMeshImportSpec& spec,
                      const FTMXYDecodedSkeletalGltf& decoded, FString& error)
{
    FString text;
    TSharedPtr<FJsonObject> root;
    const TArray<TSharedPtr<FJsonValue>>* bones = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* roots = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* selections = nullptr;
    int32 boneCount = 0;
    int32 sentinelCount = 0;
    if (!FFileHelper::LoadFileToString(text, *spec.MetadataPath))
    {
        error = TEXT("skeletal-mesh-metadata-read-failed");
        return false;
    }
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(text);
    if (!FJsonSerializer::Deserialize(reader, root) || !root.IsValid() ||
        !ReadExactInt(root, TEXT("bone_count"), boneCount) ||
        !ReadExactInt(root, TEXT("legacy_unweighted_sentinel_vertex_count"), sentinelCount, true) ||
        !root->TryGetArrayField(TEXT("bones"), bones) ||
        !root->TryGetArrayField(TEXT("root_bone_ids"), roots) ||
        !root->TryGetArrayField(TEXT("default_selections"), selections))
    {
        error = TEXT("skeletal-mesh-metadata-contract-invalid");
        return false;
    }
    int32 visibleSelectionCount = 0;
    for (const TSharedPtr<FJsonValue>& value : *selections)
    {
        const TSharedPtr<FJsonObject> selection = value->AsObject();
        const TSharedPtr<FJsonValue> section =
            selection.IsValid() ? selection->TryGetField(TEXT("section_name")) : nullptr;
        visibleSelectionCount += section.IsValid() && !section->IsNull() ? 1 : 0;
    }
    if (boneCount != spec.ExpectedBoneCount || bones->Num() != boneCount ||
        decoded.Bones.Num() != boneCount || roots->Num() != spec.ExpectedRootBoneCount ||
        decoded.RootBoneCount != spec.ExpectedRootBoneCount ||
        decoded.Bones[0].Name != spec.ExpectedRootBoneName ||
        sentinelCount != spec.ExpectedUnweightedSentinelCount ||
        decoded.Positions.Num() != spec.ExpectedSourceVertexCount ||
        CountTriangles(decoded) != spec.ExpectedTriangleCount ||
        decoded.Primitives.Num() != spec.ExpectedMaterialSlotCount ||
        visibleSelectionCount != spec.ExpectedMaterialSlotCount ||
        decoded.MaximumActiveInfluences != spec.ExpectedMaximumActiveInfluences ||
        !NearlyEqual(decoded.Bounds.Min, spec.ExpectedBoundsMinimum) ||
        !NearlyEqual(decoded.Bounds.Max, spec.ExpectedBoundsMaximum))
    {
        error = TEXT("skeletal-mesh-metadata-or-manifest-mismatch");
        return false;
    }
    return true;
}

FTransform MakeBoneTransform(const FTMXYSkeletalBone& bone)
{
    return FTransform(FQuat(bone.LocalRotation), FVector(bone.LocalTranslationCm));
}

FReferenceSkeleton BuildReferenceSkeleton(const FTMXYDecodedSkeletalGltf& decoded)
{
    FReferenceSkeleton skeleton;
    FReferenceSkeletonModifier modifier(skeleton, nullptr);
    for (const FTMXYSkeletalBone& bone : decoded.Bones)
    {
        modifier.Add(FMeshBoneInfo(FName(*bone.Name), bone.Name, bone.ParentIndex),
                     MakeBoneTransform(bone));
    }
    return skeleton;
}

UE::AnimationCore::FBoneWeights MakeBoneWeights(const FTMXYSkeletalInfluence& influence)
{
    TArray<UE::AnimationCore::FBoneWeight, TInlineAllocator<4>> weights;
    for (int32 index = 0; index < 4; ++index)
    {
        if (influence.Weights[index] > UE_SMALL_NUMBER)
        {
            weights.Emplace(static_cast<FBoneIndexType>(influence.Joints[index]),
                            influence.Weights[index]);
        }
    }
    return UE::AnimationCore::FBoneWeights::Create(weights);
}

FMeshDescription BuildMeshDescription(const FTMXYDecodedSkeletalGltf& decoded)
{
    FMeshDescription description;
    FSkeletalMeshAttributes attributes(description);
    attributes.Register();
    FMeshDescriptionBuilder builder;
    builder.SetMeshDescription(&description);
    builder.SetNumUVLayers(1);
    builder.ReserveNewVertices(decoded.Positions.Num());
    FSkinWeightsVertexAttributesRef skinWeights = attributes.GetVertexSkinWeights();

    TArray<FVertexID> vertices;
    vertices.Reserve(decoded.Positions.Num());
    for (int32 index = 0; index < decoded.Positions.Num(); ++index)
    {
        const FVertexID vertex = builder.AppendVertex(FVector(decoded.Positions[index]));
        skinWeights.Set(vertex, MakeBoneWeights(decoded.Influences[index]));
        vertices.Add(vertex);
    }
    for (const FTMXYSkeletalPrimitive& primitive : decoded.Primitives)
    {
        const FPolygonGroupID group =
            builder.AppendPolygonGroup(FName(*primitive.MaterialSlotName));
        for (int32 index = 0; index < primitive.Indices.Num(); index += 3)
        {
            FVertexInstanceID instances[3];
            for (int32 corner = 0; corner < 3; ++corner)
            {
                const int32 vertexIndex = static_cast<int32>(primitive.Indices[index + corner]);
                instances[corner] = builder.AppendInstance(vertices[vertexIndex]);
                builder.SetInstanceNormal(instances[corner], FVector(decoded.Normals[vertexIndex]));
                builder.SetInstanceUV(instances[corner], FVector2D(decoded.UV0[vertexIndex]), 0);
            }
            builder.AppendTriangle(instances[0], instances[1], instances[2], group);
        }
    }
    FSkeletalMeshAttributes::FBoneNameAttributesRef boneNames = attributes.GetBoneNames();
    FSkeletalMeshAttributes::FBoneParentIndexAttributesRef parents =
        attributes.GetBoneParentIndices();
    FSkeletalMeshAttributes::FBonePoseAttributesRef poses = attributes.GetBonePoses();
    for (const FTMXYSkeletalBone& bone : decoded.Bones)
    {
        const FBoneID boneId = attributes.CreateBone();
        boneNames.Set(boneId, FName(*bone.Name));
        parents.Set(boneId, bone.ParentIndex);
        poses.Set(boneId, MakeBoneTransform(bone));
    }
    return description;
}

TArray<FSkeletalMaterial> BuildMaterials(const FTMXYDecodedSkeletalGltf& decoded)
{
    TArray<FSkeletalMaterial> materials;
    materials.Reserve(decoded.Primitives.Num());
    for (const FTMXYSkeletalPrimitive& primitive : decoded.Primitives)
    {
        const FName slotName(*primitive.MaterialSlotName);
        materials.Emplace(nullptr, true, false, slotName, slotName);
    }
    return materials;
}

bool AssetMatches(const USkeletalMesh& mesh, const USkeleton& skeleton,
                  const FTMXYSkeletalMeshImportSpec& spec, const FTMXYDecodedSkeletalGltf& decoded)
{
    FMetaData& meshMetadata = mesh.GetPackage()->GetMetaData();
    FMetaData& skeletonMetadata = skeleton.GetPackage()->GetMetaData();
    const FMeshDescription* source = mesh.GetMeshDescription(0);
    const FSkeletalMeshModel* model = mesh.GetImportedModel();
    if (meshMetadata.GetValue(&mesh, ManifestHashKey) != spec.ManifestSha256 ||
        meshMetadata.GetValue(&mesh, ImporterVersionKey) != ImporterVersion ||
        skeletonMetadata.GetValue(&skeleton, ManifestHashKey) != spec.ManifestSha256 ||
        skeletonMetadata.GetValue(&skeleton, ImporterVersionKey) != ImporterVersion ||
        mesh.GetSkeleton() != &skeleton || source == nullptr ||
        source->Vertices().Num() != spec.ExpectedSourceVertexCount || model == nullptr ||
        model->LODModels.Num() != 1 ||
        model->LODModels[0].Sections.Num() != spec.ExpectedMaterialSlotCount ||
        mesh.GetRefSkeleton().GetRawBoneNum() != spec.ExpectedBoneCount ||
        mesh.GetMaterials().Num() != spec.ExpectedMaterialSlotCount ||
        skeleton.GetReferenceSkeleton().GetRawBoneNum() != spec.ExpectedBoneCount)
    {
        return false;
    }
    int32 triangles = 0;
    for (const FSkelMeshSection& section : model->LODModels[0].Sections)
    {
        triangles += section.NumTriangles;
    }
    const FBox observed = mesh.GetBounds().GetBox();
    return triangles == spec.ExpectedTriangleCount &&
           mesh.GetRefSkeleton().GetBoneName(0).ToString() == spec.ExpectedRootBoneName &&
           NearlyEqual(FVector3f(observed.Min), decoded.Bounds.Min) &&
           NearlyEqual(FVector3f(observed.Max), decoded.Bounds.Max);
}

bool SaveAssetPackage(UPackage& package, UObject& asset, const FString& packageName)
{
    const FString filename = FPackageName::LongPackageNameToFilename(
        packageName, FPackageName::GetAssetPackageExtension());
    FSavePackageArgs args;
    args.TopLevelFlags = RF_Public | RF_Standalone;
    args.SaveFlags = SAVE_None;
    return UPackage::SavePackage(&package, &asset, *filename, args);
}

FImportedPair ImportSkeletalMesh(const FTMXYSkeletalMeshImportSpec& spec,
                                 const FTMXYDecodedSkeletalGltf& decoded, FString& error)
{
    const FString meshName = FPackageName::GetLongPackageAssetName(spec.SkeletalMeshPackageName);
    const FString skeletonName = FPackageName::GetLongPackageAssetName(spec.SkeletonPackageName);
    USkeletalMesh* existingMesh =
        LoadObject<USkeletalMesh>(nullptr, *(spec.SkeletalMeshPackageName + TEXT(".") + meshName));
    USkeleton* existingSkeleton =
        LoadObject<USkeleton>(nullptr, *(spec.SkeletonPackageName + TEXT(".") + skeletonName));
    if (existingMesh != nullptr && existingSkeleton != nullptr &&
        AssetMatches(*existingMesh, *existingSkeleton, spec, decoded))
    {
        return {existingMesh, existingSkeleton};
    }
    if (existingMesh != nullptr || existingSkeleton != nullptr)
    {
        error = TEXT("skeletal-mesh-existing-asset-mismatch");
        return {};
    }
    UPackage* meshPackage = CreatePackage(*spec.SkeletalMeshPackageName);
    UPackage* skeletonPackage = CreatePackage(*spec.SkeletonPackageName);
    USkeletalMesh* mesh =
        NewObject<USkeletalMesh>(meshPackage, *meshName, RF_Public | RF_Standalone);
    USkeleton* skeleton =
        NewObject<USkeleton>(skeletonPackage, *skeletonName, RF_Public | RF_Standalone);
    FMeshDescription description = BuildMeshDescription(decoded);
    const FReferenceSkeleton referenceSkeleton = BuildReferenceSkeleton(decoded);
    const TArray<FSkeletalMaterial> materials = BuildMaterials(decoded);
    TArray<const FMeshDescription*> descriptions{&description};
    FStaticToSkeletalMeshConverter::FInitializationParams parameters;
    parameters.Materials = materials;
    parameters.bRecomputeNormals = false;
    parameters.bRecomputeTangents = true;
    parameters.bCacheOptimize = true;
    if (!FStaticToSkeletalMeshConverter::InitializeSkeletalMeshFromMeshDescriptions(
            mesh, descriptions, referenceSkeleton, parameters))
    {
        error = TEXT("skeletal-mesh-build-failed");
        return {};
    }
    mesh->SetSkeleton(skeleton);
    if (!skeleton->MergeAllBonesToBoneTree(mesh, false))
    {
        error = TEXT("skeleton-bone-tree-merge-failed");
        return {};
    }
    meshPackage->GetMetaData().SetValue(mesh, ManifestHashKey, *spec.ManifestSha256);
    meshPackage->GetMetaData().SetValue(mesh, ImporterVersionKey, ImporterVersion);
    skeletonPackage->GetMetaData().SetValue(skeleton, ManifestHashKey, *spec.ManifestSha256);
    skeletonPackage->GetMetaData().SetValue(skeleton, ImporterVersionKey, ImporterVersion);
    mesh->PostEditChange();
    skeleton->PostEditChange();
    mesh->MarkPackageDirty();
    skeleton->MarkPackageDirty();
    if (!SaveAssetPackage(*skeletonPackage, *skeleton, spec.SkeletonPackageName) ||
        !SaveAssetPackage(*meshPackage, *mesh, spec.SkeletalMeshPackageName))
    {
        error = TEXT("skeletal-mesh-package-save-failed");
        return {};
    }
    return {mesh, skeleton};
}

bool LoadAndValidate(const FTMXYSkeletalMeshImportSpec& spec, FTMXYDecodedSkeletalGltf& decoded,
                     FString& error)
{
    FString gltfText;
    TArray<uint8> bufferBytes;
    if (!FFileHelper::LoadFileToString(gltfText, *spec.GltfPath) ||
        !FFileHelper::LoadFileToArray(bufferBytes, *spec.BufferPath) ||
        !DecodeTMXYSkeletalGltf(gltfText, bufferBytes, spec.BufferRelativePath, decoded, error))
    {
        if (error.IsEmpty())
        {
            error = TEXT("skeletal-mesh-payload-read-failed");
        }
        return false;
    }
    return ValidateMetadata(spec, decoded, error);
}
} // namespace

FTMXYSkeletalMeshImporter::FTMXYSkeletalMeshImporter(FString rebuildRoot)
    : RebuildRoot(FPaths::ConvertRelativePathToFull(MoveTemp(rebuildRoot)))
{
    FPaths::NormalizeDirectoryName(RebuildRoot);
}

FName FTMXYSkeletalMeshImporter::GetFormatId() const
{
    return TEXT("khronos.gltf-json");
}

FTMXYImportItemResult FTMXYSkeletalMeshImporter::ImportArtifact(const FTMXYImportRequest& request,
                                                                const FString& artifactId)
{
    FTMXYSkeletalMeshImportSpec spec;
    FTMXYDecodedSkeletalGltf decoded;
    FString error;
    const FImportedPair imported =
        ReadTMXYSkeletalMeshSpec(RebuildRoot, request, artifactId, spec, error) &&
                LoadAndValidate(spec, decoded, error)
            ? ImportSkeletalMesh(spec, decoded, error)
            : FImportedPair{};
    if (imported.Mesh == nullptr || imported.Skeleton == nullptr)
    {
        return MakeFailure(request, error);
    }
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("imported");
    result.ManifestSha256 = spec.ManifestSha256;
    result.OutputPackageName = spec.SkeletalMeshPackageName;
    result.ArtifactCount = 2;
    result.ImportedAssetCount = 2;
    result.bSucceeded = true;
    return result;
}

FTMXYReimportDecision
FTMXYSkeletalMeshImporter::EvaluateReimport(const FTMXYReimportRequest& request) const
{
    if (request.FormatId != GetFormatId() || !request.PackageName.StartsWith(SkeletalMeshRoot))
    {
        return {false, TEXT("skeletal-mesh-reimport-boundary-invalid")};
    }
    const FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                           ETMXYImportMode::SingleFixture};
    FTMXYSkeletalMeshImportSpec spec;
    FString error;
    if (!ReadTMXYSkeletalMeshSpec(RebuildRoot, importRequest, request.ArtifactId, spec, error) ||
        spec.SkeletalMeshPackageName != request.PackageName)
    {
        return {false, error.IsEmpty() ? TEXT("skeletal-mesh-reimport-target-mismatch") : error};
    }
    return {true, TEXT("skeletal-mesh-reimport-supported")};
}

FTMXYImportItemResult FTMXYSkeletalMeshImporter::Reimport(const FTMXYReimportRequest& request)
{
    const FTMXYReimportDecision decision = EvaluateReimport(request);
    const FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                           ETMXYImportMode::SingleFixture};
    if (!decision.bCanReimport)
    {
        return MakeFailure(importRequest, decision.Reason);
    }
    return ImportArtifact(importRequest, request.ArtifactId);
}
