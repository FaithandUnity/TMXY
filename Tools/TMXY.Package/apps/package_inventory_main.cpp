#include "tmxy/package/package_inventory.hpp"

#include <cstddef>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <optional>
#include <vector>

namespace
{

[[nodiscard]] std::optional<std::vector<std::byte>> read_file(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream)
    {
        return std::nullopt;
    }
    const auto end = stream.tellg();
    if (end < 0 || end > std::numeric_limits<std::streamsize>::max())
    {
        return std::nullopt;
    }
    std::vector<std::byte> bytes(static_cast<std::size_t>(end));
    stream.seekg(0);
    if (!bytes.empty())
    {
        stream.read(reinterpret_cast<char*>(bytes.data()),
                    static_cast<std::streamsize>(bytes.size()));
    }
    return stream ? std::optional<std::vector<std::byte>>(std::move(bytes)) : std::nullopt;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 2)
    {
        std::cerr << "usage: tmxy_package_inventory <package-file>\n";
        return 2;
    }
    const auto bytes = read_file(arguments[1]);
    if (!bytes.has_value())
    {
        std::cerr << "package-read-failed\n";
        return 3;
    }
    std::cout << tmxy::package::package_inventory_to_json(
                     tmxy::package::inspect_package(bytes.value()))
              << '\n';
    return 0;
}
