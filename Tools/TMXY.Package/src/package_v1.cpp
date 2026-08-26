#include "tmxy/package/package_v1.hpp"

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

void add_separator(std::uint64_t& hash) noexcept
{
    hash ^= 0U;
    hash *= kFnvPrime;
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

std::string_view to_string(const PackageV1ErrorCode code) noexcept
{
    switch (code)
    {
    case PackageV1ErrorCode::read_failure:
        return "read_failure";
    case PackageV1ErrorCode::invalid_version:
        return "invalid_version";
    case PackageV1ErrorCode::negative_object_count:
        return "negative_object_count";
    case PackageV1ErrorCode::object_count_limit_exceeded:
        return "object_count_limit_exceeded";
    case PackageV1ErrorCode::impossible_object_count:
        return "impossible_object_count";
    case PackageV1ErrorCode::negative_object_offset:
        return "negative_object_offset";
    case PackageV1ErrorCode::negative_object_size:
        return "negative_object_size";
    case PackageV1ErrorCode::duplicate_object_name:
        return "duplicate_object_name";
    case PackageV1ErrorCode::non_contiguous_object_range:
        return "non_contiguous_object_range";
    case PackageV1ErrorCode::object_range_out_of_file:
        return "object_range_out_of_file";
    }
    return "unknown_package_v1_error";
}

std::uint64_t package_v1_metadata_fingerprint(const PackageV1Header& header) noexcept
{
    std::uint64_t hash = kFnvOffsetBasis;
    add_bytes(hash, header.version);
    add_separator(hash);
    for (const auto& record : header.records)
    {
        add_bytes(hash, record.name_bytes);
        add_separator(hash);
        add_bytes(hash, record.class_name_bytes);
        add_separator(hash);
        add_u64(hash, record.offset);
        add_u64(hash, record.size);
    }
    return hash;
}

} // namespace tmxy::package
