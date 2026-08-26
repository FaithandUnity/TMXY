#include "tmxy/animation/animation_error.hpp"
#include "tmxy/animation/animation_gltf.hpp"
#include "tmxy/animation/package_animation_reader.hpp"

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

[[nodiscard]] bool write_bytes(const std::filesystem::path& path,
                               const std::span<const std::byte> bytes)
{
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    stream.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
    return static_cast<bool>(stream);
}

[[nodiscard]] bool write_text(const std::filesystem::path& path, const std::string_view text)
{
    return write_bytes(path, std::as_bytes(std::span(text.data(), text.size())));
}

void print_error(const tmxy::animation::AnimationError& error)
{
    std::cerr << R"({"error_schema_version":1,"code":")" << tmxy::animation::to_string(error.code)
              << R"(","offset":)" << error.absolute_offset << R"(,"context":")" << error.context
              << R"("})" << '\n';
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count < 6)
    {
        std::cerr << "usage: tmxy_anim_gltf_export <package-file> <skeletal-mesh-object-name> "
                     "<anim-file> <output-stem> <clip-name> [clip-name...]\n";
        return 2;
    }
    const auto package_bytes = read_file(arguments[1]);
    const auto animation_bytes = read_file(arguments[3]);
    if (package_bytes.empty() || animation_bytes.empty())
    {
        std::cerr << "input-read-failed\n";
        return 3;
    }
    auto binding =
        tmxy::animation::bind_animation_set(package_bytes, arguments[2], animation_bytes);
    if (!binding.has_value())
    {
        print_error(binding.error());
        return 4;
    }
    std::vector<std::string_view> clip_names;
    for (int index = 5; index < argument_count; ++index)
    {
        clip_names.emplace_back(arguments[index]);
    }
    const std::filesystem::path stem(arguments[4]);
    const std::string buffer_name = stem.filename().string() + ".bin";
    auto gltf = tmxy::animation::build_selected_gltf2(binding.value(), buffer_name, clip_names);
    if (!gltf.has_value())
    {
        print_error(gltf.error());
        return 5;
    }
    if (!stem.parent_path().empty())
    {
        std::error_code error;
        std::filesystem::create_directories(stem.parent_path(), error);
        if (error)
        {
            std::cerr << "output-directory-failed\n";
            return 6;
        }
    }
    const auto& artifacts = gltf.value();
    if (!write_text(stem.string() + ".gltf", artifacts.json) ||
        !write_bytes(stem.string() + ".bin", artifacts.binary) ||
        !write_text(stem.string() + ".json", artifacts.metadata_json))
    {
        std::cerr << "output-write-failed\n";
        return 7;
    }
    std::cout << artifacts.metadata_json;
    return 0;
}
