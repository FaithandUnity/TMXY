#include "TMXYGltfDecoder.h"

#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
constexpr int32 MaxVertices = 4 * 1024 * 1024;
constexpr int32 MaxIndices = 50 * 1024 * 1024;
constexpr int32 MaxPrimitives = 4096;
constexpr int32 FloatComponent = 5126;
constexpr int32 UnsignedShortComponent = 5123;

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

bool ValidateAccessor(const FAccessor& accessor, const FView& view, int32 componentType,
                      const TCHAR* type, int32 componentCount, int32 maxCount)
{
    const int64 componentSize = componentType == FloatComponent ? sizeof(float) : sizeof(uint16);
    const int64 elementSize = componentSize * componentCount;
    return accessor.ComponentType == componentType && accessor.Type == type &&
           accessor.Count <= maxCount && accessor.Offset <= view.Length &&
           static_cast<int64>(accessor.Count) <= (view.Length - accessor.Offset) / elementSize;
}

template <int32 ComponentCount>
bool ReadFloats(const FAccessor& accessor, const TArray<FView>& views, const TArray<uint8>& bytes,
                TArray<TStaticArray<float, ComponentCount>>& output)
{
    const FView& view = views[accessor.ViewIndex];
    if (!ValidateAccessor(accessor, view, FloatComponent,
                          ComponentCount == 3 ? TEXT("VEC3") : TEXT("VEC2"), ComponentCount,
                          MaxVertices))
    {
        return false;
    }
    output.SetNumUninitialized(accessor.Count);
    const uint8* cursor = bytes.GetData() + view.Offset + accessor.Offset;
    for (TStaticArray<float, ComponentCount>& element : output)
    {
        for (int32 component = 0; component < ComponentCount; ++component)
        {
            FMemory::Memcpy(&element[component], cursor, sizeof(float));
            cursor += sizeof(float);
            if (!FMath::IsFinite(element[component]))
            {
                return false;
            }
        }
    }
    return true;
}

bool DecodeAttributes(const TArray<FAccessor>& accessors, const TArray<FView>& views,
                      const TArray<uint8>& bytes, int32 positionAccessor, int32 normalAccessor,
                      const TArray<int32>& uvAccessors, FTMXYDecodedGltf& decoded)
{
    if (!accessors.IsValidIndex(positionAccessor) || !accessors.IsValidIndex(normalAccessor) ||
        uvAccessors.Num() < 1 || uvAccessors.Num() > 2)
    {
        return false;
    }
    TArray<TStaticArray<float, 3>> positions;
    TArray<TStaticArray<float, 3>> normals;
    if (!ReadFloats<3>(accessors[positionAccessor], views, bytes, positions) ||
        !ReadFloats<3>(accessors[normalAccessor], views, bytes, normals) ||
        positions.Num() != normals.Num())
    {
        return false;
    }
    decoded.Positions.Reserve(positions.Num());
    decoded.Normals.Reserve(normals.Num());
    for (int32 index = 0; index < positions.Num(); ++index)
    {
        const FVector3f position(positions[index][2] * 100.0f, positions[index][0] * 100.0f,
                                 positions[index][1] * 100.0f);
        const FVector3f normal =
            FVector3f(normals[index][2], normals[index][0], normals[index][1]).GetSafeNormal();
        if (!FMath::IsFinite(position.X) || !FMath::IsFinite(position.Y) ||
            !FMath::IsFinite(position.Z) || !FMath::IsFinite(normal.X) ||
            !FMath::IsFinite(normal.Y) || !FMath::IsFinite(normal.Z) || normal.IsNearlyZero())
        {
            return false;
        }
        decoded.Positions.Add(position);
        decoded.Normals.Add(normal);
        decoded.Bounds += position;
    }
    for (const int32 uvAccessor : uvAccessors)
    {
        if (!accessors.IsValidIndex(uvAccessor))
        {
            return false;
        }
        TArray<TStaticArray<float, 2>> source;
        if (!ReadFloats<2>(accessors[uvAccessor], views, bytes, source) ||
            source.Num() != positions.Num())
        {
            return false;
        }
        TArray<FVector2f>& target = decoded.UVChannels.AddDefaulted_GetRef();
        target.Reserve(source.Num());
        for (const TStaticArray<float, 2>& uv : source)
        {
            target.Emplace(uv[0], uv[1]);
        }
    }
    return decoded.Bounds.IsValid != 0;
}

bool DecodeIndices(const FAccessor& accessor, const TArray<FView>& views,
                   const TArray<uint8>& bytes, int32 vertexCount, TArray<uint16>& indices)
{
    const FView& view = views[accessor.ViewIndex];
    if (!ValidateAccessor(accessor, view, UnsignedShortComponent, TEXT("SCALAR"), 1, MaxIndices) ||
        accessor.Count % 3 != 0)
    {
        return false;
    }
    indices.SetNumUninitialized(accessor.Count);
    const uint8* cursor = bytes.GetData() + view.Offset + accessor.Offset;
    for (uint16& index : indices)
    {
        FMemory::Memcpy(&index, cursor, sizeof(uint16));
        cursor += sizeof(uint16);
        if (index >= vertexCount)
        {
            return false;
        }
    }
    return true;
}
} // namespace

bool DecodeTMXYGltf(const FString& jsonText, const TArray<uint8>& bufferBytes,
                    const FString& expectedBufferUri, FTMXYDecodedGltf& decoded, FString& error)
{
    decoded = FTMXYDecodedGltf{};
    TSharedPtr<FJsonObject> root;
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(jsonText);
    const TSharedPtr<FJsonObject>* asset = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* buffers = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* viewsJson = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* accessorsJson = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* materials = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* meshes = nullptr;
    if (!FJsonSerializer::Deserialize(reader, root) || !root.IsValid() ||
        !root->TryGetObjectField(TEXT("asset"), asset) ||
        (*asset)->GetStringField(TEXT("version")) != TEXT("2.0") ||
        !root->TryGetArrayField(TEXT("buffers"), buffers) || buffers->Num() != 1 ||
        !root->TryGetArrayField(TEXT("bufferViews"), viewsJson) ||
        !root->TryGetArrayField(TEXT("accessors"), accessorsJson) ||
        !root->TryGetArrayField(TEXT("materials"), materials) ||
        !root->TryGetArrayField(TEXT("meshes"), meshes) || meshes->Num() != 1)
    {
        error = TEXT("gltf-contract-invalid");
        return false;
    }

    const TSharedPtr<FJsonObject> buffer = (*buffers)[0]->AsObject();
    FString bufferUri;
    int64 declaredBufferLength = 0;
    if (!buffer.IsValid() || !buffer->TryGetStringField(TEXT("uri"), bufferUri) ||
        bufferUri != expectedBufferUri ||
        !ReadExactInt64(buffer, TEXT("byteLength"), declaredBufferLength) ||
        declaredBufferLength != bufferBytes.Num())
    {
        error = TEXT("gltf-buffer-contract-invalid");
        return false;
    }

    TArray<FView> views;
    TArray<FAccessor> accessors;
    if (!ParseViews(*viewsJson, bufferBytes.Num(), views) ||
        !ParseAccessors(*accessorsJson, views, accessors))
    {
        error = TEXT("gltf-layout-invalid");
        return false;
    }

    const TSharedPtr<FJsonObject> mesh = (*meshes)[0]->AsObject();
    const TArray<TSharedPtr<FJsonValue>>* primitives = nullptr;
    if (!mesh.IsValid() || !mesh->TryGetArrayField(TEXT("primitives"), primitives) ||
        primitives->IsEmpty() || primitives->Num() > MaxPrimitives ||
        primitives->Num() != materials->Num())
    {
        error = TEXT("gltf-primitive-contract-invalid");
        return false;
    }

    int32 sharedPositionAccessor = INDEX_NONE;
    int32 sharedNormalAccessor = INDEX_NONE;
    TArray<int32> sharedUvAccessors;
    for (int32 primitiveIndex = 0; primitiveIndex < primitives->Num(); ++primitiveIndex)
    {
        const TSharedPtr<FJsonObject> primitive = (*primitives)[primitiveIndex]->AsObject();
        const TSharedPtr<FJsonObject>* attributes = nullptr;
        int32 mode = 4;
        int32 materialIndex = INDEX_NONE;
        int32 indicesAccessor = INDEX_NONE;
        int32 positionAccessor = INDEX_NONE;
        int32 normalAccessor = INDEX_NONE;
        if (!primitive.IsValid() || !primitive->TryGetObjectField(TEXT("attributes"), attributes) ||
            !ReadExactInt(primitive, TEXT("indices"), indicesAccessor) ||
            !ReadExactInt(primitive, TEXT("material"), materialIndex) ||
            materialIndex != primitiveIndex ||
            (primitive->HasField(TEXT("mode")) && !ReadExactInt(primitive, TEXT("mode"), mode)) ||
            mode != 4 || !ReadExactInt(*attributes, TEXT("POSITION"), positionAccessor) ||
            !ReadExactInt(*attributes, TEXT("NORMAL"), normalAccessor) ||
            !accessors.IsValidIndex(indicesAccessor))
        {
            error = TEXT("gltf-primitive-invalid");
            return false;
        }
        TArray<int32> uvAccessors;
        int32 uvAccessor = INDEX_NONE;
        if (!ReadExactInt(*attributes, TEXT("TEXCOORD_0"), uvAccessor))
        {
            error = TEXT("gltf-uv-contract-invalid");
            return false;
        }
        uvAccessors.Add(uvAccessor);
        if ((*attributes)->HasField(TEXT("TEXCOORD_1")))
        {
            if (!ReadExactInt(*attributes, TEXT("TEXCOORD_1"), uvAccessor))
            {
                error = TEXT("gltf-uv-contract-invalid");
                return false;
            }
            uvAccessors.Add(uvAccessor);
        }
        if (primitiveIndex == 0)
        {
            sharedPositionAccessor = positionAccessor;
            sharedNormalAccessor = normalAccessor;
            sharedUvAccessors = uvAccessors;
            if (!DecodeAttributes(accessors, views, bufferBytes, positionAccessor, normalAccessor,
                                  uvAccessors, decoded))
            {
                error = TEXT("gltf-attribute-data-invalid");
                return false;
            }
        }
        else if (positionAccessor != sharedPositionAccessor ||
                 normalAccessor != sharedNormalAccessor || uvAccessors != sharedUvAccessors)
        {
            error = TEXT("gltf-shared-attribute-contract-invalid");
            return false;
        }

        const TSharedPtr<FJsonObject> material = (*materials)[primitiveIndex]->AsObject();
        FTMXYGltfPrimitive decodedPrimitive;
        if (!material.IsValid() ||
            !material->TryGetStringField(TEXT("name"), decodedPrimitive.MaterialSlotName) ||
            decodedPrimitive.MaterialSlotName.IsEmpty() ||
            (material->HasField(TEXT("doubleSided")) &&
             !material->TryGetBoolField(TEXT("doubleSided"), decodedPrimitive.bTwoSided)) ||
            !DecodeIndices(accessors[indicesAccessor], views, bufferBytes, decoded.Positions.Num(),
                           decodedPrimitive.Indices))
        {
            error = TEXT("gltf-index-or-material-invalid");
            return false;
        }
        decoded.Primitives.Add(MoveTemp(decodedPrimitive));
    }
    return true;
}
