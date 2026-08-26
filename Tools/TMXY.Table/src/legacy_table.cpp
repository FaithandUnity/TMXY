#include "tmxy/table/legacy_table.hpp"

namespace tmxy::table
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

std::string_view to_string(const LegacyTableErrorCode code) noexcept
{
    switch (code)
    {
    case LegacyTableErrorCode::empty_ciphertext:
        return "empty_ciphertext";
    case LegacyTableErrorCode::invalid_ciphertext_size:
        return "invalid_ciphertext_size";
    case LegacyTableErrorCode::payload_limit_exceeded:
        return "payload_limit_exceeded";
    case LegacyTableErrorCode::invalid_padding_length:
        return "invalid_padding_length";
    case LegacyTableErrorCode::nonzero_padding:
        return "nonzero_padding";
    case LegacyTableErrorCode::embedded_nul:
        return "embedded_nul";
    case LegacyTableErrorCode::invalid_line_ending:
        return "invalid_line_ending";
    case LegacyTableErrorCode::no_header:
        return "no_header";
    case LegacyTableErrorCode::empty_column_name:
        return "empty_column_name";
    case LegacyTableErrorCode::duplicate_column_name:
        return "duplicate_column_name";
    case LegacyTableErrorCode::column_limit_exceeded:
        return "column_limit_exceeded";
    case LegacyTableErrorCode::row_limit_exceeded:
        return "row_limit_exceeded";
    case LegacyTableErrorCode::row_column_count_mismatch:
        return "row_column_count_mismatch";
    case LegacyTableErrorCode::invalid_separator:
        return "invalid_separator";
    }
    return "unknown_legacy_table_error";
}

std::uint64_t legacy_table_metadata_fingerprint(const LegacyTable& table) noexcept
{
    std::uint64_t hash = kFnvOffsetBasis;
    add_u64(hash, static_cast<std::uint64_t>(table.columns.size()));
    for (const auto& column : table.columns)
    {
        add_bytes(hash, column);
        add_u64(hash, static_cast<std::uint64_t>(column.size()));
    }
    add_u64(hash, static_cast<std::uint64_t>(table.rows.size()));
    for (const auto& row : table.rows)
    {
        add_u64(hash, static_cast<std::uint64_t>(row.size()));
        for (const auto& field : row)
        {
            add_bytes(hash, field);
            add_u64(hash, static_cast<std::uint64_t>(field.size()));
        }
    }
    return hash;
}

} // namespace tmxy::table
