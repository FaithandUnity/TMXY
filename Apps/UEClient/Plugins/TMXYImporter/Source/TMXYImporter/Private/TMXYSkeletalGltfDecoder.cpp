#include "TMXYSkeletalGltfDecoder.h"

#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
constexpr int32 MaxVertices = 4 * 1024 * 1024;
constexpr int32 MaxIndices = 50 * 1024 * 1024;
constexpr int32 MaxBones = 4096;
constexpr int32 MaxPrimitives = 4096;
constexpr int32 FloatComponent = 5126;
constexpr int32 UnsignedShortComponent = 5123;
constexpr int32 UnsignedIntComponent = 5125;

struct FView
{
    int64 Offset = 0;
    int64 Length = 0;
};

struct FAccessor
{
    int32 ViewIndex = INDEX_NONE;
    int64 Offset = 0;
    int32 ComponentType = 0;
    int32 Count = 0;
    FString Type;
};

bool ReadExactInt(const TSharedPtr<FJsonObject>& object, const TCHAR* field, int32& value)
{
    double number = 0.0;
    if (!object.IsValid() || !object->TryGetNumberField(field, number) ||
        !FMath::IsFinite(number) || number < static_cast<double>(MIN_int32) ||
        number > static_cast<double>(MAX_int32) || number != FMath::FloorToDouble(number))
    {
        return false;
    }
    value = static_cast<int32>(number);
    return true;
}

bool ReadExactInt64(const TSharedPtr<FJsonObject>& object, const TCHAR* field, int64& value,
                    int64 defaultValue = -1)
{
    double number = 0.0;
    if (!object.IsValid() || !object->TryGetNumberField(field, number))
    {
        if (defaultValue < 0)
        {
            return false;
        }
        value = defaultValue;
        return true;
    }
    if (!FMath::IsFinite(number) || number < 0.0 || number > 9007199254740991.0 ||
        number != FMath::FloorToDouble(number))
    {
        return false;
    }
    value = static_cast<int64>(number);
    return true;
}

bool ParseViews(const TArray<TSharedPtr<FJsonValue>>& values, int64 bufferSize,
                TArray<FView>& views)
{
    views.Reserve(values.Num());
    for (const TSharedPtr<FJsonValue>& value : values)
    {
        const TSharedPtr<FJsonObject> object = value.IsValid() ? value->AsObject() : nullptr;
        FView view;
        int32 bufferIndex = INDEX_NONE;
        if (!ReadExactInt(object, TEXT("buffer"), bufferIndex) || bufferIndex != 0 ||
            !ReadExactInt64(object, TEXT("byteOffset"), view.Offset, 0) ||
            !ReadExactInt64(object, TEXT("byteLength"), view.Length) || view.Length < 1 ||
            view.Offset > bufferSize || view.Length > bufferSize - view.Offset ||
            object->HasField(TEXT("byteStride")))
        {
            return false;
        }
        views.Add(view);
    }
    return views.Num() > 0;
}

bool ParseAccessors(const TArray<TSharedPtr<FJsonValue>>& values, const TArray<FView>& views,
                    TArray<FAccessor>& accessors)
{
    accessors.Reserve(values.Num());
    for (const TSharedPtr<FJsonValue>& value : values)
    {
        const TSharedPtr<FJsonObject> object = value.IsValid() ? value->AsObject() : nullptr;
        FAccessor accessor;
        if (!ReadExactInt(object, TEXT("bufferView"), accessor.ViewIndex) ||
            !views.IsValidIndex(accessor.ViewIndex) ||
            !ReadExactInt64(object, TEXT("byteOffset"), accessor.Offset, 0) ||
            !ReadExactInt(object, TEXT("componentType"), accessor.ComponentType) ||
            !ReadExactInt(object, TEXT("count"), accessor.Count) || accessor.Count < 1 ||
            !object->TryGetStringField(TEXT("type"), accessor.Type) ||
            object->HasField(TEXT("sparse")) || object->HasField(TEXT("normalized")))
        {
            return false;
        }
        accessors.Add(MoveTemp(accessor));
    }
    return accessors.Num() > 0;
}

int64 ComponentSize(int32 componentType)
{
    if (componentType == FloatComponent || componentType == UnsignedIntComponent)
    {
        return 4;
    }
    return componentType == UnsignedShortComponent ? 2 : 0;
}

bool ValidateAccessor(const FAccessor& accessor, const FView& view, int32 componentType,
                      const TCHAR* type, int32 componentCount, int32 maxCount)
{
    const int64 componentSize = ComponentSize(componentType);
    const int64 elementSize = componentSize * componentCount;
    return componentSize > 0 && accessor.ComponentType == componentType && accessor.Type == type &&
           accessor.Count <= maxCount && accessor.Offset <= view.Length &&
           static_cast<int64>(accessor.Count) <= (view.Length - accessor.Offset) / elementSize;
}

template <int32 ComponentCount> const TCHAR* FloatType()
{
    if constexpr (ComponentCount == 2)
    {
        return TEXT("VEC2");
    }
    else if constexpr (ComponentCount == 3)
    {
        return TEXT("VEC3");
    }
    else if constexpr (ComponentCount == 4)
    {
        return TEXT("VEC4");
    }
    else
    {
        return TEXT("MAT4");
    }
}

template <int32 ComponentCount>
bool ReadFloats(const FAccessor& accessor, const TArray<FView>& views, const TArray<uint8>& bytes,
                int32 maxCount, TArray<TStaticArray<float, ComponentCount>>& output)
{
    const FView& view = views[accessor.ViewIndex];
    if (!ValidateAccessor(accessor, view, FloatComponent, FloatType<ComponentCount>(),
                          ComponentCount, maxCount))
    {
        return false;
    }
    output.SetNumUninitialized(accessor.Count);
    const uint8* cursor = bytes.GetData() + view.Offset + accessor.Offset;
    for (TStaticArray<float, ComponentCount>& element : output)
    {
        for (float& component : element)
        {
            FMemory::Memcpy(&component, cursor, sizeof(float));
            cursor += sizeof(float);
            if (!FMath::IsFinite(component))
            {
                return false;
            }
        }
    }
    return true;
}

bool ReadJoints(const FAccessor& accessor, const TArray<FView>& views, const TArray<uint8>& bytes,
                TArray<TStaticArray<uint16, 4>>& output)
{
    const FView& view = views[accessor.ViewIndex];
    if (!ValidateAccessor(accessor, view, UnsignedShortComponent, TEXT("VEC4"), 4, MaxVertices))
    {
        return false;
    }
    output.SetNumUninitialized(accessor.Count);
    const uint8* cursor = bytes.GetData() + view.Offset + accessor.Offset;
    for (TStaticArray<uint16, 4>& element : output)
    {
        for (uint16& component : element)
        {
            FMemory::Memcpy(&component, cursor, sizeof(uint16));
            cursor += sizeof(uint16);
        }
    }
    return true;
}

bool ReadJsonVector(const TSharedPtr<FJsonObject>& object, const TCHAR* field, int32 count,
                    TArray<double>& components)
{
    const TArray<TSharedPtr<FJsonValue>>* values = nullptr;
    if (!object.IsValid() || !object->TryGetArrayField(field, values) || values->Num() != count)
    {
        return false;
    }
    components.SetNumUninitialized(count);
    for (int32 index = 0; index < count; ++index)
    {
        if (!(*values)[index].IsValid() || !(*values)[index]->TryGetNumber(components[index]) ||
            !FMath::IsFinite(components[index]))
        {
            return false;
        }
    }
    return true;
}

bool ReadAttributeIndices(const TSharedPtr<FJsonObject>& attributes,
                          TStaticArray<int32, 5>& indices)
{
    const TCHAR* names[] = {TEXT("POSITION"), TEXT("NORMAL"), TEXT("TEXCOORD_0"), TEXT("JOINTS_0"),
                            TEXT("WEIGHTS_0")};
    for (int32 index = 0; index < 5; ++index)
    {
        if (!ReadExactInt(attributes, names[index], indices[index]))
        {
            return false;
        }
    }
    return true;
}

bool DecodeVertices(const TArray<FAccessor>& accessors, const TArray<FView>& views,
                    const TArray<uint8>& bytes, const TSharedPtr<FJsonObject>& attributes,
                    FTMXYDecodedSkeletalGltf& decoded)
{
    int32 positionIndex = INDEX_NONE;
    int32 normalIndex = INDEX_NONE;
    int32 uvIndex = INDEX_NONE;
    int32 jointsIndex = INDEX_NONE;
    int32 weightsIndex = INDEX_NONE;
    if (!ReadExactInt(attributes, TEXT("POSITION"), positionIndex) ||
        !ReadExactInt(attributes, TEXT("NORMAL"), normalIndex) ||
        !ReadExactInt(attributes, TEXT("TEXCOORD_0"), uvIndex) ||
        !ReadExactInt(attributes, TEXT("JOINTS_0"), jointsIndex) ||
        !ReadExactInt(attributes, TEXT("WEIGHTS_0"), weightsIndex) ||
        !accessors.IsValidIndex(positionIndex) || !accessors.IsValidIndex(normalIndex) ||
        !accessors.IsValidIndex(uvIndex) || !accessors.IsValidIndex(jointsIndex) ||
        !accessors.IsValidIndex(weightsIndex))
    {
        return false;
    }
    TArray<TStaticArray<float, 3>> positions;
    TArray<TStaticArray<float, 3>> normals;
    TArray<TStaticArray<float, 2>> uvs;
    TArray<TStaticArray<uint16, 4>> joints;
    TArray<TStaticArray<float, 4>> weights;
    if (!ReadFloats<3>(accessors[positionIndex], views, bytes, MaxVertices, positions) ||
        !ReadFloats<3>(accessors[normalIndex], views, bytes, MaxVertices, normals) ||
        !ReadFloats<2>(accessors[uvIndex], views, bytes, MaxVertices, uvs) ||
        !ReadJoints(accessors[jointsIndex], views, bytes, joints) ||
        !ReadFloats<4>(accessors[weightsIndex], views, bytes, MaxVertices, weights) ||
        positions.Num() != normals.Num() || positions.Num() != uvs.Num() ||
        positions.Num() != joints.Num() || positions.Num() != weights.Num())
    {
        return false;
    }
    decoded.Positions.Reserve(positions.Num());
    decoded.Normals.Reserve(positions.Num());
    decoded.UV0.Reserve(positions.Num());
    decoded.Influences.Reserve(positions.Num());
    for (int32 index = 0; index < positions.Num(); ++index)
    {
        const FVector3f position(positions[index][2] * 100.0F, positions[index][0] * 100.0F,
                                 positions[index][1] * 100.0F);
        const FVector3f normal =
            FVector3f(normals[index][2], normals[index][0], normals[index][1]).GetSafeNormal();
        if (normal.IsNearlyZero())
        {
            return false;
        }
        decoded.Positions.Add(position);
        decoded.Normals.Add(normal);
        decoded.UV0.Emplace(uvs[index][0], uvs[index][1]);
        decoded.Influences.Add({.Joints = joints[index], .Weights = weights[index]});
        decoded.Bounds += position;
    }
    return decoded.Bounds.IsValid != 0;
}

bool ValidateInfluences(FTMXYDecodedSkeletalGltf& decoded, int32 boneCount)
{
    for (const FTMXYSkeletalInfluence& influence : decoded.Influences)
    {
        float sum = 0.0F;
        int32 active = 0;
        for (int32 index = 0; index < 4; ++index)
        {
            const float weight = influence.Weights[index];
            if (weight < 0.0F || weight > 1.0F || influence.Joints[index] >= boneCount)
            {
                return false;
            }
            sum += weight;
            active += weight > UE_SMALL_NUMBER ? 1 : 0;
        }
        if (active < 1 || FMath::Abs(sum - 1.0F) > 0.0001F)
        {
            return false;
        }
        decoded.MaximumActiveInfluences = FMath::Max(decoded.MaximumActiveInfluences, active);
    }
    return true;
}

bool ValidateInverseBindOrientation(const TArray<TStaticArray<float, 16>>& matrices)
{
    for (const TStaticArray<float, 16>& matrix : matrices)
    {
        const float determinant = matrix[0] * (matrix[5] * matrix[10] - matrix[9] * matrix[6]) -
                                  matrix[4] * (matrix[1] * matrix[10] - matrix[9] * matrix[2]) +
                                  matrix[8] * (matrix[1] * matrix[6] - matrix[5] * matrix[2]);
        if (!FMath::IsFinite(determinant) || determinant <= 0.0F ||
            FMath::Abs(determinant - 1.0F) > 0.001F)
        {
            return false;
        }
    }
    return true;
}

bool DecodeBones(const TArray<TSharedPtr<FJsonValue>>& nodes, const TSharedPtr<FJsonObject>& skin,
                 const TArray<FAccessor>& accessors, const TArray<FView>& views,
                 const TArray<uint8>& bytes, FTMXYDecodedSkeletalGltf& decoded)
{
    const TArray<TSharedPtr<FJsonValue>>* joints = nullptr;
    int32 skeletonRoot = INDEX_NONE;
    int32 inverseAccessor = INDEX_NONE;
    if (!skin.IsValid() || !skin->TryGetArrayField(TEXT("joints"), joints) || joints->IsEmpty() ||
        joints->Num() > MaxBones || !ReadExactInt(skin, TEXT("skeleton"), skeletonRoot) ||
        !ReadExactInt(skin, TEXT("inverseBindMatrices"), inverseAccessor) || skeletonRoot != 0 ||
        !accessors.IsValidIndex(inverseAccessor) || nodes.Num() != joints->Num() + 1)
    {
        return false;
    }
    TArray<TStaticArray<float, 16>> inverseMatrices;
    if (!ReadFloats<16>(accessors[inverseAccessor], views, bytes, MaxBones, inverseMatrices) ||
        inverseMatrices.Num() != joints->Num() || !ValidateInverseBindOrientation(inverseMatrices))
    {
        return false;
    }
    decoded.bInverseBindOrientationPreserved = true;
    decoded.Bones.SetNum(joints->Num());
    TSet<FString> names;
    for (int32 index = 0; index < joints->Num(); ++index)
    {
        double nodeNumber = -1.0;
        if (!(*joints)[index].IsValid() || !(*joints)[index]->TryGetNumber(nodeNumber) ||
            nodeNumber != index)
        {
            return false;
        }
        const TSharedPtr<FJsonObject> node = nodes[index]->AsObject();
        TArray<double> translation;
        TArray<double> rotation;
        FString name;
        if (!node.IsValid() || !node->TryGetStringField(TEXT("name"), name) || name.IsEmpty() ||
            names.Contains(name) || !ReadJsonVector(node, TEXT("translation"), 3, translation) ||
            !ReadJsonVector(node, TEXT("rotation"), 4, rotation))
        {
            return false;
        }
        names.Add(name);
        FQuat4f quaternion(static_cast<float>(rotation[2]), static_cast<float>(rotation[0]),
                           static_cast<float>(rotation[1]), static_cast<float>(rotation[3]));
        if (quaternion.ContainsNaN() || quaternion.SizeSquared() <= UE_SMALL_NUMBER)
        {
            return false;
        }
        quaternion.Normalize();
        decoded.Bones[index].Name = MoveTemp(name);
        decoded.Bones[index].LocalRotation = quaternion;
        decoded.Bones[index].LocalTranslationCm = FVector3f(
            static_cast<float>(translation[2] * 100.0), static_cast<float>(translation[0] * 100.0),
            static_cast<float>(translation[1] * 100.0));
    }
    for (int32 parent = 0; parent < decoded.Bones.Num(); ++parent)
    {
        const TSharedPtr<FJsonObject> node = nodes[parent]->AsObject();
        const TArray<TSharedPtr<FJsonValue>>* children = nullptr;
        if (!node->TryGetArrayField(TEXT("children"), children))
        {
            continue;
        }
        for (const TSharedPtr<FJsonValue>& childValue : *children)
        {
            double childNumber = -1.0;
            if (!childValue.IsValid() || !childValue->TryGetNumber(childNumber) ||
                childNumber <= parent || childNumber >= decoded.Bones.Num() ||
                childNumber != FMath::FloorToDouble(childNumber) ||
                decoded.Bones[static_cast<int32>(childNumber)].ParentIndex != INDEX_NONE)
            {
                return false;
            }
            decoded.Bones[static_cast<int32>(childNumber)].ParentIndex = parent;
        }
    }
    decoded.RootBoneCount = 0;
    for (const FTMXYSkeletalBone& bone : decoded.Bones)
    {
        decoded.RootBoneCount += bone.ParentIndex == INDEX_NONE ? 1 : 0;
    }
    return decoded.RootBoneCount == 1 && ValidateInfluences(decoded, decoded.Bones.Num());
}

bool DecodeIndices(const FAccessor& accessor, const TArray<FView>& views,
                   const TArray<uint8>& bytes, int32 vertexCount, TArray<uint32>& indices)
{
    const FView& view = views[accessor.ViewIndex];
    if (!ValidateAccessor(accessor, view, UnsignedIntComponent, TEXT("SCALAR"), 1, MaxIndices) ||
        accessor.Count % 3 != 0)
    {
        return false;
    }
    indices.SetNumUninitialized(accessor.Count);
    const uint8* cursor = bytes.GetData() + view.Offset + accessor.Offset;
    for (uint32& index : indices)
    {
        FMemory::Memcpy(&index, cursor, sizeof(uint32));
        cursor += sizeof(uint32);
        if (index >= static_cast<uint32>(vertexCount))
        {
            return false;
        }
    }
    return true;
}

bool DecodePrimitives(const TArray<TSharedPtr<FJsonValue>>& primitives,
                      const TArray<TSharedPtr<FJsonValue>>& materials,
                      const TArray<FAccessor>& accessors, const TArray<FView>& views,
                      const TArray<uint8>& bytes, FTMXYDecodedSkeletalGltf& decoded)
{
    if (primitives.IsEmpty() || primitives.Num() > MaxPrimitives ||
        primitives.Num() != materials.Num())
    {
        return false;
    }
    TSharedPtr<FJsonObject> sharedAttributes;
    TStaticArray<int32, 5> sharedAttributeIndices{};
    for (int32 primitiveIndex = 0; primitiveIndex < primitives.Num(); ++primitiveIndex)
    {
        const TSharedPtr<FJsonObject> primitive = primitives[primitiveIndex]->AsObject();
        const TSharedPtr<FJsonObject>* attributes = nullptr;
        int32 indicesIndex = INDEX_NONE;
        int32 materialIndex = INDEX_NONE;
        int32 mode = 4;
        if (!primitive.IsValid() || !primitive->TryGetObjectField(TEXT("attributes"), attributes) ||
            !ReadExactInt(primitive, TEXT("indices"), indicesIndex) ||
            !ReadExactInt(primitive, TEXT("material"), materialIndex) ||
            materialIndex != primitiveIndex || !accessors.IsValidIndex(indicesIndex) ||
            (primitive->HasField(TEXT("mode")) && !ReadExactInt(primitive, TEXT("mode"), mode)) ||
            mode != 4)
        {
            return false;
        }
        TStaticArray<int32, 5> attributeIndices{};
        if (!ReadAttributeIndices(*attributes, attributeIndices))
        {
            return false;
        }
        if (primitiveIndex == 0)
        {
            sharedAttributes = *attributes;
            sharedAttributeIndices = attributeIndices;
            if (!DecodeVertices(accessors, views, bytes, sharedAttributes, decoded))
            {
                return false;
            }
        }
        else if (attributeIndices != sharedAttributeIndices)
        {
            return false;
        }
        const TSharedPtr<FJsonObject> material = materials[primitiveIndex]->AsObject();
        FTMXYSkeletalPrimitive output;
        if (!material.IsValid() ||
            !material->TryGetStringField(TEXT("name"), output.MaterialSlotName) ||
            output.MaterialSlotName.IsEmpty() ||
            (material->HasField(TEXT("doubleSided")) &&
             !material->TryGetBoolField(TEXT("doubleSided"), output.bTwoSided)) ||
            !DecodeIndices(accessors[indicesIndex], views, bytes, decoded.Positions.Num(),
                           output.Indices))
        {
            return false;
        }
        decoded.Primitives.Add(MoveTemp(output));
    }
    return true;
}
} // namespace

bool DecodeTMXYSkeletalGltf(const FString& jsonText, const TArray<uint8>& bufferBytes,
                            const FString& expectedBufferUri, FTMXYDecodedSkeletalGltf& decoded,
                            FString& error)
{
    decoded = FTMXYDecodedSkeletalGltf{};
    TSharedPtr<FJsonObject> root;
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(jsonText);
    const TSharedPtr<FJsonObject>* asset = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* buffers = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* viewsJson = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* accessorsJson = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* materials = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* meshes = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* nodes = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* skins = nullptr;
    if (!FJsonSerializer::Deserialize(reader, root) || !root.IsValid() ||
        !root->TryGetObjectField(TEXT("asset"), asset) ||
        (*asset)->GetStringField(TEXT("version")) != TEXT("2.0") ||
        !root->TryGetArrayField(TEXT("buffers"), buffers) || buffers->Num() != 1 ||
        !root->TryGetArrayField(TEXT("bufferViews"), viewsJson) ||
        !root->TryGetArrayField(TEXT("accessors"), accessorsJson) ||
        !root->TryGetArrayField(TEXT("materials"), materials) ||
        !root->TryGetArrayField(TEXT("meshes"), meshes) || meshes->Num() != 1 ||
        !root->TryGetArrayField(TEXT("nodes"), nodes) ||
        !root->TryGetArrayField(TEXT("skins"), skins) || skins->Num() != 1)
    {
        error = TEXT("skeletal-gltf-contract-invalid");
        return false;
    }
    const TSharedPtr<FJsonObject> buffer = (*buffers)[0]->AsObject();
    FString bufferUri;
    int64 declaredLength = 0;
    if (!buffer.IsValid() || !buffer->TryGetStringField(TEXT("uri"), bufferUri) ||
        bufferUri != expectedBufferUri ||
        !ReadExactInt64(buffer, TEXT("byteLength"), declaredLength) ||
        declaredLength != bufferBytes.Num())
    {
        error = TEXT("skeletal-gltf-buffer-invalid");
        return false;
    }
    TArray<FView> views;
    TArray<FAccessor> accessors;
    const TSharedPtr<FJsonObject> mesh = (*meshes)[0]->AsObject();
    const TArray<TSharedPtr<FJsonValue>>* primitives = nullptr;
    if (!ParseViews(*viewsJson, bufferBytes.Num(), views) ||
        !ParseAccessors(*accessorsJson, views, accessors) || !mesh.IsValid() ||
        !mesh->TryGetArrayField(TEXT("primitives"), primitives) ||
        !DecodePrimitives(*primitives, *materials, accessors, views, bufferBytes, decoded) ||
        !DecodeBones(*nodes, (*skins)[0]->AsObject(), accessors, views, bufferBytes, decoded))
    {
        error = TEXT("skeletal-gltf-payload-invalid");
        return false;
    }
    return true;
}
