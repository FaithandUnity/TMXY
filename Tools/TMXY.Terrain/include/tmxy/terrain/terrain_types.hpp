#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <vector>

namespace tmxy::terrain
{

struct Vec3 final
{
    float x{0.0F};
    float y{0.0F};
    float z{0.0F};
};

struct Color4 final
{
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
    float alpha{0.0F};
};

struct TerrainVertex final
{
    float height{0.0F};
    Vec3 normal;
    Color4 color;
    std::array<std::uint8_t, 4> layer_alpha{};
};

struct HeightStatistics final
{
    float minimum{0.0F};
    float maximum{0.0F};
    double mean{0.0};
};

struct TerrainTile final
{
    std::uint32_t edge_vertex_count{0};
    std::uint32_t tile_count_per_axis{0};
    std::vector<TerrainVertex> vertices;
    bool water_enabled{false};
    float water_height{0.0F};
    std::vector<std::int32_t> active_layers;
    std::optional<Color4> water_color;
    HeightStatistics height;
};

} // namespace tmxy::terrain
