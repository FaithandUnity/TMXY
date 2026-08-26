#include "tmxy/static_mesh/package_static_mesh_reader.hpp"
#include "tmxy/static_mesh/static_mesh_error.hpp"
#include "tmxy/static_mesh/static_mesh_export.hpp"
#include "tmxy/static_mesh/static_mesh_gltf.hpp"

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

[[nodiscard]] bool write_bytes(const std::filesystem::path& path,
                               const std::span<const std::byte> bytes)
{
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    stream.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
    return static_cast<bool>(stream);
}

void print_error(const tmxy::static_mesh::StaticMeshError& error)
{
    std::cerr << R"({"error_schema_version":1,"code":")" << tmxy::static_mesh::to_string(error.code)
              << R"(","offset":)" << error.absolute_offset << R"(,"context":")" << error.context
              << R"("})" << '\n';
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 5)
    {
        std::cerr << "usage: tmxy_sm_export <package-file> <object-name> <sm-file> "
                     "<output-stem>\n";
        return 2;
    }
    const auto package_bytes = read_file(arguments[1]);
    const auto sm_bytes = read_file(arguments[3]);
    if (package_bytes.empty() || sm_bytes.empty())
    {
        std::cerr << "input-read-failed\n";
        return 3;
    }
    auto binding = tmxy::static_mesh::bind_static_mesh(package_bytes, arguments[2], sm_bytes);
    if (!binding.has_value())
    {
        print_error(binding.error());
        return 4;
    }
    auto obj = tmxy::static_mesh::build_ue_obj(binding.value());
    if (!obj.has_value())
    {
        print_error(obj.error());
        return 5;
    }
    const auto json = tmxy::static_mesh::build_static_mesh_json(binding.value());
    const std::filesystem::path stem(arguments[4]);
    auto gltf = tmxy::static_mesh::build_gltf2(binding.value(), stem.filename().string() + ".bin");
    if (!gltf.has_value())
    {
        print_error(gltf.error());
        return 6;
    }
    if (!stem.parent_path().empty())
    {
        std::error_code error;
        std::filesystem::create_directories(stem.parent_path(), error);
        if (error)
        {
            std::cerr << "output-directory-failed\n";
            return 7;
        }
    }
    if (!write_text(stem.string() + ".obj", obj.value()) ||
        !write_text(stem.string() + ".json", json) ||
        !write_text(stem.string() + ".gltf", gltf.value().json) ||
        !write_bytes(stem.string() + ".bin", gltf.value().binary))
    {
        std::cerr << "output-write-failed\n";
        return 8;
    }
    std::cout << json;
    return 0;
}
