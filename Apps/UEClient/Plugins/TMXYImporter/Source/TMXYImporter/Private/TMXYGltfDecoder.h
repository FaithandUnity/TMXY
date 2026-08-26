#pragma once

#include "CoreMinimal.h"

struct FTMXYGltfPrimitive
{
    TArray<uint16> Indices;
    FString MaterialSlotName;
    bool bTwoSided = false;
};

struct FTMXYDecodedGltf
{
    TArray<FVector3f> Positions;
    TArray<FVector3f> Normals;
    TArray<TArray<FVector2f>> UVChannels;
    TArray<FTMXYGltfPrimitive> Primitives;
    FBox3f Bounds = FBox3f(ForceInit);
};

bool DecodeTMXYGltf(const FString& jsonText, const TArray<uint8>& bufferBytes,
                    const FString& expectedBufferUri, FTMXYDecodedGltf& decoded, FString& error);
