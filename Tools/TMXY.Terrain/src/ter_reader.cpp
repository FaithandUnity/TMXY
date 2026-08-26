#include "tmxy/terrain/ter_reader.hpp"

#include "tmxy/format/binary_reader.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <ranges>
#include <string>
#include <utility>
#include <vector>

namespace tmxy::terrain
{
namespace
{

constexpr std::int32_t kMaximumVertexCount = 4 * 1024 * 1024;
constexpr std::int32_t kMaximumLayerCount = 4;
constexpr std::int32_t kMaximumLayerIndex = 1024 * 1024;

[[nodiscard]] TerrainError read_failure(const format::ReadError& error)
{
    return TerrainError{
        .code = TerrainErrorCode::read_failure,
        .absolute_offset = error.absolute_offset,
        .context = error.context,
        .read_error_code = error.code,
    };
}

[[nodiscard]] TerrainError validation_failure(const TerrainErrorCode code,
                                              const std::uint64_t offset,
                                              const std::string_view context)
{
    return TerrainError{
        .code = code,
        .absolute_offset = offset,
        .context = std::string(context),
        .read_error_code = std::nullopt,
    };
}

[[nodiscard]] bool finite_color(const Color4& color) noexcept
{
    return std::isfinite(color.red) && std::isfinite(color.green) && std::isfinite(color.blue) &&
           std::isfinite(color.alpha);
}

[[nodiscard]] TerrainResult<TerrainVertex> read_vertex(format::BinaryReader& reader)
{
    const auto vertex_offset = reader.absolute_position();
    std::array<float, 8> fields{};
    for (float& field : fields)
    {
        auto value = reader.read_f32();
        if (!value.has_value())
        {
            return TerrainResult<TerrainVertex>::failure(read_failure(value.error()));
        }
        field = value.value();
    }
    auto alpha = reader.read_bytes(4U);
    if (!alpha.has_value())
    {
        return TerrainResult<TerrainVertex>::failure(read_failure(alpha.error()));
    }

    TerrainVertex vertex{
        .height = fields[0],
        .normal = {.x = fields[1], .y = fields[2], .z = fields[3]},
        .color = {.red = fields[4], .green = fields[5], .blue = fields[6], .alpha = fields[7]},
    };
    for (std::size_t index = 0; index < vertex.layer_alpha.size(); ++index)
    {
        vertex.layer_alpha[index] = std::to_integer<std::uint8_t>(alpha.value()[index]);
    }
    if (!std::isfinite(vertex.height) || !std::isfinite(vertex.normal.x) ||
        !std::isfinite(vertex.normal.y) || !std::isfinite(vertex.normal.z) ||
        !finite_color(vertex.color))
    {
        return TerrainResult<TerrainVertex>::failure(validation_failure(
            TerrainErrorCode::non_finite_vertex, vertex_offset, reader.context()));
    }
    return TerrainResult<TerrainVertex>::success(vertex);
}

[[nodiscard]] TerrainResult<Color4> read_color(format::BinaryReader& reader)
{
    const auto color_offset = reader.absolute_position();
    std::array<float, 4> fields{};
    for (float& field : fields)
    {
        auto value = reader.read_f32();
        if (!value.has_value())
        {
            return TerrainResult<Color4>::failure(read_failure(value.error()));
        }
        field = value.value();
    }
    Color4 color{
        .red = fields[0],
        .green = fields[1],
        .blue = fields[2],
        .alpha = fields[3],
    };
    if (!finite_color(color))
    {
        return TerrainResult<Color4>::failure(validation_failure(
            TerrainErrorCode::non_finite_water_color, color_offset, reader.context()));
    }
    return TerrainResult<Color4>::success(color);
}

[[nodiscard]] std::uint32_t square_edge(const std::int32_t vertex_count)
{
    const auto root = std::sqrt(static_cast<double>(vertex_count));
    return static_cast<std::uint32_t>(root);
}

[[nodiscard]] std::optional<TerrainError> validate_vertex_count(const format::BinaryReader& reader,
                                                                const std::int32_t vertex_count,
                                                                std::uint32_t& edge_vertex_count)
{
    if (vertex_count <= 0)
    {
        return validation_failure(TerrainErrorCode::invalid_vertex_count, 0U, reader.context());
    }
    if (vertex_count > kMaximumVertexCount)
    {
        return validation_failure(TerrainErrorCode::vertex_count_limit_exceeded, 0U,
                                  reader.context());
    }
    edge_vertex_count = square_edge(vertex_count);
    const auto square = static_cast<std::uint64_t>(edge_vertex_count) * edge_vertex_count;
    if (std::cmp_less(edge_vertex_count, 2U) || std::cmp_not_equal(square, vertex_count))
    {
        return validation_failure(TerrainErrorCode::non_square_vertex_grid, 0U, reader.context());
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<TerrainError>
read_vertex_plane(format::BinaryReader& reader, const std::int32_t vertex_count, TerrainTile& tile)
{
    tile.vertices.reserve(static_cast<std::size_t>(vertex_count));
    double height_sum = 0.0;
    for (std::int32_t index = 0; index < vertex_count; ++index)
    {
        auto vertex = read_vertex(reader);
        if (!vertex.has_value())
        {
            return vertex.error();
        }
        if (index == 0)
        {
            tile.height.minimum = vertex.value().height;
            tile.height.maximum = vertex.value().height;
        }
        else
        {
            tile.height.minimum = std::min(tile.height.minimum, vertex.value().height);
            tile.height.maximum = std::max(tile.height.maximum, vertex.value().height);
        }
        height_sum += static_cast<double>(vertex.value().height);
        tile.vertices.push_back(vertex.value());
    }
    tile.height.mean = height_sum / static_cast<double>(vertex_count);
    return std::nullopt;
}

[[nodiscard]] std::optional<TerrainError> read_water(format::BinaryReader& reader,
                                                     TerrainTile& tile)
{
    const auto enabled_offset = reader.absolute_position();
    auto enabled = reader.read_u8();
    if (!enabled.has_value())
    {
        return read_failure(enabled.error());
    }
    if (enabled.value() > 1U)
    {
        return validation_failure(TerrainErrorCode::invalid_water_boolean, enabled_offset,
                                  reader.context());
    }
    tile.water_enabled = enabled.value() != 0U;

    const auto height_offset = reader.absolute_position();
    auto height = reader.read_f32();
    if (!height.has_value())
    {
        return read_failure(height.error());
    }
    if (!std::isfinite(height.value()))
    {
        return validation_failure(TerrainErrorCode::non_finite_water_height, height_offset,
                                  reader.context());
    }
    tile.water_height = height.value();
    return std::nullopt;
}

[[nodiscard]] std::optional<TerrainError> read_layers(format::BinaryReader& reader,
                                                      TerrainTile& tile)
{
    const auto count_offset = reader.absolute_position();
    auto count_value = reader.read_i32();
    if (!count_value.has_value())
    {
        return read_failure(count_value.error());
    }
    const auto count = count_value.value();
    if (count < 0 || count > kMaximumLayerCount)
    {
        return validation_failure(TerrainErrorCode::invalid_layer_count, count_offset,
                                  reader.context());
    }
    tile.active_layers.reserve(static_cast<std::size_t>(count));
    for (std::int32_t index = 0; index < count; ++index)
    {
        const auto layer_offset = reader.absolute_position();
        auto layer = reader.read_i32();
        if (!layer.has_value())
        {
            return read_failure(layer.error());
        }
        if (layer.value() < 0 || layer.value() > kMaximumLayerIndex)
        {
            return validation_failure(TerrainErrorCode::invalid_layer_index, layer_offset,
                                      reader.context());
        }
        if (std::ranges::find(tile.active_layers, layer.value()) != tile.active_layers.end())
        {
            return validation_failure(TerrainErrorCode::duplicate_layer_index, layer_offset,
                                      reader.context());
        }
        tile.active_layers.push_back(layer.value());
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<TerrainError> read_optional_water_color(format::BinaryReader& reader,
                                                                    TerrainTile& tile)
{
    if (reader.remaining() == 0U)
    {
        return std::nullopt;
    }
    if (reader.remaining() != 16U)
    {
        return validation_failure(TerrainErrorCode::invalid_water_color_tail,
                                  reader.absolute_position(), reader.context());
    }
    auto color = read_color(reader);
    if (!color.has_value())
    {
        return color.error();
    }
    tile.water_color = color.value();
    return std::nullopt;
}

} // namespace

TerrainResult<TerrainTile> TerReader::parse(const std::span<const std::byte> bytes,
                                            std::string context)
{
    format::BinaryReader reader(bytes, format::ByteOrder::little_endian, 0U, std::move(context));
    auto vertex_count_value = reader.read_i32();
    if (!vertex_count_value.has_value())
    {
        return TerrainResult<TerrainTile>::failure(read_failure(vertex_count_value.error()));
    }
    const auto vertex_count = vertex_count_value.value();
    std::uint32_t edge_vertex_count = 0;
    if (const auto error = validate_vertex_count(reader, vertex_count, edge_vertex_count))
    {
        return TerrainResult<TerrainTile>::failure(error.value());
    }
    TerrainTile tile;
    tile.edge_vertex_count = edge_vertex_count;
    tile.tile_count_per_axis = edge_vertex_count - 1U;
    if (const auto error = read_vertex_plane(reader, vertex_count, tile))
    {
        return TerrainResult<TerrainTile>::failure(error.value());
    }
    if (const auto error = read_water(reader, tile))
    {
        return TerrainResult<TerrainTile>::failure(error.value());
    }
    if (const auto error = read_layers(reader, tile))
    {
        return TerrainResult<TerrainTile>::failure(error.value());
    }
    if (const auto error = read_optional_water_color(reader, tile))
    {
        return TerrainResult<TerrainTile>::failure(error.value());
    }
    return TerrainResult<TerrainTile>::success(std::move(tile));
}

} // namespace tmxy::terrain
