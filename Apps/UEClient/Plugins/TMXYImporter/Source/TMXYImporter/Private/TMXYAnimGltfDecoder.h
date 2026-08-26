#pragma once

#include "CoreMinimal.h"

struct FTMXYAnimTrack
{
    TArray<FVector3f> PositionsCm;
    TArray<FQuat4f> Rotations;
};

struct FTMXYDecodedAnimClip
{
    FString Name;
    TArray<float> Times;
    TArray<FTMXYAnimTrack> Tracks;
};

struct FTMXYDecodedAnimSet
{
    TArray<FString> BoneNames;
    TArray<FTMXYDecodedAnimClip> Clips;
};

bool DecodeTMXYAnimGltf(const FString& gltfText, const TArray<uint8>& bufferBytes,
                        const FString& expectedBufferUri, int32 expectedBoneCount,
                        int32 expectedClipCount, FTMXYDecodedAnimSet& decoded, FString& error);
