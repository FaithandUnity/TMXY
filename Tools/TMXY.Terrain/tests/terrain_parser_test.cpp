#include "tmxy/terrain/ter_reader.hpp"
#include "tmxy/terrain/terrain_error.hpp"
#include "tmxy/terrain/terrain_export.hpp"

#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

namespace
{

class TestContext final
{
  public:
    void expect(const bool condition, const std::string_view message)
    {
        if (!condition)
        {
            ++failures_;
            std::cerr << "FAILED: " << message << '\n';
        }
    }

    [[nodiscard]] int failures() const noexcept
    {
        return failures_;
    }

  private:
    int failures_{0};
};

void append_u8(std::vector<std::byte>& bytes, const std::uint8_t value)
{
    bytes.push_back(static_cast<std::byte>(value));
}

void append_i32(std::vector<std::byte>& bytes, const std::int32_t value)
{
    const auto raw = std::bit_cast<std::uint32_t>(value);
    for (unsigned int shift = 0U; shift < 32U; shift += 8U)
    {
        append_u8(bytes, static_cast<std::uint8_t>((raw >> shift) & 0xFFU));
    }
}

void append_f32(std::vector<std::byte>& bytes, const float value)
{
    append_i32(bytes, std::bit_cast<std::int32_t>(value));
}

struct VertexInput final
{
    float height{0.0F};
    std::uint8_t layer_zero{0};
};

void append_vertex(std::vector<std::byte>& bytes, const VertexInput input)
{
    append_f32(bytes, input.height);
    append_f32(bytes, 0.0F);
    append_f32(bytes, 0.0F);
    append_f32(bytes, 1.0F);
    append_f32(bytes, 1.0F);
    append_f32(bytes, 0.5F);
    append_f32(bytes, 0.25F);
    append_f32(bytes, 1.0F);
    append_u8(bytes, input.layer_zero);
    append_u8(bytes, 0U);
    append_u8(bytes, 0U);
    append_u8(bytes, 0U);
}

[[nodiscard]] std::vector<std::byte> make_terrain(const bool include_water_color = true,
                                                  const std::vector<std::int32_t>& active_layers = {
                                                      0, 2})
{
    std::vector<std::byte> bytes;
    append_i32(bytes, 4);
    append_vertex(bytes, {.height = 1.0F, .layer_zero = 255U});
    append_vertex(bytes, {.height = 2.0F, .layer_zero = 192U});
    append_vertex(bytes, {.height = 3.0F, .layer_zero = 128U});
    append_vertex(bytes, {.height = 4.0F, .layer_zero = 64U});
    append_u8(bytes, 1U);
    append_f32(bytes, 8.0F);
    append_i32(bytes, static_cast<std::int32_t>(active_layers.size()));
    for (const auto layer : active_layers)
    {
        append_i32(bytes, layer);
    }
    if (include_water_color)
    {
        append_f32(bytes, 0.1F);
        append_f32(bytes, 0.2F);
        append_f32(bytes, 0.3F);
        append_f32(bytes, 0.4F);
    }
    return bytes;
}

void test_valid_tile(TestContext& test)
{
    const auto parsed = tmxy::terrain::TerReader::parse(make_terrain(), "map_name_007_009.ter");
    test.expect(parsed.has_value(), "valid terrain parses");
    if (!parsed.has_value())
    {
        return;
    }
    const auto& tile = parsed.value();
    test.expect(tile.vertices.size() == 4U && tile.edge_vertex_count == 2U &&
                    tile.tile_count_per_axis == 1U,
                "grid dimensions derived from vertex count");
    test.expect(tile.height.minimum == 1.0F && tile.height.maximum == 4.0F &&
                    tile.height.mean == 2.5,
                "height statistics retained");
    test.expect(tile.water_enabled && tile.water_height == 8.0F && tile.water_color.has_value(),
                "water tail retained");
    test.expect(tile.active_layers == std::vector<std::int32_t>({0, 2}),
                "active layer order retained");

    const auto json = tmxy::terrain::build_terrain_json(tile, "map_name_007_009.ter");
    const auto edges = tmxy::terrain::build_terrain_edges_csv(tile);
    const auto heights = tmxy::terrain::build_height_f32le(tile);
    const auto layers = tmxy::terrain::build_layer_rgba8(tile);
    test.expect(json.find(R"("map_name": "map_name", "x": 7, "y": 9)") != std::string::npos,
                "filename tile identity exported from final coordinate suffixes");
    test.expect(edges.find("right,1,4") != std::string::npos &&
                    edges.find("left,1,3") != std::string::npos,
                "all natural-orientation edge samples exported");
    test.expect(heights.size() == 16U && layers.size() == 16U,
                "height and four-channel layer payload sizes deterministic");

    const auto legacy = tmxy::terrain::TerReader::parse(make_terrain(false), "legacy.ter");
    test.expect(legacy.has_value() && !legacy.value().water_color.has_value(),
                "legacy file without optional water color accepted");
}

void test_corruption(TestContext& test)
{
    std::vector<std::byte> non_square;
    append_i32(non_square, 3);
    const auto non_square_result = tmxy::terrain::TerReader::parse(non_square);
    test.expect(!non_square_result.has_value() &&
                    non_square_result.error().code ==
                        tmxy::terrain::TerrainErrorCode::non_square_vertex_grid,
                "non-square grid rejected before allocation");

    auto truncated = make_terrain();
    truncated.resize(20U);
    const auto truncated_result = tmxy::terrain::TerReader::parse(truncated);
    test.expect(!truncated_result.has_value() &&
                    truncated_result.error().code == tmxy::terrain::TerrainErrorCode::read_failure,
                "truncated vertex payload rejected");

    auto invalid_boolean = make_terrain();
    invalid_boolean[4U + (4U * 36U)] = std::byte{0x02};
    const auto boolean_result = tmxy::terrain::TerReader::parse(invalid_boolean);
    test.expect(!boolean_result.has_value() &&
                    boolean_result.error().code ==
                        tmxy::terrain::TerrainErrorCode::invalid_water_boolean,
                "non-boolean water flag rejected");

    const auto duplicate_result = tmxy::terrain::TerReader::parse(make_terrain(false, {1, 1}));
    test.expect(!duplicate_result.has_value() &&
                    duplicate_result.error().code ==
                        tmxy::terrain::TerrainErrorCode::duplicate_layer_index,
                "duplicate active layer rejected");

    auto trailing = make_terrain(false);
    trailing.push_back(std::byte{0x00});
    const auto trailing_result = tmxy::terrain::TerReader::parse(trailing);
    test.expect(!trailing_result.has_value() &&
                    trailing_result.error().code ==
                        tmxy::terrain::TerrainErrorCode::invalid_water_color_tail,
                "partial optional water color rejected");

    auto nan_vertex = make_terrain();
    const auto nan = std::bit_cast<std::uint32_t>(std::numeric_limits<float>::quiet_NaN());
    for (unsigned int index = 0U; index < 4U; ++index)
    {
        nan_vertex[4U + index] = static_cast<std::byte>((nan >> (index * 8U)) & 0xFFU);
    }
    const auto nan_result = tmxy::terrain::TerReader::parse(nan_vertex);
    test.expect(!nan_result.has_value() &&
                    nan_result.error().code == tmxy::terrain::TerrainErrorCode::non_finite_vertex,
                "non-finite vertex rejected");
}

} // namespace

int main()
{
    TestContext test;
    test_valid_tile(test);
    test_corruption(test);
    if (test.failures() != 0)
    {
        return 1;
    }
    std::cout << "terrain parser tests passed\n";
    return 0;
}
