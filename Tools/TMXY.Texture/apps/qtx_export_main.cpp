#include "tmxy/texture/package_texture_reader.hpp"
#include "tmxy/texture/qtx_reader.hpp"
#include "tmxy/texture/texture_error.hpp"
#include "tmxy/texture/texture_export.hpp"

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

[[nodiscard]] bool write_file(const std::filesystem::path& path,
                              const std::span<const std::byte> bytes)
{
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream)
    {
        return false;
    }
    if (!bytes.empty())
    {
        stream.write(reinterpret_cast<const char*>(bytes.data()),
                     static_cast<std::streamsize>(bytes.size()));
    }
    return static_cast<bool>(stream);
}

[[nodiscard]] bool write_text(const std::filesystem::path& path, const std::string_view text)
{
    return write_file(path, std::as_bytes(std::span(text.data(), text.size())));
}

void report_error(const tmxy::texture::TextureError& error)
{
    std::cerr << tmxy::texture::to_string(error.code) << " offset=" << error.absolute_offset
              << " context=" << error.context << '\n';
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 5)
    {
        std::cerr << "usage: tmxy_qtx_export <package-file> <full-object-name> <qtx-file> "
                     "<output-stem>\n";
        return 2;
    }
    const auto package_bytes = read_file(arguments[1]);
    const auto qtx_bytes = read_file(arguments[3]);
    if (package_bytes.empty() || qtx_bytes.empty())
    {
        std::cerr << "input-read-failed\n";
        return 3;
    }
    auto descriptor = tmxy::texture::read_package_texture_descriptor(package_bytes, arguments[2]);
    if (!descriptor.has_value())
    {
        report_error(descriptor.error());
        return 4;
    }
    auto texture = tmxy::texture::QtxReader{}.parse(descriptor.value().descriptor, qtx_bytes);
    if (!texture.has_value())
    {
        report_error(texture.error());
        return 5;
    }
    auto dds = tmxy::texture::build_dds(texture.value(), qtx_bytes);
    auto png = tmxy::texture::build_png(texture.value(), qtx_bytes);
    auto tga = tmxy::texture::build_tga(texture.value(), qtx_bytes);
    if (!dds.has_value() || !png.has_value() || !tga.has_value())
    {
        if (!dds.has_value())
        {
            report_error(dds.error());
        }
        else if (!png.has_value())
        {
            report_error(png.error());
        }
        else
        {
            report_error(tga.error());
        }
        return 6;
    }

    const std::filesystem::path stem(arguments[4]);
    const auto dds_path = std::filesystem::path(stem.string() + ".dds");
    const auto png_path = std::filesystem::path(stem.string() + ".png");
    const auto tga_path = std::filesystem::path(stem.string() + ".tga");
    const auto json_path = std::filesystem::path(stem.string() + ".json");
    const auto json = tmxy::texture::build_texture_json(texture.value(),
                                                        {.object_name = arguments[2],
                                                         .dds_name = dds_path.filename().string(),
                                                         .png_name = png_path.filename().string(),
                                                         .tga_name = tga_path.filename().string()});
    if (!write_file(dds_path, dds.value()) || !write_file(png_path, png.value()) ||
        !write_file(tga_path, tga.value()) || !write_text(json_path, json))
    {
        std::cerr << "output-write-failed\n";
        return 7;
    }
    std::cout << json;
    return 0;
}
