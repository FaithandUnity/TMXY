#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>

namespace tmxy::package
{

struct PackageInventory final
{
    std::string version{"unknown"};
    bool recognized{false};
    bool parsed{false};
    std::uint64_t file_bytes{0};
    std::uint64_t directory_bytes{0};
    std::uint64_t record_count{0};
    std::uint64_t distinct_class_count{0};
    std::uint64_t unknown_object_count{0};
    std::uint64_t metadata_fingerprint{0};
    std::string error{"unknown_version"};
    std::uint64_t error_offset{0};
};

[[nodiscard]] PackageInventory inspect_package(std::span<const std::byte> bytes);
[[nodiscard]] std::string package_inventory_to_json(const PackageInventory& inventory);

} // namespace tmxy::package
