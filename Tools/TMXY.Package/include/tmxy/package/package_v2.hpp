#pragma once

#include "tmxy/format/read_error.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::package
{

inline constexpr std::string_view kPackageV2Version = "QRENDER PACKAGE VER 2.0";
inline constexpr std::array<std::byte, 14> kPackageV2DirectoryPrefix{
    std::byte{0x03}, std::byte{0x00}, std::byte{0x76}, std::byte{0x65}, std::byte{0x72},
    std::byte{0x64}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x01},
    std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x3F},
};

enum class PackageV2ErrorCode : std::uint8_t
{
    read_failure = 1,
    invalid_version = 2,
    negative_directory_size = 3,
    directory_size_limit_exceeded = 4,
    directory_out_of_file = 5,
    directory_too_small = 6,
    invalid_directory_prefix = 7,
    negative_object_count = 8,
    object_count_limit_exceeded = 9,
    impossible_object_count = 10,
    negative_object_offset = 11,
    negative_object_size = 12,
    duplicate_object_name = 13,
    directory_trailing_bytes = 14,
    non_contiguous_object_range = 15,
    object_range_out_of_file = 16,
};

struct PackageV2Error final
{
    static constexpr std::uint32_t kSchemaVersion = 1;
    static constexpr std::uint64_t kNoRecordIndex = std::numeric_limits<std::uint64_t>::max();

    PackageV2ErrorCode code{PackageV2ErrorCode::read_failure};
    std::uint64_t absolute_offset{0};
    std::uint64_t record_index{kNoRecordIndex};
    std::string context;
    std::optional<format::ReadErrorCode> read_error_code;
};

struct PackageV2ObjectRecord final
{
    std::string name_bytes;
    std::string class_name_bytes;
    std::uint64_t offset{0};
    std::uint64_t size{0};
};

struct PackageV2Header final
{
    std::string version;
    std::vector<PackageV2ObjectRecord> records;
    std::uint64_t directory_offset{0};
    std::uint64_t directory_size{0};
    std::uint64_t header_size{0};
    std::uint64_t file_size{0};
};

[[nodiscard]] std::string_view to_string(PackageV2ErrorCode code) noexcept;
[[nodiscard]] std::uint64_t package_v2_metadata_fingerprint(const PackageV2Header& header) noexcept;

} // namespace tmxy::package
