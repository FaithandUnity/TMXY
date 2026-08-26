#include "tmxy/terrain/ter_reader.hpp"
#include "tmxy/terrain/terrain_error.hpp"
#include "tmxy/terrain/terrain_export.hpp"

#include <cstddef>
#include <filesystem>
#include <fstream>
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

[[nodiscard]] bool write_text(const std::filesystem::path& path, const std::string_view text)
{
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    stream.write(text.data(), static_cast<std::streamsize>(text.size()));
    return static_cast<bool>(stream);
}

[[nodiscard]] bool write_binary(const std::filesystem::path& path,
                                const std::span<const std::byte> bytes)
{
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    stream.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
    return static_cast<bool>(stream);
}

void print_error(const tmxy::terrain::TerrainError& error)
{
    std::cerr << R"({"error_schema_version":1,"code":")" << tmxy::terrain::to_string(error.code)
              << R"(","offset":)" << error.absolute_offset << R"(,"context":")" << error.context
              << R"("})" << '\n';
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 3)
    {
        std::cerr << "usage: tmxy_ter_export <ter-file> <output-stem>\n";
        return 2;
    }
    const std::filesystem::path source(arguments[1]);
    const auto bytes = read_file(source);
    if (bytes.empty())
    {
        std::cerr << "input-read-failed\n";
        return 3;
    }
    auto tile = tmxy::terrain::TerReader::parse(bytes, source.filename().string());
    if (!tile.has_value())
    {
        print_error(tile.error());
        return 4;
    }
    const auto json = tmxy::terrain::build_terrain_json(tile.value(), source.filename().string());
    const auto edges = tmxy::terrain::build_terrain_edges_csv(tile.value());
    const auto heights = tmxy::terrain::build_height_f32le(tile.value());
    const auto layers = tmxy::terrain::build_layer_rgba8(tile.value());
    const std::filesystem::path stem(arguments[2]);
    if (!stem.parent_path().empty())
    {
        std::error_code error;
        std::filesystem::create_directories(stem.parent_path(), error);
        if (error)
        {
            std::cerr << "output-directory-failed\n";
            return 5;
        }
    }
    if (!write_text(stem.string() + ".json", json) ||
        !write_text(stem.string() + ".edges.csv", edges) ||
        !write_binary(stem.string() + ".height.f32le", heights) ||
        !write_binary(stem.string() + ".layers.rgba8", layers))
    {
        std::cerr << "output-write-failed\n";
        return 6;
    }
    std::cout << json;
    return 0;
}
