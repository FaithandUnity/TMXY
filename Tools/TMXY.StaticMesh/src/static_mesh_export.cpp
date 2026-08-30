#include "tmxy/static_mesh/static_mesh_export.hpp"

#include "tmxy/transform/legacy_to_ue_transform.hpp"

#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>

namespace tmxy::static_mesh
{
namespace
{

[[nodiscard]] StaticMeshError transform_error(std::string context)
{
    return {.code = StaticMeshErrorCode::transform_failure,
            .absolute_offset = 0,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] std::string json_string(const std::string_view value)
{
    std::ostringstream output;
    output << '"';
    for (const char raw_character : value)
    {
        const auto character = static_cast<unsigned char>(raw_character);
        switch (character)
        {
        case '"':
            output << "\\\"";
            break;
        case '\\':
            output << "\\\\";
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
            if (character < 0x20U)
            {
                output << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                       << static_cast<unsigned int>(character) << std::dec;
            }
            else
            {
                output << static_cast<char>(character);
            }
        }
    }
    output << '"';
    return output.str();
}

[[nodiscard]] std::string obj_identifier(const std::string_view value)
{
    std::string result;
    result.reserve(value.size());
    for (const char raw_character : value)
    {
        const auto character = static_cast<unsigned char>(raw_character);
        result.push_back(character <= 0x20U || character == 0x7FU ? '_' : raw_character);
    }
    return result.empty() ? std::string("unnamed") : result;
}

void write_aabb_json(std::ostringstream& output, const Aabb& bounds, const float scale)
{
    output << "{\"minimum\": [" << bounds.minimum.x * scale << ", " << bounds.minimum.y * scale
           << ", " << bounds.minimum.z * scale << "], \"maximum\": [" << bounds.maximum.x * scale
           << ", " << bounds.maximum.y * scale << ", " << bounds.maximum.z * scale << "]}";
}

} // namespace

StaticMeshResult<std::string> build_ue_obj(const StaticMeshBinding& binding)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<double>::max_digits10);
    output << "# TMXY static mesh OBJ preview\n"
           << "# coordinates: Unreal X-forward/Y-right/Z-up centimeters\n"
           << "# winding: preserved from legacy runtime\n"
           << "o " << obj_identifier(binding.package.object_name_bytes) << '\n';

    for (std::size_t index = 0; index < binding.mesh.positions.size(); ++index)
    {
        const auto& value = binding.mesh.positions[index];
        const auto converted =
            transform::LegacyToUETransform::position({.x = value.x, .y = value.y, .z = value.z});
        if (!converted.has_value())
        {
            return StaticMeshResult<std::string>::failure(
                transform_error("static_mesh.positions[" + std::to_string(index) + "]"));
        }
        output << "v " << converted.value().x << ' ' << converted.value().y << ' '
               << converted.value().z << '\n';
    }
    for (std::size_t index = 0; index < binding.mesh.uv0.size(); ++index)
    {
        const auto& value = binding.mesh.uv0[index];
        const auto converted = transform::LegacyToUETransform::uv({.x = value.u, .y = value.v});
        if (!converted.has_value())
        {
            return StaticMeshResult<std::string>::failure(
                transform_error("static_mesh.uv0[" + std::to_string(index) + "]"));
        }
        output << "vt " << converted.value().x << ' ' << converted.value().y << '\n';
    }
    for (std::size_t index = 0; index < binding.mesh.normals.size(); ++index)
    {
        const auto& value = binding.mesh.normals[index];
        const auto converted =
            transform::LegacyToUETransform::normal({.x = value.x, .y = value.y, .z = value.z});
        if (!converted.has_value())
        {
            return StaticMeshResult<std::string>::failure(
                transform_error("static_mesh.normals[" + std::to_string(index) + "]"));
        }
        output << "vn " << converted.value().x << ' ' << converted.value().y << ' '
               << converted.value().z << '\n';
    }
    for (std::size_t section_index = 0; section_index < binding.mesh.sections.size();
         ++section_index)
    {
        const auto& section = binding.mesh.sections[section_index];
        output << "g section_" << section_index << '\n'
               << "usemtl "
               << obj_identifier(binding.package.descriptor.material_object_names[section_index])
               << '\n';
        const auto end =
            section.first_index + (static_cast<std::uint64_t>(section.triangle_count) * 3U);
        for (std::uint64_t index = section.first_index; index < end; index += 3U)
        {
            output << 'f';
            for (std::uint64_t corner = 0; corner < 3U; ++corner)
            {
                const auto vertex =
                    static_cast<std::uint64_t>(binding.mesh.indices[index + corner]) + 1U;
                output << ' ' << vertex << '/' << vertex << '/' << vertex;
            }
            output << '\n';
        }
    }
    return StaticMeshResult<std::string>::success(output.str());
}

std::string build_static_mesh_json(const StaticMeshBinding& binding)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<float>::max_digits10);
    output << "{\n"
           << "  \"schema_version\": 1,\n"
           << "  \"object_name\": " << json_string(binding.package.object_name_bytes) << ",\n"
           << "  \"coordinate_contract\": "
              "\"legacy-runtime-x-forward-y-right-z-up-meters\",\n"
           << "  \"ue_preview_contract\": \"x-forward-y-right-z-up-centimeters\",\n"
           << "  \"vertex_count\": " << binding.mesh.positions.size() << ",\n"
           << "  \"index_count\": " << binding.mesh.indices.size() << ",\n"
           << "  \"triangle_count\": " << binding.mesh.indices.size() / 3U << ",\n"
           << "  \"section_count\": " << binding.mesh.sections.size() << ",\n"
           << "  \"material_slot_basis\": "
           << json_string(to_string(binding.material_slot_resolution.basis)) << ",\n"
           << "  \"declared_material_slot_count\": "
           << binding.material_slot_resolution.declared_material_slot_count << ",\n"
           << "  \"effective_material_slot_count\": "
           << binding.material_slot_resolution.effective_material_slot_count << ",\n"
           << "  \"ignored_material_slot_count\": "
           << binding.material_slot_resolution.ignored_material_slot_count << ",\n"
           << "  \"uv_channel_count\": " << (binding.mesh.uv1_field_present ? 2 : 1) << ",\n"
           << "  \"shadow_vertex_count\": " << binding.mesh.shadow_positions.size() << ",\n"
           << "  \"shadow_index_count\": " << binding.mesh.shadow_indices.size() << ",\n"
           << "  \"collision_vertex_count\": " << binding.mesh.collision_positions.size() << ",\n"
           << "  \"collision_index_count\": " << binding.mesh.collision_indices.size() << ",\n"
           << "  \"octree_node_count\": " << binding.mesh.octree_nodes.size() << ",\n"
           << "  \"octree_index_count\": " << binding.mesh.octree_indices.size() << ",\n"
           << "  \"emitter_point_count\": " << binding.mesh.emitter_points.size() << ",\n"
           << "  \"legacy_bounds\": ";
    write_aabb_json(output, binding.effective_bounds, 1.0F);
    output << ",\n  \"ue_centimeter_bounds\": ";
    write_aabb_json(output, binding.effective_bounds, 100.0F);
    output << ",\n"
           << "  \"declared_bounds_relation\": "
           << json_string(to_string(binding.declared_bounds_relation)) << ",\n"
           << "  \"use_light_map\": ";
    if (binding.package.descriptor.use_light_map.has_value())
    {
        output << (*binding.package.descriptor.use_light_map ? "true" : "false");
    }
    else
    {
        output << "false";
    }
    output << ",\n"
           << "  \"unknown_property_count\": "
           << binding.package.descriptor.unknown_properties.size() << ",\n"
           << "  \"sections\": [\n";
    for (std::size_t index = 0; index < binding.mesh.sections.size(); ++index)
    {
        const auto& section = binding.mesh.sections[index];
        output << "    {\"slot\": " << index << ", \"material\": "
               << json_string(binding.package.descriptor.material_object_names[index])
               << ", \"first_index\": " << section.first_index
               << ", \"triangle_count\": " << section.triangle_count
               << ", \"minimum_vertex\": " << section.minimum_vertex_index
               << ", \"maximum_vertex\": " << section.maximum_vertex_index
               << ", \"two_sided\": " << (section.two_sided ? "true" : "false") << '}';
        output << (index + 1U == binding.mesh.sections.size() ? "\n" : ",\n");
    }
    output << "  ]\n}\n";
    return output.str();
}

std::uint64_t bytes_fingerprint(const std::span<const std::byte> bytes) noexcept
{
    std::uint64_t hash = 14695981039346656037ULL;
    for (const auto byte : bytes)
    {
        hash ^= std::to_integer<std::uint8_t>(byte);
        hash *= 1099511628211ULL;
    }
    return hash;
}

std::uint64_t text_fingerprint(const std::string_view text) noexcept
{
    return bytes_fingerprint(std::as_bytes(std::span(text.data(), text.size())));
}

} // namespace tmxy::static_mesh
