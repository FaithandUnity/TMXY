#pragma once

#include "CoreMinimal.h"

struct FTMXYTerrainTileSpec;

struct FTMXYDecodedTerrainTile
{
    TArray<float> Heights;
    TArray<FColor> LayerWeights;
    float MinimumHeight = 0.0F;
    float MaximumHeight = 0.0F;
};

bool DecodeTMXYTerrainTile(const FTMXYTerrainTileSpec& spec, FTMXYDecodedTerrainTile& decoded,
                           FString& error);
