#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::table
{

inline constexpr std::size_t kLegacyTableBlockSize = 16;
using LegacyTableKey = std::array<std::byte, kLegacyTableBlockSize>;

enum class LegacyTableErrorCode : std::uint8_t
{
    empty_ciphertext = 1,
    invalid_ciphertext_size = 2,
    payload_limit_exceeded = 3,
    invalid_padding_length = 4,
    nonzero_padding = 5,
    embedded_nul = 6,
    invalid_line_ending = 7,
    no_header = 8,
    empty_column_name = 9,
    duplicate_column_name = 10,
    column_limit_exceeded = 11,
    row_limit_exceeded = 12,
    row_column_count_mismatch = 13,
    invalid_separator = 14,
};

struct LegacyTableError final
{
    static constexpr std::uint32_t kSchemaVersion = 1;
    static constexpr std::uint64_t kNoRowIndex = std::numeric_limits<std::uint64_t>::max();

    LegacyTableErrorCode code{LegacyTableErrorCode::empty_ciphertext};
    std::uint64_t absolute_offset{0};
    std::uint64_t row_index{kNoRowIndex};
    std::string context;
};

struct LegacyTable final
{
    std::vector<std::byte> payload_bytes;
    std::vector<std::string> columns;
    std::vector<std::vector<std::string>> rows;
    std::size_t padding_bytes{0};
};

[[nodiscard]] std::string_view to_string(LegacyTableErrorCode code) noexcept;
[[nodiscard]] std::uint64_t legacy_table_metadata_fingerprint(const LegacyTable& table) noexcept;

} // namespace tmxy::table
