#pragma once

#include "tmxy/table/legacy_table.hpp"

#include <cstddef>
#include <span>
#include <variant>

namespace tmxy::table
{

struct LegacyTableLimits final
{
    std::size_t maximum_payload_bytes{std::size_t{16} * 1024U * 1024U};
    std::size_t maximum_columns{4'096};
    std::size_t maximum_rows{1'000'000};
};

class [[nodiscard]] LegacyTableParseResult final
{
  public:
    [[nodiscard]] static LegacyTableParseResult success(LegacyTable table);
    [[nodiscard]] static LegacyTableParseResult failure(LegacyTableError error);
    [[nodiscard]] bool has_value() const noexcept;
    [[nodiscard]] const LegacyTable& value() const& noexcept;
    [[nodiscard]] const LegacyTableError& error() const& noexcept;

  private:
    explicit LegacyTableParseResult(LegacyTable table);
    explicit LegacyTableParseResult(LegacyTableError error);

    std::variant<LegacyTable, LegacyTableError> storage_;
};

class LegacyTableReader final
{
  public:
    explicit LegacyTableReader(LegacyTableLimits limits = {});

    [[nodiscard]] LegacyTableParseResult
    decode_and_parse(std::span<const std::byte> ciphertext,
                     std::span<const std::byte, kLegacyTableBlockSize> key,
                     char separator = ',') const;

  private:
    LegacyTableLimits limits_;
};

} // namespace tmxy::table
