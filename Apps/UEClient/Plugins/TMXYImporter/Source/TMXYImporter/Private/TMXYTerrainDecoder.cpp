#include "TMXYTerrainDecoder.h"

#include "Dom/JsonObject.h"
#include "Misc/FileHelper.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "TMXYTerrainManifest.h"

#include <bit>
#include <cstdint>

namespace
{
float ReadFloat32LittleEndian(const uint8* bytes)
{
    const uint32 bits = static_cast<uint32>(bytes[0]) | (static_cast<uint32>(bytes[1]) << 8U) |
                        (static_cast<uint32>(bytes[2]) << 16U) |
                        (static_cast<uint32>(bytes[3]) << 24U);
    return std::bit_cast<float>(bits);
}

bool ValidateMetadata(const FTMXYTerrainTileSpec& spec, const FString& text,
                      const FTMXYDecodedTerrainTile& decoded, FString& error)
{
    TSharedPtr<FJsonObject> metadata;
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(text);
    const TSharedPtr<FJsonObject>* identity = nullptr;
    const TSharedPtr<FJsonObject>* height = nullptr;
    FString mapName;
    double schemaVersion = 0.0;
    double vertexCount = 0.0;
    double edgeCount = 0.0;
    double tileCount = 0.0;
    double tileX = 0.0;
    double tileY = 0.0;
    double minimum = 0.0;
    double maximum = 0.0;
    if (!FJsonSerializer::Deserialize(reader, metadata) || !metadata.IsValid() ||
        !metadata->TryGetNumberField(TEXT("schema_version"), schemaVersion) ||
        schemaVersion != 1.0 || !metadata->TryGetNumberField(TEXT("vertex_count"), vertexCount) ||
        vertexCount != spec.ExpectedVertexCount ||
        !metadata->TryGetNumberField(TEXT("edge_vertex_count"), edgeCount) || edgeCount != 64.0 ||
        !metadata->TryGetNumberField(TEXT("tile_count_per_axis"), tileCount) || tileCount != 63.0 ||
        !metadata->TryGetObjectField(TEXT("tile_identity"), identity) ||
        !(*identity)->TryGetStringField(TEXT("map_name"), mapName) || mapName != TEXT("world") ||
        !(*identity)->TryGetNumberField(TEXT("x"), tileX) || tileX != spec.TileX ||
        !(*identity)->TryGetNumberField(TEXT("y"), tileY) || tileY != spec.TileY ||
        !metadata->TryGetObjectField(TEXT("height_source_units"), height) ||
        !(*height)->TryGetNumberField(TEXT("minimum"), minimum) ||
        !(*height)->TryGetNumberField(TEXT("maximum"), maximum) ||
        !FMath::IsNearlyEqual(static_cast<float>(minimum), decoded.MinimumHeight) ||
        !FMath::IsNearlyEqual(static_cast<float>(maximum), decoded.MaximumHeight))
    {
        error = TEXT("terrain-metadata-contract-invalid");
        return false;
    }
    return true;
}
} // namespace

bool DecodeTMXYTerrainTile(const FTMXYTerrainTileSpec& spec, FTMXYDecodedTerrainTile& decoded,
                           FString& error)
{
    TArray<uint8> heightBytes;
    TArray<uint8> layerBytes;
    FString metadataText;
    if (!FFileHelper::LoadFileToArray(heightBytes, *spec.HeightPath) ||
        !FFileHelper::LoadFileToArray(layerBytes, *spec.LayerPath) ||
        !FFileHelper::LoadFileToString(metadataText, *spec.MetadataPath))
    {
        error = TEXT("terrain-payload-read-failed");
        return false;
    }
    if (heightBytes.Num() != spec.ExpectedVertexCount * 4 ||
        layerBytes.Num() != spec.ExpectedVertexCount * 4)
    {
        error = TEXT("terrain-payload-size-invalid");
        return false;
    }
    decoded.Heights.Reset(spec.ExpectedVertexCount);
    decoded.LayerWeights.Reset(spec.ExpectedVertexCount);
    decoded.MinimumHeight = TNumericLimits<float>::Max();
    decoded.MaximumHeight = TNumericLimits<float>::Lowest();
    for (int32 index = 0; index < spec.ExpectedVertexCount; ++index)
    {
        const float value = ReadFloat32LittleEndian(heightBytes.GetData() + index * 4);
        if (!FMath::IsFinite(value))
        {
            error = TEXT("terrain-height-nonfinite");
            return false;
        }
        decoded.Heights.Add(value);
        decoded.MinimumHeight = FMath::Min(decoded.MinimumHeight, value);
        decoded.MaximumHeight = FMath::Max(decoded.MaximumHeight, value);
        const uint8* weights = layerBytes.GetData() + index * 4;
        decoded.LayerWeights.Emplace(weights[0], weights[1], weights[2], weights[3]);
    }
    if (!FMath::IsNearlyEqual(decoded.MinimumHeight, spec.ExpectedMinimumHeight) ||
        !FMath::IsNearlyEqual(decoded.MaximumHeight, spec.ExpectedMaximumHeight))
    {
        error = TEXT("terrain-height-range-mismatch");
        return false;
    }
    return ValidateMetadata(spec, metadataText, decoded, error);
}
