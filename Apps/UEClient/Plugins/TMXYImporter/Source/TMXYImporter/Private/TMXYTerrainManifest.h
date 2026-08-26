#pragma once

#include "CoreMinimal.h"
#include "TMXYImportTypes.h"

struct FTMXYTerrainTileSpec
{
    FString FixtureId;
    FString PackageName;
    FString MetadataPath;
    FString HeightPath;
    FString LayerPath;
    int32 TileX = 0;
    int32 TileY = 0;
    int32 ExpectedVertexCount = 0;
    int32 ExpectedTriangleCount = 0;
    float ExpectedMinimumHeight = 0.0F;
    float ExpectedMaximumHeight = 0.0F;
};

struct FTMXYTerrainAdjacencySpec
{
    FString First;
    FString FirstEdge;
    FString Second;
    FString SecondEdge;
    int32 SampleCount = 0;
    int32 DifferingSampleCount = 0;
    double MaximumDeltaSourceUnits = 0.0;
    double MaximumDeltaCentimeters = 0.0;
};

struct FTMXYTerrainImportSpec
{
    FString ManifestSha256;
    TArray<FTMXYTerrainTileSpec> Tiles;
    TArray<FTMXYTerrainAdjacencySpec> Adjacencies;
    int32 EdgeVertexCount = 0;
    int32 CellsPerAxis = 0;
    float SourceUnitsPerCell = 0.0F;
    float CentimetersPerSourceUnit = 0.0F;
    float CellSpacingCentimeters = 0.0F;
    float ZoneSizeCentimeters = 0.0F;
    bool bPreserveExistingEdgeDifferences = false;
};

bool ReadTMXYTerrainSpec(const FString& rebuildRoot, const FTMXYImportRequest& request,
                         const FString& artifactId, FTMXYTerrainImportSpec& spec, FString& error);
