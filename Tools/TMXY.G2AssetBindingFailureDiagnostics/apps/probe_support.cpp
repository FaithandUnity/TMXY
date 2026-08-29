#include "probe_support.hpp"

#include "sha256.hpp"
#include "tmxy/package/package_normalized_tree.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3_reader.hpp"

#include <algorithm>
#include <charconv>
#include <exception>
#include <fstream>
#include <limits>
#include <optional>
#include <ranges>
#include <set>
#include <utility>

namespace tmxy::g2_asset_binding_failure
{
namespace
{

using tmxy::g2_asset_descriptor_diagnostics::sha256_hex;
struct IdentityKey final
{
    std::string package_path;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    std::string class_name;
    [[nodiscard]] auto operator<=>(const IdentityKey&) const = default;
};

[[nodiscard]] bool is_safe_relative_path(const std::string_view value) noexcept
{
    if (value.empty() || value.front() == '/' || value.find('\\') != std::string_view::npos ||
        value.find(':') != std::string_view::npos)
    {
        return false;
    }
    std::size_t start = 0;
    while (start <= value.size())
    {
        const auto end = value.find('/', start);
        const auto part = value.substr(
            start, end == std::string_view::npos ? value.size() - start : end - start);
        if (part.empty() || part == "." || part == ".." ||
            std::ranges::any_of(part, [](const unsigned char byte) { return byte < 0x20U; }))
        {
            return false;
        }
        if (end == std::string_view::npos)
        {
            break;
        }
        start = end + 1U;
    }
    return true;
}

[[nodiscard]] std::uint64_t parse_u64(const std::string_view text)
{
    if (text.empty() || (text.size() > 1U && text.front() == '0'))
    {
        fail("noncanonical_integer");
    }
    std::uint64_t value = 0;
    const auto result = std::from_chars(text.data(), text.data() + text.size(), value);
    if (result.ec != std::errc{} || result.ptr != text.data() + text.size())
    {
        fail("invalid_integer");
    }
    return value;
}

[[nodiscard]] std::vector<std::string> split_exact(const std::string& line,
                                                   const char separator,
                                                   const std::size_t expected)
{
    std::vector<std::string> fields;
    std::size_t start = 0;
    while (true)
    {
        const auto end = line.find(separator, start);
        fields.push_back(line.substr(start, end == std::string::npos ? std::string::npos
                                                                    : end - start));
        if (end == std::string::npos)
        {
            break;
        }
        start = end + 1U;
    }
    if (fields.size() != expected)
    {
        fail("invalid_tsv_field_count");
    }
    return fields;
}

[[nodiscard]] std::vector<std::string> parse_ids(const std::string& value)
{
    if (value.empty())
    {
        fail("candidate_set_empty");
    }
    auto ids = split_exact(value, ',',
                           static_cast<std::size_t>(std::ranges::count(value, ',') + 1));
    if (std::ranges::any_of(ids, [](const auto& id) { return !is_lower_hex_sha256(id); }))
    {
        fail("candidate_id_invalid");
    }
    std::ranges::sort(ids);
    if (std::ranges::adjacent_find(ids) != ids.end())
    {
        fail("candidate_id_duplicate");
    }
    return ids;
}

[[nodiscard]] bool has_version(const std::span<const std::byte> bytes,
                               const std::string_view version) noexcept
{
    if (bytes.size() < version.size() + 2U)
    {
        return false;
    }
    const auto size = static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[0])) |
                      (static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[1])) << 8U);
    return size == version.size() &&
           std::ranges::equal(bytes.subspan(2U, size), version,
                              [](const std::byte left, const char right)
                              {
                                  return std::to_integer<unsigned char>(left) ==
                                         static_cast<unsigned char>(right);
                              });
}

[[nodiscard]] tmxy::package::NormalizedPackageTree
read_package_tree(const std::span<const std::byte> bytes, const std::string& label)
{
    if (has_version(bytes, tmxy::package::kPackageV1Version))
    {
        auto parsed = tmxy::package::PackageV1Reader{}.parse(bytes);
        if (!parsed.has_value()) { fail("recognized_package_parse_failed"); }
        return tmxy::package::normalize_package_tree(parsed.value(), label);
    }
    if (has_version(bytes, tmxy::package::kPackageV2Version))
    {
        auto parsed = tmxy::package::PackageV2Reader{}.parse(bytes);
        if (!parsed.has_value()) { fail("recognized_package_parse_failed"); }
        return tmxy::package::normalize_package_tree(parsed.value(), label);
    }
    if (has_version(bytes, tmxy::package::kPackageV3Version))
    {
        auto parsed = tmxy::package::PackageV3Reader{}.parse(bytes);
        if (!parsed.has_value()) { fail("recognized_package_parse_failed"); }
        return tmxy::package::normalize_package_tree(parsed.value(), label);
    }
    fail("candidate_package_version_unrecognized");
}

} // namespace

ProbeFailure::ProbeFailure(std::string category) : category_(std::move(category)) {}
const char* ProbeFailure::what() const noexcept { return category_.c_str(); }

[[noreturn]] void fail(const std::string_view category)
{
    throw ProbeFailure(std::string(category));
}

bool is_lower_hex_sha256(const std::string_view value) noexcept
{
    return value.size() == 64U && std::ranges::all_of(value, [](const char character)
    {
        return (character >= '0' && character <= '9') ||
               (character >= 'a' && character <= 'f');
    });
}

std::string lower_ascii(std::string value)
{
    std::ranges::transform(value, value.begin(), [](const unsigned char character)
    {
        return character >= 'A' && character <= 'Z'
                   ? static_cast<char>(character + ('a' - 'A'))
                   : static_cast<char>(character);
    });
    return value;
}

std::filesystem::path safe_join(const std::filesystem::path& root,
                                const std::string_view relative)
{
    if (!is_safe_relative_path(relative)) { fail("unsafe_relative_path"); }
    const auto canonical_root = std::filesystem::weakly_canonical(root);
    const auto candidate = std::filesystem::weakly_canonical(root / std::filesystem::path(relative));
    auto root_text = lower_ascii(canonical_root.generic_string());
    const auto candidate_text = lower_ascii(candidate.generic_string());
    if (!root_text.empty() && root_text.back() != '/') { root_text.push_back('/'); }
    if (!candidate_text.starts_with(root_text)) { fail("relative_path_escape"); }
    return candidate;
}

std::vector<std::byte> read_file(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) { fail("input_file_unreadable"); }
    const auto end = stream.tellg();
    if (end < 0 || end > std::numeric_limits<std::streamsize>::max())
    {
        fail("input_file_size_invalid");
    }
    std::vector<std::byte> bytes(static_cast<std::size_t>(end));
    stream.seekg(0);
    if (!bytes.empty())
    {
        stream.read(reinterpret_cast<char*>(bytes.data()),
                    static_cast<std::streamsize>(bytes.size()));
    }
    if (!stream) { fail("input_file_read_failed"); }
    return bytes;
}

std::vector<AssetEntry> read_asset_tsv(const std::filesystem::path& path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input) { fail("asset_tsv_unreadable"); }
    std::vector<AssetEntry> result;
    std::set<std::string> seen;
    std::string line;
    while (std::getline(input, line))
    {
        if (!line.empty() && line.back() == '\r') { line.pop_back(); }
        auto fields = split_exact(line, '\t', 8U);
        auto ids = parse_ids(fields[7]);
        if (!is_lower_hex_sha256(fields[0]) || !seen.insert(fields[0]).second ||
            !is_safe_relative_path(fields[1]) || !is_lower_hex_sha256(fields[2]) ||
            !is_lower_hex_sha256(fields[6]) || candidate_set_sha256(ids) != fields[6] ||
            (fields[4] != "anim" && fields[4] != "qtx" && fields[4] != "sm"))
        {
            fail("asset_tsv_row_invalid");
        }
        result.push_back({std::move(fields[0]), std::move(fields[1]), std::move(fields[2]),
                          parse_u64(fields[3]), std::move(fields[4]), std::move(fields[5]),
                          std::move(fields[6]), std::move(ids)});
    }
    if (!input.eof()) { fail("asset_tsv_read_failed"); }
    return result;
}

std::vector<CandidateInput> read_candidate_tsv(const std::filesystem::path& path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input) { fail("candidate_tsv_unreadable"); }
    std::vector<CandidateInput> result;
    std::set<std::string> seen;
    std::string line;
    while (std::getline(input, line))
    {
        if (!line.empty() && line.back() == '\r') { line.pop_back(); }
        auto fields = split_exact(line, '\t', 5U);
        if (!is_lower_hex_sha256(fields[0]) || !seen.insert(fields[0]).second ||
            !is_safe_relative_path(fields[1]) || !fields[1].starts_with("Packages/") ||
            (fields[4] != "QTexture" && fields[4] != "QStaticMesh" && fields[4] != "QSkelMesh"))
        {
            fail("candidate_tsv_row_invalid");
        }
        result.push_back({std::move(fields[0]), std::move(fields[1]), parse_u64(fields[2]),
                          parse_u64(fields[3]), std::move(fields[4])});
    }
    if (!input.eof()) { fail("candidate_tsv_read_failed"); }
    return result;
}

CandidateIndex load_candidates(const std::filesystem::path& client_root,
                               const std::vector<CandidateInput>& expected)
{
    std::map<IdentityKey, const CandidateInput*> by_identity;
    std::map<std::string, std::vector<const CandidateInput*>> by_package;
    for (const auto& candidate : expected)
    {
        const IdentityKey key{candidate.package_path, candidate.body_offset,
                              candidate.body_size, candidate.class_name};
        if (!by_identity.emplace(key, &candidate).second) { fail("candidate_identity_duplicate"); }
        by_package[candidate.package_path].push_back(&candidate);
    }
    CandidateIndex result;
    for (const auto& [package_path, required] : by_package)
    {
        static_cast<void>(required);
        auto bytes = read_file(safe_join(client_root, package_path));
        auto tree = read_package_tree(bytes, package_path);
        auto inserted = result.packages.emplace(package_path,
                                                PackageData{package_path, std::move(bytes)});
        for (const auto& object : tree.objects)
        {
            const IdentityKey key{package_path, object.body_offset, object.body_size,
                                  object.class_name_bytes};
            const auto found = by_identity.find(key);
            if (found == by_identity.end()) { continue; }
            std::string identity(package_path);
            identity.push_back('\0');
            identity.append(object.name_bytes);
            if (sha256_hex(std::string_view(identity.data(), identity.size())) != found->second->id)
            {
                fail("candidate_id_drift");
            }
            const auto& package = inserted.first->second;
            if (object.body_offset > package.bytes.size() ||
                object.body_size > package.bytes.size() - object.body_offset)
            {
                fail("candidate_body_range_invalid");
            }
            if (!result.candidates.emplace(
                    found->second->id,
                    Candidate{found->second->id, package_path, object.name_bytes,
                              object.body_offset, object.body_size, object.class_name_bytes}).second)
            {
                fail("candidate_match_duplicate");
            }
        }
    }
    if (result.candidates.size() != expected.size()) { fail("candidate_coverage_incomplete"); }
    return result;
}

std::span<const std::byte> candidate_body(const CandidateIndex& index,
                                          const Candidate& candidate)
{
    const auto& bytes = index.packages.at(candidate.package_path).bytes;
    return std::span<const std::byte>(bytes.data(), bytes.size())
        .subspan(static_cast<std::size_t>(candidate.body_offset),
                 static_cast<std::size_t>(candidate.body_size));
}

std::string candidate_set_sha256(const std::vector<std::string>& ids)
{
    auto sorted = ids;
    std::ranges::sort(sorted);
    std::string canonical;
    for (const auto& id : sorted)
    {
        canonical.append(id);
        canonical.push_back('\n');
    }
    return sha256_hex(std::string_view(canonical.data(), canonical.size()));
}

} // namespace tmxy::g2_asset_binding_failure
