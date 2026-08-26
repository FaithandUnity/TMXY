#pragma once

#include "tmxy/terrain/terrain_result.hpp"
#include "tmxy/terrain/terrain_types.hpp"

#include <cstddef>
#include <span>
#include <string>

namespace tmxy::terrain
{

class TerReader final
{
  public:
    [[nodiscard]] static TerrainResult<TerrainTile> parse(std::span<const std::byte> bytes,
                                                          std::string context = {});
};

} // namespace tmxy::terrain
