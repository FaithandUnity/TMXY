#pragma once

#include "tmxy/format/read_error.hpp"

#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::package
{

inline constexpr std::string_view kPackageV1Version = "QRENDER PACKAGE VER 1.0";

enum class PackageV1ErrorCode : std::uint8_t
{
    read_failure = 1,
    invalid_version = 2,
    negative_object_count = 3,
    object_count_limit_exceeded = 4,
    impossible_object_count = 5,
    negative_object_offset = 6,
    negative_object_size = 7,
    duplicate_object_name = 8,
    non_contiguous_object_range = 9,
    object_range_out_of_file = 10,
};

struct PackageV1Error final
{
    static constexpr std::uint32_t kSchemaVersion = 1;
    static constexpr std::uint64_t kNoRecordIndex = std::numeric_limits<std::uint64_t>::max();

    PackageV1ErrorCode code{PackageV1ErrorCode::read_failure};
    std::uint64_t absolute_offset{0};
    std::uint64_t record_index{kNoRecordIndex};
    std::string context;
    std::optional<format::ReadErrorCode> read_error_code;
};

struct PackageV1ObjectRecord final
{
    std::string name_bytes;
    std::string class_name_bytes;
    std::uint64_t offset{0};
    std::uint64_t size{0};
};

struct PackageV1Header final
{
    std::string version;
    std::vector<PackageV1ObjectRecord> records;
    std::uint64_t header_size{0};
    std::uint64_t file_size{0};
};

[[nodiscard]] std::string_view to_string(PackageV1ErrorCode code) noexcept;
[[nodiscard]] std::uint64_t package_v1_metadata_fingerprint(const PackageV1Header& header) noexcept;

} // namespace tmxy::package
