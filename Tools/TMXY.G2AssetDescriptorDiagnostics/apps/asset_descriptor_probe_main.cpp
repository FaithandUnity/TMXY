#include "descriptor_semantic_signature.hpp"
#include "probe_output.hpp"
#include "probe_types.hpp"
#include "qtx_recovery.hpp"
#include "recovery_plan.hpp"
#include "semantic_hash.hpp"
#include "sha256.hpp"
#include "tmxy/animation/package_animation_reader.hpp"
#include "tmxy/package/package_normalized_tree.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3_reader.hpp"
#include "tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp"
#include "tmxy/static_mesh/package_static_mesh_reader.hpp"
#include "tmxy/texture/legacy_texture_descriptor_reader.hpp"
#include "tmxy/texture/qtx_reader.hpp"

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace
{

using tmxy::g2_asset_descriptor_diagnostics::apply_qtx_recovery;
using tmxy::g2_asset_descriptor_diagnostics::AssetResult;
using tmxy::g2_asset_descriptor_diagnostics::CandidateResult;
using tmxy::g2_asset_descriptor_diagnostics::descriptor_semantic_sha256;
using tmxy::g2_asset_descriptor_diagnostics::emit_result;
using tmxy::g2_asset_descriptor_diagnostics::normalized_semantic_sha256;
using tmxy::g2_asset_descriptor_diagnostics::qtx_recovery_self_test;
using tmxy::g2_asset_descriptor_diagnostics::RecoveryDirective;
using tmxy::g2_asset_descriptor_diagnostics::RecoveryPlan;
using tmxy::g2_asset_descriptor_diagnostics::semantic_sha256;
using tmxy::g2_asset_descriptor_diagnostics::sha256_hex;
constexpr std::string_view kCandidateSetDomain = "tmxy-g2-asset-descriptor-candidate-set-v1";

struct AssetEntry final
{
    std::string id;
    std::string relative_path;
    std::string source_sha256;
    std::uint64_t bytes{0};
    std::string family;
    std::string structure;
    std::vector<std::string> expected_candidate_ids;
};

struct CandidateMapEntry final
{
    std::string id;
    std::string package_path;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    std::string class_name;
    bool matched{false};
};

struct IdentityKey final
{
    std::string package_path;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    std::string class_name;

    [[nodiscard]] auto operator<=>(const IdentityKey&) const = default;
};

struct PackageData final
{
    std::string relative_path;
    std::vector<std::byte> bytes;
};

struct Candidate final
{
    std::string id;
    std::size_t package_index{0};
    std::string object_name;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    std::string class_name;
};

struct PackageIndex final
{
    std::vector<PackageData> packages;
    std::vector<Candidate> candidates;
    std::unordered_map<std::string, std::vector<std::size_t>> by_class_and_lower_name;
};

enum class FieldSeparator : char
{
    comma = ',',
    tab = '\t',
};

struct ClassLookupParts final
{
    std::string_view class_name;
    std::string_view lower_name;
};

class ProbeFailure final : public std::exception
{
  public:
    explicit ProbeFailure(std::string category) : category_(std::move(category)) {}

    [[nodiscard]] const char* what() const noexcept override
    {
        return category_.c_str();
    }

  private:
    std::string category_;
};

[[noreturn]] void fail(const std::string_view category)
{
    throw ProbeFailure(std::string(category));
}

[[nodiscard]] bool is_lower_hex_sha256(const std::string_view value) noexcept
{
    return value.size() == 64U &&
           std::ranges::all_of(value,
                               [](const char character)
                               {
                                   return (character >= '0' && character <= '9') ||
                                          (character >= 'a' && character <= 'f');
                               });
}

[[nodiscard]] bool is_safe_token(const std::string_view value) noexcept
{
    return !value.empty() &&
           std::ranges::all_of(value,
                               [](const unsigned char character)
                               {
                                   return (character >= 'A' && character <= 'Z') ||
                                          (character >= 'a' && character <= 'z') ||
                                          (character >= '0' && character <= '9') ||
                                          character == '_' || character == '-' ||
                                          character == '.' || character == ':';
                               });
}

[[nodiscard]] std::string lower_ascii(std::string value)
{
    std::ranges::transform(value, value.begin(),
                           [](const unsigned char character)
                           {
                               if (character >= 'A' && character <= 'Z')
                               {
                                   return static_cast<char>(character + ('a' - 'A'));
                               }
                               return static_cast<char>(character);
                           });
    return value;
}

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
        const auto component =
            value.substr(start, end == std::string_view::npos ? value.size() - start : end - start);
        if (component.empty() || component == "." || component == ".." ||
            std::ranges::any_of(component, [](const unsigned char byte) { return byte < 0x20U; }))
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

[[nodiscard]] std::filesystem::path safe_join(const std::filesystem::path& root,
                                              const std::string_view relative)
{
    if (!is_safe_relative_path(relative))
    {
        fail("unsafe_relative_path");
    }
    const auto canonical_root = std::filesystem::weakly_canonical(root);
    const auto candidate =
        std::filesystem::weakly_canonical(root / std::filesystem::path(relative));
    auto root_text = lower_ascii(canonical_root.generic_string());
    auto candidate_text = lower_ascii(candidate.generic_string());
    if (!root_text.empty() && root_text.back() != '/')
    {
        root_text.push_back('/');
    }
    if (candidate_text.size() < root_text.size() || !candidate_text.starts_with(root_text))
    {
        fail("relative_path_escape");
    }
    return candidate;
}

[[nodiscard]] std::vector<std::byte> read_file(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream)
    {
        fail("input_file_unreadable");
    }
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
    if (!stream)
    {
        fail("input_file_read_failed");
    }
    return bytes;
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
                                                   const FieldSeparator field_separator,
                                                   const std::size_t expected_fields)
{
    const auto separator = static_cast<char>(field_separator);
    std::vector<std::string> fields;
    std::size_t start = 0;
    while (true)
    {
        const auto end = line.find(separator, start);
        fields.push_back(
            line.substr(start, end == std::string::npos ? std::string::npos : end - start));
        if (end == std::string::npos)
        {
            break;
        }
        start = end + 1U;
    }
    if (fields.size() != expected_fields)
    {
        fail("invalid_tsv_field_count");
    }
    return fields;
}

[[nodiscard]] std::vector<std::string> parse_candidate_ids(const std::string& text)
{
    if (text.empty())
    {
        return {};
    }
    auto ids = split_exact(text, FieldSeparator::comma,
                           static_cast<std::size_t>(std::ranges::count(text, ',') + 1));
    for (const auto& id : ids)
    {
        if (!is_lower_hex_sha256(id))
        {
            fail("invalid_candidate_id");
        }
    }
    std::ranges::sort(ids);
    if (std::ranges::adjacent_find(ids) != ids.end())
    {
        fail("duplicate_expected_candidate_id");
    }
    return ids;
}

[[nodiscard]] std::vector<AssetEntry> read_asset_tsv(const std::filesystem::path& path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input)
    {
        fail("asset_tsv_unreadable");
    }
    std::vector<AssetEntry> entries;
    std::set<std::string> ids;
    std::string line;
    while (std::getline(input, line))
    {
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        if (line.empty())
        {
            fail("empty_asset_tsv_row");
        }
        auto fields = split_exact(line, FieldSeparator::tab, 7U);
        if (!is_lower_hex_sha256(fields[0]) || !ids.insert(fields[0]).second ||
            !is_safe_relative_path(fields[1]) || !is_lower_hex_sha256(fields[2]) ||
            !is_safe_token(fields[5]))
        {
            fail("invalid_asset_tsv_row");
        }
        const auto family = lower_ascii(fields[4]);
        if (family != fields[4] ||
            (family != "qtx" && family != "sm" && family != "skem" && family != "anim"))
        {
            fail("unsupported_asset_family");
        }
        entries.push_back({.id = std::move(fields[0]),
                           .relative_path = std::move(fields[1]),
                           .source_sha256 = std::move(fields[2]),
                           .bytes = parse_u64(fields[3]),
                           .family = family,
                           .structure = std::move(fields[5]),
                           .expected_candidate_ids = parse_candidate_ids(fields[6])});
    }
    if (!input.eof())
    {
        fail("asset_tsv_read_failed");
    }
    return entries;
}

[[nodiscard]] std::map<IdentityKey, CandidateMapEntry>
read_candidate_map_tsv(const std::filesystem::path& path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input)
    {
        fail("candidate_map_unreadable");
    }
    std::map<IdentityKey, CandidateMapEntry> entries;
    std::set<std::string> ids;
    std::string line;
    while (std::getline(input, line))
    {
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        if (line.empty())
        {
            fail("empty_candidate_map_row");
        }
        auto fields = split_exact(line, FieldSeparator::tab, 5U);
        if (!is_lower_hex_sha256(fields[0]) || !ids.insert(fields[0]).second ||
            !is_safe_relative_path(fields[1]) || !fields[1].starts_with("Packages/") ||
            (fields[4] != "QTexture" && fields[4] != "QStaticMesh" && fields[4] != "QSkelMesh"))
        {
            fail("invalid_candidate_map_row");
        }
        IdentityKey key{.package_path = fields[1],
                        .body_offset = parse_u64(fields[2]),
                        .body_size = parse_u64(fields[3]),
                        .class_name = fields[4]};
        CandidateMapEntry entry{.id = std::move(fields[0]),
                                .package_path = fields[1],
                                .body_offset = key.body_offset,
                                .body_size = key.body_size,
                                .class_name = fields[4]};
        if (!entries.emplace(std::move(key), std::move(entry)).second)
        {
            fail("duplicate_candidate_identity");
        }
    }
    if (!input.eof())
    {
        fail("candidate_map_read_failed");
    }
    return entries;
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
    if (size != version.size())
    {
        return false;
    }
    return std::ranges::equal(
        bytes.subspan(2U, size), version, [](const std::byte left, const char right)
        { return std::to_integer<unsigned char>(left) == static_cast<unsigned char>(right); });
}

[[nodiscard]] std::optional<tmxy::package::NormalizedPackageTree>
read_package_tree(const std::span<const std::byte> bytes, const std::string& label)
{
    if (has_version(bytes, tmxy::package::kPackageV1Version))
    {
        auto parsed = tmxy::package::PackageV1Reader{}.parse(bytes);
        if (!parsed.has_value())
        {
            fail("recognized_package_parse_failed");
        }
        return tmxy::package::normalize_package_tree(parsed.value(), label);
    }
    if (has_version(bytes, tmxy::package::kPackageV2Version))
    {
        auto parsed = tmxy::package::PackageV2Reader{}.parse(bytes);
        if (!parsed.has_value())
        {
            fail("recognized_package_parse_failed");
        }
        return tmxy::package::normalize_package_tree(parsed.value(), label);
    }
    if (has_version(bytes, tmxy::package::kPackageV3Version))
    {
        auto parsed = tmxy::package::PackageV3Reader{}.parse(bytes);
        if (!parsed.has_value())
        {
            fail("recognized_package_parse_failed");
        }
        return tmxy::package::normalize_package_tree(parsed.value(), label);
    }
    return std::nullopt;
}

[[nodiscard]] bool is_candidate_class(const std::string_view class_name) noexcept
{
    return class_name == "QTexture" || class_name == "QStaticMesh" || class_name == "QSkelMesh";
}

[[nodiscard]] std::string class_lookup_key(const ClassLookupParts parts)
{
    std::string key(parts.class_name);
    key.push_back('\0');
    key.append(parts.lower_name);
    return key;
}

[[nodiscard]] PackageIndex
build_package_index(const std::filesystem::path& client_root,
                    std::map<IdentityKey, CandidateMapEntry>& candidate_map)
{
    const auto packages_root = safe_join(client_root, "Packages");
    std::vector<std::filesystem::path> paths;
    for (const auto& item : std::filesystem::recursive_directory_iterator(packages_root))
    {
        if (item.is_regular_file())
        {
            paths.push_back(item.path());
        }
    }
    std::ranges::sort(paths, {}, [](const std::filesystem::path& path)
                      { return lower_ascii(path.generic_string()); });

    PackageIndex index;
    for (const auto& path : paths)
    {
        auto bytes = read_file(path);
        const auto relative = std::filesystem::relative(path, client_root).generic_string();
        const auto tree = read_package_tree(bytes, relative);
        if (!tree.has_value())
        {
            continue;
        }
        const auto package_index = index.packages.size();
        index.packages.push_back({.relative_path = relative, .bytes = std::move(bytes)});
        for (const auto& object : tree->objects)
        {
            if (!is_candidate_class(object.class_name_bytes))
            {
                continue;
            }
            IdentityKey key{.package_path = relative,
                            .body_offset = object.body_offset,
                            .body_size = object.body_size,
                            .class_name = object.class_name_bytes};
            const auto mapped = candidate_map.find(key);
            if (mapped == candidate_map.end() || mapped->second.matched)
            {
                fail("candidate_map_coverage_drift");
            }
            std::string identity(relative);
            identity.push_back('\0');
            identity.append(object.name_bytes);
            if (sha256_hex(std::string_view(identity.data(), identity.size())) != mapped->second.id)
            {
                fail("p2_03_candidate_identity_drift");
            }
            if (object.body_offset > index.packages.back().bytes.size() ||
                object.body_size > index.packages.back().bytes.size() - object.body_offset)
            {
                fail("candidate_body_range_drift");
            }
            mapped->second.matched = true;
            const auto candidate_index = index.candidates.size();
            index.candidates.push_back({.id = mapped->second.id,
                                        .package_index = package_index,
                                        .object_name = object.name_bytes,
                                        .body_offset = object.body_offset,
                                        .body_size = object.body_size,
                                        .class_name = object.class_name_bytes});
            index
                .by_class_and_lower_name[class_lookup_key(
                    {.class_name = object.class_name_bytes,
                     .lower_name = lower_ascii(object.name_bytes)})]
                .push_back(candidate_index);
        }
    }
    if (index.candidates.size() != candidate_map.size() ||
        std::ranges::any_of(candidate_map, [](const auto& entry) { return !entry.second.matched; }))
    {
        fail("candidate_map_coverage_drift");
    }
    for (auto& [key, candidates] : index.by_class_and_lower_name)
    {
        static_cast<void>(key);
        std::ranges::sort(candidates, {},
                          [&index](const std::size_t item) { return index.candidates[item].id; });
    }
    return index;
}

[[nodiscard]] std::string extension_of(const std::string_view path)
{
    const auto slash = path.find_last_of('/');
    const auto dot = path.find_last_of('.');
    if (dot == std::string_view::npos || (slash != std::string_view::npos && dot < slash))
    {
        return {};
    }
    return lower_ascii(std::string(path.substr(dot)));
}

[[nodiscard]] std::string logical_name_of(const std::string_view path)
{
    const auto slash = path.find_last_of('/');
    if (slash == std::string_view::npos || slash == 0U || slash + 1U == path.size())
    {
        fail("asset_logical_name_unavailable");
    }
    const auto parent_end = slash;
    const auto parent_start = path.find_last_of('/', parent_end - 1U);
    const auto parent =
        path.substr(parent_start == std::string_view::npos ? 0U : parent_start + 1U,
                    parent_end - (parent_start == std::string_view::npos ? 0U : parent_start + 1U));
    const auto file = path.substr(slash + 1U);
    const auto dot = file.find_last_of('.');
    if (parent.empty() || dot == std::string_view::npos || dot == 0U)
    {
        fail("asset_logical_name_unavailable");
    }
    std::string logical(parent);
    logical.push_back('.');
    logical.append(file.substr(0U, dot));
    return lower_ascii(std::move(logical));
}

[[nodiscard]] std::string class_for_family(const std::string_view family)
{
    if (family == "qtx")
    {
        return "QTexture";
    }
    if (family == "sm")
    {
        return "QStaticMesh";
    }
    if (family == "skem" || family == "anim")
    {
        return "QSkelMesh";
    }
    fail("unsupported_asset_family");
}

[[nodiscard]] std::span<const std::byte> body_span(const PackageData& package,
                                                   const Candidate& candidate)
{
    return std::span<const std::byte>(package.bytes.data(), package.bytes.size())
        .subspan(static_cast<std::size_t>(candidate.body_offset),
                 static_cast<std::size_t>(candidate.body_size));
}

[[nodiscard]] std::string candidate_set_sha256(const std::vector<std::string>& ids)
{
    std::string canonical(kCandidateSetDomain);
    canonical.push_back('\0');
    for (const auto& id : ids)
    {
        canonical.append(id);
        canonical.push_back('\0');
    }
    return sha256_hex(std::string_view(canonical.data(), canonical.size()));
}

void set_semantic_hashes(CandidateResult& result, const std::string_view object_name,
                         const std::string_view exact_signature,
                         const std::optional<std::string_view> normalized_signature)
{
    result.semantic_sha256 = semantic_sha256(object_name, exact_signature);
    result.descriptor_semantic_sha256 = descriptor_semantic_sha256(exact_signature);
    if (normalized_signature.has_value())
    {
        result.identity_normalized_descriptor_semantic_sha256 =
            descriptor_semantic_sha256(*normalized_signature);
        result.identity_normalized_semantic_sha256 =
            normalized_semantic_sha256(object_name, *normalized_signature);
    }
}

[[nodiscard]] CandidateResult
inspect_candidate(const std::string_view family, const std::span<const std::byte> asset_bytes,
                  const PackageData& package, const Candidate& candidate,
                  const std::string_view source_sha256, const RecoveryDirective* const directive)
{
    CandidateResult result;
    result.candidate_id = candidate.id;
    result.body_sha256 = sha256_hex(body_span(package, candidate));
    if (directive != nullptr &&
        (directive->asset_id.empty() || directive->candidate_id != candidate.id ||
         directive->body_sha256 != result.body_sha256 ||
         directive->source_sha256 != source_sha256 || directive->family != family))
    {
        fail("recovery_plan_binding_drift");
    }
    if (family == "qtx")
    {
        auto descriptor = tmxy::texture::LegacyTextureDescriptorReader{}.parse(
            body_span(package, candidate), candidate.body_offset);
        if (descriptor.has_value())
        {
            result.descriptor_parsed = true;
            const auto semantic = tmxy::asset_inventory::semantic_signature(descriptor.value());
            const auto signature = std::string_view(semantic.data(), semantic.size());
            set_semantic_hashes(result, candidate.object_name, signature, signature);
            const auto strict = tmxy::texture::QtxReader{}.parse(descriptor.value(), asset_bytes);
            result.strict_binding_passed = strict.has_value();
            result.effective_binding_passed = strict.has_value();
            if (strict.has_value())
            {
                result.effective_semantic_sha256 = result.semantic_sha256;
            }
            if (directive != nullptr)
            {
                result.recovery_kind = directive->recovery_kind;
                if (strict.has_value() ||
                    tmxy::texture::to_string(strict.error().code) != directive->strict_error_code)
                {
                    fail("recovery_plan_strict_error_drift");
                }
                apply_qtx_recovery(descriptor.value(), asset_bytes, candidate.object_name,
                                   *directive, result);
            }
        }
        return result;
    }
    if (family == "sm")
    {
        auto descriptor = tmxy::static_mesh::read_static_mesh_descriptor(
            body_span(package, candidate), candidate.body_offset);
        if (descriptor.has_value())
        {
            result.descriptor_parsed = true;
            const auto semantic = tmxy::asset_inventory::semantic_signature(descriptor.value());
            const auto signature = std::string_view(semantic.data(), semantic.size());
            set_semantic_hashes(result, candidate.object_name, signature, signature);
        }
        result.strict_binding_passed =
            tmxy::static_mesh::bind_static_mesh(package.bytes, candidate.object_name, asset_bytes)
                .has_value();
        result.effective_binding_passed = result.strict_binding_passed;
        result.effective_semantic_sha256 =
            result.strict_binding_passed ? result.semantic_sha256 : std::nullopt;
        return result;
    }
    if (family == "skem")
    {
        auto descriptor = tmxy::skeletal_mesh::read_skeletal_mesh_descriptor(
            body_span(package, candidate), candidate.body_offset);
        if (descriptor.has_value())
        {
            result.descriptor_parsed = true;
            const auto semantic = tmxy::asset_inventory::semantic_signature(descriptor.value());
            const auto signature = std::string_view(semantic.data(), semantic.size());
            set_semantic_hashes(result, candidate.object_name, signature, signature);
        }
        result.strict_binding_passed = tmxy::skeletal_mesh::bind_skeletal_mesh(
                                           package.bytes, candidate.object_name, asset_bytes)
                                           .has_value();
        result.effective_binding_passed = result.strict_binding_passed;
        result.effective_semantic_sha256 =
            result.strict_binding_passed ? result.semantic_sha256 : std::nullopt;
        return result;
    }
    if (family == "anim")
    {
        auto descriptor = tmxy::animation::read_package_animation_set_descriptor(
            package.bytes, candidate.object_name);
        if (descriptor.has_value())
        {
            result.descriptor_parsed = true;
            const auto semantic = tmxy::asset_inventory::semantic_signature(descriptor.value());
            const auto signature = std::string_view(semantic.data(), semantic.size());
            auto normalized_descriptor = descriptor.value();
            const auto outer_lower = lower_ascii(candidate.object_name);
            const auto mirror_lower =
                lower_ascii(normalized_descriptor.skeletal_mesh.object_name_bytes);
            result.identity_mirror_ascii_lower_match = outer_lower == mirror_lower;
            if (result.identity_mirror_ascii_lower_match)
            {
                normalized_descriptor.skeletal_mesh.object_name_bytes = mirror_lower;
                const auto normalized =
                    tmxy::asset_inventory::semantic_signature(normalized_descriptor);
                const auto normalized_signature =
                    std::string_view(normalized.data(), normalized.size());
                set_semantic_hashes(result, candidate.object_name, signature, normalized_signature);
            }
            else
            {
                set_semantic_hashes(result, candidate.object_name, signature, std::nullopt);
            }
        }
        const auto strict =
            tmxy::animation::bind_animation_set(package.bytes, candidate.object_name, asset_bytes);
        result.strict_binding_passed = strict.has_value();
        result.effective_binding_passed = strict.has_value();
        if (strict.has_value())
        {
            result.effective_semantic_sha256 = result.semantic_sha256;
        }
        if (directive != nullptr)
        {
            result.recovery_kind = directive->recovery_kind;
            if (strict.has_value() ||
                tmxy::animation::to_string(strict.error().code) != directive->strict_error_code)
            {
                fail("recovery_plan_strict_error_drift");
            }
            const auto recovered = tmxy::animation::bind_animation_set_with_payload_frame_counts(
                package.bytes, candidate.object_name, asset_bytes);
            if (recovered.has_value())
            {
                auto effective_descriptor = recovered.value().package;
                if (effective_descriptor.animations.size() !=
                    recovered.value().payload.clips.size())
                {
                    fail("recovery_plan_anim_clip_drift");
                }
                for (std::size_t index = 0; index < effective_descriptor.animations.size(); ++index)
                {
                    effective_descriptor.animations[index].frame_count =
                        recovered.value().payload.clips[index].effective_frame_count;
                }
                const auto effective =
                    tmxy::asset_inventory::semantic_signature(effective_descriptor);
                result.effective_semantic_sha256 = semantic_sha256(
                    candidate.object_name, std::string_view(effective.data(), effective.size()));
                result.effective_binding_passed = true;
                result.recovery_applied = true;
            }
        }
        return result;
    }
    fail("unsupported_asset_family");
}

[[nodiscard]] AssetResult inspect_asset(const AssetEntry& asset,
                                        const std::filesystem::path& client_root,
                                        const PackageIndex& packages, RecoveryPlan& recovery_plan)
{
    static const std::map<std::string, std::string> expected_extensions{
        {"qtx", ".qtx"}, {"sm", ".sm"}, {"skem", ".skem"}, {"anim", ".anim"}};
    if (extension_of(asset.relative_path) != expected_extensions.at(asset.family))
    {
        fail("asset_family_extension_drift");
    }
    const auto bytes = read_file(safe_join(client_root, asset.relative_path));
    if (bytes.size() != asset.bytes || sha256_hex(bytes) != asset.source_sha256)
    {
        fail("asset_source_hash_drift");
    }
    const auto key = class_lookup_key({.class_name = class_for_family(asset.family),
                                       .lower_name = logical_name_of(asset.relative_path)});
    const auto found = packages.by_class_and_lower_name.find(key);
    const std::vector<std::size_t> empty;
    const auto& candidate_indices =
        found == packages.by_class_and_lower_name.end() ? empty : found->second;
    std::vector<std::string> actual_ids;
    actual_ids.reserve(candidate_indices.size());
    for (const auto index : candidate_indices)
    {
        actual_ids.push_back(packages.candidates[index].id);
    }
    if (actual_ids != asset.expected_candidate_ids)
    {
        fail("asset_candidate_set_drift");
    }

    AssetResult result{.asset_id = asset.id,
                       .family = asset.family,
                       .structure = asset.structure,
                       .candidate_set_sha256 = candidate_set_sha256(actual_ids),
                       .candidates = {},
                       .counts = {}};
    std::set<std::string> semantic_hashes;
    for (const auto index : candidate_indices)
    {
        const auto& candidate = packages.candidates[index];
        auto* const directive = recovery_plan.find(asset.id, candidate.id);
        auto inspected =
            inspect_candidate(asset.family, bytes, packages.packages[candidate.package_index],
                              candidate, asset.source_sha256, directive);
        if (inspected.descriptor_parsed)
        {
            ++result.counts.descriptor_parsed;
            if (!inspected.semantic_sha256.has_value())
            {
                fail("semantic_hash_invariant_failed");
            }
            semantic_hashes.insert(inspected.semantic_sha256.value());
        }
        else
        {
            ++result.counts.descriptor_rejected;
        }
        if (inspected.strict_binding_passed)
        {
            ++result.counts.binding_pass;
        }
        else
        {
            ++result.counts.binding_rejected;
        }
        if (inspected.effective_binding_passed)
        {
            ++result.counts.effective_binding_pass;
        }
        else
        {
            ++result.counts.effective_binding_rejected;
        }
        result.counts.recovery_applied += inspected.recovery_applied ? 1U : 0U;
        result.candidates.push_back(std::move(inspected));
    }
    result.counts.candidates = result.candidates.size();
    result.counts.semantic_distinct = semantic_hashes.size();
    std::set<std::string> effective_semantic_hashes;
    for (const auto& candidate : result.candidates)
    {
        if (candidate.effective_binding_passed && candidate.effective_semantic_sha256.has_value())
        {
            effective_semantic_hashes.insert(*candidate.effective_semantic_sha256);
        }
    }
    result.counts.effective_semantic_distinct = effective_semantic_hashes.size();
    return result;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 5)
    {
        std::cerr << "usage: tmxy_g2_asset_descriptor_probe <client-root> <asset-tsv> "
                     "<candidate-map-tsv> <eligible-recovery-attempts-tsv>\n";
        return 2;
    }
    try
    {
        if (!tmxy::g2_asset_descriptor_diagnostics::sha256_self_test() ||
            !tmxy::asset_inventory::semantic_signature_self_test() || !qtx_recovery_self_test())
        {
            fail("startup_self_test_failed");
        }
        const auto client_root = std::filesystem::weakly_canonical(arguments[1]);
        if (!std::filesystem::is_directory(client_root))
        {
            fail("client_root_invalid");
        }
        const auto assets = read_asset_tsv(arguments[2]);
        auto candidate_map = read_candidate_map_tsv(arguments[3]);
        auto recovery_plan = RecoveryPlan::read(arguments[4]);
        const auto packages = build_package_index(client_root, candidate_map);

        std::vector<AssetResult> results;
        results.reserve(assets.size());
        for (const auto& asset : assets)
        {
            results.push_back(inspect_asset(asset, client_root, packages, recovery_plan));
        }
        recovery_plan.require_complete();
        for (const auto& result : results)
        {
            emit_result(result);
        }
        std::cerr << "asset_descriptor_probe assets=" << results.size()
                  << " candidates=" << packages.candidates.size()
                  << " recovery_attempts=" << recovery_plan.size() << " result=PASS\n";
        return 0;
    }
    catch (const ProbeFailure& error)
    {
        std::cerr << "asset_descriptor_probe_error=" << error.what() << '\n';
        return 3;
    }
    catch (const std::runtime_error& error)
    {
        std::cerr << "asset_descriptor_probe_error=" << error.what() << '\n';
        return 3;
    }
    catch (...)
    {
        std::cerr << "asset_descriptor_probe_error=unexpected_failure\n";
        return 4;
    }
}
