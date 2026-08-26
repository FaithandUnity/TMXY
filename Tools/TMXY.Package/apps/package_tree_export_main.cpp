#include "tmxy/package/package_normalized_tree.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3_reader.hpp"

#include <cstddef>
#include <cstdint>
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

enum class PackageKind : std::uint8_t
{
    unknown = 0,
    v1 = 1,
    v2 = 2,
    v3 = 3,
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

[[nodiscard]] bool has_version(const std::span<const std::byte> bytes,
                               const std::string_view version)
{
    if (bytes.size() < 2U + version.size())
    {
        return false;
    }
    const auto length = static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[0])) |
                        (static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[1])) << 8U);
    if (length != version.size())
    {
        return false;
    }
    for (std::size_t index = 0; index < length; ++index)
    {
        if (std::to_integer<unsigned char>(bytes[index + 2U]) !=
            static_cast<unsigned char>(version[index]))
        {
            return false;
        }
    }
    return true;
}

[[nodiscard]] PackageKind detect_package(const std::span<const std::byte> bytes)
{
    if (has_version(bytes, tmxy::package::kPackageV1Version))
    {
        return PackageKind::v1;
    }
    if (has_version(bytes, tmxy::package::kPackageV2Version))
    {
        return PackageKind::v2;
    }
    if (has_version(bytes, tmxy::package::kPackageV3Version))
    {
        return PackageKind::v3;
    }
    return PackageKind::unknown;
}

[[nodiscard]] std::string export_tree(const std::span<const std::byte> bytes,
                                      const PackageKind kind, const std::string_view source_label)
{
    if (kind == PackageKind::v1)
    {
        const auto result = tmxy::package::PackageV1Reader{}.parse(bytes);
        return result.has_value()
                   ? tmxy::package::package_tree_to_json(tmxy::package::normalize_package_tree(
                         result.value(), std::string(source_label)))
                   : std::string{};
    }
    if (kind == PackageKind::v2)
    {
        const auto result = tmxy::package::PackageV2Reader{}.parse(bytes);
        return result.has_value()
                   ? tmxy::package::package_tree_to_json(tmxy::package::normalize_package_tree(
                         result.value(), std::string(source_label)))
                   : std::string{};
    }
    if (kind == PackageKind::v3)
    {
        const auto result = tmxy::package::PackageV3Reader{}.parse(bytes);
        return result.has_value()
                   ? tmxy::package::package_tree_to_json(tmxy::package::normalize_package_tree(
                         result.value(), std::string(source_label)))
                   : std::string{};
    }
    return {};
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 3)
    {
        std::cerr << "usage: tmxy_package_tree_export <package-file> <source-label>\n";
        return 2;
    }
    const auto bytes = read_file(arguments[1]);
    if (bytes.empty())
    {
        std::cerr << "package-read-failed\n";
        return 3;
    }
    const auto json = export_tree(bytes, detect_package(bytes), arguments[2]);
    if (json.empty())
    {
        std::cerr << "package-parse-failed\n";
        return 4;
    }
    std::cout << json << '\n';
    return 0;
}
