#pragma once

#include "CoreMinimal.h"

struct FTMXYSkeletalInfluence
{
    TStaticArray<uint16, 4> Joints{};
    TStaticArray<float, 4> Weights{};
};

struct FTMXYSkeletalBone
{
    FString Name;
    int32 ParentIndex = INDEX_NONE;
    FQuat4f LocalRotation = FQuat4f::Identity;
    FVector3f LocalTranslationCm = FVector3f::ZeroVector;
};

struct FTMXYSkeletalPrimitive
{
    TArray<uint32> Indices;
    FString MaterialSlotName;
    bool bTwoSided = false;
};

struct FTMXYDecodedSkeletalGltf
{
    TArray<FVector3f> Positions;
    TArray<FVector3f> Normals;
    TArray<FVector2f> UV0;
    TArray<FTMXYSkeletalInfluence> Influences;
    TArray<FTMXYSkeletalBone> Bones;
    TArray<FTMXYSkeletalPrimitive> Primitives;
    FBox3f Bounds = FBox3f(ForceInit);
    int32 RootBoneCount = 0;
    int32 MaximumActiveInfluences = 0;
    bool bInverseBindOrientationPreserved = false;
};

bool DecodeTMXYSkeletalGltf(const FString& jsonText, const TArray<uint8>& bufferBytes,
                            const FString& expectedBufferUri, FTMXYDecodedSkeletalGltf& decoded,
                            FString& error);
