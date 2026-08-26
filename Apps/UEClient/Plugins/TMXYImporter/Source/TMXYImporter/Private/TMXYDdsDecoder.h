#pragma once

#include "CoreMinimal.h"

struct FTMXYDecodedDds
{
    TArray<uint8> Bgra8MipData;
    FString LegacyFormat;
    int32 Width = 0;
    int32 Height = 0;
    int32 MipCount = 0;
};

bool DecodeTMXYDds(const TArray<uint8>& bytes, FTMXYDecodedDds& decoded, FString& error);
