#include "tmxy/terrain/terrain_error.hpp"

namespace tmxy::terrain
{

std::string_view to_string(const TerrainErrorCode code) noexcept
{
    switch (code)
    {
    case TerrainErrorCode::read_failure:
        return "read_failure";
    case TerrainErrorCode::invalid_vertex_count:
        return "invalid_vertex_count";
    case TerrainErrorCode::vertex_count_limit_exceeded:
        return "vertex_count_limit_exceeded";
    case TerrainErrorCode::non_square_vertex_grid:
        return "non_square_vertex_grid";
    case TerrainErrorCode::non_finite_vertex:
        return "non_finite_vertex";
    case TerrainErrorCode::invalid_water_boolean:
        return "invalid_water_boolean";
    case TerrainErrorCode::non_finite_water_height:
        return "non_finite_water_height";
    case TerrainErrorCode::invalid_layer_count:
        return "invalid_layer_count";
    case TerrainErrorCode::invalid_layer_index:
        return "invalid_layer_index";
    case TerrainErrorCode::duplicate_layer_index:
        return "duplicate_layer_index";
    case TerrainErrorCode::invalid_water_color_tail:
        return "invalid_water_color_tail";
    case TerrainErrorCode::non_finite_water_color:
        return "non_finite_water_color";
    }
    return "unknown";
}

} // namespace tmxy::terrain
