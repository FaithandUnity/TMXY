#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace tmxy::package
{

enum class PackageDirectoryVersion : std::uint8_t
{
    v2 = 2,
    v3 = 3,
};

struct PackageDirectoryOffset final
{
    PackageDirectoryVersion version{PackageDirectoryVersion::v2};
    std::uint64_t file_offset{0};
    std::size_t directory_size{0};
    std::uint64_t decoded_offset{0};
};

[[nodiscard]] std::vector<std::byte>
decode_package_directory(PackageDirectoryVersion version,
                         std::span<const std::byte> encoded_directory);

[[nodiscard]] std::vector<std::byte>
encode_package_directory(PackageDirectoryVersion version,
                         std::span<const std::byte> decoded_directory);

[[nodiscard]] std::uint64_t map_package_directory_offset(PackageDirectoryOffset offset) noexcept;

} // namespace tmxy::package
