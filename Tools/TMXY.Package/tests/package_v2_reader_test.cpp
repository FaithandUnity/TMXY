#include "tmxy/package/package_v2_reader.hpp"

#include <algorithm>
#include <array>
#include <bit>
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

struct SyntheticRecord final
{
    std::string name;
    std::string class_name;
    std::vector<std::byte> body;
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

struct I32Overwrite final
{
    std::size_t position{0};
    std::int32_t value{0};
};

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

[[nodiscard]] std::byte invert_byte(const std::byte value) noexcept
{
    return static_cast<std::byte>(static_cast<std::uint8_t>(~std::to_integer<std::uint8_t>(value)));
}

[[nodiscard]] std::vector<std::byte> transform_directory(const std::span<const std::byte> input)
{
    std::vector<std::byte> output(input.size());
    const auto full_bytes = input.size() - (input.size() % 4U);
    for (std::size_t offset = 0; offset < full_bytes; offset += 4U)
    {
        output[offset] = invert_byte(input[offset + 2U]);
        output[offset + 1U] = invert_byte(input[offset + 3U]);
        output[offset + 2U] = invert_byte(input[offset]);
        output[offset + 3U] = invert_byte(input[offset + 1U]);
    }
    for (std::size_t offset = full_bytes; offset < input.size(); ++offset)
    {
        output[offset] = invert_byte(input[offset]);
    }
    return output;
}

[[nodiscard]] std::size_t directory_size(const std::span<const SyntheticRecord> records)
{
    std::size_t size = tmxy::package::kPackageV2DirectoryPrefix.size() + 4U;
    for (const auto& record : records)
    {
        size += 2U + record.name.size() + 2U + record.class_name.size() + 8U;
    }
    return size;
}

[[nodiscard]] std::vector<std::byte> make_package(const std::span<const SyntheticRecord> records)
{
    std::vector<std::byte> decoded_directory(tmxy::package::kPackageV2DirectoryPrefix.begin(),
                                             tmxy::package::kPackageV2DirectoryPrefix.end());
    append_i32(decoded_directory, static_cast<std::int32_t>(records.size()));
    const auto blob_size = directory_size(records);
    std::size_t object_offset = 2U + tmxy::package::kPackageV2Version.size() + 4U + blob_size;
    for (const auto& record : records)
    {
        append_string(decoded_directory, record.name);
        append_string(decoded_directory, record.class_name);
        append_i32(decoded_directory, static_cast<std::int32_t>(object_offset));
        append_i32(decoded_directory, static_cast<std::int32_t>(record.body.size()));
        object_offset += record.body.size();
    }

    std::vector<std::byte> bytes;
    append_string(bytes, tmxy::package::kPackageV2Version);
    append_i32(bytes, static_cast<std::int32_t>(decoded_directory.size()));
    const auto encoded = transform_directory(decoded_directory);
    bytes.insert(bytes.end(), encoded.begin(), encoded.end());
    for (const auto& record : records)
    {
        bytes.insert(bytes.end(), record.body.begin(), record.body.end());
    }
    return bytes;
}

struct DirectoryI32Mutation final
{
    std::size_t decoded_offset{0};
    std::int32_t value{0};
};

[[nodiscard]] std::vector<std::byte> mutate_directory_i32(std::vector<std::byte> package,
                                                          const DirectoryI32Mutation mutation)
{
    constexpr std::size_t kOuterHeaderSize = 29;
    const auto blob_size = static_cast<std::size_t>(std::bit_cast<std::int32_t>(
        static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(package[25])) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(package[26])) << 8U) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(package[27])) << 16U) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(package[28])) << 24U)));
    auto decoded = transform_directory(
        std::span<const std::byte>(package).subspan(kOuterHeaderSize, blob_size));
    overwrite_i32(decoded, {.position = mutation.decoded_offset, .value = mutation.value});
    const auto encoded = transform_directory(decoded);
    std::ranges::copy(encoded, package.begin() + static_cast<std::ptrdiff_t>(kOuterHeaderSize));
    return package;
}

void expect_error(TestContext& test, const tmxy::package::PackageV2ParseResult& result,
                  const tmxy::package::PackageV2ErrorCode code, const std::string_view message)
{
    test.expect(!result.has_value() && result.error().code == code, message);
}

void test_valid_package(TestContext& test)
{
    const std::array records{
        SyntheticRecord{
            .name = "first", .class_name = "QActor", .body = {std::byte{0x01}, std::byte{0x02}}},
        SyntheticRecord{.name = "second", .class_name = "QLevel", .body = {std::byte{0x03}}},
    };
    const auto bytes = make_package(records);
    const auto result = tmxy::package::PackageV2Reader{}.parse(bytes);
    test.expect(result.has_value(), "valid Package 2.0 parses");
    if (!result.has_value())
    {
        return;
    }
    test.expect(result.value().records.size() == 2U, "record count");
    test.expect(result.value().directory_offset == 29U, "directory offset");
    test.expect(result.value().directory_size == directory_size(records), "directory size");
    test.expect(result.value().header_size == 29U + directory_size(records), "header size");
    test.expect(result.value().records[0].name_bytes == "first", "decoded name");
    test.expect(result.value().records[1].class_name_bytes == "QLevel", "decoded class");
}

void test_outer_errors(TestContext& test)
{
    const std::array records{
        SyntheticRecord{.name = "one", .class_name = "QActor", .body = {std::byte{0x01}}}};
    auto wrong_version = make_package(records);
    wrong_version[2] = std::byte{0x58};
    auto negative_size = make_package(records);
    overwrite_i32(negative_size, {.position = 25U, .value = -1});
    auto out_of_file = make_package(records);
    overwrite_i32(out_of_file, {.position = 25U, .value = 1'000'000});
    auto too_small = make_package(records);
    overwrite_i32(too_small, {.position = 25U, .value = 17});

    expect_error(test, tmxy::package::PackageV2Reader{}.parse(wrong_version),
                 tmxy::package::PackageV2ErrorCode::invalid_version, "invalid version rejected");
    expect_error(test, tmxy::package::PackageV2Reader{}.parse(negative_size),
                 tmxy::package::PackageV2ErrorCode::negative_directory_size,
                 "negative directory size rejected");
    expect_error(test, tmxy::package::PackageV2Reader{}.parse(out_of_file),
                 tmxy::package::PackageV2ErrorCode::directory_out_of_file,
                 "directory beyond file rejected");
    expect_error(test, tmxy::package::PackageV2Reader{}.parse(too_small),
                 tmxy::package::PackageV2ErrorCode::directory_too_small,
                 "short directory rejected");
}

void test_directory_errors(TestContext& test)
{
    const std::array records{
        SyntheticRecord{.name = "one", .class_name = "QActor", .body = {std::byte{0x01}}}};
    const auto valid = make_package(records);
    auto prefix = valid;
    constexpr std::size_t kOuterHeaderSize = 29;
    prefix[kOuterHeaderSize + 2U] = std::byte{0x7F};
    const auto negative_count = mutate_directory_i32(valid, {.decoded_offset = 14U, .value = -1});
    const auto limited = tmxy::package::PackageV2Reader{{.maximum_object_count = 0}}.parse(valid);

    const auto prefix_result = tmxy::package::PackageV2Reader{}.parse(prefix);
    expect_error(test, prefix_result, tmxy::package::PackageV2ErrorCode::invalid_directory_prefix,
                 "directory prefix rejected");
    test.expect(prefix_result.error().absolute_offset == 31U,
                "decoded prefix error maps to encoded file offset");
    expect_error(test, tmxy::package::PackageV2Reader{}.parse(negative_count),
                 tmxy::package::PackageV2ErrorCode::negative_object_count,
                 "negative record count rejected");
    expect_error(test, limited, tmxy::package::PackageV2ErrorCode::object_count_limit_exceeded,
                 "record count limit enforced");
}

void test_record_and_range_errors(TestContext& test)
{
    const std::array duplicate_records{
        SyntheticRecord{.name = "same", .class_name = "QActor", .body = {std::byte{0x01}}},
        SyntheticRecord{.name = "same", .class_name = "QActor", .body = {std::byte{0x02}}},
    };
    const std::array one_record{SyntheticRecord{
        .name = "one", .class_name = "QActor", .body = {std::byte{0x01}, std::byte{0x02}}}};
    auto truncated = make_package(one_record);
    truncated.pop_back();
    auto gap = make_package(one_record);
    constexpr std::size_t kFirstOffsetInDecodedDirectory = 18U + 2U + 3U + 2U + 6U;
    const auto expected_offset = static_cast<std::int32_t>(gap.size() - one_record[0].body.size());
    gap = mutate_directory_i32(
        gap, {.decoded_offset = kFirstOffsetInDecodedDirectory, .value = expected_offset + 1});

    expect_error(test, tmxy::package::PackageV2Reader{}.parse(make_package(duplicate_records)),
                 tmxy::package::PackageV2ErrorCode::duplicate_object_name,
                 "duplicate object name rejected");
    expect_error(test, tmxy::package::PackageV2Reader{}.parse(truncated),
                 tmxy::package::PackageV2ErrorCode::object_range_out_of_file,
                 "truncated body rejected");
    expect_error(test, tmxy::package::PackageV2Reader{}.parse(gap),
                 tmxy::package::PackageV2ErrorCode::non_contiguous_object_range,
                 "object gap rejected");
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
    return stream ? bytes : std::vector<std::byte>{};
}

[[nodiscard]] bool is_package_v2(const std::span<const std::byte> bytes)
{
    if (bytes.size() < 2U + tmxy::package::kPackageV2Version.size())
    {
        return false;
    }
    const auto length = static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[0])) |
                        (static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[1])) << 8U);
    if (length != tmxy::package::kPackageV2Version.size())
    {
        return false;
    }
    for (std::size_t index = 0; index < length; ++index)
    {
        if (std::to_integer<unsigned char>(bytes[index + 2U]) !=
            static_cast<unsigned char>(tmxy::package::kPackageV2Version[index]))
        {
            return false;
        }
    }
    return true;
}

[[nodiscard]] std::string hex_u64(const std::uint64_t value)
{
    std::ostringstream output;
    output << std::hex << std::setfill('0') << std::setw(16) << value;
    return output.str();
}

void add_fingerprint_bytes(std::uint64_t& hash, const std::string_view bytes) noexcept
{
    constexpr std::uint64_t kFnvPrime = 1'099'511'628'211ULL;
    for (const char value : bytes)
    {
        hash ^= static_cast<unsigned char>(value);
        hash *= kFnvPrime;
    }
}

void add_fingerprint_u64(std::uint64_t& hash, std::uint64_t value) noexcept
{
    constexpr std::uint64_t kFnvPrime = 1'099'511'628'211ULL;
    for (unsigned int index = 0; index < 8U; ++index)
    {
        hash ^= value & 0xFFU;
        hash *= kFnvPrime;
        value >>= 8U;
    }
}

int validate_frozen_packages(const std::filesystem::path& packages_root)
{
    std::vector<std::filesystem::path> paths;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(packages_root))
    {
        if (entry.is_regular_file())
        {
            paths.push_back(entry.path());
        }
    }
    std::ranges::sort(paths, {}, [](const auto& path) { return path.generic_string(); });

    std::uint64_t aggregate = 14'695'981'039'346'656'037ULL;
    std::uint64_t total_records = 0;
    std::uint64_t total_directory_bytes = 0;
    std::uint64_t total_file_bytes = 0;
    std::size_t sample_count = 0;
    for (const auto& path : paths)
    {
        const auto bytes = read_file(path);
        if (!is_package_v2(bytes))
        {
            continue;
        }
        const auto result = tmxy::package::PackageV2Reader{}.parse(bytes);
        if (!result.has_value())
        {
            return 1;
        }
        const auto relative = std::filesystem::relative(path, packages_root).generic_string();
        add_fingerprint_bytes(aggregate, relative);
        add_fingerprint_u64(aggregate,
                            tmxy::package::package_v2_metadata_fingerprint(result.value()));
        total_records += result.value().records.size();
        total_directory_bytes += result.value().directory_size;
        total_file_bytes += result.value().file_size;
        ++sample_count;
    }
    if (sample_count != 22U || total_records != 27'637U)
    {
        return 1;
    }
    std::cout << R"({"sample_result":"PASS","sample_count":)" << sample_count
              << R"(,"record_count":)" << total_records << R"(,"directory_bytes":)"
              << total_directory_bytes << R"(,"file_bytes":)" << total_file_bytes
              << R"(,"aggregate_fnv1a64":")" << hex_u64(aggregate) << R"("})" << '\n';
    return 0;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count == 2)
    {
        return validate_frozen_packages(arguments[1]);
    }
    if (argument_count != 1)
    {
        return 2;
    }
    TestContext test;
    test_valid_package(test);
    test_outer_errors(test);
    test_directory_errors(test);
    test_record_and_range_errors(test);
    return test.failure_count() == 0 ? 0 : 1;
}
