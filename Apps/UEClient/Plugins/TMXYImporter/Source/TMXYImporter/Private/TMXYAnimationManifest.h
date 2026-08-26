#pragma once

#include "CoreMinimal.h"
#include "TMXYImportTypes.h"

struct FTMXYAnimationClipSpec
{
    FString SourceName;
    FString PackageName;
    int32 SourceIndex = INDEX_NONE;
    int32 ExpectedFrameCount = 0;
    int32 ExpectedTrackCount = 0;
    double ExpectedSampledDurationSeconds = 0.0;
    double ExpectedLegacyLoopPeriodSeconds = 0.0;
    double ExpectedRootTranslationDistanceMeters = 0.0;
    double ExpectedMaximumEndpointTranslationMeters = 0.0;
    double ExpectedMaximumEndpointRotationDegrees = 0.0;
    bool bLegacySelfLoop = false;
    bool bExpectedRootMoving = false;
};

struct FTMXYAnimationImportSpec
{
    FString ManifestSha256;
    FString GltfPath;
    FString BufferPath;
    FString BufferRelativePath;
    FString MetadataPath;
    FString SkeletonPackageName;
    FString SkeletalMeshPackageName;
    FString SkeletonManifestPath;
    FString SkeletonManifestSha256;
    int32 ExpectedBoneCount = 0;
    int32 SampleRateNumerator = 0;
    int32 SampleRateDenominator = 0;
    TArray<FTMXYAnimationClipSpec> Clips;
};

bool ReadTMXYAnimationSpec(const FString& rebuildRoot, const FTMXYImportRequest& request,
                           const FString& artifactId, FTMXYAnimationImportSpec& spec,
                           FString& error);
