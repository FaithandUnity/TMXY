#include "tmxy/static_mesh/package_static_mesh_reader.hpp"
#include "tmxy/static_mesh/static_mesh_export.hpp"

#include <array>
#include <cstddef>
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

struct SampleArguments final
{
    std::string_view package_path;
    std::string_view object_name;
    std::string_view sm_path;
    std::string_view expected_output;
};

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

[[nodiscard]] bool inspect_sample(const SampleArguments sample)
{
    const auto package = read_file(sample.package_path);
    const auto sm = read_file(sample.sm_path);
    if (package.empty() || sm.empty())
    {
        std::cerr << "sample-read-failed: " << sample.object_name << '\n';
        return false;
    }
    const auto binding = tmxy::static_mesh::bind_static_mesh(package, sample.object_name, sm);
    if (!binding.has_value())
    {
        std::cerr << "sample-parse-failed: " << sample.object_name
                  << " code=" << tmxy::static_mesh::to_string(binding.error().code)
                  << " context=" << binding.error().context << '\n';
        return false;
    }
    const auto& resolution = binding.value().material_slot_resolution;
    if (resolution.basis != tmxy::static_mesh::MaterialSlotBasis::package_descriptor ||
        resolution.declared_material_slot_count != binding.value().mesh.sections.size() ||
        resolution.effective_material_slot_count != binding.value().mesh.sections.size() ||
        resolution.ignored_material_slot_count != 0U)
    {
        std::cerr << "sample-material-resolution-failed: " << sample.object_name << '\n';
        return false;
    }
    const auto json = tmxy::static_mesh::build_static_mesh_json(binding.value());
    std::uint64_t obj_fingerprint = 0;
    if (sm.size() < 1024U)
    {
        const auto obj = tmxy::static_mesh::build_ue_obj(binding.value());
        if (!obj.has_value())
        {
            std::cerr << "sample-obj-failed: " << sample.object_name << '\n';
            return false;
        }
        obj_fingerprint = tmxy::static_mesh::text_fingerprint(obj.value());
    }
    const auto& mesh = binding.value().mesh;
    const auto& bounds = binding.value().effective_bounds;
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<float>::max_digits10) << sample.object_name
           << " vertices=" << mesh.positions.size() << " indices=" << mesh.indices.size()
           << " sections=" << mesh.sections.size()
           << " uv_channels=" << (mesh.uv1_field_present ? 2 : 1)
           << " shadow_vertices=" << mesh.shadow_positions.size()
           << " shadow_indices=" << mesh.shadow_indices.size()
           << " collision_vertices=" << mesh.collision_positions.size()
           << " octree_nodes=" << mesh.octree_nodes.size()
           << " octree_indices=" << mesh.octree_indices.size() << " declared_bounds="
           << tmxy::static_mesh::to_string(binding.value().declared_bounds_relation)
           << " bounds=" << bounds.minimum.x << ',' << bounds.minimum.y << ',' << bounds.minimum.z
           << ':' << bounds.maximum.x << ',' << bounds.maximum.y << ',' << bounds.maximum.z
           << " json_fnv=" << tmxy::static_mesh::text_fingerprint(json)
           << " obj_fnv=" << obj_fingerprint;
    std::cout << output.str() << '\n';
    if (output.str() != sample.expected_output)
    {
        std::cerr << "sample-signature-mismatch: " << sample.object_name << '\n';
        return false;
    }
    return true;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    constexpr int arguments_per_sample = 3;
    constexpr std::array<std::string_view, 4> expected_outputs = {
        "particle.ZFH_O_S_Tianpian100 vertices=4 indices=6 sections=1 "
        "uv_channels=1 "
        "shadow_vertices=0 shadow_indices=0 collision_vertices=0 octree_nodes=0 "
        "octree_indices=0 declared_bounds=contains "
        "bounds=-17.5672302,-17.2778435,-4.68960619:-14.7323551,14.307416,19."
        "1825714 "
        "json_fnv=13026901066817879978 obj_fnv=7919486951111466039",
        "newscenc.dy_bx_stl_005 vertices=157638 indices=157638 sections=1 "
        "uv_channels=2 "
        "shadow_vertices=74907 shadow_indices=366357 collision_vertices=0 "
        "octree_nodes=11 "
        "octree_indices=114924 declared_bounds=contains "
        "bounds=-100.774826,-3.03948212,2.30944395:10.8779144,317.66629,5."
        "70774889 "
        "json_fnv=5344752217521232092 obj_fnv=0",
        "newscenc.dy_bx_bqg_006 vertices=47964 indices=250614 sections=1 "
        "uv_channels=2 "
        "shadow_vertices=250614 shadow_indices=1002456 collision_vertices=0 "
        "octree_nodes=194 "
        "octree_indices=291201 declared_bounds=mismatch "
        "bounds=-150.552399,-173.027374,-71.6268158:289.874359,217.916229,109."
        "383087 "
        "json_fnv=7825768401660102655 obj_fnv=0",
        "scene09.GT_B_S_BangPai05 vertices=11847 indices=19533 sections=43 "
        "uv_channels=2 "
        "shadow_vertices=0 shadow_indices=0 collision_vertices=6416 "
        "octree_nodes=340 "
        "octree_indices=23379 declared_bounds=exact "
        "bounds=-37.4604683,-42.9401703,-8.96472454:37.3805618,42.9401779,8."
        "96472931 "
        "json_fnv=6463187087661512439 obj_fnv=0"};
    if (argument_count != 13)
    {
        std::cerr << "usage: tmxy_sm_real_samples_test "
                     "<package> <object> <sm> repeated four times\n";
        return 2;
    }
    bool passed = true;
    std::size_t sample_index = 0;
    for (int offset = 1; offset < argument_count; offset += arguments_per_sample)
    {
        passed = inspect_sample({.package_path = arguments[offset],
                                 .object_name = arguments[offset + 1],
                                 .sm_path = arguments[offset + 2],
                                 .expected_output = expected_outputs[sample_index]}) &&
                 passed;
        ++sample_index;
    }
    return passed ? 0 : 1;
}
