#include "tmxy/package/package_v2.hpp"

namespace tmxy::package
{

namespace
{

constexpr std::uint64_t kFnvOffsetBasis = 14'695'981'039'346'656'037ULL;
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

std::string_view to_string(const PackageV2ErrorCode code) noexcept
{
    switch (code)
    {
    case PackageV2ErrorCode::read_failure:
        return "read_failure";
    case PackageV2ErrorCode::invalid_version:
        return "invalid_version";
    case PackageV2ErrorCode::negative_directory_size:
        return "negative_directory_size";
    case PackageV2ErrorCode::directory_size_limit_exceeded:
        return "directory_size_limit_exceeded";
    case PackageV2ErrorCode::directory_out_of_file:
        return "directory_out_of_file";
    case PackageV2ErrorCode::directory_too_small:
        return "directory_too_small";
    case PackageV2ErrorCode::invalid_directory_prefix:
        return "invalid_directory_prefix";
    case PackageV2ErrorCode::negative_object_count:
        return "negative_object_count";
    case PackageV2ErrorCode::object_count_limit_exceeded:
        return "object_count_limit_exceeded";
    case PackageV2ErrorCode::impossible_object_count:
        return "impossible_object_count";
    case PackageV2ErrorCode::negative_object_offset:
        return "negative_object_offset";
    case PackageV2ErrorCode::negative_object_size:
        return "negative_object_size";
    case PackageV2ErrorCode::duplicate_object_name:
        return "duplicate_object_name";
    case PackageV2ErrorCode::directory_trailing_bytes:
        return "directory_trailing_bytes";
    case PackageV2ErrorCode::non_contiguous_object_range:
        return "non_contiguous_object_range";
    case PackageV2ErrorCode::object_range_out_of_file:
        return "object_range_out_of_file";
    }
    return "unknown_package_v2_error";
}

std::uint64_t package_v2_metadata_fingerprint(const PackageV2Header& header) noexcept
{
    std::uint64_t hash = kFnvOffsetBasis;
    add_bytes(hash, header.version);
    add_u64(hash, header.directory_size);
    add_u64(hash, static_cast<std::uint64_t>(header.records.size()));
    for (const auto& record : header.records)
    {
        add_bytes(hash, record.name_bytes);
        add_u64(hash, static_cast<std::uint64_t>(record.name_bytes.size()));
        add_bytes(hash, record.class_name_bytes);
        add_u64(hash, static_cast<std::uint64_t>(record.class_name_bytes.size()));
        add_u64(hash, record.offset);
        add_u64(hash, record.size);
    }
    return hash;
}

} // namespace tmxy::package
