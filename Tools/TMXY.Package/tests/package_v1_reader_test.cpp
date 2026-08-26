#include "tmxy/package/package_v1_reader.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <set>
#include <span>
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
            ++failure_count_;
            std::cerr << "FAILED: " << message << '\n';
        }
    }

    [[nodiscard]] int failure_count() const noexcept
    {
        return failure_count_;
    }

  private:
    int failure_count_{0};
};

struct SyntheticRecord final
{
    std::string name;
    std::string class_name;
    std::vector<std::byte> body;
};

struct I32Overwrite final
{
    std::size_t position{0};
    std::int32_t value{0};
};

void append_u16(std::vector<std::byte>& bytes, const std::uint16_t value)
{
    bytes.push_back(static_cast<std::byte>(value & 0xFFU));
    bytes.push_back(static_cast<std::byte>((value >> 8U) & 0xFFU));
}

void append_i32(std::vector<std::byte>& bytes, const std::int32_t value)
{
    const auto raw = std::bit_cast<std::uint32_t>(value);
    for (unsigned int index = 0; index < 4U; ++index)
    {
        bytes.push_back(static_cast<std::byte>((raw >> (index * 8U)) & 0xFFU));
    }
}

void overwrite_i32(std::vector<std::byte>& bytes, const I32Overwrite overwrite)
{
    const auto raw = std::bit_cast<std::uint32_t>(overwrite.value);
    for (unsigned int index = 0; index < 4U; ++index)
    {
        bytes[overwrite.position + index] = static_cast<std::byte>((raw >> (index * 8U)) & 0xFFU);
    }
}

void append_string(std::vector<std::byte>& bytes, const std::string_view value)
{
    append_u16(bytes, static_cast<std::uint16_t>(value.size()));
    for (const char character : value)
    {
        bytes.push_back(static_cast<std::byte>(static_cast<unsigned char>(character)));
    }
}

[[nodiscard]] std::size_t serialized_header_size(const std::span<const SyntheticRecord> records)
{
    std::size_t size = 2U + tmxy::package::kPackageV1Version.size() + 4U;
    for (const auto& record : records)
    {
        size += 2U + record.name.size() + 2U + record.class_name.size() + 8U;
    }
    return size;
}

[[nodiscard]] std::vector<std::byte> make_package(const std::span<const SyntheticRecord> records)
{
    std::vector<std::byte> bytes;
    const auto header_size = serialized_header_size(records);
    append_string(bytes, tmxy::package::kPackageV1Version);
    append_i32(bytes, static_cast<std::int32_t>(records.size()));

    std::size_t object_offset = header_size;
    for (const auto& record : records)
    {
        append_string(bytes, record.name);
        append_string(bytes, record.class_name);
        append_i32(bytes, static_cast<std::int32_t>(object_offset));
        append_i32(bytes, static_cast<std::int32_t>(record.body.size()));
        object_offset += record.body.size();
    }
    for (const auto& record : records)
    {
        bytes.insert(bytes.end(), record.body.begin(), record.body.end());
    }
    return bytes;
}

[[nodiscard]] std::vector<std::byte> make_count_prefix(const std::int32_t count)
{
    std::vector<std::byte> bytes;
    append_string(bytes, tmxy::package::kPackageV1Version);
    append_i32(bytes, count);
    return bytes;
}

[[nodiscard]] std::size_t first_offset_position(const SyntheticRecord& record)
{
    return 2U + tmxy::package::kPackageV1Version.size() + 4U + 2U + record.name.size() + 2U +
           record.class_name.size();
}

void test_valid_package(TestContext& test)
{
    const std::array records{
        SyntheticRecord{
            .name = "first", .class_name = "Texture", .body = {std::byte{0x01}, std::byte{0x02}}},
        SyntheticRecord{.name = "second", .class_name = "Mesh", .body = {std::byte{0x03}}},
    };
    const auto bytes = make_package(records);
    const auto result = tmxy::package::PackageV1Reader{}.parse(bytes);

    test.expect(result.has_value(), "valid package parses");
    if (!result.has_value())
    {
        return;
    }
    test.expect(result.value().version == tmxy::package::kPackageV1Version, "version field");
    test.expect(result.value().records.size() == 2U, "record count");
    test.expect(result.value().header_size == serialized_header_size(records), "header size");
    test.expect(result.value().file_size == bytes.size(), "file size");
    test.expect(result.value().records[0].name_bytes == "first", "name bytes");
    test.expect(result.value().records[1].class_name_bytes == "Mesh", "class bytes");
}

void test_version_and_count_errors(TestContext& test)
{
    const std::array records{
        SyntheticRecord{.name = "one", .class_name = "Texture", .body = {std::byte{0x01}}}};
    auto wrong_version = make_package(records);
    wrong_version[2] = std::byte{0x58};
    const auto version_result = tmxy::package::PackageV1Reader{}.parse(wrong_version);
    const auto negative_result = tmxy::package::PackageV1Reader{}.parse(make_count_prefix(-1));
    const auto impossible_result = tmxy::package::PackageV1Reader{}.parse(make_count_prefix(1));
    const auto limited_result =
        tmxy::package::PackageV1Reader{{.maximum_object_count = 0}}.parse(make_package(records));

    test.expect(!version_result.has_value() &&
                    version_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::invalid_version,
                "invalid version rejected");
    test.expect(!negative_result.has_value() &&
                    negative_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::negative_object_count,
                "negative count rejected");
    test.expect(!impossible_result.has_value() &&
                    impossible_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::impossible_object_count,
                "impossible count rejected before allocation");
    test.expect(!limited_result.has_value() &&
                    limited_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::object_count_limit_exceeded,
                "configured count limit enforced");
}

void test_truncation_error(TestContext& test)
{
    const std::array<std::byte, 1> truncated{std::byte{0x17}};
    const auto result = tmxy::package::PackageV1Reader{}.parse(truncated);

    test.expect(!result.has_value(), "truncated header rejected");
    test.expect(result.error().code == tmxy::package::PackageV1ErrorCode::read_failure,
                "truncated header stable code");
    test.expect(result.error().read_error_code == tmxy::format::ReadErrorCode::out_of_bounds,
                "nested bounded-reader code retained");
    test.expect(result.error().absolute_offset == 0U, "truncated absolute offset");
}

void test_record_field_errors(TestContext& test)
{
    const SyntheticRecord record{.name = "one", .class_name = "Texture", .body = {std::byte{0x01}}};
    const std::array records{record};
    const auto offset_position = first_offset_position(record);
    auto negative_offset = make_package(records);
    auto negative_size = make_package(records);
    overwrite_i32(negative_offset, {.position = offset_position, .value = -1});
    overwrite_i32(negative_size, {.position = offset_position + 4U, .value = -1});

    const auto offset_result = tmxy::package::PackageV1Reader{}.parse(negative_offset);
    const auto size_result = tmxy::package::PackageV1Reader{}.parse(negative_size);
    test.expect(!offset_result.has_value() &&
                    offset_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::negative_object_offset,
                "negative object offset rejected");
    test.expect(!size_result.has_value() &&
                    size_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::negative_object_size,
                "negative object size rejected");
}

void test_range_and_identity_errors(TestContext& test)
{
    const SyntheticRecord record{
        .name = "one",
        .class_name = "Texture",
        .body = {std::byte{0x01}, std::byte{0x02}},
    };
    const std::array records{record};
    const auto offset_position = first_offset_position(record);
    auto gap = make_package(records);
    overwrite_i32(gap, {.position = offset_position,
                        .value = static_cast<std::int32_t>(serialized_header_size(records) + 1U)});
    auto truncated_body = make_package(records);
    truncated_body.pop_back();
    const std::array duplicates{
        SyntheticRecord{.name = "same", .class_name = "Texture", .body = {std::byte{0x01}}},
        SyntheticRecord{.name = "same", .class_name = "Texture", .body = {std::byte{0x02}}},
    };

    const auto gap_result = tmxy::package::PackageV1Reader{}.parse(gap);
    const auto body_result = tmxy::package::PackageV1Reader{}.parse(truncated_body);
    const auto duplicate_result = tmxy::package::PackageV1Reader{}.parse(make_package(duplicates));
    test.expect(!gap_result.has_value() &&
                    gap_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::non_contiguous_object_range,
                "object gap rejected");
    test.expect(!body_result.has_value() &&
                    body_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::object_range_out_of_file,
                "truncated object body rejected");
    test.expect(!duplicate_result.has_value() &&
                    duplicate_result.error().code ==
                        tmxy::package::PackageV1ErrorCode::duplicate_object_name,
                "duplicate object name rejected");
}

[[nodiscard]] int validate_frozen_sample(const char* path)
{
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    const auto end = input.tellg();
    if (!input || end <= 0 || end > std::numeric_limits<std::streamsize>::max())
    {
        std::cerr << "FAILED: sample open or size" << '\n';
        return 1;
    }
    const auto size = static_cast<std::size_t>(end);
    std::vector<char> storage(size);
    input.seekg(0);
    input.read(storage.data(), static_cast<std::streamsize>(storage.size()));
    if (!input)
    {
        std::cerr << "FAILED: sample read" << '\n';
        return 1;
    }

    const auto result = tmxy::package::PackageV1Reader{}.parse(std::as_bytes(std::span(storage)));
    if (!result.has_value())
    {
        std::cerr << "FAILED: frozen sample parse code=" << to_string(result.error().code) << '\n';
        return 1;
    }
    const auto& header = result.value();
    std::set<std::string> classes;
    for (const auto& record : header.records)
    {
        classes.insert(record.class_name_bytes);
    }
    constexpr std::uint64_t kExpectedFingerprint = 0x1691FAFACD3AB5BDULL;
    const bool passed =
        header.version == tmxy::package::kPackageV1Version && header.records.size() == 3004U &&
        header.header_size == 145581U && header.file_size == 319813U && classes.size() == 1U &&
        tmxy::package::package_v1_metadata_fingerprint(header) == kExpectedFingerprint;
    if (!passed)
    {
        std::cerr << "FAILED: frozen sample fields" << '\n';
        return 1;
    }
    std::cout << "{\"sample_result\":\"PASS\",\"record_count\":3004,"
                 "\"header_size\":145581,\"file_size\":319813,"
                 "\"class_count\":1,\"metadata_fnv1a64\":\"1691fafacd3ab5bd\"}"
              << '\n';
    return 0;
}

} // namespace

int main(const int argument_count, const char* const* arguments)
{
    if (argument_count == 2)
    {
        return validate_frozen_sample(arguments[1]);
    }
    if (argument_count != 1)
    {
        return 2;
    }

    TestContext test;
    test_valid_package(test);
    test_version_and_count_errors(test);
    test_truncation_error(test);
    test_record_field_errors(test);
    test_range_and_identity_errors(test);
    return test.failure_count() == 0 ? 0 : 1;
}
