#pragma once

#include "CoreMinimal.h"

enum class ETMXYImportMode : uint8
{
    ValidateOnly,
    SingleFixture,
    Batch
};

struct FTMXYImportRequest
{
    FString RequestId;
    FString RelativeManifestPath;
    ETMXYImportMode Mode = ETMXYImportMode::ValidateOnly;
};

struct FTMXYImportItemResult
{
    FString RequestId;
    FString RelativeManifestPath;
    FString Status;
    FString ErrorCode;
    FString ManifestSha256;
    FString OutputPackageName;
    int32 SourceCount = 0;
    int32 ArtifactCount = 0;
    int32 ImportedAssetCount = 0;
    bool bSucceeded = false;
};

struct FTMXYImportBatchResult
{
    TArray<FTMXYImportItemResult> Items;
    int32 SucceededCount = 0;
    int32 FailedCount = 0;
    int32 ImportedAssetCount = 0;
};

struct FTMXYReimportRequest
{
    FName FormatId;
    FString PackageName;
    FString RelativeManifestPath;
    FString ArtifactId;
};

struct FTMXYReimportDecision
{
    bool bCanReimport = false;
    FString Reason;
};
