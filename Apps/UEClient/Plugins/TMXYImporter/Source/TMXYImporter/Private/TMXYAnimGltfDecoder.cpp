#include "TMXYAnimGltfDecoder.h"

#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
bool ReadFloatAccessor(const TSharedPtr<FJsonObject>& root, const TArray<uint8>& bytes,
                       const int32 accessorIndex, const TCHAR* expectedType,
                       const int32 componentCount, TArray<float>& values)
{
    const TArray<TSharedPtr<FJsonValue>>* accessors = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* views = nullptr;
    if (!root->TryGetArrayField(TEXT("accessors"), accessors) ||
        !root->TryGetArrayField(TEXT("bufferViews"), views) ||
        !accessors->IsValidIndex(accessorIndex))
    {
        return false;
    }
    const TSharedPtr<FJsonObject> accessor = (*accessors)[accessorIndex]->AsObject();
    double viewNumber = -1.0;
    double componentType = 0.0;
    double countNumber = 0.0;
    FString type;
    if (!accessor.IsValid() || !accessor->TryGetNumberField(TEXT("bufferView"), viewNumber) ||
        !accessor->TryGetNumberField(TEXT("componentType"), componentType) ||
        componentType != 5126.0 || !accessor->TryGetNumberField(TEXT("count"), countNumber) ||
        countNumber <= 0.0 || countNumber > MAX_int32 ||
        countNumber != FMath::FloorToDouble(countNumber) ||
        !accessor->TryGetStringField(TEXT("type"), type) || type != expectedType)
    {
        return false;
    }
    const int32 viewIndex = static_cast<int32>(viewNumber);
    if (viewNumber != viewIndex || !views->IsValidIndex(viewIndex))
    {
        return false;
    }
    const TSharedPtr<FJsonObject> view = (*views)[viewIndex]->AsObject();
    double buffer = -1.0;
    double offset = 0.0;
    double length = -1.0;
    const int64 required = static_cast<int64>(countNumber) * componentCount * sizeof(float);
    if (!view.IsValid() || !view->TryGetNumberField(TEXT("buffer"), buffer) || buffer != 0.0 ||
        !view->TryGetNumberField(TEXT("byteOffset"), offset) || offset < 0.0 ||
        offset != FMath::FloorToDouble(offset) ||
        !view->TryGetNumberField(TEXT("byteLength"), length) || length != required ||
        offset + required > bytes.Num() || offset > MAX_int32 || required > MAX_int32)
    {
        return false;
    }
    values.SetNumUninitialized(static_cast<int32>(countNumber) * componentCount);
    FMemory::Memcpy(values.GetData(), bytes.GetData() + static_cast<int32>(offset),
                    static_cast<SIZE_T>(required));
    for (const float value : values)
    {
        if (!FMath::IsFinite(value))
        {
            return false;
        }
    }
    return true;
}

bool ReadSampler(const TSharedPtr<FJsonObject>& animation, const int32 samplerIndex,
                 int32& inputAccessor, int32& outputAccessor)
{
    const TArray<TSharedPtr<FJsonValue>>* samplers = nullptr;
    if (!animation->TryGetArrayField(TEXT("samplers"), samplers) ||
        !samplers->IsValidIndex(samplerIndex))
    {
        return false;
    }
    const TSharedPtr<FJsonObject> sampler = (*samplers)[samplerIndex]->AsObject();
    double input = -1.0;
    double output = -1.0;
    FString interpolation;
    if (!sampler.IsValid() || !sampler->TryGetNumberField(TEXT("input"), input) ||
        !sampler->TryGetNumberField(TEXT("output"), output) ||
        !sampler->TryGetStringField(TEXT("interpolation"), interpolation) ||
        interpolation != TEXT("LINEAR"))
    {
        return false;
    }
    inputAccessor = static_cast<int32>(input);
    outputAccessor = static_cast<int32>(output);
    return input == inputAccessor && output == outputAccessor;
}

bool ValidateChannel(const TSharedPtr<FJsonObject>& animation, const int32 channelIndex,
                     const int32 nodeIndex, const TCHAR* expectedPath)
{
    const TArray<TSharedPtr<FJsonValue>>* channels = nullptr;
    if (!animation->TryGetArrayField(TEXT("channels"), channels) ||
        !channels->IsValidIndex(channelIndex))
    {
        return false;
    }
    const TSharedPtr<FJsonObject> channel = (*channels)[channelIndex]->AsObject();
    const TSharedPtr<FJsonObject>* target = nullptr;
    double sampler = -1.0;
    double node = -1.0;
    FString path;
    return channel.IsValid() && channel->TryGetNumberField(TEXT("sampler"), sampler) &&
           sampler == channelIndex && channel->TryGetObjectField(TEXT("target"), target) &&
           (*target)->TryGetNumberField(TEXT("node"), node) && node == nodeIndex &&
           (*target)->TryGetStringField(TEXT("path"), path) && path == expectedPath;
}

bool DecodeTrack(const TSharedPtr<FJsonObject>& root, const TSharedPtr<FJsonObject>& animation,
                 const TArray<uint8>& bytes, const int32 trackIndex, const int32 timeAccessor,
                 const int32 frameCount, FTMXYAnimTrack& track)
{
    int32 translationInput = INDEX_NONE;
    int32 translationOutput = INDEX_NONE;
    int32 rotationInput = INDEX_NONE;
    int32 rotationOutput = INDEX_NONE;
    TArray<float> translations;
    TArray<float> rotations;
    if (!ReadSampler(animation, trackIndex * 2, translationInput, translationOutput) ||
        !ReadSampler(animation, trackIndex * 2 + 1, rotationInput, rotationOutput) ||
        translationInput != timeAccessor || rotationInput != timeAccessor ||
        !ValidateChannel(animation, trackIndex * 2, trackIndex, TEXT("translation")) ||
        !ValidateChannel(animation, trackIndex * 2 + 1, trackIndex, TEXT("rotation")) ||
        !ReadFloatAccessor(root, bytes, translationOutput, TEXT("VEC3"), 3, translations) ||
        !ReadFloatAccessor(root, bytes, rotationOutput, TEXT("VEC4"), 4, rotations) ||
        translations.Num() != frameCount * 3 || rotations.Num() != frameCount * 4)
    {
        return false;
    }
    track.PositionsCm.Reserve(frameCount);
    track.Rotations.Reserve(frameCount);
    for (int32 frame = 0; frame < frameCount; ++frame)
    {
        track.PositionsCm.Emplace(translations[frame * 3 + 2] * 100.0F,
                                  translations[frame * 3] * 100.0F,
                                  translations[frame * 3 + 1] * 100.0F);
        FQuat4f rotation(rotations[frame * 4 + 2], rotations[frame * 4], rotations[frame * 4 + 1],
                         rotations[frame * 4 + 3]);
        if (rotation.ContainsNaN() || rotation.SizeSquared() <= UE_SMALL_NUMBER)
        {
            return false;
        }
        rotation.Normalize();
        if (!track.Rotations.IsEmpty() && (track.Rotations.Last() | rotation) < -UE_SMALL_NUMBER)
        {
            return false;
        }
        track.Rotations.Add(rotation);
    }
    return true;
}

bool DecodeClip(const TSharedPtr<FJsonObject>& root, const TSharedPtr<FJsonObject>& animation,
                const TArray<uint8>& bytes, const int32 boneCount, FTMXYDecodedAnimClip& clip)
{
    const TArray<TSharedPtr<FJsonValue>>* samplers = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* channels = nullptr;
    int32 timeAccessor = INDEX_NONE;
    int32 ignoredOutput = INDEX_NONE;
    if (!animation.IsValid() || !animation->TryGetStringField(TEXT("name"), clip.Name) ||
        clip.Name.IsEmpty() || !animation->TryGetArrayField(TEXT("samplers"), samplers) ||
        !animation->TryGetArrayField(TEXT("channels"), channels) ||
        samplers->Num() != boneCount * 2 || channels->Num() != boneCount * 2 ||
        !ReadSampler(animation, 0, timeAccessor, ignoredOutput) ||
        !ReadFloatAccessor(root, bytes, timeAccessor, TEXT("SCALAR"), 1, clip.Times) ||
        clip.Times.IsEmpty())
    {
        return false;
    }
    for (int32 frame = 0; frame < clip.Times.Num(); ++frame)
    {
        if (clip.Times[frame] < 0.0F || (frame > 0 && clip.Times[frame] <= clip.Times[frame - 1]))
        {
            return false;
        }
    }
    clip.Tracks.SetNum(boneCount);
    for (int32 track = 0; track < boneCount; ++track)
    {
        if (!DecodeTrack(root, animation, bytes, track, timeAccessor, clip.Times.Num(),
                         clip.Tracks[track]))
        {
            return false;
        }
    }
    return true;
}
} // namespace

bool DecodeTMXYAnimGltf(const FString& gltfText, const TArray<uint8>& bufferBytes,
                        const FString& expectedBufferUri, const int32 expectedBoneCount,
                        const int32 expectedClipCount, FTMXYDecodedAnimSet& decoded, FString& error)
{
    TSharedPtr<FJsonObject> root;
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(gltfText);
    const TSharedPtr<FJsonObject>* asset = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* buffers = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* nodes = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* animations = nullptr;
    FString version;
    FString uri;
    double byteLength = -1.0;
    TSharedPtr<FJsonObject> buffer;
    if (!FJsonSerializer::Deserialize(reader, root) || !root.IsValid() ||
        !root->TryGetObjectField(TEXT("asset"), asset) || !asset->IsValid() ||
        !(*asset)->TryGetStringField(TEXT("version"), version) || version != TEXT("2.0") ||
        !root->TryGetArrayField(TEXT("buffers"), buffers) || buffers->Num() != 1 ||
        !(*buffers)[0].IsValid() || !(buffer = (*buffers)[0]->AsObject()).IsValid() ||
        !buffer->TryGetStringField(TEXT("uri"), uri) || uri != expectedBufferUri ||
        !buffer->TryGetNumberField(TEXT("byteLength"), byteLength) ||
        byteLength != bufferBytes.Num() || !root->TryGetArrayField(TEXT("nodes"), nodes) ||
        nodes->Num() != expectedBoneCount ||
        !root->TryGetArrayField(TEXT("animations"), animations) ||
        animations->Num() != expectedClipCount)
    {
        error = TEXT("animation-gltf-contract-invalid");
        return false;
    }
    TSet<FString> names;
    for (const TSharedPtr<FJsonValue>& node : *nodes)
    {
        FString name;
        const TSharedPtr<FJsonObject> object = node.IsValid() ? node->AsObject() : nullptr;
        if (!object.IsValid() || !object->TryGetStringField(TEXT("name"), name) || name.IsEmpty() ||
            names.Contains(name))
        {
            error = TEXT("animation-gltf-bone-invalid");
            return false;
        }
        names.Add(name);
        decoded.BoneNames.Add(MoveTemp(name));
    }
    for (const TSharedPtr<FJsonValue>& value : *animations)
    {
        FTMXYDecodedAnimClip clip;
        if (!DecodeClip(root, value->AsObject(), bufferBytes, expectedBoneCount, clip))
        {
            error = TEXT("animation-gltf-clip-invalid");
            return false;
        }
        decoded.Clips.Add(MoveTemp(clip));
    }
    return true;
}
