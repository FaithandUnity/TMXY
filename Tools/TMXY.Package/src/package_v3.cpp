#include "tmxy/package/package_v3.hpp"

#include <cstdint>
#include <string_view>

namespace tmxy::package
{

namespace
{

constexpr std::uint64_t kFnvOffset = 14'695'981'039'346'656'037ULL;
constexpr std::uint64_t kFnvPrime = 1'099'511'628'211ULL;

void add_bytes(std::uint64_t& hash, const std::string_view bytes) noexcept
{
    for (const char value : bytes)
    {
        hash ^= static_cast<unsigned char>(value);
        hash *= kFnvPrime;
    }
}

void add_u64(std::uint64_t& hash, std::uint64_t value) noexcept
{
    for (unsigned int index = 0; index < 8U; ++index)
    {
        hash ^= value & 0xFFU;
        hash *= kFnvPrime;
        value >>= 8U;
    }
}

} // namespace

std::string_view to_string(const PackageV3ErrorCode code) noexcept
{
    switch (code)
    {
    case PackageV3ErrorCode::read_failure:
        return "read_failure";
    case PackageV3ErrorCode::invalid_version:
        return "invalid_version";
    case PackageV3ErrorCode::negative_directory_size:
        return "negative_directory_size";
    case PackageV3ErrorCode::directory_size_limit_exceeded:
        return "directory_size_limit_exceeded";
    case PackageV3ErrorCode::directory_out_of_file:
        return "directory_out_of_file";
    case PackageV3ErrorCode::directory_too_small:
        return "directory_too_small";
    case PackageV3ErrorCode::invalid_directory_prefix:
        return "invalid_directory_prefix";
    case PackageV3ErrorCode::negative_object_count:
        return "negative_object_count";
    case PackageV3ErrorCode::object_count_limit_exceeded:
        return "object_count_limit_exceeded";
    case PackageV3ErrorCode::impossible_object_count:
        return "impossible_object_count";
    case PackageV3ErrorCode::negative_object_offset:
        return "negative_object_offset";
    case PackageV3ErrorCode::negative_object_size:
        return "negative_object_size";
    case PackageV3ErrorCode::duplicate_object_name:
        return "duplicate_object_name";
    case PackageV3ErrorCode::directory_trailing_bytes:
        return "directory_trailing_bytes";
    case PackageV3ErrorCode::non_contiguous_object_range:
        return "non_contiguous_object_range";
    case PackageV3ErrorCode::object_range_out_of_file:
        return "object_range_out_of_file";
    }
    return "unknown";
}

std::uint64_t package_v3_metadata_fingerprint(const PackageV3Header& header) noexcept
{
    std::uint64_t hash = kFnvOffset;
    add_bytes(hash, header.version);
    add_u64(hash, header.directory_offset);
    add_u64(hash, header.directory_size);
    add_u64(hash, header.header_size);
    add_u64(hash, header.file_size);
    add_u64(hash, header.records.size());
    for (const auto& record : header.records)
    {
        add_u64(hash, record.name_bytes.size());
        add_bytes(hash, record.name_bytes);
        add_u64(hash, record.class_name_bytes.size());
        add_bytes(hash, record.class_name_bytes);
        add_u64(hash, record.offset);
        add_u64(hash, record.size);
    }
    return hash;
}

} // namespace tmxy::package
