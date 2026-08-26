#include "tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_export.hpp"
#include "tmxy/skeletal_mesh/skem_reader.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace
{

[[nodiscard]] std::vector<std::byte> read_file(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream)
    {
        return {};
    }
    const auto end = stream.tellg();
    if (end <= 0 || end > std::numeric_limits<std::streamsize>::max())
    {
        return {};
    }
    std::vector<std::byte> bytes(static_cast<std::size_t>(end));
    stream.seekg(0);
    stream.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    return stream ? bytes : std::vector<std::byte>{};
}

[[nodiscard]] std::uint64_t fingerprint(const std::string_view text) noexcept
{
    std::uint64_t hash = 14695981039346656037ULL;
    for (const char character : text)
    {
        hash ^= static_cast<unsigned char>(character);
        hash *= 1099511628211ULL;
    }
    return hash;
}

void print_payload(const std::string_view name,
                   const tmxy::skeletal_mesh::SkeletalMeshPayload& payload)
{
    std::cout << "PAYLOAD name=" << name << " groups=" << payload.groups.size()
              << " submeshes=" << payload.total_submesh_count
              << " vertices=" << payload.total_vertex_count
              << " indices=" << payload.total_index_count
              << " triangles=" << payload.total_triangle_count
              << " shadow_indices=" << payload.total_shadow_index_count << '\n';
}

bool parse_payload_sample(const std::filesystem::path& path, const std::string_view name)
{
    const auto bytes = read_file(path);
    const auto parsed = tmxy::skeletal_mesh::SkemReader{}.parse(bytes);
    if (!parsed.has_value())
    {
        std::cerr << "parse-failed name=" << name
                  << " code=" << tmxy::skeletal_mesh::to_string(parsed.error().code)
                  << " offset=" << parsed.error().absolute_offset
                  << " context=" << parsed.error().context << '\n';
        return false;
    }
    const auto& value = parsed.value();
    const auto passed = value.groups.size() == 1U && value.total_submesh_count == 1U &&
                        value.total_vertex_count == 4U && value.total_index_count == 6U &&
                        value.total_triangle_count == 2U && value.total_shadow_index_count == 0U;
    print_payload(name, parsed.value());
    return passed;
}

struct BoundExpectation final
{
    std::uint64_t submeshes{0};
    std::uint64_t vertices{0};
    std::uint64_t indices{0};
    std::uint64_t triangles{0};
    std::uint64_t shadow_indices{0};
    std::uint64_t animation_references{0};
    std::uint64_t json_fingerprint{0};
    std::uint64_t obj_fingerprint{0};
    std::uint64_t descriptor_offset{0};
    std::uint64_t descriptor_size{0};
    std::uint64_t sentinel_vertices{0};
};

[[nodiscard]] bool matches(const tmxy::skeletal_mesh::SkeletalMeshBinding& binding,
                           const BoundExpectation expected, const std::uint64_t json_fingerprint,
                           const std::uint64_t obj_fingerprint, const std::string_view json)
{
    const auto& payload = binding.payload;
    const auto& descriptor = binding.package.descriptor;
    const auto sentinel = "\"legacy_unweighted_sentinel_vertex_count\": " +
                          std::to_string(expected.sentinel_vertices);
    return payload.groups.size() == 12U && payload.total_submesh_count == expected.submeshes &&
           payload.total_vertex_count == expected.vertices &&
           payload.total_index_count == expected.indices &&
           payload.total_triangle_count == expected.triangles &&
           payload.total_shadow_index_count == expected.shadow_indices &&
           descriptor.bones.size() == 80U && descriptor.root_bone_ids.size() == 1U &&
           descriptor.root_bone_ids.front() == 0 &&
           descriptor.animation_object_names.size() == expected.animation_references &&
           binding.default_selections.size() == 12U &&
           binding.package.body_offset == expected.descriptor_offset &&
           binding.package.body_size == expected.descriptor_size &&
           json_fingerprint == expected.json_fingerprint &&
           obj_fingerprint == expected.obj_fingerprint &&
           json.find(sentinel) != std::string_view::npos;
}

bool parse_bound_sample(const std::filesystem::path& package_path,
                        const std::filesystem::path& skem_path, const std::string_view object_name,
                        const BoundExpectation expected)
{
    const auto package = read_file(package_path);
    const auto skem = read_file(skem_path);
    auto binding = tmxy::skeletal_mesh::bind_skeletal_mesh(package, object_name, skem);
    if (!binding.has_value())
    {
        std::cerr << "bind-failed object=" << object_name
                  << " code=" << tmxy::skeletal_mesh::to_string(binding.error().code)
                  << " offset=" << binding.error().absolute_offset
                  << " context=" << binding.error().context << '\n';
        return false;
    }
    const auto json = tmxy::skeletal_mesh::build_skeletal_mesh_json(binding.value());
    auto obj = tmxy::skeletal_mesh::build_default_ue_obj(binding.value());
    if (!obj.has_value())
    {
        return false;
    }
    const auto& value = binding.value();
    const auto json_hash = fingerprint(json);
    const auto obj_hash = fingerprint(obj.value());
    const auto passed = matches(value, expected, json_hash, obj_hash, json);
    std::cout << "BOUND result=" << (passed ? "PASS" : "FAIL") << " object=" << object_name
              << " groups=" << value.payload.groups.size()
              << " submeshes=" << value.payload.total_submesh_count
              << " vertices=" << value.payload.total_vertex_count
              << " indices=" << value.payload.total_index_count
              << " bones=" << value.package.descriptor.bones.size()
              << " roots=" << value.package.descriptor.root_bone_ids.size()
              << " anim_refs=" << value.package.descriptor.animation_object_names.size()
              << " defaults=" << value.default_selections.size() << " json_fnv=" << json_hash
              << " obj_fnv=" << obj_hash << '\n';
    return passed;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 3)
    {
        std::cerr << "usage: tmxy_skem_real_samples_test <legacy-packages-root> "
                     "<legacy-skelmesh-resource-root>\n";
        return 2;
    }
    const std::filesystem::path packages(arguments[1]);
    const std::filesystem::path resources(arguments[2]);
    bool passed = true;
    passed &= parse_payload_sample(resources / "particle/FXH_O_S_shizuo.skem", "minimum");
    passed &= parse_bound_sample(packages / "SkelMesh/skchar", resources / "skchar/Boy01.skem",
                                 "skchar.Boy01",
                                 {.submeshes = 1620,
                                  .vertices = 842929,
                                  .indices = 2944338,
                                  .triangles = 981446,
                                  .shadow_indices = 1863993,
                                  .animation_references = 272,
                                  .json_fingerprint = 15247003949501018541ULL,
                                  .obj_fingerprint = 5471625972164385819ULL,
                                  .descriptor_offset = 164605,
                                  .descriptor_size = 40975,
                                  .sentinel_vertices = 0});
    passed &= parse_bound_sample(packages / "SkelMesh/skchar", resources / "skchar/Girl01.skem",
                                 "skchar.Girl01",
                                 {.submeshes = 1806,
                                  .vertices = 1014104,
                                  .indices = 3668820,
                                  .triangles = 1222940,
                                  .shadow_indices = 2255022,
                                  .animation_references = 270,
                                  .json_fingerprint = 1574790148036450785ULL,
                                  .obj_fingerprint = 7828294081594915180ULL,
                                  .descriptor_offset = 230361,
                                  .descriptor_size = 41181,
                                  .sentinel_vertices = 2});
    return passed ? 0 : 1;
}
