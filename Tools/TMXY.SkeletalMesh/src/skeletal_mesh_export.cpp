#include "tmxy/skeletal_mesh/skeletal_mesh_export.hpp"

#include "tmxy/transform/legacy_to_ue_transform.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>

namespace tmxy::skeletal_mesh
{
namespace
{

[[nodiscard]] SkeletalMeshError transform_error(std::string context)
{
    return {.code = SkeletalMeshErrorCode::transform_failure,
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
            if (character < 0x20U || character >= 0x80U)
            {
                output << "\\u00" << std::hex << std::setw(2) << std::setfill('0')
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
        result.push_back(character <= 0x20U || character >= 0x7FU ? '_' : raw_character);
    }
    return result.empty() ? std::string("unnamed") : result;
}

struct WeightSummary final
{
    float minimum{1.0F};
    float maximum{0.0F};
    float maximum_sum_error{0.0F};
    std::uint32_t maximum_bone_index{0};
    std::array<std::uint64_t, 5> influence_histogram{};
    std::uint64_t legacy_unweighted_sentinel_count{0};
};

[[nodiscard]] bool is_legacy_unweighted_sentinel(const Vec4& weights,
                                                 const Vec4& bone_indices) noexcept
{
    return weights.x == -1.0F && weights.y == -1.0F && weights.z == -1.0F && weights.w == -1.0F &&
           bone_indices.x == 0.0F && bone_indices.y == 0.0F && bone_indices.z == 0.0F &&
           bone_indices.w == 0.0F;
}

[[nodiscard]] WeightSummary summarize_weights(const SkeletalMeshPayload& payload) noexcept
{
    WeightSummary summary;
    for (const auto& group : payload.groups)
    {
        for (const auto& mesh : group.submeshes)
        {
            for (std::size_t vertex = 0; vertex < mesh.weights.size(); ++vertex)
            {
                const auto& weight = mesh.weights[vertex];
                const auto& bone = mesh.bone_indices[vertex];
                const std::array weights{weight.x, weight.y, weight.z, weight.w};
                const std::array bones{bone.x, bone.y, bone.z, bone.w};
                if (is_legacy_unweighted_sentinel(weight, bone))
                {
                    summary.minimum = -1.0F;
                    ++summary.legacy_unweighted_sentinel_count;
                    ++summary.influence_histogram[0];
                    continue;
                }
                float sum = 0.0F;
                std::size_t active = 0;
                for (std::size_t influence = 0; influence < weights.size(); ++influence)
                {
                    summary.minimum = std::min(summary.minimum, weights[influence]);
                    summary.maximum = std::max(summary.maximum, weights[influence]);
                    sum += weights[influence];
                    if (weights[influence] > 0.00001F)
                    {
                        ++active;
                        summary.maximum_bone_index =
                            std::max(summary.maximum_bone_index,
                                     static_cast<std::uint32_t>(std::lround(bones[influence])));
                    }
                }
                summary.maximum_sum_error =
                    std::max(summary.maximum_sum_error, std::abs(sum - 1.0F));
                ++summary.influence_histogram[active];
            }
        }
    }
    if (payload.total_vertex_count == 0U)
    {
        summary.minimum = 0.0F;
    }
    return summary;
}

[[nodiscard]] const SkeletalSubmesh*
selected_submesh(const SkeletalMeshBinding& binding,
                 const DefaultSubmeshSelection& selection) noexcept
{
    if (!selection.submesh_index_in_group.has_value())
    {
        return nullptr;
    }
    return &binding.payload.groups[selection.group_index]
                .submeshes[selection.submesh_index_in_group.value()];
}

[[nodiscard]] SkeletalMeshResult<std::uint64_t>
write_obj_vertices(std::ostringstream& output, const SkeletalSubmesh& mesh,
                   const std::uint64_t vertex_offset)
{
    for (std::size_t index = 0; index < mesh.positions.size(); ++index)
    {
        const auto& value = mesh.positions[index];
        const auto converted =
            transform::LegacyToUETransform::position({.x = value.x, .y = value.y, .z = value.z});
        if (!converted.has_value())
        {
            return SkeletalMeshResult<std::uint64_t>::failure(
                transform_error("skeletal_mesh.positions[" + std::to_string(index) + "]"));
        }
        output << "v " << converted.value().x << ' ' << converted.value().y << ' '
               << converted.value().z << '\n';
    }
    for (const auto& value : mesh.uv0)
    {
        const auto converted = transform::LegacyToUETransform::uv({.x = value.u, .y = value.v});
        if (!converted.has_value())
        {
            return SkeletalMeshResult<std::uint64_t>::failure(transform_error("skeletal_mesh.uv0"));
        }
        output << "vt " << converted.value().x << ' ' << converted.value().y << '\n';
    }
    for (const auto& value : mesh.normals)
    {
        const auto converted =
            transform::LegacyToUETransform::normal({.x = value.x, .y = value.y, .z = value.z});
        if (!converted.has_value())
        {
            return SkeletalMeshResult<std::uint64_t>::failure(
                transform_error("skeletal_mesh.normals"));
        }
        output << "vn " << converted.value().x << ' ' << converted.value().y << ' '
               << converted.value().z << '\n';
    }
    return SkeletalMeshResult<std::uint64_t>::success(vertex_offset + mesh.positions.size());
}

void write_obj_faces(std::ostringstream& output, const SkeletalSubmesh& mesh,
                     const DefaultSubmeshSelection& selection, const std::uint64_t vertex_offset)
{
    output << "g group_" << selection.group_index << '_' << obj_identifier(mesh.section_name_bytes)
           << '\n'
           << "usemtl " << obj_identifier(selection.material_object_name) << '\n';
    for (std::size_t index = 0; index < mesh.indices.size(); index += 3U)
    {
        output << 'f';
        for (std::size_t corner = 0; corner < 3U; ++corner)
        {
            const auto vertex = vertex_offset + mesh.indices[index + corner] + 1U;
            output << ' ' << vertex << '/' << vertex << '/' << vertex;
        }
        output << '\n';
    }
}

void write_vec3(std::ostringstream& output, const Vec3& value)
{
    output << '[' << value.x << ", " << value.y << ", " << value.z << ']';
}

void write_vec4(std::ostringstream& output, const Vec4& value)
{
    output << '[' << value.x << ", " << value.y << ", " << value.z << ", " << value.w << ']';
}

void write_bones(std::ostringstream& output, const SkeletalMeshDescriptor& descriptor)
{
    output << "  \"bones\": [\n";
    for (std::size_t index = 0; index < descriptor.bones.size(); ++index)
    {
        const auto& bone = descriptor.bones[index];
        output << "    {\"id\": " << bone.id << ", \"name\": " << json_string(bone.name_bytes)
               << ", \"parent_id\": " << bone.parent_id << ", \"bind_rotation_xyzw\": ";
        write_vec4(output, bone.rotation);
        output << ", \"bind_translation_legacy_meters\": ";
        write_vec3(output, bone.translation);
        output << ", \"bind_translation_ue_centimeters\": [" << bone.translation.x * 100.0F << ", "
               << bone.translation.y * 100.0F << ", " << bone.translation.z * 100.0F
               << "], \"children\": [";
        for (std::size_t child = 0; child < bone.children.size(); ++child)
        {
            output << bone.children[child] << (child + 1U == bone.children.size() ? "" : ", ");
        }
        output << "]}" << (index + 1U == descriptor.bones.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

void write_selections(std::ostringstream& output, const SkeletalMeshBinding& binding)
{
    output << "  \"default_selections\": [\n";
    for (std::size_t index = 0; index < binding.default_selections.size(); ++index)
    {
        const auto& selection = binding.default_selections[index];
        const auto* mesh = selected_submesh(binding, selection);
        output << "    {\"group_index\": " << selection.group_index
               << ", \"group_id\": " << binding.payload.groups[index].id
               << ", \"global_submesh_index\": " << selection.global_submesh_index
               << ", \"material\": " << json_string(selection.material_object_name)
               << ", \"section_name\": "
               << (mesh == nullptr ? "null" : json_string(mesh->section_name_bytes)) << '}';
        output << (index + 1U == binding.default_selections.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

void write_attachment_candidates(std::ostringstream& output,
                                 const SkeletalMeshDescriptor& descriptor)
{
    output << "  \"attachment_contract\": "
              "\"legacy runtime resolves attachments by bone name; no distinct "
              "socket record in "
              "QSkelMesh\",\n"
           << "  \"attachment_point_candidates\": [";
    for (std::size_t index = 0; index < descriptor.bones.size(); ++index)
    {
        output << json_string(descriptor.bones[index].name_bytes)
               << (index + 1U == descriptor.bones.size() ? "" : ", ");
    }
    output << "]\n";
}

} // namespace

SkeletalMeshResult<std::string> build_default_ue_obj(const SkeletalMeshBinding& binding)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<double>::max_digits10);
    output << "# TMXY skeletal mesh default-selection OBJ review artifact\n"
           << "# coordinates: Unreal X-forward/Y-right/Z-up centimeters\n"
           << "# skinning remains in the adjacent deterministic JSON metadata\n"
           << "o " << obj_identifier(binding.package.object_name_bytes) << '\n';
    std::uint64_t vertex_offset = 0;
    for (const auto& selection : binding.default_selections)
    {
        const auto* mesh = selected_submesh(binding, selection);
        if (mesh == nullptr)
        {
            continue;
        }
        auto next_offset = write_obj_vertices(output, *mesh, vertex_offset);
        if (!next_offset.has_value())
        {
            return SkeletalMeshResult<std::string>::failure(next_offset.error());
        }
        write_obj_faces(output, *mesh, selection, vertex_offset);
        vertex_offset = next_offset.value();
    }
    return SkeletalMeshResult<std::string>::success(output.str());
}

std::string build_skeletal_mesh_json(const SkeletalMeshBinding& binding)
{
    const auto weights = summarize_weights(binding.payload);
    const auto& descriptor = binding.package.descriptor;
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<float>::max_digits10);
    output << "{\n"
           << "  \"schema_version\": 1,\n"
           << "  \"object_name\": " << json_string(binding.package.object_name_bytes) << ",\n"
           << "  \"coordinate_contract\": "
              "\"legacy-runtime-x-forward-y-right-z-up-meters\",\n"
           << "  \"ue_preview_contract\": \"x-forward-y-right-z-up-centimeters\",\n"
           << "  \"group_count\": " << binding.payload.groups.size() << ",\n"
           << "  \"submesh_count\": " << binding.payload.total_submesh_count << ",\n"
           << "  \"vertex_count\": " << binding.payload.total_vertex_count << ",\n"
           << "  \"index_count\": " << binding.payload.total_index_count << ",\n"
           << "  \"triangle_count\": " << binding.payload.total_triangle_count << ",\n"
           << "  \"shadow_index_count\": " << binding.payload.total_shadow_index_count << ",\n"
           << "  \"bone_count\": " << descriptor.bones.size() << ",\n"
           << "  \"root_bone_ids\": [";
    for (std::size_t index = 0; index < descriptor.root_bone_ids.size(); ++index)
    {
        output << descriptor.root_bone_ids[index]
               << (index + 1U == descriptor.root_bone_ids.size() ? "" : ", ");
    }
    output << "],\n"
           << "  \"animation_reference_count\": " << descriptor.animation_object_names.size()
           << ",\n"
           << "  \"default_animation\": " << json_string(descriptor.default_animation_name_bytes)
           << ",\n"
           << "  \"weight_minimum\": " << weights.minimum << ",\n"
           << "  \"weight_maximum\": " << weights.maximum << ",\n"
           << "  \"weight_maximum_sum_error\": " << weights.maximum_sum_error << ",\n"
           << "  \"legacy_unweighted_sentinel_vertex_count\": "
           << weights.legacy_unweighted_sentinel_count << ",\n"
           << "  \"maximum_active_legacy_one_based_bone_index\": " << weights.maximum_bone_index
           << ",\n"
           << "  \"active_influence_histogram_0_to_4\": [";
    for (std::size_t index = 0; index < weights.influence_histogram.size(); ++index)
    {
        output << weights.influence_histogram[index]
               << (index + 1U == weights.influence_histogram.size() ? "" : ", ");
    }
    output << "],\n"
           << "  \"unknown_property_count\": " << descriptor.unknown_properties.size() << ",\n";
    write_bones(output, descriptor);
    write_selections(output, binding);
    write_attachment_candidates(output, descriptor);
    output << "}\n";
    return output.str();
}

} // namespace tmxy::skeletal_mesh
