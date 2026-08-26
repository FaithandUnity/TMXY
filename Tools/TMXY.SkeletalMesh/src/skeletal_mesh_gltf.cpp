#include "tmxy/skeletal_mesh/skeletal_mesh_gltf.hpp"

#include "skeletal_mesh_gltf_internal.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <ranges>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::skeletal_mesh
{
namespace
{

constexpr float kActiveWeight = 0.00001F;

using detail::BinaryLayout;
using detail::ByteRange;
using detail::Primitive;

struct SelectedMesh final
{
    const DefaultSubmeshSelection* selection{nullptr};
    const SkeletalSubmesh* mesh{nullptr};
    std::uint32_t vertex_offset{0};
};

struct RigidTransform final
{
    std::array<float, 4> rotation{};
    std::array<float, 3> translation{};
};

[[nodiscard]] SkeletalMeshError gltf_error(std::string context)
{
    return {.code = SkeletalMeshErrorCode::transform_failure,
            .absolute_offset = 0,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] bool is_safe_buffer_uri(const std::string_view value) noexcept
{
    return !value.empty() && value != "." && value != ".." &&
           std::ranges::all_of(value,
                               [](const char character)
                               {
                                   return std::isalnum(static_cast<unsigned char>(character)) !=
                                              0 ||
                                          character == '.' || character == '_' || character == '-';
                               });
}

void align_four(std::vector<std::byte>& bytes)
{
    while ((bytes.size() & 3U) != 0U)
    {
        bytes.push_back(std::byte{0});
    }
}

void append_u16(std::vector<std::byte>& bytes, const std::uint16_t value)
{
    bytes.push_back(static_cast<std::byte>(value & 0xFFU));
    bytes.push_back(static_cast<std::byte>((value >> 8U) & 0xFFU));
}

void append_u32(std::vector<std::byte>& bytes, const std::uint32_t value)
{
    for (std::uint32_t shift = 0; shift < 32U; shift += 8U)
    {
        bytes.push_back(static_cast<std::byte>((value >> shift) & 0xFFU));
    }
}

void append_f32(std::vector<std::byte>& bytes, const float value)
{
    append_u32(bytes, std::bit_cast<std::uint32_t>(value));
}

template <typename Writer>
[[nodiscard]] ByteRange append_range(std::vector<std::byte>& bytes, const int target, Writer writer)
{
    align_four(bytes);
    const auto offset = bytes.size();
    writer();
    return {.offset = offset, .size = bytes.size() - offset, .target = target};
}

[[nodiscard]] std::array<float, 3> to_gltf(const Vec3& value) noexcept
{
    return {value.y, value.z, value.x};
}

[[nodiscard]] std::optional<std::array<float, 3>> normalized_gltf(const Vec3& value) noexcept
{
    auto mapped = to_gltf(value);
    const auto length =
        std::sqrt((mapped[0] * mapped[0]) + (mapped[1] * mapped[1]) + (mapped[2] * mapped[2]));
    if (!std::isfinite(length) || length <= std::numeric_limits<float>::epsilon())
    {
        return std::nullopt;
    }
    for (float& component : mapped)
    {
        component /= length;
    }
    return mapped;
}

[[nodiscard]] std::optional<std::array<float, 4>> normalized_gltf(const Quaternion& value) noexcept
{
    std::array mapped{value.y, value.z, value.x, value.w};
    float length_squared = 0.0F;
    for (const float component : mapped)
    {
        length_squared += component * component;
    }
    const auto length = std::sqrt(length_squared);
    if (!std::isfinite(length) || length <= std::numeric_limits<float>::epsilon())
    {
        return std::nullopt;
    }
    for (float& component : mapped)
    {
        component /= length;
    }
    return mapped;
}

[[nodiscard]] std::array<float, 4> multiply(const std::array<float, 4>& left,
                                            const std::array<float, 4>& right) noexcept
{
    return {
        (left[3] * right[0]) + (left[0] * right[3]) + (left[1] * right[2]) - (left[2] * right[1]),
        (left[3] * right[1]) - (left[0] * right[2]) + (left[1] * right[3]) + (left[2] * right[0]),
        (left[3] * right[2]) + (left[0] * right[1]) - (left[1] * right[0]) + (left[2] * right[3]),
        (left[3] * right[3]) - (left[0] * right[0]) - (left[1] * right[1]) - (left[2] * right[2])};
}

[[nodiscard]] std::array<float, 3> rotate(const std::array<float, 4>& quaternion,
                                          const std::array<float, 3>& value) noexcept
{
    const std::array<float, 3> q{quaternion[0], quaternion[1], quaternion[2]};
    const std::array cross{(q[1] * value[2]) - (q[2] * value[1]),
                           (q[2] * value[0]) - (q[0] * value[2]),
                           (q[0] * value[1]) - (q[1] * value[0])};
    const std::array cross_twice{(q[1] * cross[2]) - (q[2] * cross[1]),
                                 (q[2] * cross[0]) - (q[0] * cross[2]),
                                 (q[0] * cross[1]) - (q[1] * cross[0])};
    return {value[0] + (2.0F * ((quaternion[3] * cross[0]) + cross_twice[0])),
            value[1] + (2.0F * ((quaternion[3] * cross[1]) + cross_twice[1])),
            value[2] + (2.0F * ((quaternion[3] * cross[2]) + cross_twice[2]))};
}

[[nodiscard]] bool build_global_pose(const SkeletalMeshDescriptor& descriptor,
                                     std::vector<RigidTransform>& globals)
{
    globals.reserve(descriptor.bones.size());
    for (std::size_t index = 0; index < descriptor.bones.size(); ++index)
    {
        const Bone& bone = descriptor.bones[index];
        const auto rotation = normalized_gltf(bone.rotation);
        if (bone.id < 0 || std::cmp_not_equal(bone.id, index) || !rotation.has_value() ||
            (bone.parent_id >= 0 && std::cmp_greater_equal(bone.parent_id, index)))
        {
            return false;
        }
        RigidTransform value{.rotation = *rotation, .translation = to_gltf(bone.translation)};
        if (bone.parent_id >= 0)
        {
            const auto& parent = globals[static_cast<std::size_t>(bone.parent_id)];
            const auto relative = rotate(parent.rotation, value.translation);
            value.translation = {parent.translation[0] + relative[0],
                                 parent.translation[1] + relative[1],
                                 parent.translation[2] + relative[2]};
            value.rotation = multiply(parent.rotation, value.rotation);
        }
        globals.push_back(value);
    }
    return !globals.empty();
}

void append_inverse_matrix(std::vector<std::byte>& bytes, const RigidTransform& transform)
{
    const auto& q = transform.rotation;
    const float x2 = q[0] + q[0];
    const float y2 = q[1] + q[1];
    const float z2 = q[2] + q[2];
    const float xx = q[0] * x2;
    const float xy = q[0] * y2;
    const float xz = q[0] * z2;
    const float yy = q[1] * y2;
    const float yz = q[1] * z2;
    const float zz = q[2] * z2;
    const float wx = q[3] * x2;
    const float wy = q[3] * y2;
    const float wz = q[3] * z2;
    const std::array<std::array<float, 3>, 3> rotation{{
        {1.0F - (yy + zz), xy - wz, xz + wy},
        {xy + wz, 1.0F - (xx + zz), yz - wx},
        {xz - wy, yz + wx, 1.0F - (xx + yy)},
    }};
    std::array<float, 3> inverse_translation{};
    for (std::size_t row = 0; row < 3U; ++row)
    {
        inverse_translation[row] = -((rotation[0][row] * transform.translation[0]) +
                                     (rotation[1][row] * transform.translation[1]) +
                                     (rotation[2][row] * transform.translation[2]));
    }
    for (std::size_t column = 0; column < 4U; ++column)
    {
        for (std::size_t row = 0; row < 4U; ++row)
        {
            float value = row == column ? 1.0F : 0.0F;
            if (column < 3U && row < 3U)
            {
                value = rotation[column][row];
            }
            else if (column == 3U && row < 3U)
            {
                value = inverse_translation[row];
            }
            append_f32(bytes, value);
        }
    }
}

[[nodiscard]] std::optional<std::vector<SelectedMesh>>
collect_selected_meshes(const SkeletalMeshBinding& binding)
{
    std::vector<SelectedMesh> result;
    std::uint64_t vertex_offset = 0;
    for (const auto& selection : binding.default_selections)
    {
        if (!selection.submesh_index_in_group.has_value())
        {
            continue;
        }
        if (selection.group_index >= binding.payload.groups.size())
        {
            return std::nullopt;
        }
        const auto& group = binding.payload.groups[selection.group_index];
        if (*selection.submesh_index_in_group >= group.submeshes.size())
        {
            return std::nullopt;
        }
        const auto& mesh = group.submeshes[*selection.submesh_index_in_group];
        if (mesh.positions.empty() || mesh.positions.size() != mesh.normals.size() ||
            mesh.positions.size() != mesh.uv0.size() ||
            mesh.positions.size() != mesh.weights.size() ||
            mesh.positions.size() != mesh.bone_indices.size() ||
            vertex_offset + mesh.positions.size() > std::numeric_limits<std::uint32_t>::max())
        {
            return std::nullopt;
        }
        result.push_back({.selection = &selection,
                          .mesh = &mesh,
                          .vertex_offset = static_cast<std::uint32_t>(vertex_offset)});
        vertex_offset += mesh.positions.size();
    }
    return result.empty() ? std::nullopt : std::optional(std::move(result));
}

[[nodiscard]] ByteRange append_positions(BinaryLayout& layout,
                                         const std::vector<SelectedMesh>& meshes)
{
    return append_range(layout.bytes, 34962,
                        [&]
                        {
                            for (const auto& selected : meshes)
                            {
                                for (const auto& source : selected.mesh->positions)
                                {
                                    const auto value = to_gltf(source);
                                    for (std::size_t axis = 0; axis < 3U; ++axis)
                                    {
                                        append_f32(layout.bytes, value[axis]);
                                        layout.minimum[axis] =
                                            std::min(layout.minimum[axis], value[axis]);
                                        layout.maximum[axis] =
                                            std::max(layout.maximum[axis], value[axis]);
                                    }
                                    ++layout.vertex_count;
                                }
                            }
                        });
}

[[nodiscard]] ByteRange append_normals(BinaryLayout& layout,
                                       const std::vector<SelectedMesh>& meshes, bool& valid)
{
    return append_range(layout.bytes, 34962,
                        [&]
                        {
                            for (const auto& selected : meshes)
                            {
                                for (const auto& source : selected.mesh->normals)
                                {
                                    const auto value = normalized_gltf(source);
                                    if (!value.has_value())
                                    {
                                        valid = false;
                                        continue;
                                    }
                                    for (const float component : *value)
                                    {
                                        append_f32(layout.bytes, component);
                                    }
                                }
                            }
                        });
}

[[nodiscard]] ByteRange append_uvs(BinaryLayout& layout, const std::vector<SelectedMesh>& meshes)
{
    return append_range(layout.bytes, 34962,
                        [&]
                        {
                            for (const auto& selected : meshes)
                            {
                                for (const auto& uv : selected.mesh->uv0)
                                {
                                    append_f32(layout.bytes, uv.u);
                                    append_f32(layout.bytes, uv.v);
                                }
                            }
                        });
}

[[nodiscard]] bool append_joint_set(std::vector<std::byte>& bytes, const Vec4& weights,
                                    const Vec4& bones, const std::size_t bone_count)
{
    const std::array weight{weights.x, weights.y, weights.z, weights.w};
    const std::array bone{bones.x, bones.y, bones.z, bones.w};
    std::size_t active = 0;
    bool valid = true;
    for (std::size_t index = 0; index < 4U; ++index)
    {
        std::uint16_t joint = 0;
        if (weight[index] > kActiveWeight)
        {
            const auto legacy = std::lround(bone[index]);
            if (legacy <= 0 || std::cmp_greater(legacy, bone_count))
            {
                valid = false;
            }
            else
            {
                joint = static_cast<std::uint16_t>(legacy - 1);
            }
            ++active;
        }
        append_u16(bytes, joint);
    }
    return valid && active > 0U;
}

[[nodiscard]] ByteRange append_joints(BinaryLayout& layout, const std::vector<SelectedMesh>& meshes,
                                      const std::size_t bone_count, bool& valid)
{
    return append_range(
        layout.bytes, 34962,
        [&]
        {
            for (const auto& selected : meshes)
            {
                for (std::size_t vertex = 0; vertex < selected.mesh->weights.size(); ++vertex)
                {
                    const auto& weights = selected.mesh->weights[vertex];
                    const auto& bones = selected.mesh->bone_indices[vertex];
                    valid = append_joint_set(layout.bytes, weights, bones, bone_count) && valid;
                }
            }
        });
}

[[nodiscard]] ByteRange append_weights(BinaryLayout& layout,
                                       const std::vector<SelectedMesh>& meshes)
{
    return append_range(layout.bytes, 34962,
                        [&]
                        {
                            for (const auto& selected : meshes)
                            {
                                for (const auto& weights : selected.mesh->weights)
                                {
                                    append_f32(layout.bytes, weights.x);
                                    append_f32(layout.bytes, weights.y);
                                    append_f32(layout.bytes, weights.z);
                                    append_f32(layout.bytes, weights.w);
                                }
                            }
                        });
}

[[nodiscard]] bool append_vertex_data(BinaryLayout& layout, const std::vector<SelectedMesh>& meshes,
                                      const std::size_t bone_count)
{
    layout.minimum.fill(std::numeric_limits<float>::max());
    layout.maximum.fill(std::numeric_limits<float>::lowest());
    bool valid = true;
    layout.attributes[0] = append_positions(layout, meshes);
    layout.attributes[1] = append_normals(layout, meshes, valid);
    layout.attributes[2] = append_uvs(layout, meshes);
    layout.attributes[3] = append_joints(layout, meshes, bone_count, valid);
    layout.attributes[4] = append_weights(layout, meshes);
    return valid;
}

[[nodiscard]] bool append_skeleton_and_indices(BinaryLayout& layout,
                                               const std::vector<SelectedMesh>& meshes,
                                               const SkeletalMeshDescriptor& descriptor)
{
    std::vector<RigidTransform> globals;
    if (!build_global_pose(descriptor, globals))
    {
        return false;
    }
    layout.attributes[5] = append_range(layout.bytes, 0,
                                        [&]
                                        {
                                            for (const auto& transform : globals)
                                            {
                                                append_inverse_matrix(layout.bytes, transform);
                                            }
                                        });
    for (const auto& selected : meshes)
    {
        for (std::size_t section_index = 0; section_index < selected.mesh->sections.size();
             ++section_index)
        {
            const auto& section = selected.mesh->sections[section_index];
            const auto first = section.first_index;
            const auto count = static_cast<std::uint64_t>(section.triangle_count) * 3U;
            if (first > selected.mesh->indices.size() ||
                count > selected.mesh->indices.size() - first)
            {
                return false;
            }
            const auto range =
                append_range(layout.bytes, 34963,
                             [&]
                             {
                                 for (std::uint64_t index = first; index < first + count; ++index)
                                 {
                                     append_u32(layout.bytes, selected.vertex_offset +
                                                                  selected.mesh->indices[index]);
                                 }
                             });
            const auto suffix = selected.mesh->sections.size() == 1U
                                    ? std::string{}
                                    : "_section_" + std::to_string(section_index);
            layout.primitives.push_back(
                {.indices = range,
                 .name = "group_" + std::to_string(selected.selection->group_index) + "_" +
                         selected.mesh->section_name_bytes + suffix,
                 .legacy_material = selected.selection->material_object_name,
                 .two_sided = section.two_sided});
        }
    }
    return !layout.primitives.empty();
}

[[nodiscard]] SkeletalMeshResult<BinaryLayout> build_binary(const SkeletalMeshBinding& binding)
{
    const auto bone_count = binding.package.descriptor.bones.size();
    auto meshes = collect_selected_meshes(binding);
    if (!meshes.has_value() || bone_count == 0U || bone_count > 65535U)
    {
        return SkeletalMeshResult<BinaryLayout>::failure(gltf_error("gltf.selection"));
    }
    BinaryLayout layout;
    if (!append_vertex_data(layout, *meshes, bone_count) ||
        !append_skeleton_and_indices(layout, *meshes, binding.package.descriptor))
    {
        return SkeletalMeshResult<BinaryLayout>::failure(gltf_error("gltf.skinning"));
    }
    return SkeletalMeshResult<BinaryLayout>::success(std::move(layout));
}

} // namespace

SkeletalMeshResult<SkeletalGltfArtifacts> build_default_gltf2(const SkeletalMeshBinding& binding,
                                                              const std::string_view buffer_uri)
{
    if (!is_safe_buffer_uri(buffer_uri) || binding.package.descriptor.root_bone_ids.empty())
    {
        return SkeletalMeshResult<SkeletalGltfArtifacts>::failure(gltf_error("gltf.contract"));
    }
    auto layout = build_binary(binding);
    if (!layout.has_value())
    {
        return SkeletalMeshResult<SkeletalGltfArtifacts>::failure(layout.error());
    }
    auto value = std::move(layout).take_value();
    SkeletalGltfArtifacts result;
    result.json = detail::build_gltf_json(binding, value, buffer_uri);
    result.binary = std::move(value.bytes);
    return SkeletalMeshResult<SkeletalGltfArtifacts>::success(std::move(result));
}

} // namespace tmxy::skeletal_mesh
