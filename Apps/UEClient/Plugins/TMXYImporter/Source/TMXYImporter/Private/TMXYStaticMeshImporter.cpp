#include "TMXYStaticMeshImporter.h"

#include "Dom/JsonObject.h"
#include "Engine/StaticMesh.h"
#include "MeshDescription.h"
#include "MeshDescriptionBuilder.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "StaticMeshAttributes.h"
#include "TMXYGltfDecoder.h"
#include "TMXYStaticMeshManifest.h"
#include "UObject/MetaData.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"

namespace
{
constexpr TCHAR StaticMeshRoot[] = TEXT("/Game/TMXY/Golden/StaticMeshes/");
constexpr TCHAR ManifestHashKey[] = TEXT("TMXY.ManifestSha256");
constexpr TCHAR ImporterVersionKey[] = TEXT("TMXY.StaticMeshImporterVersion");
constexpr TCHAR ImporterVersion[] = TEXT("1");

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

bool ReadVector(const TSharedPtr<FJsonObject>& object, const TCHAR* field, FVector3f& vector)
{
    const TArray<TSharedPtr<FJsonValue>>* values = nullptr;
    if (!object.IsValid() || !object->TryGetArrayField(field, values) || values->Num() != 3)
    {
        return false;
    }
    double component[3]{};
    for (int32 index = 0; index < 3; ++index)
    {
        if (!(*values)[index].IsValid() || !(*values)[index]->TryGetNumber(component[index]) ||
            !FMath::IsFinite(component[index]))
        {
            return false;
        }
    }
    vector = FVector3f(static_cast<float>(component[0]), static_cast<float>(component[1]),
                       static_cast<float>(component[2]));
    return FMath::IsFinite(vector.X) && FMath::IsFinite(vector.Y) && FMath::IsFinite(vector.Z);
}

bool NearlyEqual(const FVector3f& left, const FVector3f& right, float tolerance = 0.05f)
{
    return FMath::Abs(left.X - right.X) <= tolerance && FMath::Abs(left.Y - right.Y) <= tolerance &&
           FMath::Abs(left.Z - right.Z) <= tolerance;
}

bool ValidateMetadata(const FTMXYStaticMeshImportSpec& spec, const FTMXYDecodedGltf& decoded,
                      FString& error)
{
    FString text;
    TSharedPtr<FJsonObject> root;
    const TArray<TSharedPtr<FJsonValue>>* sections = nullptr;
    const TSharedPtr<FJsonObject>* bounds = nullptr;
    int32 vertexCount = 0;
    int32 triangleCount = 0;
    int32 sectionCount = 0;
    int32 uvCount = 0;
    bool useLightMap = false;
    if (!FFileHelper::LoadFileToString(text, *spec.MetadataPath))
    {
        error = TEXT("static-mesh-metadata-read-failed");
        return false;
    }
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(text);
    if (!FJsonSerializer::Deserialize(reader, root) || !root.IsValid() ||
        !ReadExactInt(root, TEXT("vertex_count"), vertexCount) ||
        !ReadExactInt(root, TEXT("triangle_count"), triangleCount) ||
        !ReadExactInt(root, TEXT("section_count"), sectionCount) ||
        !ReadExactInt(root, TEXT("uv_channel_count"), uvCount) ||
        !root->TryGetBoolField(TEXT("use_light_map"), useLightMap) ||
        !root->TryGetObjectField(TEXT("ue_centimeter_bounds"), bounds) ||
        !root->TryGetArrayField(TEXT("sections"), sections))
    {
        error = TEXT("static-mesh-metadata-contract-invalid");
        return false;
    }
    FVector3f minimum;
    FVector3f maximum;
    if (!ReadVector(*bounds, TEXT("minimum"), minimum) ||
        !ReadVector(*bounds, TEXT("maximum"), maximum))
    {
        error = TEXT("static-mesh-metadata-bounds-invalid");
        return false;
    }
    if (vertexCount != spec.ExpectedVertexCount || vertexCount != decoded.Positions.Num())
    {
        error = TEXT("static-mesh-vertex-count-mismatch");
        return false;
    }
    if (triangleCount != spec.ExpectedTriangleCount)
    {
        error = TEXT("static-mesh-triangle-count-mismatch");
        return false;
    }
    if (sectionCount != spec.ExpectedMaterialSlotCount ||
        sectionCount != decoded.Primitives.Num() || sections->Num() != sectionCount)
    {
        error = TEXT("static-mesh-section-count-mismatch");
        return false;
    }
    if (uvCount != spec.ExpectedUvChannelCount || uvCount != decoded.UVChannels.Num())
    {
        error = TEXT("static-mesh-uv-count-mismatch");
        return false;
    }
    if (useLightMap != spec.bExpectedUseLightMap)
    {
        error = TEXT("static-mesh-light-map-policy-mismatch");
        return false;
    }
    if (!NearlyEqual(minimum, spec.ExpectedLegacyBoundsMinimum) ||
        !NearlyEqual(maximum, spec.ExpectedLegacyBoundsMaximum))
    {
        error = TEXT("static-mesh-declared-bounds-mismatch");
        return false;
    }
    if (!NearlyEqual(decoded.Bounds.Min, spec.ExpectedBoundsMinimum) ||
        !NearlyEqual(decoded.Bounds.Max, spec.ExpectedBoundsMaximum))
    {
        error = TEXT("static-mesh-decoded-bounds-mismatch");
        return false;
    }

    int32 observedTriangles = 0;
    for (int32 index = 0; index < sections->Num(); ++index)
    {
        const TSharedPtr<FJsonObject> section = (*sections)[index]->AsObject();
        FString material;
        bool twoSided = false;
        int32 slot = INDEX_NONE;
        int32 sectionTriangles = 0;
        if (!section.IsValid() || !ReadExactInt(section, TEXT("slot"), slot, true) ||
            slot != index || !ReadExactInt(section, TEXT("triangle_count"), sectionTriangles) ||
            !section->TryGetStringField(TEXT("material"), material) ||
            !section->TryGetBoolField(TEXT("two_sided"), twoSided) ||
            material != decoded.Primitives[index].MaterialSlotName ||
            twoSided != decoded.Primitives[index].bTwoSided ||
            decoded.Primitives[index].Indices.Num() / 3 != sectionTriangles)
        {
            error = TEXT("static-mesh-section-contract-mismatch");
            return false;
        }
        observedTriangles += sectionTriangles;
    }
    if (observedTriangles != triangleCount)
    {
        error = TEXT("static-mesh-triangle-count-mismatch");
        return false;
    }
    return true;
}

FMeshDescription BuildMeshDescription(const FTMXYDecodedGltf& decoded)
{
    FMeshDescription description;
    FStaticMeshAttributes attributes(description);
    attributes.Register();
    FMeshDescriptionBuilder builder;
    builder.SetMeshDescription(&description);
    builder.SetNumUVLayers(decoded.UVChannels.Num());
    builder.ReserveNewVertices(decoded.Positions.Num());

    TArray<FVertexID> vertices;
    vertices.Reserve(decoded.Positions.Num());
    for (const FVector3f& position : decoded.Positions)
    {
        vertices.Add(builder.AppendVertex(FVector(position)));
    }
    for (const FTMXYGltfPrimitive& primitive : decoded.Primitives)
    {
        const FPolygonGroupID group =
            builder.AppendPolygonGroup(FName(*primitive.MaterialSlotName));
        for (int32 index = 0; index < primitive.Indices.Num(); index += 3)
        {
            FVertexInstanceID instances[3];
            for (int32 corner = 0; corner < 3; ++corner)
            {
                const int32 vertexIndex = primitive.Indices[index + corner];
                instances[corner] = builder.AppendInstance(vertices[vertexIndex]);
                builder.SetInstanceNormal(instances[corner], FVector(decoded.Normals[vertexIndex]));
                for (int32 uvChannel = 0; uvChannel < decoded.UVChannels.Num(); ++uvChannel)
                {
                    builder.SetInstanceUV(instances[corner],
                                          FVector2D(decoded.UVChannels[uvChannel][vertexIndex]),
                                          uvChannel);
                }
            }
            builder.AppendTriangle(instances[0], instances[1], instances[2], group);
        }
    }
    return description;
}

bool AssetMatches(const UStaticMesh& mesh, const FTMXYStaticMeshImportSpec& spec,
                  const FTMXYDecodedGltf& decoded)
{
    UPackage* package = mesh.GetPackage();
    FMetaData* metadata = package != nullptr ? &package->GetMetaData() : nullptr;
    const FMeshDescription* sourceDescription = mesh.GetMeshDescription(0);
    if (metadata == nullptr || metadata->GetValue(&mesh, ManifestHashKey) != spec.ManifestSha256 ||
        metadata->GetValue(&mesh, ImporterVersionKey) != ImporterVersion ||
        sourceDescription == nullptr ||
        sourceDescription->Vertices().Num() != spec.ExpectedVertexCount ||
        mesh.GetNumTriangles(0) != spec.ExpectedTriangleCount ||
        mesh.GetNumSections(0) != spec.ExpectedMaterialSlotCount ||
        mesh.GetNumUVChannels(0) != spec.ExpectedUvChannelCount ||
        mesh.GetLightMapCoordinateIndex() != (spec.bExpectedUseLightMap ? 1 : 0) ||
        mesh.GetStaticMaterials().Num() != decoded.Primitives.Num())
    {
        return false;
    }
    const FBox bounds = mesh.GetBounds().GetBox();
    const FBox3f observedBounds(FVector3f(bounds.Min), FVector3f(bounds.Max));
    if (!NearlyEqual(observedBounds.Min, decoded.Bounds.Min) ||
        !NearlyEqual(observedBounds.Max, decoded.Bounds.Max))
    {
        return false;
    }
    for (int32 index = 0; index < decoded.Primitives.Num(); ++index)
    {
        const FStaticMaterial& material = mesh.GetStaticMaterials()[index];
        if (material.MaterialSlotName.ToString() != decoded.Primitives[index].MaterialSlotName ||
            material.ImportedMaterialSlotName.ToString() !=
                decoded.Primitives[index].MaterialSlotName)
        {
            return false;
        }
    }
    return true;
}

UStaticMesh* ImportStaticMesh(const FTMXYStaticMeshImportSpec& spec,
                              const FTMXYDecodedGltf& decoded, FString& error)
{
    const FString assetName = FPackageName::GetLongPackageAssetName(spec.PackageName);
    const FString objectPath = spec.PackageName + TEXT(".") + assetName;
    UStaticMesh* mesh = LoadObject<UStaticMesh>(nullptr, *objectPath);
    if (mesh != nullptr && AssetMatches(*mesh, spec, decoded))
    {
        return mesh;
    }

    UPackage* package = mesh != nullptr ? mesh->GetPackage() : CreatePackage(*spec.PackageName);
    package->FullyLoad();
    if (mesh == nullptr)
    {
        mesh = NewObject<UStaticMesh>(package, *assetName, RF_Public | RF_Standalone);
    }
    mesh->Modify();
    mesh->SetNumSourceModels(1);
    FMeshBuildSettings& buildSettings = mesh->GetSourceModel(0).BuildSettings;
    buildSettings.bRecomputeNormals = false;
    buildSettings.bRecomputeTangents = true;
    buildSettings.bUseMikkTSpace = true;
    buildSettings.bGenerateLightmapUVs = false;
    buildSettings.bRemoveDegenerates = false;
    mesh->SetLightMapCoordinateIndex(spec.bExpectedUseLightMap ? 1 : 0);
    TArray<FStaticMaterial>& materials = mesh->GetStaticMaterials();
    materials.Reset(decoded.Primitives.Num());
    for (const FTMXYGltfPrimitive& primitive : decoded.Primitives)
    {
        const FName slotName(*primitive.MaterialSlotName);
        materials.Emplace(nullptr, slotName, slotName);
    }

    FMeshDescription description = BuildMeshDescription(decoded);
    TArray<const FMeshDescription*> descriptions{&description};
    UStaticMesh::FBuildMeshDescriptionsParams params;
    params.bUseHashAsGuid = true;
    params.bCommitMeshDescription = true;
    params.bFastBuild = false;
    params.bBuildSimpleCollision = false;
    params.bAllowCpuAccess = false;
    if (!mesh->BuildFromMeshDescriptions(descriptions, params))
    {
        error = TEXT("static-mesh-build-failed");
        return nullptr;
    }
    package->GetMetaData().SetValue(mesh, ManifestHashKey, *spec.ManifestSha256);
    package->GetMetaData().SetValue(mesh, ImporterVersionKey, ImporterVersion);
    mesh->PostEditChange();
    mesh->MarkPackageDirty();
    const FString filename = FPackageName::LongPackageNameToFilename(
        spec.PackageName, FPackageName::GetAssetPackageExtension());
    FSavePackageArgs saveArgs;
    saveArgs.TopLevelFlags = RF_Public | RF_Standalone;
    saveArgs.SaveFlags = SAVE_None;
    if (!UPackage::SavePackage(package, mesh, *filename, saveArgs))
    {
        error = TEXT("static-mesh-package-save-failed");
        return nullptr;
    }
    return mesh;
}

bool LoadAndValidate(const FTMXYStaticMeshImportSpec& spec, FTMXYDecodedGltf& decoded,
                     FString& error)
{
    FString gltfText;
    TArray<uint8> bufferBytes;
    if (!FFileHelper::LoadFileToString(gltfText, *spec.GltfPath) ||
        !FFileHelper::LoadFileToArray(bufferBytes, *spec.BufferPath) ||
        !DecodeTMXYGltf(gltfText, bufferBytes, spec.BufferRelativePath, decoded, error))
    {
        if (error.IsEmpty())
        {
            error = TEXT("static-mesh-payload-read-failed");
        }
        return false;
    }
    return ValidateMetadata(spec, decoded, error);
}
} // namespace

FTMXYStaticMeshImporter::FTMXYStaticMeshImporter(FString rebuildRoot)
    : RebuildRoot(FPaths::ConvertRelativePathToFull(MoveTemp(rebuildRoot)))
{
    FPaths::NormalizeDirectoryName(RebuildRoot);
}

FName FTMXYStaticMeshImporter::GetFormatId() const
{
    return TEXT("khronos.gltf-json");
}

FTMXYImportItemResult FTMXYStaticMeshImporter::ImportArtifact(const FTMXYImportRequest& request,
                                                              const FString& artifactId)
{
    FTMXYStaticMeshImportSpec spec;
    FTMXYDecodedGltf decoded;
    FString error;
    if (!ReadTMXYStaticMeshSpec(RebuildRoot, request, artifactId, spec, error) ||
        !LoadAndValidate(spec, decoded, error) || ImportStaticMesh(spec, decoded, error) == nullptr)
    {
        return MakeFailure(request, error);
    }
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("imported");
    result.ManifestSha256 = spec.ManifestSha256;
    result.OutputPackageName = spec.PackageName;
    result.ArtifactCount = 2;
    result.ImportedAssetCount = 1;
    result.bSucceeded = true;
    return result;
}

FTMXYReimportDecision
FTMXYStaticMeshImporter::EvaluateReimport(const FTMXYReimportRequest& request) const
{
    if (request.FormatId != GetFormatId() || !request.PackageName.StartsWith(StaticMeshRoot))
    {
        return {false, TEXT("static-mesh-reimport-boundary-invalid")};
    }
    const FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                           ETMXYImportMode::SingleFixture};
    FTMXYStaticMeshImportSpec spec;
    FString error;
    if (!ReadTMXYStaticMeshSpec(RebuildRoot, importRequest, request.ArtifactId, spec, error) ||
        spec.PackageName != request.PackageName)
    {
        return {false, error.IsEmpty() ? TEXT("static-mesh-reimport-target-mismatch") : error};
    }
    return {true, TEXT("static-mesh-reimport-supported")};
}

FTMXYImportItemResult FTMXYStaticMeshImporter::Reimport(const FTMXYReimportRequest& request)
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
