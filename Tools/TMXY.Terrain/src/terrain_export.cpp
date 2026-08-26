#include "tmxy/terrain/terrain_export.hpp"

#include <array>
#include <bit>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>

namespace tmxy::terrain
{
namespace
{

struct TileIdentity final
{
    std::string map_name;
    std::uint32_t x{0};
    std::uint32_t y{0};
};

[[nodiscard]] std::string json_string(const std::string_view value)
{
    std::ostringstream output;
    output << '"';
    for (const char raw_character : value)
    {
        const auto character = static_cast<unsigned char>(raw_character);
        if (character == '"')
        {
            output << "\\\"";
        }
        else if (character == '\\')
        {
            output << "\\\\";
        }
        else if (character < 0x20U || character >= 0x80U)
        {
            output << "\\u00" << std::hex << std::setw(2) << std::setfill('0')
                   << static_cast<unsigned int>(character) << std::dec;
        }
        else
        {
            output << static_cast<char>(character);
        }
    }
    output << '"';
    return output.str();
}

[[nodiscard]] bool parse_three_digits(const std::string_view text, std::uint32_t& value)
{
    if (text.size() != 3U)
    {
        return false;
    }
    const auto result = std::from_chars(text.data(), text.data() + text.size(), value);
    return result.ec == std::errc{} && result.ptr == text.data() + text.size();
}

[[nodiscard]] std::optional<TileIdentity> parse_identity(const std::string_view source_name)
{
    const auto slash = source_name.find_last_of("/\\");
    auto stem = source_name.substr(slash == std::string_view::npos ? 0U : slash + 1U);
    const auto dot = stem.find_last_of('.');
    if (dot != std::string_view::npos)
    {
        stem = stem.substr(0U, dot);
    }
    const auto y_separator = stem.find_last_of('_');
    if (y_separator == std::string_view::npos)
    {
        return std::nullopt;
    }
    const auto x_separator = stem.find_last_of('_', y_separator - 1U);
    if (x_separator == std::string_view::npos || x_separator == 0U)
    {
        return std::nullopt;
    }
    TileIdentity identity{.map_name = std::string(stem.substr(0U, x_separator))};
    if (!parse_three_digits(stem.substr(x_separator + 1U, y_separator - x_separator - 1U),
                            identity.x) ||
        !parse_three_digits(stem.substr(y_separator + 1U), identity.y))
    {
        return std::nullopt;
    }
    return identity;
}

void write_color(std::ostringstream& output, const Color4& color)
{
    output << '[' << color.red << ", " << color.green << ", " << color.blue << ", " << color.alpha
           << ']';
}

struct EdgeAddress final
{
    std::size_t side{0};
    std::uint32_t sample{0};
};

[[nodiscard]] std::size_t edge_vertex_index(const std::uint32_t edge_size,
                                            const EdgeAddress address)
{
    const auto edge = static_cast<std::size_t>(edge_size);
    const auto position = static_cast<std::size_t>(address.sample);
    switch (address.side)
    {
    case 0U:
        return position;
    case 1U:
        return (position * edge) + edge - 1U;
    case 2U:
        return ((edge - 1U) * edge) + position;
    default:
        return position * edge;
    }
}

void append_u32le(std::vector<std::byte>& output, const std::uint32_t value)
{
    for (unsigned int shift = 0U; shift < 32U; shift += 8U)
    {
        output.push_back(static_cast<std::byte>((value >> shift) & 0xFFU));
    }
}

} // namespace

std::string build_terrain_json(const TerrainTile& tile, const std::string_view source_name)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<double>::max_digits10);
    const auto identity = parse_identity(source_name);
    output << "{\n"
           << "  \"schema_version\": 1,\n"
           << "  \"source_contract\": \"little-endian QArchive TerrainVertex array plus water and "
              "active-layer tail\",\n"
           << "  \"source_name\": " << json_string(source_name) << ",\n"
           << "  \"tile_identity\": ";
    if (identity.has_value())
    {
        output << "{\"map_name\": " << json_string(identity->map_name) << ", \"x\": " << identity->x
               << ", \"y\": " << identity->y << "},\n";
    }
    else
    {
        output << "null,\n";
    }
    output << "  \"vertex_count\": " << tile.vertices.size() << ",\n"
           << "  \"edge_vertex_count\": " << tile.edge_vertex_count << ",\n"
           << "  \"tile_count_per_axis\": " << tile.tile_count_per_axis << ",\n"
           << R"(  "height_source_units": {"minimum": )" << tile.height.minimum
           << ", \"maximum\": " << tile.height.maximum << ", \"mean\": " << tile.height.mean
           << "},\n"
           << R"(  "water": {"enabled": )" << (tile.water_enabled ? "true" : "false")
           << ", \"height_source_units\": " << tile.water_height << ", \"color\": ";
    if (tile.water_color.has_value())
    {
        write_color(output, tile.water_color.value());
    }
    else
    {
        output << "null";
    }
    output << "},\n  \"active_layers\": [";
    for (std::size_t index = 0; index < tile.active_layers.size(); ++index)
    {
        output << (index == 0U ? "" : ", ") << tile.active_layers[index];
    }
    output << "],\n"
           << "  \"layout\": {\n"
           << "    \"vertex_order\": \"row-major, x changes fastest\",\n"
           << "    \"height_payload\": \"float32 little-endian source units\",\n"
           << "    \"layer_payload\": \"four uint8 source alpha channels per vertex\",\n"
           << "    \"edge_order\": [\"top\", \"right\", \"bottom\", \"left\"]\n"
           << "  },\n"
           << "  \"scale_policy\": \"source samples preserved; physical zone scale requires level "
              "metadata and is not inferred\"\n"
           << "}\n";
    return output.str();
}

std::string build_terrain_edges_csv(const TerrainTile& tile)
{
    static constexpr std::array<std::string_view, 4> kSideNames{"top", "right", "bottom", "left"};
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<float>::max_digits10)
           << "side,sample,height_source_units,normal_x,normal_y,normal_z,color_r,color_g,"
              "color_b,color_a,layer_0,layer_1,layer_2,layer_3\n";
    for (std::size_t side = 0; side < kSideNames.size(); ++side)
    {
        for (std::uint32_t sample = 0; sample < tile.edge_vertex_count; ++sample)
        {
            const auto index = edge_vertex_index(tile.edge_vertex_count,
                                                 EdgeAddress{.side = side, .sample = sample});
            const auto& vertex = tile.vertices[index];
            output << kSideNames[side] << ',' << sample << ',' << vertex.height << ','
                   << vertex.normal.x << ',' << vertex.normal.y << ',' << vertex.normal.z << ','
                   << vertex.color.red << ',' << vertex.color.green << ',' << vertex.color.blue
                   << ',' << vertex.color.alpha;
            for (const auto alpha : vertex.layer_alpha)
            {
                output << ',' << static_cast<unsigned int>(alpha);
            }
            output << '\n';
        }
    }
    return output.str();
}

std::vector<std::byte> build_height_f32le(const TerrainTile& tile)
{
    std::vector<std::byte> output;
    output.reserve(tile.vertices.size() * sizeof(float));
    for (const auto& vertex : tile.vertices)
    {
        append_u32le(output, std::bit_cast<std::uint32_t>(vertex.height));
    }
    return output;
}

std::vector<std::byte> build_layer_rgba8(const TerrainTile& tile)
{
    std::vector<std::byte> output;
    output.reserve(tile.vertices.size() * 4U);
    for (const auto& vertex : tile.vertices)
    {
        for (const auto alpha : vertex.layer_alpha)
        {
            output.push_back(static_cast<std::byte>(alpha));
        }
    }
    return output;
}

} // namespace tmxy::terrain
