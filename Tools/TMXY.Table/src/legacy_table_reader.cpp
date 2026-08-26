#include "tmxy/table/legacy_table_reader.hpp"

#include "aes128_decryptor.hpp"

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>
#include <variant>
#include <vector>

namespace tmxy::table
{

namespace
{

struct LineView final
{
    std::string_view bytes;
    std::size_t payload_offset{0};
};

[[nodiscard]] LegacyTableError
make_error(const LegacyTableErrorCode code, const std::uint64_t absolute_offset,
           std::string context, const std::uint64_t row_index = LegacyTableError::kNoRowIndex)
{
    return LegacyTableError{
        .code = code,
        .absolute_offset = absolute_offset,
        .row_index = row_index,
        .context = std::move(context),
    };
}

[[nodiscard]] std::optional<std::size_t>
find_invalid_line_ending(const std::string_view payload) noexcept
{
    for (std::size_t index = 0; index < payload.size(); ++index)
    {
        if (payload[index] == '\r')
        {
            if (index + 1U >= payload.size() || payload[index + 1U] != '\n')
            {
                return index;
            }
            ++index;
        }
        else if (payload[index] == '\n')
        {
            return index;
        }
    }
    return std::nullopt;
}

[[nodiscard]] std::vector<LineView> split_nonempty_lines(const std::string_view payload)
{
    std::vector<LineView> lines;
    std::size_t begin = 0;
    while (begin < payload.size())
    {
        const auto end = payload.find("\r\n", begin);
        const auto length = end == std::string_view::npos ? payload.size() - begin : end - begin;
        if (length != 0U)
        {
            lines.push_back(
                LineView{.bytes = payload.substr(begin, length), .payload_offset = begin});
        }
        if (end == std::string_view::npos)
        {
            break;
        }
        begin = end + 2U;
    }
    return lines;
}

[[nodiscard]] std::vector<std::string> split_fields(const std::string_view line,
                                                    const char separator)
{
    std::vector<std::string> fields;
    std::size_t begin = 0;
    while (true)
    {
        const auto end = line.find(separator, begin);
        if (end == std::string_view::npos)
        {
            fields.emplace_back(line.substr(begin));
            break;
        }
        fields.emplace_back(line.substr(begin, end - begin));
        begin = end + 1U;
    }
    return fields;
}

[[nodiscard]] std::vector<std::byte>
decrypt_legacy_payload(const std::span<const std::byte> ciphertext,
                       const std::span<const std::byte, kLegacyTableBlockSize> key)
{
    std::vector<std::byte> plaintext(ciphertext.begin(), ciphertext.end());
    const detail::Aes128Decryptor decryptor(key);
    for (std::size_t offset = 0; offset < plaintext.size(); offset += kLegacyTableBlockSize)
    {
        std::span<std::byte, kLegacyTableBlockSize> block(plaintext.data() + offset,
                                                          kLegacyTableBlockSize);
        decryptor.decrypt_block(block);
        decryptor.decrypt_block(block);
    }
    return plaintext;
}

template <typename Value> using StepResult = std::variant<Value, LegacyTableError>;

struct DecodedPayload final
{
    std::vector<std::byte> bytes;
    std::size_t padding_bytes{0};
};

[[nodiscard]] std::optional<LegacyTableError>
validate_input(const std::span<const std::byte> ciphertext, const LegacyTableLimits& limits,
               const char separator)
{
    if (separator == '\0' || separator == '\r' || separator == '\n')
    {
        return make_error(LegacyTableErrorCode::invalid_separator, 0, "table.separator");
    }
    if (ciphertext.empty())
    {
        return make_error(LegacyTableErrorCode::empty_ciphertext, 0, "table.ciphertext");
    }
    if (ciphertext.size() % kLegacyTableBlockSize != 0U)
    {
        return make_error(LegacyTableErrorCode::invalid_ciphertext_size, ciphertext.size(),
                          "table.ciphertext");
    }
    if (ciphertext.size() > limits.maximum_payload_bytes &&
        ciphertext.size() - limits.maximum_payload_bytes > kLegacyTableBlockSize)
    {
        return make_error(LegacyTableErrorCode::payload_limit_exceeded, ciphertext.size(),
                          "table.payload");
    }
    return std::nullopt;
}

[[nodiscard]] StepResult<DecodedPayload> decryption_failure(std::vector<std::byte>& plaintext,
                                                            LegacyTableError error)
{
    std::ranges::fill(plaintext, std::byte{0});
    return error;
}

[[nodiscard]] StepResult<DecodedPayload>
decode_and_validate_payload(const std::span<const std::byte> ciphertext,
                            const std::span<const std::byte, kLegacyTableBlockSize> key,
                            const LegacyTableLimits& limits)
{
    auto plaintext = decrypt_legacy_payload(ciphertext, key);
    const auto padding = std::to_integer<std::size_t>(plaintext.front());
    if (padding >= kLegacyTableBlockSize || plaintext.size() <= padding + 1U)
    {
        return decryption_failure(
            plaintext,
            make_error(LegacyTableErrorCode::invalid_padding_length, 0, "table.padding_length"));
    }

    const auto payload_end = plaintext.size() - padding;
    const auto padding_range = std::span<const std::byte>(plaintext).subspan(payload_end);
    const auto nonzero_padding = std::ranges::find_if(padding_range, [](const std::byte value)
                                                      { return value != std::byte{0}; });
    if (nonzero_padding != padding_range.end())
    {
        const auto offset =
            payload_end +
            static_cast<std::size_t>(std::distance(padding_range.begin(), nonzero_padding));
        return decryption_failure(
            plaintext, make_error(LegacyTableErrorCode::nonzero_padding, offset, "table.padding"));
    }

    const auto payload_size = payload_end - 1U;
    if (payload_size > limits.maximum_payload_bytes)
    {
        return decryption_failure(plaintext,
                                  make_error(LegacyTableErrorCode::payload_limit_exceeded,
                                             payload_size, "table.payload"));
    }

    DecodedPayload decoded{.bytes = {}, .padding_bytes = padding};
    decoded.bytes.assign(plaintext.begin() + 1,
                         plaintext.begin() + static_cast<std::ptrdiff_t>(payload_end));
    std::ranges::fill(plaintext, std::byte{0});
    return decoded;
}

[[nodiscard]] StepResult<std::string>
make_payload_text(const std::span<const std::byte> payload_bytes)
{
    std::string payload;
    payload.reserve(payload_bytes.size());
    for (const auto value : payload_bytes)
    {
        if (value == std::byte{0})
        {
            return make_error(LegacyTableErrorCode::embedded_nul, payload.size() + 1U,
                              "table.payload");
        }
        payload.push_back(static_cast<char>(std::to_integer<unsigned char>(value)));
    }
    return payload;
}

[[nodiscard]] std::optional<LegacyTableError>
validate_columns(const std::vector<std::string>& columns, const LegacyTableLimits& limits)
{
    if (columns.empty())
    {
        return make_error(LegacyTableErrorCode::no_header, 1, "table.header");
    }
    if (columns.size() > limits.maximum_columns)
    {
        return make_error(LegacyTableErrorCode::column_limit_exceeded, 1, "table.header");
    }
    std::unordered_set<std::string> column_names;
    for (const auto& column : columns)
    {
        if (column.empty())
        {
            return make_error(LegacyTableErrorCode::empty_column_name, 1, "table.header");
        }
        if (!column_names.insert(column).second)
        {
            return make_error(LegacyTableErrorCode::duplicate_column_name, 1, "table.header");
        }
    }
    return std::nullopt;
}

[[nodiscard]] LegacyTableParseResult
parse_decoded_payload(DecodedPayload decoded, const LegacyTableLimits& limits, const char separator)
{
    auto payload_result = make_payload_text(decoded.bytes);
    if (const auto* error = std::get_if<LegacyTableError>(&payload_result))
    {
        return LegacyTableParseResult::failure(*error);
    }
    const auto& payload = std::get<std::string>(payload_result);
    if (const auto invalid_ending = find_invalid_line_ending(payload))
    {
        return LegacyTableParseResult::failure(make_error(
            LegacyTableErrorCode::invalid_line_ending, *invalid_ending + 1U, "table.line_ending"));
    }

    const auto lines = split_nonempty_lines(payload);
    if (lines.empty())
    {
        return LegacyTableParseResult::failure(
            make_error(LegacyTableErrorCode::no_header, 1, "table.header"));
    }
    LegacyTable table{
        .payload_bytes = std::move(decoded.bytes),
        .columns = split_fields(lines.front().bytes, separator),
        .rows = {},
        .padding_bytes = decoded.padding_bytes,
    };
    if (const auto error = validate_columns(table.columns, limits))
    {
        return LegacyTableParseResult::failure(*error);
    }
    if (lines.size() - 1U > limits.maximum_rows)
    {
        return LegacyTableParseResult::failure(
            make_error(LegacyTableErrorCode::row_limit_exceeded, 1, "table.rows"));
    }

    table.rows.reserve(lines.size() - 1U);
    for (std::size_t line_index = 1; line_index < lines.size(); ++line_index)
    {
        auto fields = split_fields(lines[line_index].bytes, separator);
        if (fields.size() != table.columns.size())
        {
            return LegacyTableParseResult::failure(
                make_error(LegacyTableErrorCode::row_column_count_mismatch,
                           static_cast<std::uint64_t>(lines[line_index].payload_offset + 1U),
                           "table.rows", static_cast<std::uint64_t>(line_index - 1U)));
        }
        table.rows.push_back(std::move(fields));
    }
    return LegacyTableParseResult::success(std::move(table));
}

} // namespace

LegacyTableParseResult LegacyTableParseResult::success(LegacyTable table)
{
    return LegacyTableParseResult(std::move(table));
}

LegacyTableParseResult LegacyTableParseResult::failure(LegacyTableError error)
{
    return LegacyTableParseResult(std::move(error));
}

bool LegacyTableParseResult::has_value() const noexcept
{
    return std::holds_alternative<LegacyTable>(storage_);
}

const LegacyTable& LegacyTableParseResult::value() const& noexcept
{
    const auto* result = std::get_if<LegacyTable>(&storage_);
    assert(result != nullptr);
    return *result;
}

const LegacyTableError& LegacyTableParseResult::error() const& noexcept
{
    const auto* result = std::get_if<LegacyTableError>(&storage_);
    assert(result != nullptr);
    return *result;
}

LegacyTableParseResult::LegacyTableParseResult(LegacyTable table) : storage_(std::move(table)) {}

LegacyTableParseResult::LegacyTableParseResult(LegacyTableError error) : storage_(std::move(error))
{
}

LegacyTableReader::LegacyTableReader(const LegacyTableLimits limits) : limits_(limits) {}

LegacyTableParseResult
LegacyTableReader::decode_and_parse(const std::span<const std::byte> ciphertext,
                                    const std::span<const std::byte, kLegacyTableBlockSize> key,
                                    const char separator) const
{
    if (const auto error = validate_input(ciphertext, limits_, separator))
    {
        return LegacyTableParseResult::failure(*error);
    }
    auto decoded = decode_and_validate_payload(ciphertext, key, limits_);
    if (const auto* error = std::get_if<LegacyTableError>(&decoded))
    {
        return LegacyTableParseResult::failure(*error);
    }
    return parse_decoded_payload(std::get<DecodedPayload>(std::move(decoded)), limits_, separator);
}

} // namespace tmxy::table
