#include "tmxy/package/package_v3_reader.hpp"

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

struct I32Overwrite final
{
    std::size_t position{0};
    std::int32_t value{0};
};

struct DirectoryI32Mutation final
{
    std::size_t decoded_offset{0};
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

[[nodiscard]] std::byte invert_byte(const std::byte value) noexcept
{
    return static_cast<std::byte>(static_cast<std::uint8_t>(~std::to_integer<std::uint8_t>(value)));
}

void encode_tail(const std::span<const std::byte> decoded, std::span<std::byte> encoded)
{
    if (decoded.size() == 1U)
    {
        encoded[0] = decoded[0];
        return;
    }
    if (decoded.size() == 2U)
    {
        encoded[0] = decoded[0];
        encoded[1] = invert_byte(decoded[1]);
        return;
    }
    if (decoded.size() == 3U)
    {
        encoded[0] = decoded[1];
        encoded[1] = invert_byte(decoded[2]);
        encoded[2] = invert_byte(decoded[0]);
    }
}

[[nodiscard]] std::vector<std::byte> encode_directory(const std::span<const std::byte> decoded)
{
    std::vector<std::byte> encoded(decoded.size());
    const auto full_bytes = decoded.size() - (decoded.size() % 4U);
    for (std::size_t offset = 0; offset < full_bytes; offset += 4U)
    {
        encoded[offset] = decoded[offset + 2U];
        encoded[offset + 1U] = invert_byte(decoded[offset + 3U]);
        encoded[offset + 2U] = invert_byte(decoded[offset]);
        encoded[offset + 3U] = invert_byte(decoded[offset + 1U]);
    }
    encode_tail(decoded.subspan(full_bytes), std::span<std::byte>(encoded).subspan(full_bytes));
    return encoded;
}

[[nodiscard]] std::vector<std::byte> decode_directory(const std::span<const std::byte> encoded)
{
    std::vector<std::byte> decoded(encoded.size());
    const auto full_bytes = encoded.size() - (encoded.size() % 4U);
    for (std::size_t offset = 0; offset < full_bytes; offset += 4U)
    {
        decoded[offset] = invert_byte(encoded[offset + 2U]);
        decoded[offset + 1U] = invert_byte(encoded[offset + 3U]);
        decoded[offset + 2U] = encoded[offset];
        decoded[offset + 3U] = invert_byte(encoded[offset + 1U]);
    }
    const auto remainder = encoded.size() % 4U;
    if (remainder == 1U)
    {
        decoded[full_bytes] = encoded[full_bytes];
    }
    else if (remainder == 2U)
    {
        decoded[full_bytes] = encoded[full_bytes];
        decoded[full_bytes + 1U] = invert_byte(encoded[full_bytes + 1U]);
    }
    else if (remainder == 3U)
    {
        decoded[full_bytes] = invert_byte(encoded[full_bytes + 2U]);
        decoded[full_bytes + 1U] = encoded[full_bytes];
        decoded[full_bytes + 2U] = invert_byte(encoded[full_bytes + 1U]);
    }
    return decoded;
}

[[nodiscard]] std::size_t directory_size(const std::span<const SyntheticRecord> records)
{
    std::size_t size = tmxy::package::kPackageV3DirectoryPrefix.size() + 4U;
    for (const auto& record : records)
    {
        size += 2U + record.name.size() + 2U + record.class_name.size() + 8U;
    }
    return size;
}

[[nodiscard]] std::vector<std::byte> make_package(const std::span<const SyntheticRecord> records)
{
    std::vector<std::byte> directory(tmxy::package::kPackageV3DirectoryPrefix.begin(),
                                     tmxy::package::kPackageV3DirectoryPrefix.end());
    append_i32(directory, static_cast<std::int32_t>(records.size()));
    const auto blob_size = directory_size(records);
    std::size_t object_offset = 2U + tmxy::package::kPackageV3Version.size() + 4U + blob_size;
    for (const auto& record : records)
    {
        append_string(directory, record.name);
        append_string(directory, record.class_name);
        append_i32(directory, static_cast<std::int32_t>(object_offset));
        append_i32(directory, static_cast<std::int32_t>(record.body.size()));
        object_offset += record.body.size();
    }

    std::vector<std::byte> bytes;
    append_string(bytes, tmxy::package::kPackageV3Version);
    append_i32(bytes, static_cast<std::int32_t>(directory.size()));
    const auto encoded = encode_directory(directory);
    bytes.insert(bytes.end(), encoded.begin(), encoded.end());
    for (const auto& record : records)
    {
        bytes.insert(bytes.end(), record.body.begin(), record.body.end());
    }
    return bytes;
}

[[nodiscard]] std::vector<std::byte> mutate_directory_i32(std::vector<std::byte> package,
                                                          const DirectoryI32Mutation mutation)
{
    constexpr std::size_t kOuterHeaderSize = 29;
    const auto directory_bytes = static_cast<std::size_t>(std::bit_cast<std::int32_t>(
        static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(package[25])) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(package[26])) << 8U) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(package[27])) << 16U) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(package[28])) << 24U)));
    auto decoded = decode_directory(
        std::span<const std::byte>(package).subspan(kOuterHeaderSize, directory_bytes));
    overwrite_i32(decoded, {.position = mutation.decoded_offset, .value = mutation.value});
    const auto encoded = encode_directory(decoded);
    std::ranges::copy(encoded, package.begin() + static_cast<std::ptrdiff_t>(kOuterHeaderSize));
    return package;
}

void expect_error(TestContext& test, const tmxy::package::PackageV3ParseResult& result,
                  const tmxy::package::PackageV3ErrorCode code, const std::string_view message)
{
    test.expect(!result.has_value() && result.error().code == code, message);
}

void test_valid_and_tail_variants(TestContext& test)
{
    for (std::size_t name_size = 1; name_size <= 4U; ++name_size)
    {
        const std::array records{SyntheticRecord{
            .name = std::string(name_size, 'n'),
            .class_name = "C",
            .body = std::vector<std::byte>(559U, std::byte{0x5A}),
        }};
        const auto result = tmxy::package::PackageV3Reader{}.parse(make_package(records));
        test.expect(result.has_value(), "Package 3.0 tail remainder parses");
        if (result.has_value())
        {
            test.expect(result.value().directory_size % 4U == (name_size + 3U) % 4U,
                        "requested directory remainder reached");
            test.expect(result.value().records[0].size == 559U, "tail preserves object size");
        }
    }
}

void test_corruption_errors(TestContext& test)
{
    const std::array records{SyntheticRecord{
        .name = "one", .class_name = "QActor", .body = {std::byte{0x01}, std::byte{0x02}}}};
    const auto valid = make_package(records);
    auto wrong_version = valid;
    wrong_version[2] = std::byte{0x58};
    auto negative_size = valid;
    overwrite_i32(negative_size, {.position = 25U, .value = -1});
    auto prefix = valid;
    prefix[31] = std::byte{0x7F};
    const auto negative_count = mutate_directory_i32(valid, {.decoded_offset = 14U, .value = -1});
    const auto limited = tmxy::package::PackageV3Reader{{.maximum_object_count = 0}}.parse(valid);
    auto truncated = valid;
    truncated.pop_back();
    constexpr std::size_t kFirstOffset = 18U + 2U + 3U + 2U + 6U;
    const auto expected_offset = static_cast<std::int32_t>(valid.size() - records[0].body.size());
    const auto gap =
        mutate_directory_i32(valid, {.decoded_offset = kFirstOffset, .value = expected_offset + 1});

    expect_error(test, tmxy::package::PackageV3Reader{}.parse(wrong_version),
                 tmxy::package::PackageV3ErrorCode::invalid_version, "invalid version rejected");
    expect_error(test, tmxy::package::PackageV3Reader{}.parse(negative_size),
                 tmxy::package::PackageV3ErrorCode::negative_directory_size,
                 "negative directory size rejected");
    const auto prefix_result = tmxy::package::PackageV3Reader{}.parse(prefix);
    expect_error(test, prefix_result, tmxy::package::PackageV3ErrorCode::invalid_directory_prefix,
                 "invalid directory prefix rejected");
    test.expect(prefix_result.error().absolute_offset == 31U,
                "decoded error maps to encoded file offset");
    expect_error(test, tmxy::package::PackageV3Reader{}.parse(negative_count),
                 tmxy::package::PackageV3ErrorCode::negative_object_count,
                 "negative object count rejected");
    expect_error(test, limited, tmxy::package::PackageV3ErrorCode::object_count_limit_exceeded,
                 "object count limit enforced");
    expect_error(test, tmxy::package::PackageV3Reader{}.parse(truncated),
                 tmxy::package::PackageV3ErrorCode::object_range_out_of_file,
                 "truncated object body rejected");
    expect_error(test, tmxy::package::PackageV3Reader{}.parse(gap),
                 tmxy::package::PackageV3ErrorCode::non_contiguous_object_range,
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

[[nodiscard]] bool is_package_v3(const std::span<const std::byte> bytes)
{
    if (bytes.size() < 2U + tmxy::package::kPackageV3Version.size())
    {
        return false;
    }
    const auto length = static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[0])) |
                        (static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[1])) << 8U);
    if (length != tmxy::package::kPackageV3Version.size())
    {
        return false;
    }
    for (std::size_t index = 0; index < length; ++index)
    {
        if (std::to_integer<unsigned char>(bytes[index + 2U]) !=
            static_cast<unsigned char>(tmxy::package::kPackageV3Version[index]))
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
        if (!is_package_v3(bytes))
        {
            continue;
        }
        const auto result = tmxy::package::PackageV3Reader{}.parse(bytes);
        if (!result.has_value())
        {
            return 1;
        }
        const auto relative = std::filesystem::relative(path, packages_root).generic_string();
        add_fingerprint_bytes(aggregate, relative);
        add_fingerprint_u64(aggregate,
                            tmxy::package::package_v3_metadata_fingerprint(result.value()));
        total_records += result.value().records.size();
        total_directory_bytes += result.value().directory_size;
        total_file_bytes += result.value().file_size;
        ++sample_count;
    }
    if (sample_count != 140U || total_records != 91'074U)
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
    test_valid_and_tail_variants(test);
    test_corruption_errors(test);
    return test.failure_count() == 0 ? 0 : 1;
}
