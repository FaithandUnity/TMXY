#include "tmxy/animation/animation_error.hpp"
#include "tmxy/animation/animation_export.hpp"
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

[[nodiscard]] bool write_text(const std::filesystem::path& path, const std::string_view text)
{
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    stream.write(text.data(), static_cast<std::streamsize>(text.size()));
    return static_cast<bool>(stream);
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
    if (argument_count != 5)
    {
        std::cerr << "usage: tmxy_anim_export <package-file> <skeletal-mesh-object-name> "
                     "<anim-file> <output-stem>\n";
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
    const auto json = tmxy::animation::build_animation_json(binding.value());
    const auto root_motion = tmxy::animation::build_root_motion_csv(binding.value());
    const std::filesystem::path stem(arguments[4]);
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
        !write_text(stem.string() + ".root-motion.csv", root_motion))
    {
        std::cerr << "output-write-failed\n";
        return 6;
    }
    std::cout << json;
    return 0;
}
