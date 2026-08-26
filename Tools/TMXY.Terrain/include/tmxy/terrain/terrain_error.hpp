#pragma once

#include "tmxy/format/read_error.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace tmxy::terrain
{

enum class TerrainErrorCode : std::uint8_t
{
    read_failure = 1,
    invalid_vertex_count = 2,
    vertex_count_limit_exceeded = 3,
    non_square_vertex_grid = 4,
    non_finite_vertex = 5,
    invalid_water_boolean = 6,
    non_finite_water_height = 7,
    invalid_layer_count = 8,
    invalid_layer_index = 9,
    duplicate_layer_index = 10,
    invalid_water_color_tail = 11,
    non_finite_water_color = 12,
};

struct TerrainError final
{
    static constexpr std::uint32_t kSchemaVersion = 1;

    TerrainErrorCode code{TerrainErrorCode::read_failure};
    std::uint64_t absolute_offset{0};
    std::string context;
    std::optional<format::ReadErrorCode> read_error_code;
};

[[nodiscard]] std::string_view to_string(TerrainErrorCode code) noexcept;

} // namespace tmxy::terrain
