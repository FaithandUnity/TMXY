#include "tmxy/terrain/ter_reader.hpp"
#include "tmxy/terrain/terrain_export.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace
{

[[nodiscard]] std::vector<std::byte> read_file(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream)
    {
        return {};
    }
    const auto end = stream.tellg();
    if (end <= 0 || end > std::numeric_limits<std::streamsize>::max())
    {
        return {};
    }
    std::vector<std::byte> bytes(static_cast<std::size_t>(end));
    stream.seekg(0);
    stream.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    return stream ? bytes : std::vector<std::byte>{};
}

[[nodiscard]] std::uint64_t fnv1a(const std::span<const std::byte> bytes)
{
    std::uint64_t hash = 14695981039346656037ULL;
    for (const auto value : bytes)
    {
        hash ^= std::to_integer<std::uint8_t>(value);
        hash *= 1099511628211ULL;
    }
    return hash;
}

[[nodiscard]] std::uint64_t fnv1a(const std::string_view text)
{
    return fnv1a(std::as_bytes(std::span(text.data(), text.size())));
}

struct ParsedSample final
{
    std::filesystem::path path;
    std::size_t byte_count{0};
    tmxy::terrain::TerrainTile tile;
    std::uint64_t json_hash{0};
    std::uint64_t height_hash{0};
    std::uint64_t layer_hash{0};
    std::uint64_t edge_hash{0};
};

[[nodiscard]] bool load_sample(const std::filesystem::path& path, ParsedSample& sample)
{
    const auto bytes = read_file(path);
    if (bytes.empty())
    {
        std::cerr << "FAILED: cannot read " << path << '\n';
        return false;
    }
    auto parsed = tmxy::terrain::TerReader::parse(bytes, path.filename().string());
    if (!parsed.has_value())
    {
        std::cerr << "FAILED: parse " << path << " at " << parsed.error().absolute_offset << '\n';
        return false;
    }
    sample.path = path;
    sample.byte_count = bytes.size();
    sample.tile = std::move(parsed).take_value();
    const auto json = tmxy::terrain::build_terrain_json(sample.tile, path.filename().string());
    const auto heights = tmxy::terrain::build_height_f32le(sample.tile);
    const auto layers = tmxy::terrain::build_layer_rgba8(sample.tile);
    const auto edges = tmxy::terrain::build_terrain_edges_csv(sample.tile);
    sample.json_hash = fnv1a(json);
    sample.height_hash = fnv1a(heights);
    sample.layer_hash = fnv1a(layers);
    sample.edge_hash = fnv1a(edges);
    return true;
}

[[nodiscard]] std::size_t vertex_index(const std::uint32_t edge, const std::uint32_t x,
                                       const std::uint32_t y)
{
    return (static_cast<std::size_t>(y) * static_cast<std::size_t>(edge)) +
           static_cast<std::size_t>(x);
}

struct EdgeDifference final
{
    std::uint32_t differing_samples{0};
    float maximum_absolute_height_delta{0.0F};
};

[[nodiscard]] EdgeDifference compare_horizontal(const tmxy::terrain::TerrainTile& left,
                                                const tmxy::terrain::TerrainTile& right)
{
    EdgeDifference result;
    const auto edge = left.edge_vertex_count;
    for (std::uint32_t sample = 0; sample < edge; ++sample)
    {
        const auto left_height = left.vertices[vertex_index(edge, edge - 1U, sample)].height;
        const auto right_height = right.vertices[vertex_index(edge, 0U, sample)].height;
        const auto delta = std::abs(left_height - right_height);
        if (delta != 0.0F)
        {
            ++result.differing_samples;
        }
        result.maximum_absolute_height_delta =
            std::max(result.maximum_absolute_height_delta, delta);
    }
    return result;
}

[[nodiscard]] EdgeDifference compare_vertical(const tmxy::terrain::TerrainTile& top,
                                              const tmxy::terrain::TerrainTile& bottom)
{
    EdgeDifference result;
    const auto edge = top.edge_vertex_count;
    for (std::uint32_t sample = 0; sample < edge; ++sample)
    {
        const auto top_height = top.vertices[vertex_index(edge, sample, edge - 1U)].height;
        const auto bottom_height = bottom.vertices[vertex_index(edge, sample, 0U)].height;
        const auto delta = std::abs(top_height - bottom_height);
        if (delta != 0.0F)
        {
            ++result.differing_samples;
        }
        result.maximum_absolute_height_delta =
            std::max(result.maximum_absolute_height_delta, delta);
    }
    return result;
}

void print_sample(const ParsedSample& sample)
{
    const auto& tile = sample.tile;
    std::cout << "TERRAIN_SAMPLE result=PASS name=" << sample.path.filename().string()
              << " bytes=" << sample.byte_count << " vertices=" << tile.vertices.size()
              << " edge=" << tile.edge_vertex_count << " tiles=" << tile.tile_count_per_axis
              << " layers=" << tile.active_layers.size()
              << " water=" << (tile.water_enabled ? 1 : 0)
              << " color=" << (tile.water_color.has_value() ? 1 : 0)
              << " min=" << tile.height.minimum << " max=" << tile.height.maximum
              << " json_fnv=" << sample.json_hash << " height_fnv=" << sample.height_hash
              << " layer_fnv=" << sample.layer_hash << " edge_fnv=" << sample.edge_hash << '\n';
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 2)
    {
        std::cerr << "usage: tmxy_ter_real_samples_test <terrain-root>\n";
        return 2;
    }
    const std::filesystem::path root(arguments[1]);
    ParsedSample minimum;
    ParsedSample maximum;
    ParsedSample world;
    ParsedSample world_right;
    ParsedSample world_bottom;
    if (!load_sample(root / "bqg2" / "bqg2_000_000.ter", minimum) ||
        !load_sample(root / "zyhsz" / "zyhsz_015_015.ter", maximum) ||
        !load_sample(root / "world_001_001.ter", world) ||
        !load_sample(root / "world_002_001.ter", world_right) ||
        !load_sample(root / "world_001_002.ter", world_bottom))
    {
        return 1;
    }
    const bool dimensions_valid =
        minimum.byte_count == 147485U && maximum.byte_count == 147501U &&
        minimum.tile.vertices.size() == 4096U && maximum.tile.vertices.size() == 4096U &&
        minimum.tile.edge_vertex_count == 64U && maximum.tile.tile_count_per_axis == 63U;
    const bool tails_valid =
        minimum.tile.active_layers.size() == 4U && !minimum.tile.water_color.has_value() &&
        maximum.tile.active_layers.size() == 4U && maximum.tile.water_color.has_value();
    const bool heights_valid =
        minimum.tile.height.minimum == 50.0F && minimum.tile.height.maximum == 50.0F &&
        world.tile.height.minimum < -15.0F && world.tile.height.maximum > 26.0F;
    const bool signatures_valid = minimum.json_hash == 17639934814673212859ULL &&
                                  minimum.height_hash == 8514296656032408357ULL &&
                                  minimum.layer_hash == 10596818350380000037ULL &&
                                  minimum.edge_hash == 17560127726405711754ULL &&
                                  maximum.json_hash == 12620290506198056086ULL &&
                                  maximum.height_hash == 11248824735641314085ULL &&
                                  maximum.layer_hash == 10596818350380000037ULL &&
                                  maximum.edge_hash == 16928986208558536282ULL &&
                                  world.json_hash == 17591700090707867230ULL &&
                                  world.height_hash == 17368412191409383455ULL &&
                                  world.layer_hash == 1961755361218945919ULL &&
                                  world.edge_hash == 8241279424783832823ULL;
    if (!dimensions_valid || !tails_valid || !heights_valid || !signatures_valid)
    {
        std::cerr << "FAILED: locked terrain sample invariants changed\n";
        return 1;
    }
    const auto horizontal = compare_horizontal(world.tile, world_right.tile);
    const auto vertical = compare_vertical(world.tile, world_bottom.tile);
    if (horizontal.differing_samples != 16U || vertical.differing_samples != 10U ||
        horizontal.maximum_absolute_height_delta < 0.032F ||
        horizontal.maximum_absolute_height_delta > 0.033F ||
        vertical.maximum_absolute_height_delta < 0.004F ||
        vertical.maximum_absolute_height_delta > 0.005F)
    {
        std::cerr << "FAILED: locked world adjacency evidence changed\n";
        return 1;
    }
    print_sample(minimum);
    print_sample(maximum);
    print_sample(world);
    std::cout << std::setprecision(std::numeric_limits<float>::max_digits10)
              << "TERRAIN_ADJACENCY result=PASS base=world_001_001.ter right_different="
              << horizontal.differing_samples
              << " right_max_delta=" << horizontal.maximum_absolute_height_delta
              << " bottom_different=" << vertical.differing_samples
              << " bottom_max_delta=" << vertical.maximum_absolute_height_delta << '\n';
    return 0;
}
