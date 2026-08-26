#pragma once

#include "CoreMinimal.h"
#include "TMXYImportTypes.h"

struct FTMXYSkeletalMeshImportSpec
{
    FString ManifestSha256;
    FString GltfPath;
    FString BufferPath;
    FString BufferRelativePath;
    FString MetadataPath;
    FString SkeletalMeshPackageName;
    FString SkeletonPackageName;
    FString ExpectedRootBoneName;
    FVector3f ExpectedBoundsMinimum = FVector3f::ZeroVector;
    FVector3f ExpectedBoundsMaximum = FVector3f::ZeroVector;
    int32 ExpectedSourceVertexCount = 0;
    int32 ExpectedTriangleCount = 0;
    int32 ExpectedMaterialSlotCount = 0;
    int32 ExpectedBoneCount = 0;
    int32 ExpectedRootBoneCount = 0;
    int32 ExpectedMaximumActiveInfluences = 0;
    int32 ExpectedUnweightedSentinelCount = 0;
    bool bPreserveWinding = false;
    bool bRecomputeTangents = false;
};

bool ReadTMXYSkeletalMeshSpec(const FString& rebuildRoot, const FTMXYImportRequest& request,
                              const FString& artifactId, FTMXYSkeletalMeshImportSpec& spec,
                              FString& error);
