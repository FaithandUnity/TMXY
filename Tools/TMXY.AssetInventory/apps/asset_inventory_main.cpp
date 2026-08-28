#include "tmxy/animation/anim_reader.hpp"
#include "tmxy/animation/package_animation_reader.hpp"
#include "tmxy/package/package_normalized_tree.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3_reader.hpp"
#include "tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp"
#include "tmxy/skeletal_mesh/skem_reader.hpp"
#include "tmxy/static_mesh/package_static_mesh_reader.hpp"
#include "tmxy/static_mesh/sm_reader.hpp"
#include "tmxy/terrain/ter_reader.hpp"
#include "tmxy/texture/legacy_texture_descriptor_reader.hpp"
#include "tmxy/texture/qtx_reader.hpp"

#include <algorithm>
#include <bit>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <span>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace
{

struct ManifestEntry final
{
    std::string path;
    std::uint64_t bytes{0};
    std::string sha256;
};

struct PackageData final
{
    std::string path;
    std::vector<std::byte> bytes;
};

struct Candidate final
{
    std::size_t package_index{0};
    std::string object_name;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
};

using CandidateIndex = std::unordered_map<std::string, std::vector<Candidate>>;

struct PackageIndex final
{
    std::vector<PackageData> packages;
    CandidateIndex textures;
    CandidateIndex static_meshes;
    CandidateIndex skeletal_meshes;
};

struct Inspection final
{
    std::string family;
    std::string contract;
    bool passed{false};
    bool unresolved{false};
    std::string error{"none"};
    std::uint64_t error_offset{0};
    std::uint64_t package_candidates{0};
    std::uint64_t descriptor_variants{0};
    std::uint64_t valid_variants{0};
    std::string package_state{"not_applicable"};
    std::map<std::string, std::uint64_t> metrics;
    std::map<std::string, std::string> labels;
};

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

[[nodiscard]] std::string lower_ascii(std::string value)
{
    std::ranges::transform(value, value.begin(), [](const unsigned char byte)
                           { return static_cast<char>(std::tolower(byte)); });
    return value;
}

[[nodiscard]] bool has_version(const std::span<const std::byte> bytes,
                               const std::string_view version) noexcept
{
    if (bytes.size() < version.size() + 2U)
    {
        return false;
    }
    const auto length = static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[0])) |
                        (static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[1])) << 8U);
    if (length != version.size())
    {
        return false;
    }
    return std::ranges::equal(
        bytes.subspan(2U, length), version, [](const std::byte left, const char right)
        { return std::to_integer<unsigned char>(left) == static_cast<unsigned char>(right); });
}

[[nodiscard]] std::optional<tmxy::package::NormalizedPackageTree>
read_package_tree(const std::span<const std::byte> bytes, std::string label)
{
    if (has_version(bytes, tmxy::package::kPackageV1Version))
    {
        auto result = tmxy::package::PackageV1Reader{}.parse(bytes);
        if (result.has_value())
        {
            return tmxy::package::normalize_package_tree(result.value(), std::move(label));
        }
    }
    if (has_version(bytes, tmxy::package::kPackageV2Version))
    {
        auto result = tmxy::package::PackageV2Reader{}.parse(bytes);
        if (result.has_value())
        {
            return tmxy::package::normalize_package_tree(result.value(), std::move(label));
        }
    }
    if (has_version(bytes, tmxy::package::kPackageV3Version))
    {
        auto result = tmxy::package::PackageV3Reader{}.parse(bytes);
        if (result.has_value())
        {
            return tmxy::package::normalize_package_tree(result.value(), std::move(label));
        }
    }
    return std::nullopt;
}

void add_candidate(CandidateIndex& index, const tmxy::package::NormalizedPackageObject& object,
                   const std::size_t package_index)
{
    index[lower_ascii(object.name_bytes)].push_back(Candidate{.package_index = package_index,
                                                              .object_name = object.name_bytes,
                                                              .body_offset = object.body_offset,
                                                              .body_size = object.body_size});
}

[[nodiscard]] PackageIndex build_package_index(const std::filesystem::path& client_root)
{
    std::vector<std::filesystem::path> paths;
    for (const auto& item : std::filesystem::recursive_directory_iterator(client_root / "Packages"))
    {
        if (item.is_regular_file())
        {
            paths.push_back(item.path());
        }
    }
    std::ranges::sort(paths, {}, [](const std::filesystem::path& path)
                      { return lower_ascii(path.generic_string()); });

    PackageIndex index;
    index.packages.reserve(paths.size());
    for (const auto& path : paths)
    {
        auto bytes = read_file(path);
        auto relative = std::filesystem::relative(path, client_root).generic_string();
        auto tree = read_package_tree(bytes, relative);
        if (!tree.has_value())
        {
            continue;
        }
        const auto package_index = index.packages.size();
        index.packages.push_back({.path = std::move(relative), .bytes = std::move(bytes)});
        for (const auto& object : tree->objects)
        {
            if (object.class_name_bytes == "QTexture")
            {
                add_candidate(index.textures, object, package_index);
            }
            else if (object.class_name_bytes == "QStaticMesh")
            {
                add_candidate(index.static_meshes, object, package_index);
            }
            else if (object.class_name_bytes == "QSkelMesh")
            {
                add_candidate(index.skeletal_meshes, object, package_index);
            }
        }
    }
    return index;
}

[[nodiscard]] std::span<const std::byte> body_span(const PackageData& package,
                                                   const Candidate& candidate)
{
    if (candidate.body_offset > package.bytes.size() ||
        candidate.body_size > package.bytes.size() - candidate.body_offset)
    {
        return {};
    }
    return std::span(package.bytes)
        .subspan(static_cast<std::size_t>(candidate.body_offset),
                 static_cast<std::size_t>(candidate.body_size));
}

[[nodiscard]] std::string logical_name(const ManifestEntry& entry)
{
    const std::filesystem::path path(entry.path);
    return path.parent_path().filename().string() + "." + path.stem().string();
}

[[nodiscard]] std::string texture_signature(const tmxy::texture::TextureDescriptor& descriptor)
{
    std::ostringstream output;
    output << static_cast<unsigned int>(descriptor.format) << '|' << descriptor.width << '|'
           << descriptor.height << '|' << descriptor.mip_count << '|'
           << static_cast<unsigned int>(descriptor.u_clamp) << '|'
           << static_cast<unsigned int>(descriptor.v_clamp);
    return output.str();
}

[[nodiscard]] std::string
static_mesh_signature(const tmxy::static_mesh::StaticMeshDescriptor& descriptor)
{
    std::uint8_t light_map_state = 0;
    if (descriptor.use_light_map.has_value())
    {
        light_map_state = *descriptor.use_light_map ? 2U : 1U;
    }
    std::ostringstream output;
    output << descriptor.material_object_names.size() << '|' << descriptor.unknown_properties.size()
           << '|' << static_cast<unsigned int>(light_map_state) << '|'
           << (descriptor.declared_bounds.has_value() ? 1 : 0);
    return output.str();
}

[[nodiscard]] std::string
skeletal_mesh_signature(const tmxy::skeletal_mesh::SkeletalMeshDescriptor& descriptor)
{
    std::ostringstream output;
    output << descriptor.bones.size() << '|' << descriptor.animation_object_names.size() << '|'
           << descriptor.default_submesh_indices.size() << '|'
           << descriptor.material_object_names.size() << '|'
           << descriptor.unknown_properties.size();
    return output.str();
}

[[nodiscard]] std::string
animation_signature(const tmxy::animation::PackageAnimationSetDescriptor& descriptor)
{
    std::ostringstream output;
    output << descriptor.skeletal_mesh.descriptor.bones.size() << '|'
           << descriptor.animations.size();
    for (const auto& animation : descriptor.animations)
    {
        output << '|' << animation.object_name_bytes << ':' << animation.frame_count << ':'
               << std::bit_cast<std::uint32_t>(animation.frame_delta_seconds) << ':'
               << (animation.self_loop ? 1 : 0);
    }
    return output.str();
}

void set_package_state(Inspection& result)
{
    if (result.package_candidates == 0U)
    {
        result.package_state = "missing";
    }
    else if (result.valid_variants == 0U)
    {
        result.package_state = "no_valid_variant";
    }
    else if (result.descriptor_variants > 1U)
    {
        result.package_state = "ambiguous_divergent";
    }
    else if (result.package_candidates > 1U)
    {
        result.package_state = "ambiguous_equivalent";
    }
    else
    {
        result.package_state = "unique";
    }
}

[[nodiscard]] Inspection inspect_qtx(const ManifestEntry& entry,
                                     const std::span<const std::byte> bytes,
                                     const PackageIndex& packages)
{
    Inspection result;
    result.family = "qtx";
    result.contract = "qtx-headerless-v1";
    const auto found = packages.textures.find(lower_ascii(logical_name(entry)));
    if (found == packages.textures.end())
    {
        result.error = "package_object_missing";
        result.unresolved = true;
        set_package_state(result);
        return result;
    }
    result.package_candidates = found->second.size();
    std::map<std::string, tmxy::texture::TextureDescriptor> variants;
    for (const auto& candidate : found->second)
    {
        const auto& package = packages.packages[candidate.package_index];
        auto descriptor = tmxy::texture::LegacyTextureDescriptorReader{}.parse(
            body_span(package, candidate), candidate.body_offset);
        if (descriptor.has_value())
        {
            variants.emplace(texture_signature(descriptor.value()), descriptor.value());
        }
        else if (result.error == "none")
        {
            result.error = std::string(tmxy::texture::to_string(descriptor.error().code));
            result.error_offset = descriptor.error().absolute_offset;
        }
    }
    result.descriptor_variants = variants.size();
    for (const auto& [signature, descriptor] : variants)
    {
        static_cast<void>(signature);
        auto parsed = tmxy::texture::QtxReader{}.parse(descriptor, bytes);
        if (!parsed.has_value())
        {
            if (result.error == "none")
            {
                result.error = std::string(tmxy::texture::to_string(parsed.error().code));
                result.error_offset = parsed.error().absolute_offset;
            }
            continue;
        }
        ++result.valid_variants;
        if (!result.passed)
        {
            const auto& texture = parsed.value();
            result.metrics["width"] = texture.descriptor.width;
            result.metrics["height"] = texture.descriptor.height;
            result.metrics["mips"] = texture.descriptor.mip_count;
            result.labels["format"] = tmxy::texture::to_string(texture.descriptor.format);
            result.labels["alpha"] = tmxy::texture::to_string(texture.alpha_coverage);
        }
        result.passed = true;
    }
    if (result.passed)
    {
        result.error = "none";
        result.error_offset = 0;
    }
    else
    {
        result.unresolved = true;
    }
    set_package_state(result);
    return result;
}

[[nodiscard]] Inspection inspect_sm(const ManifestEntry& entry,
                                    const std::span<const std::byte> bytes,
                                    const PackageIndex& packages)
{
    Inspection result;
    result.family = "sm";
    result.contract = "sm-headerless-v1";
    auto parsed = tmxy::static_mesh::SmReader{}.parse(bytes);
    if (!parsed.has_value())
    {
        result.error = std::string(tmxy::static_mesh::to_string(parsed.error().code));
        result.error_offset = parsed.error().absolute_offset;
        return result;
    }
    result.passed = true;
    result.metrics["vertices"] = parsed.value().positions.size();
    result.metrics["indices"] = parsed.value().indices.size();
    result.metrics["sections"] = parsed.value().sections.size();
    const auto found = packages.static_meshes.find(lower_ascii(logical_name(entry)));
    if (found != packages.static_meshes.end())
    {
        result.package_candidates = found->second.size();
        std::set<std::string> variants;
        for (const auto& candidate : found->second)
        {
            const auto& package = packages.packages[candidate.package_index];
            auto descriptor = tmxy::static_mesh::read_static_mesh_descriptor(
                body_span(package, candidate), candidate.body_offset);
            if (descriptor.has_value())
            {
                variants.insert(static_mesh_signature(descriptor.value()));
                if (descriptor.value().material_object_names.size() ==
                    parsed.value().sections.size())
                {
                    ++result.valid_variants;
                }
            }
        }
        result.descriptor_variants = variants.size();
    }
    set_package_state(result);
    return result;
}

[[nodiscard]] Inspection inspect_skem(const ManifestEntry& entry,
                                      const std::span<const std::byte> bytes,
                                      const PackageIndex& packages)
{
    Inspection result;
    result.family = "skem";
    result.contract = "skem-headerless-v1";
    auto parsed = tmxy::skeletal_mesh::SkemReader{}.parse(bytes);
    if (!parsed.has_value())
    {
        result.error = std::string(tmxy::skeletal_mesh::to_string(parsed.error().code));
        result.error_offset = parsed.error().absolute_offset;
        return result;
    }
    result.passed = true;
    result.metrics["groups"] = parsed.value().groups.size();
    result.metrics["submeshes"] = parsed.value().total_submesh_count;
    result.metrics["vertices"] = parsed.value().total_vertex_count;
    result.metrics["indices"] = parsed.value().total_index_count;
    const auto found = packages.skeletal_meshes.find(lower_ascii(logical_name(entry)));
    if (found != packages.skeletal_meshes.end())
    {
        result.package_candidates = found->second.size();
        std::set<std::string> variants;
        for (const auto& candidate : found->second)
        {
            const auto& package = packages.packages[candidate.package_index];
            auto descriptor = tmxy::skeletal_mesh::read_skeletal_mesh_descriptor(
                body_span(package, candidate), candidate.body_offset);
            if (descriptor.has_value())
            {
                variants.insert(skeletal_mesh_signature(descriptor.value()));
                if (descriptor.value().material_object_names.size() ==
                        parsed.value().groups.size() &&
                    descriptor.value().default_submesh_indices.size() ==
                        parsed.value().groups.size())
                {
                    ++result.valid_variants;
                }
            }
        }
        result.descriptor_variants = variants.size();
    }
    set_package_state(result);
    return result;
}

[[nodiscard]] Inspection inspect_anim(const ManifestEntry& entry,
                                      const std::span<const std::byte> bytes,
                                      const PackageIndex& packages)
{
    Inspection result;
    result.family = "anim";
    result.contract = "anim-headerless-v1";
    const auto found = packages.skeletal_meshes.find(lower_ascii(logical_name(entry)));
    if (found == packages.skeletal_meshes.end())
    {
        const std::vector<tmxy::animation::AnimationDescriptor> empty_descriptors;
        auto parsed = tmxy::animation::AnimReader::parse(bytes, empty_descriptors, 0U);
        if (parsed.has_value())
        {
            result.passed = true;
            result.metrics["clips"] = parsed.value().clips.size();
            result.metrics["tracks"] = parsed.value().total_track_count;
            result.metrics["keys"] = parsed.value().total_key_count;
        }
        else
        {
            result.error = "package_object_missing";
            result.unresolved = true;
        }
        set_package_state(result);
        return result;
    }
    result.package_candidates = found->second.size();
    std::map<std::string, tmxy::animation::PackageAnimationSetDescriptor> variants;
    for (const auto& candidate : found->second)
    {
        const auto& package = packages.packages[candidate.package_index];
        auto descriptor = tmxy::animation::read_package_animation_set_descriptor(
            package.bytes, candidate.object_name);
        if (descriptor.has_value())
        {
            variants.emplace(animation_signature(descriptor.value()), descriptor.value());
        }
        else if (result.error == "none")
        {
            result.error = std::string(tmxy::animation::to_string(descriptor.error().code));
            result.error_offset = descriptor.error().absolute_offset;
        }
    }
    result.descriptor_variants = variants.size();
    for (const auto& [signature, descriptor] : variants)
    {
        static_cast<void>(signature);
        auto parsed = tmxy::animation::AnimReader::parse(
            bytes, descriptor.animations,
            static_cast<std::uint32_t>(descriptor.skeletal_mesh.descriptor.bones.size()));
        if (!parsed.has_value())
        {
            if (result.error == "none")
            {
                result.error = std::string(tmxy::animation::to_string(parsed.error().code));
                result.error_offset = parsed.error().absolute_offset;
            }
            continue;
        }
        ++result.valid_variants;
        if (!result.passed)
        {
            result.metrics["clips"] = parsed.value().clips.size();
            result.metrics["tracks"] = parsed.value().total_track_count;
            result.metrics["keys"] = parsed.value().total_key_count;
        }
        result.passed = true;
    }
    if (result.passed)
    {
        result.error = "none";
        result.error_offset = 0;
    }
    else
    {
        result.unresolved = true;
    }
    set_package_state(result);
    return result;
}

[[nodiscard]] Inspection inspect_ter(const std::span<const std::byte> bytes)
{
    Inspection result;
    result.family = "ter";
    result.contract = "ter-headerless-v1";
    auto parsed = tmxy::terrain::TerReader::parse(bytes, "asset_inventory");
    if (!parsed.has_value())
    {
        result.error = std::string(tmxy::terrain::to_string(parsed.error().code));
        result.error_offset = parsed.error().absolute_offset;
        return result;
    }
    result.passed = true;
    result.metrics["vertices"] = parsed.value().vertices.size();
    result.metrics["edge_vertices"] = parsed.value().edge_vertex_count;
    result.metrics["active_layers"] = parsed.value().active_layers.size();
    result.metrics["water"] = parsed.value().water_enabled ? 1U : 0U;
    return result;
}

[[nodiscard]] std::string extension_of(const std::string& path)
{
    return lower_ascii(std::filesystem::path(path).extension().string());
}

[[nodiscard]] std::vector<ManifestEntry> read_manifest_tsv(const std::filesystem::path& path)
{
    std::ifstream input(path, std::ios::binary);
    std::vector<ManifestEntry> entries;
    std::string line;
    while (std::getline(input, line))
    {
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        const auto first = line.find('\t');
        const auto second = first == std::string::npos ? first : line.find('\t', first + 1U);
        if (first == std::string::npos || second == std::string::npos)
        {
            throw std::runtime_error("invalid manifest TSV row");
        }
        entries.push_back({.path = line.substr(0, first),
                           .bytes = std::stoull(line.substr(first + 1U, second - first - 1U)),
                           .sha256 = line.substr(second + 1U)});
    }
    return entries;
}

void append_json_string(std::ostream& output, const std::string_view value)
{
    constexpr std::string_view digits = "0123456789abcdef";
    output << '"';
    for (const char character : value)
    {
        const auto byte = static_cast<unsigned char>(character);
        switch (byte)
        {
        case '"':
            output << "\\\"";
            break;
        case '\\':
            output << "\\\\";
            break;
        case '\b':
            output << "\\b";
            break;
        case '\f':
            output << "\\f";
            break;
        case '\n':
            output << "\\n";
            break;
        case '\r':
            output << "\\r";
            break;
        case '\t':
            output << "\\t";
            break;
        default:
            if (byte < 0x20U)
            {
                output << "\\u00" << digits[byte >> 4U] << digits[byte & 0x0FU];
            }
            else
            {
                output << static_cast<char>(byte);
            }
        }
    }
    output << '"';
}

void emit_record(const ManifestEntry& entry, const Inspection& result)
{
    std::cout << R"({"path":)";
    append_json_string(std::cout, entry.path);
    std::cout << R"(,"sha256":)";
    append_json_string(std::cout, entry.sha256);
    std::cout << R"(,"bytes":)" << entry.bytes << R"(,"family":)";
    append_json_string(std::cout, result.family);
    std::cout << R"(,"format_contract":)";
    append_json_string(std::cout, result.contract);
    std::string_view structure = "FAIL";
    if (result.passed)
    {
        structure = "PASS";
    }
    else if (result.unresolved)
    {
        structure = "UNRESOLVED";
    }
    std::cout << R"(,"structure":")" << structure << '"';
    std::cout << R"(,"package_candidates":)" << result.package_candidates
              << R"(,"descriptor_variants":)" << result.descriptor_variants
              << R"(,"valid_variants":)" << result.valid_variants << R"(,"package_state":)";
    append_json_string(std::cout, result.package_state);
    std::cout << R"(,"error":)";
    append_json_string(std::cout, result.error);
    std::cout << R"(,"error_offset":)" << result.error_offset << R"(,"metrics":{)";
    bool first = true;
    for (const auto& [name, value] : result.metrics)
    {
        if (!std::exchange(first, false))
        {
            std::cout << ',';
        }
        append_json_string(std::cout, name);
        std::cout << ':' << value;
    }
    for (const auto& [name, value] : result.labels)
    {
        if (!std::exchange(first, false))
        {
            std::cout << ',';
        }
        append_json_string(std::cout, name);
        std::cout << ':';
        append_json_string(std::cout, value);
    }
    std::cout << "}}\n";
}

[[nodiscard]] Inspection inspect(const ManifestEntry& entry, const std::span<const std::byte> bytes,
                                 const PackageIndex& packages)
{
    const auto extension = extension_of(entry.path);
    if (extension == ".qtx")
    {
        return inspect_qtx(entry, bytes, packages);
    }
    if (extension == ".sm")
    {
        return inspect_sm(entry, bytes, packages);
    }
    if (extension == ".skem")
    {
        return inspect_skem(entry, bytes, packages);
    }
    if (extension == ".anim")
    {
        return inspect_anim(entry, bytes, packages);
    }
    if (extension == ".ter")
    {
        return inspect_ter(bytes);
    }
    Inspection result;
    result.family = "unknown";
    result.contract = "unsupported";
    result.error = "unsupported_extension";
    return result;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 3)
    {
        std::cerr << "usage: tmxy_asset_inventory <client-root> <manifest-tsv>\n";
        return 2;
    }
    try
    {
        const std::filesystem::path client_root(arguments[1]);
        const auto entries = read_manifest_tsv(arguments[2]);
        const auto packages = build_package_index(client_root);
        std::uint64_t failed = 0;
        std::uint64_t unresolved = 0;
        for (const auto& entry : entries)
        {
            auto bytes = read_file(client_root / std::filesystem::path(entry.path));
            Inspection result;
            if (bytes.size() != entry.bytes)
            {
                result.family = extension_of(entry.path).substr(1U);
                result.contract = "manifest-bound";
                result.error = "size_mismatch";
            }
            else
            {
                result = inspect(entry, bytes, packages);
            }
            if (!result.passed)
            {
                if (result.unresolved)
                {
                    ++unresolved;
                }
                else
                {
                    ++failed;
                }
            }
            emit_record(entry, result);
        }
        std::cerr << "asset_inventory files=" << entries.size() << " failed=" << failed
                  << " unresolved=" << unresolved << " packages=" << packages.packages.size()
                  << '\n';
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "asset_inventory_error=" << error.what() << '\n';
        return 3;
    }
}
