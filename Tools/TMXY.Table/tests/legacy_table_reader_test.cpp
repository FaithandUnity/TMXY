#include "tmxy/table/legacy_table_reader.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <span>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace
{

class TestContext final
{
  public:
    void expect(const bool condition, const std::string_view message)
    {
        if (!condition)
        {
            std::cerr << "FAILED: " << message << '\n';
            ++failure_count_;
        }
    }

    [[nodiscard]] int failure_count() const noexcept
    {
        return failure_count_;
    }

  private:
    int failure_count_{0};
};

[[nodiscard]] std::uint8_t hex_nibble(const char value)
{
    if (value >= '0' && value <= '9')
    {
        return static_cast<std::uint8_t>(value - '0');
    }
    if (value >= 'a' && value <= 'f')
    {
        return static_cast<std::uint8_t>(value - 'a' + 10);
    }
    return static_cast<std::uint8_t>(value - 'A' + 10);
}

[[nodiscard]] std::vector<std::byte> bytes_from_hex(const std::string_view hex)
{
    std::vector<std::byte> bytes;
    bytes.reserve(hex.size() / 2U);
    for (std::size_t index = 0; index < hex.size(); index += 2U)
    {
        const auto value =
            static_cast<std::uint8_t>((hex_nibble(hex[index]) << 4U) | hex_nibble(hex[index + 1U]));
        bytes.push_back(static_cast<std::byte>(value));
    }
    return bytes;
}

[[nodiscard]] tmxy::table::LegacyTableKey fixed_test_key()
{
    tmxy::table::LegacyTableKey key{};
    for (std::size_t index = 0; index < key.size(); ++index)
    {
        key[index] = static_cast<std::byte>(index);
    }
    return key;
}

[[nodiscard]] std::string payload_string(const std::vector<std::byte>& bytes)
{
    std::string result;
    result.reserve(bytes.size());
    for (const auto value : bytes)
    {
        result.push_back(static_cast<char>(std::to_integer<unsigned char>(value)));
    }
    return result;
}

void expect_error(TestContext& test, const tmxy::table::LegacyTableParseResult& result,
                  const tmxy::table::LegacyTableErrorCode code, const std::string_view message)
{
    const bool matches = !result.has_value() && result.error().code == code;
    if (!matches)
    {
        std::cerr << "Expected " << tmxy::table::to_string(code) << "; actual "
                  << (result.has_value() ? "success" : tmxy::table::to_string(result.error().code))
                  << '\n';
    }
    test.expect(matches, message);
}

void test_fixed_vector(TestContext& test)
{
    constexpr std::string_view kCiphertext =
        "8c5267abd3447df7cc476e91b955b32a111ff78d264399cb8e666df71ee7e990";
    constexpr std::string_view kPayload = "id,name\r\n1,alpha\r\n2,\r\n";
    const auto ciphertext = bytes_from_hex(kCiphertext);
    const auto key = fixed_test_key();
    const auto result = tmxy::table::LegacyTableReader{}.decode_and_parse(ciphertext, key);

    test.expect(result.has_value(), "independently generated double-AES fixed vector parses");
    if (!result.has_value())
    {
        return;
    }
    test.expect(result.value().padding_bytes == 9U, "legacy padding count");
    test.expect(payload_string(result.value().payload_bytes) == kPayload, "decoded payload bytes");
    test.expect(result.value().columns == std::vector<std::string>{"id", "name"}, "header fields");
    test.expect(result.value().rows.size() == 2U, "row count");
    test.expect(result.value().rows[0] == std::vector<std::string>{"1", "alpha"}, "first row");
    test.expect(result.value().rows[1] == std::vector<std::string>{"2", ""},
                "trailing empty field");
}

void test_input_boundaries(TestContext& test)
{
    const auto key = fixed_test_key();
    const std::array<std::byte, 1> one_byte{std::byte{0}};
    const auto valid_ciphertext =
        bytes_from_hex("8c5267abd3447df7cc476e91b955b32a111ff78d264399cb8e666df71ee7e990");
    const auto empty_result = tmxy::table::LegacyTableReader{}.decode_and_parse({}, key);
    const auto size_result = tmxy::table::LegacyTableReader{}.decode_and_parse(one_byte, key);
    const auto limit_result =
        tmxy::table::LegacyTableReader{{.maximum_payload_bytes = 0}}.decode_and_parse(
            valid_ciphertext, key);
    const auto separator_result =
        tmxy::table::LegacyTableReader{}.decode_and_parse(valid_ciphertext, key, '\n');

    expect_error(test, empty_result, tmxy::table::LegacyTableErrorCode::empty_ciphertext,
                 "empty ciphertext rejected");
    expect_error(test, size_result, tmxy::table::LegacyTableErrorCode::invalid_ciphertext_size,
                 "non-block ciphertext rejected");
    expect_error(test, limit_result, tmxy::table::LegacyTableErrorCode::payload_limit_exceeded,
                 "payload allocation limit enforced");
    expect_error(test, separator_result, tmxy::table::LegacyTableErrorCode::invalid_separator,
                 "line-ending separator rejected");
}

void test_decrypted_structure_errors(TestContext& test)
{
    const auto key = fixed_test_key();
    struct ErrorVector final
    {
        std::string_view ciphertext;
        tmxy::table::LegacyTableErrorCode code;
        std::string_view message;
    };
    constexpr std::array vectors{
        ErrorVector{.ciphertext = "d0ffc2fa487288f1925c3af726e3afa4",
                    .code = tmxy::table::LegacyTableErrorCode::invalid_padding_length,
                    .message = "invalid padding length rejected"},
        ErrorVector{.ciphertext = "7c073849aa8403c13c51b488c4c0e034",
                    .code = tmxy::table::LegacyTableErrorCode::nonzero_padding,
                    .message = "nonzero padding rejected"},
        ErrorVector{.ciphertext = "2a43240c750b98adbc5550afbad86e45",
                    .code = tmxy::table::LegacyTableErrorCode::embedded_nul,
                    .message = "embedded NUL rejected"},
        ErrorVector{.ciphertext = "7932f7ba7f5cb018151bf8411325894f",
                    .code = tmxy::table::LegacyTableErrorCode::invalid_line_ending,
                    .message = "lone LF rejected"},
        ErrorVector{.ciphertext = "27ffb29a6a202c3b4df2f3b8164416bb",
                    .code = tmxy::table::LegacyTableErrorCode::no_header,
                    .message = "empty payload rejected"},
        ErrorVector{.ciphertext = "3f1def2c85cd24bb05406ef9be47f663",
                    .code = tmxy::table::LegacyTableErrorCode::duplicate_column_name,
                    .message = "duplicate header rejected"},
        ErrorVector{.ciphertext = "f8beb09824698aac5cc31c9facec4b77",
                    .code = tmxy::table::LegacyTableErrorCode::row_column_count_mismatch,
                    .message = "short row rejected"},
    };
    for (const auto& vector : vectors)
    {
        const auto result = tmxy::table::LegacyTableReader{}.decode_and_parse(
            bytes_from_hex(vector.ciphertext), key);
        expect_error(test, result, vector.code, vector.message);
    }
}

[[nodiscard]] std::vector<std::byte> read_file(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream)
    {
        return {};
    }
    const auto end = stream.tellg();
    if (end < 0 || end > std::numeric_limits<std::streamsize>::max())
    {
        return {};
    }
    std::vector<std::byte> bytes(static_cast<std::size_t>(end));
    stream.seekg(0);
    if (!bytes.empty())
    {
        stream.read(reinterpret_cast<char*>(bytes.data()),
                    static_cast<std::streamsize>(bytes.size()));
    }
    if (!stream)
    {
        return {};
    }
    return bytes;
}

[[nodiscard]] std::string hex_u64(const std::uint64_t value)
{
    std::ostringstream output;
    output << std::hex << std::setfill('0') << std::setw(16) << value;
    return output.str();
}

int validate_legacy_pair(const std::filesystem::path& ciphertext_path,
                         const std::filesystem::path& csv_path,
                         const std::filesystem::path& key_path)
{
    const auto ciphertext = read_file(ciphertext_path);
    const auto csv = read_file(csv_path);
    auto key_bytes = read_file(key_path);
    if (ciphertext.empty() || csv.empty() || key_bytes.size() != tmxy::table::kLegacyTableBlockSize)
    {
        return 1;
    }
    tmxy::table::LegacyTableKey key{};
    std::ranges::copy(key_bytes, key.begin());
    std::ranges::fill(key_bytes, std::byte{0});

    const auto result = tmxy::table::LegacyTableReader{}.decode_and_parse(ciphertext, key);
    std::ranges::fill(key, std::byte{0});
    if (!result.has_value() || result.value().payload_bytes != csv)
    {
        return 1;
    }
    std::cout << R"({"sample_result":"PASS","cipher_bytes":)" << ciphertext.size()
              << R"(,"payload_bytes":)" << result.value().payload_bytes.size()
              << R"(,"padding_bytes":)" << result.value().padding_bytes << R"(,"column_count":)"
              << result.value().columns.size() << R"(,"row_count":)" << result.value().rows.size()
              << R"(,"metadata_fnv1a64":")"
              << hex_u64(tmxy::table::legacy_table_metadata_fingerprint(result.value())) << R"("})"
              << '\n';
    return 0;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count == 4)
    {
        return validate_legacy_pair(arguments[1], arguments[2], arguments[3]);
    }
    if (argument_count != 1)
    {
        return 2;
    }

    TestContext test;
    test_fixed_vector(test);
    test_input_boundaries(test);
    test_decrypted_structure_errors(test);
    return test.failure_count() == 0 ? 0 : 1;
}
