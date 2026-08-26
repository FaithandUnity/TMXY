#pragma once

#include "CoreMinimal.h"
#include "TMXYImportTypes.h"

struct FTMXYStaticMeshImportSpec
{
    FString ManifestSha256;
    FString GltfPath;
    FString GltfSha256;
    FString BufferPath;
    FString BufferRelativePath;
    FString MetadataPath;
    FString PackageName;
    FVector3f ExpectedBoundsMinimum = FVector3f::ZeroVector;
    FVector3f ExpectedBoundsMaximum = FVector3f::ZeroVector;
    FVector3f ExpectedLegacyBoundsMinimum = FVector3f::ZeroVector;
    FVector3f ExpectedLegacyBoundsMaximum = FVector3f::ZeroVector;
    int32 ExpectedVertexCount = 0;
    int32 ExpectedTriangleCount = 0;
    int32 ExpectedMaterialSlotCount = 0;
    int32 ExpectedUvChannelCount = 0;
    bool bExpectedUseLightMap = false;
    bool bPreserveWinding = false;
    bool bRecomputeTangents = false;
};

bool ReadTMXYStaticMeshSpec(const FString& rebuildRoot, const FTMXYImportRequest& request,
                            const FString& artifactId, FTMXYStaticMeshImportSpec& spec,
                            FString& error);
