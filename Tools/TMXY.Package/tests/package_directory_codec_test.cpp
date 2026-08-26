#include "tmxy/package/package_directory_codec.hpp"
#include "tmxy/package/package_v2_reader.hpp"
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
#include <ranges>
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

enum class PackageKind : std::uint8_t
{
    other = 0,
    v2 = 2,
    v3 = 3,
};

[[nodiscard]] std::byte invert_byte(const std::byte value) noexcept
{
    return static_cast<std::byte>(static_cast<std::uint8_t>(~std::to_integer<std::uint8_t>(value)));
}

void test_fixed_vectors(TestContext& test)
{
    constexpr std::array decoded{std::byte{0x03}, std::byte{0x00}, std::byte{0x76},
                                 std::byte{0x65}};
    constexpr std::array expected_v2{std::byte{0x89}, std::byte{0x9A}, std::byte{0xFC},
                                     std::byte{0xFF}};
    constexpr std::array expected_v3{std::byte{0x76}, std::byte{0x9A}, std::byte{0xFC},
                                     std::byte{0xFF}};
    test.expect(std::ranges::equal(tmxy::package::encode_package_directory(
                                       tmxy::package::PackageDirectoryVersion::v2, decoded),
                                   expected_v2),
                "Package 2.0 fixed directory vector");
    test.expect(std::ranges::equal(tmxy::package::encode_package_directory(
                                       tmxy::package::PackageDirectoryVersion::v3, decoded),
                                   expected_v3),
                "Package 3.0 fixed directory vector");
}

void test_all_remainders(TestContext& test)
{
    for (const auto version :
         {tmxy::package::PackageDirectoryVersion::v2, tmxy::package::PackageDirectoryVersion::v3})
    {
        for (std::size_t size = 0; size < 20U; ++size)
        {
            std::vector<std::byte> decoded(size);
            for (std::size_t index = 0; index < size; ++index)
            {
                decoded[index] = static_cast<std::byte>((index * 37U + size) & 0xFFU);
            }
            const auto encoded = tmxy::package::encode_package_directory(version, decoded);
            test.expect(tmxy::package::decode_package_directory(version, encoded) == decoded,
                        "directory encode/decode round trip");
            auto arbitrary = encoded;
            std::ranges::transform(arbitrary, arbitrary.begin(), invert_byte);
            const auto decoded_arbitrary =
                tmxy::package::decode_package_directory(version, arbitrary);
            test.expect(tmxy::package::encode_package_directory(version, decoded_arbitrary) ==
                            arbitrary,
                        "directory decode/encode round trip");
        }
    }
}

void test_offset_mapping(TestContext& test)
{
    constexpr std::array expected_full{31U, 32U, 29U, 30U};
    for (std::size_t decoded = 0; decoded < expected_full.size(); ++decoded)
    {
        const auto actual = tmxy::package::map_package_directory_offset({
            .version = tmxy::package::PackageDirectoryVersion::v2,
            .file_offset = 29U,
            .directory_size = 8U,
            .decoded_offset = decoded,
        });
        test.expect(actual == expected_full[decoded], "full-group offset mapping");
    }
    constexpr std::array expected_v3_tail{35U, 33U, 34U};
    for (std::size_t tail = 0; tail < expected_v3_tail.size(); ++tail)
    {
        const auto actual = tmxy::package::map_package_directory_offset({
            .version = tmxy::package::PackageDirectoryVersion::v3,
            .file_offset = 29U,
            .directory_size = 7U,
            .decoded_offset = 4U + tail,
        });
        test.expect(actual == expected_v3_tail[tail], "Package 3.0 tail offset mapping");
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
    return stream ? bytes : std::vector<std::byte>{};
}

[[nodiscard]] bool has_version(const std::span<const std::byte> bytes,
                               const std::string_view version)
{
    if (bytes.size() < 2U + version.size())
    {
        return false;
    }
    const auto length = static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[0])) |
                        (static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[1])) << 8U);
    if (length != version.size())
    {
        return false;
    }
    for (std::size_t index = 0; index < length; ++index)
    {
        if (std::to_integer<unsigned char>(bytes[index + 2U]) !=
            static_cast<unsigned char>(version[index]))
        {
            return false;
        }
    }
    return true;
}

[[nodiscard]] PackageKind detect_package(const std::span<const std::byte> bytes)
{
    if (has_version(bytes, tmxy::package::kPackageV2Version))
    {
        return PackageKind::v2;
    }
    if (has_version(bytes, tmxy::package::kPackageV3Version))
    {
        return PackageKind::v3;
    }
    return PackageKind::other;
}

[[nodiscard]] std::int32_t read_i32(const std::span<const std::byte> bytes,
                                    const std::size_t offset) noexcept
{
    const auto raw =
        static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset])) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset + 1U])) << 8U) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset + 2U])) << 16U) |
        (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset + 3U])) << 24U);
    return std::bit_cast<std::int32_t>(raw);
}

void add_fingerprint_bytes(std::uint64_t& hash, const std::span<const std::byte> bytes) noexcept
{
    constexpr std::uint64_t kFnvPrime = 1'099'511'628'211ULL;
    for (const auto value : bytes)
    {
        hash ^= std::to_integer<std::uint8_t>(value);
        hash *= kFnvPrime;
    }
}

void add_fingerprint_string(std::uint64_t& hash, const std::string_view bytes) noexcept
{
    add_fingerprint_bytes(hash, std::as_bytes(std::span<const char>(bytes.data(), bytes.size())));
}

[[nodiscard]] std::string hex_u64(const std::uint64_t value)
{
    std::ostringstream output;
    output << std::hex << std::setfill('0') << std::setw(16) << value;
    return output.str();
}

struct ValidationTotals final
{
    std::uint64_t v2_samples{0};
    std::uint64_t v3_samples{0};
    std::uint64_t records{0};
    std::uint64_t directory_bytes{0};
    std::uint64_t file_bytes{0};
    std::uint64_t fingerprint{14'695'981'039'346'656'037ULL};
};

struct PackageValidationInput final
{
    const std::filesystem::path& path;
    const std::filesystem::path& packages_root;
    std::span<const std::byte> bytes;
    PackageKind kind{PackageKind::other};
};

[[nodiscard]] bool validate_package(const PackageValidationInput& input, ValidationTotals& totals)
{
    const auto bytes = input.bytes;
    if (bytes.size() < 29U)
    {
        return false;
    }
    const auto raw_directory_size = read_i32(bytes, 25U);
    if (raw_directory_size < 0)
    {
        return false;
    }
    const auto directory_size = static_cast<std::size_t>(raw_directory_size);
    if (directory_size > bytes.size() - 29U)
    {
        return false;
    }
    const auto version = input.kind == PackageKind::v2 ? tmxy::package::PackageDirectoryVersion::v2
                                                       : tmxy::package::PackageDirectoryVersion::v3;
    const auto encoded = bytes.subspan(29U, directory_size);
    const auto decoded = tmxy::package::decode_package_directory(version, encoded);
    if (tmxy::package::encode_package_directory(version, decoded) !=
        std::vector<std::byte>(encoded.begin(), encoded.end()))
    {
        return false;
    }

    std::uint64_t record_count = 0;
    if (input.kind == PackageKind::v2)
    {
        const auto parsed = tmxy::package::PackageV2Reader{}.parse(bytes);
        if (!parsed.has_value())
        {
            return false;
        }
        record_count = parsed.value().records.size();
        ++totals.v2_samples;
    }
    else
    {
        const auto parsed = tmxy::package::PackageV3Reader{}.parse(bytes);
        if (!parsed.has_value())
        {
            return false;
        }
        record_count = parsed.value().records.size();
        ++totals.v3_samples;
    }
    const auto relative =
        std::filesystem::relative(input.path, input.packages_root).generic_string();
    add_fingerprint_string(totals.fingerprint, relative);
    add_fingerprint_bytes(totals.fingerprint, decoded);
    totals.records += record_count;
    totals.directory_bytes += directory_size;
    totals.file_bytes += bytes.size();
    return true;
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

    ValidationTotals totals;
    for (const auto& path : paths)
    {
        const auto bytes = read_file(path);
        const auto kind = detect_package(bytes);
        if (kind == PackageKind::other)
        {
            continue;
        }
        if (!validate_package(
                {
                    .path = path,
                    .packages_root = packages_root,
                    .bytes = bytes,
                    .kind = kind,
                },
                totals))
        {
            return 1;
        }
    }
    if (totals.v2_samples != 22U || totals.v3_samples != 140U || totals.records != 118'711U ||
        totals.directory_bytes != 5'364'459U)
    {
        return 1;
    }
    std::cout << R"({"sample_result":"PASS","v2_sample_count":)" << totals.v2_samples
              << R"(,"v3_sample_count":)" << totals.v3_samples << R"(,"record_count":)"
              << totals.records << R"(,"directory_bytes":)" << totals.directory_bytes
              << R"(,"file_bytes":)" << totals.file_bytes << R"(,"decoded_fnv1a64":")"
              << hex_u64(totals.fingerprint) << R"("})" << '\n';
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
    test_fixed_vectors(test);
    test_all_remainders(test);
    test_offset_mapping(test);
    return test.failure_count() == 0 ? 0 : 1;
}
