#include "tmxy/texture/package_texture_reader.hpp"
#include "tmxy/texture/qtx_reader.hpp"
#include "tmxy/texture/texture_export.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <string_view>
#include <vector>

namespace
{

struct Expected final
{
    tmxy::texture::TextureFormat format;
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t mips;
    std::uint64_t payload_size;
    tmxy::texture::AlphaCoverage alpha;
    bool build_previews;
};

struct SampleInput final
{
    const char* package_path;
    const char* object_name;
    const char* qtx_path;
    Expected expected;
};

[[nodiscard]] std::vector<std::byte> read_file(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream)
    {
        return {};
    }
    const auto end = stream.tellg();
    if (end < 0 || end > std::numeric_limits<std::streamsize>::max())
    {
        return {};
    }
    std::vector<std::byte> bytes(static_cast<std::size_t>(end));
    stream.seekg(0);
    if (!bytes.empty())
    {
        stream.read(reinterpret_cast<char*>(bytes.data()),
                    static_cast<std::streamsize>(bytes.size()));
    }
    return stream ? bytes : std::vector<std::byte>{};
}

[[nodiscard]] bool check_sample(const SampleInput input)
{
    const auto package = read_file(input.package_path);
    const auto qtx = read_file(input.qtx_path);
    auto descriptor = tmxy::texture::read_package_texture_descriptor(package, input.object_name);
    if (!descriptor.has_value())
    {
        std::cerr << input.object_name << ": descriptor failure\n";
        return false;
    }
    auto texture = tmxy::texture::QtxReader{}.parse(descriptor.value().descriptor, qtx);
    if (!texture.has_value())
    {
        std::cerr << input.object_name << ": qtx failure\n";
        return false;
    }
    const auto& value = texture.value();
    if (value.descriptor.format != input.expected.format ||
        value.descriptor.width != input.expected.width ||
        value.descriptor.height != input.expected.height ||
        value.descriptor.mip_count != input.expected.mips ||
        value.payload_size != input.expected.payload_size ||
        value.alpha_coverage != input.expected.alpha)
    {
        std::cerr << input.object_name
                  << ": metadata mismatch alpha=" << tmxy::texture::to_string(value.alpha_coverage)
                  << '\n';
        return false;
    }
    auto dds_first = tmxy::texture::build_dds(value, qtx);
    auto dds_second = tmxy::texture::build_dds(value, qtx);
    if (!dds_first.has_value() || !dds_second.has_value() ||
        dds_first.value() != dds_second.value())
    {
        std::cerr << input.object_name << ": dds determinism failure\n";
        return false;
    }
    std::uint64_t png_hash = 0;
    std::uint64_t tga_hash = 0;
    if (input.expected.build_previews)
    {
        auto png_first = tmxy::texture::build_png(value, qtx);
        auto png_second = tmxy::texture::build_png(value, qtx);
        auto tga_first = tmxy::texture::build_tga(value, qtx);
        auto tga_second = tmxy::texture::build_tga(value, qtx);
        if (!png_first.has_value() || !png_second.has_value() || !tga_first.has_value() ||
            !tga_second.has_value() || png_first.value() != png_second.value() ||
            tga_first.value() != tga_second.value())
        {
            std::cerr << input.object_name << ": preview determinism failure\n";
            return false;
        }
        png_hash = tmxy::texture::texture_bytes_fingerprint(png_first.value());
        tga_hash = tmxy::texture::texture_bytes_fingerprint(tga_first.value());
    }
    std::cout << input.object_name
              << " format=" << tmxy::texture::to_string(value.descriptor.format)
              << " size=" << value.descriptor.width << 'x' << value.descriptor.height
              << " mips=" << value.descriptor.mip_count
              << " alpha=" << tmxy::texture::to_string(value.alpha_coverage)
              << " dds_fnv=" << tmxy::texture::texture_bytes_fingerprint(dds_first.value())
              << " png_fnv=" << png_hash << " tga_fnv=" << tga_hash << '\n';
    return true;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 13)
    {
        std::cerr << "expected four package/object/qtx triples\n";
        return 2;
    }
    constexpr std::array<Expected, 4> expected{{
        {.format = tmxy::texture::TextureFormat::dxt1,
         .width = 8U,
         .height = 8U,
         .mips = 1U,
         .payload_size = 32U,
         .alpha = tmxy::texture::AlphaCoverage::opaque,
         .build_previews = true},
        {.format = tmxy::texture::TextureFormat::dxt5,
         .width = 4096U,
         .height = 4096U,
         .mips = 13U,
         .payload_size = 22369648U,
         .alpha = tmxy::texture::AlphaCoverage::opaque,
         .build_previews = false},
        {.format = tmxy::texture::TextureFormat::dxt5,
         .width = 16U,
         .height = 16U,
         .mips = 1U,
         .payload_size = 256U,
         .alpha = tmxy::texture::AlphaCoverage::transparent,
         .build_previews = true},
        {.format = tmxy::texture::TextureFormat::rgba8,
         .width = 512U,
         .height = 512U,
         .mips = 1U,
         .payload_size = 1048576U,
         .alpha = tmxy::texture::AlphaCoverage::translucent,
         .build_previews = true},
    }};
    for (std::size_t index = 0; index < expected.size(); ++index)
    {
        const auto argument = 1U + (index * 3U);
        if (!check_sample({.package_path = arguments[argument],
                           .object_name = arguments[argument + 1U],
                           .qtx_path = arguments[argument + 2U],
                           .expected = expected[index]}))
        {
            return 3;
        }
    }
    return 0;
}
