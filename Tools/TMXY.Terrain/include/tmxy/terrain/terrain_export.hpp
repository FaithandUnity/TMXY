#pragma once

#include "tmxy/terrain/terrain_types.hpp"

#include <cstddef>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::terrain
{

[[nodiscard]] std::string build_terrain_json(const TerrainTile& tile, std::string_view source_name);
[[nodiscard]] std::string build_terrain_edges_csv(const TerrainTile& tile);
[[nodiscard]] std::vector<std::byte> build_height_f32le(const TerrainTile& tile);
[[nodiscard]] std::vector<std::byte> build_layer_rgba8(const TerrainTile& tile);

} // namespace tmxy::terrain
