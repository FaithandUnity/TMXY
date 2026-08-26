#include "tmxy/static_mesh/sm_reader.hpp"

#include "tmxy/format/binary_reader.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::static_mesh
{
namespace
{

[[nodiscard]] StaticMeshError read_error(const format::ReadError& error, std::string context)
{
    return {.code = StaticMeshErrorCode::read_failure,
            .absolute_offset = error.absolute_offset,
            .context = std::move(context),
            .read_error_code = error.code};
}

[[nodiscard]] StaticMeshError make_error(const StaticMeshErrorCode code, const std::uint64_t offset,
                                         std::string context)
{
    return {.code = code,
            .absolute_offset = offset,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] StaticMeshResult<std::uint32_t>
read_count(format::BinaryReader& reader, const std::uint32_t maximum, const std::string& context)
{
    const auto offset = reader.absolute_position();
    const auto count = reader.read_i32();
    if (!count.has_value())
    {
        return StaticMeshResult<std::uint32_t>::failure(read_error(count.error(), context));
    }
    if (count.value() < 0)
    {
        return StaticMeshResult<std::uint32_t>::failure(
            make_error(StaticMeshErrorCode::negative_count, offset, context));
    }
    const auto value = static_cast<std::uint32_t>(count.value());
    if (value > maximum)
    {
        return StaticMeshResult<std::uint32_t>::failure(
            make_error(StaticMeshErrorCode::count_limit_exceeded, offset, context));
    }
    return StaticMeshResult<std::uint32_t>::success(value);
}

[[nodiscard]] StaticMeshResult<float> read_finite_f32(format::BinaryReader& reader,
                                                      const std::string& context)
{
    const auto offset = reader.absolute_position();
    const auto value = reader.read_f32();
    if (!value.has_value())
    {
        return StaticMeshResult<float>::failure(read_error(value.error(), context));
    }
    if (!std::isfinite(value.value()))
    {
        return StaticMeshResult<float>::failure(
            make_error(StaticMeshErrorCode::non_finite_component, offset, context));
    }
    return StaticMeshResult<float>::success(value.value());
}

[[nodiscard]] StaticMeshResult<Vec3> read_vec3(format::BinaryReader& reader,
                                               const std::string& context)
{
    auto x = read_finite_f32(reader, context + ".x");
    if (!x.has_value())
    {
        return StaticMeshResult<Vec3>::failure(x.error());
    }
    auto y = read_finite_f32(reader, context + ".y");
    if (!y.has_value())
    {
        return StaticMeshResult<Vec3>::failure(y.error());
    }
    auto z = read_finite_f32(reader, context + ".z");
    if (!z.has_value())
    {
        return StaticMeshResult<Vec3>::failure(z.error());
    }
    return StaticMeshResult<Vec3>::success({.x = x.value(), .y = y.value(), .z = z.value()});
}

[[nodiscard]] StaticMeshResult<Vec2> read_vec2(format::BinaryReader& reader,
                                               const std::string& context)
{
    auto u = read_finite_f32(reader, context + ".u");
    if (!u.has_value())
    {
        return StaticMeshResult<Vec2>::failure(u.error());
    }
    auto v = read_finite_f32(reader, context + ".v");
    if (!v.has_value())
    {
        return StaticMeshResult<Vec2>::failure(v.error());
    }
    return StaticMeshResult<Vec2>::success({.u = u.value(), .v = v.value()});
}

[[nodiscard]] StaticMeshResult<std::vector<Vec3>> read_vec3_array(format::BinaryReader& reader,
                                                                  const std::uint32_t maximum,
                                                                  const std::string& context)
{
    auto count = read_count(reader, maximum, context + ".count");
    if (!count.has_value())
    {
        return StaticMeshResult<std::vector<Vec3>>::failure(count.error());
    }
    std::vector<Vec3> values;
    values.reserve(count.value());
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        auto value = read_vec3(reader, context + "[" + std::to_string(index) + "]");
        if (!value.has_value())
        {
            return StaticMeshResult<std::vector<Vec3>>::failure(value.error());
        }
        values.push_back(value.value());
    }
    return StaticMeshResult<std::vector<Vec3>>::success(std::move(values));
}

[[nodiscard]] StaticMeshResult<std::vector<Vec2>> read_vec2_array(format::BinaryReader& reader,
                                                                  const std::uint32_t maximum,
                                                                  const std::string& context)
{
    auto count = read_count(reader, maximum, context + ".count");
    if (!count.has_value())
    {
        return StaticMeshResult<std::vector<Vec2>>::failure(count.error());
    }
    std::vector<Vec2> values;
    values.reserve(count.value());
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        auto value = read_vec2(reader, context + "[" + std::to_string(index) + "]");
        if (!value.has_value())
        {
            return StaticMeshResult<std::vector<Vec2>>::failure(value.error());
        }
        values.push_back(value.value());
    }
    return StaticMeshResult<std::vector<Vec2>>::success(std::move(values));
}

[[nodiscard]] StaticMeshResult<std::vector<std::uint16_t>>
read_index_array(format::BinaryReader& reader, const std::uint32_t maximum,
                 const std::string& context)
{
    auto count = read_count(reader, maximum, context + ".count");
    if (!count.has_value())
    {
        return StaticMeshResult<std::vector<std::uint16_t>>::failure(count.error());
    }
    std::vector<std::uint16_t> values;
    values.reserve(count.value());
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        const auto value = reader.read_u16();
        if (!value.has_value())
        {
            return StaticMeshResult<std::vector<std::uint16_t>>::failure(
                read_error(value.error(), context + "[" + std::to_string(index) + "]"));
        }
        values.push_back(value.value());
    }
    return StaticMeshResult<std::vector<std::uint16_t>>::success(std::move(values));
}

[[nodiscard]] Aabb calculate_bounds(const std::vector<Vec3>& positions) noexcept
{
    if (positions.empty())
    {
        return {};
    }
    Aabb bounds{.minimum = positions.front(), .maximum = positions.front()};
    for (const auto& position : positions)
    {
        bounds.minimum.x = std::min(bounds.minimum.x, position.x);
        bounds.minimum.y = std::min(bounds.minimum.y, position.y);
        bounds.minimum.z = std::min(bounds.minimum.z, position.z);
        bounds.maximum.x = std::max(bounds.maximum.x, position.x);
        bounds.maximum.y = std::max(bounds.maximum.y, position.y);
        bounds.maximum.z = std::max(bounds.maximum.z, position.z);
    }
    return bounds;
}

struct IndexValidationContext final
{
    std::size_t vertex_count{0};
    std::uint64_t offset{0};
    std::string_view context;
};

[[nodiscard]] std::optional<StaticMeshError>
validate_index_buffer(const std::vector<std::uint16_t>& indices,
                      const IndexValidationContext validation)
{
    if ((indices.size() % 3U) != 0U)
    {
        return make_error(StaticMeshErrorCode::index_count_not_triangles, validation.offset,
                          std::string(validation.context));
    }
    for (std::size_t index = 0; index < indices.size(); ++index)
    {
        if (indices[index] >= validation.vertex_count)
        {
            return make_error(StaticMeshErrorCode::index_out_of_range, validation.offset,
                              std::string(validation.context) + "[" + std::to_string(index) + "]");
        }
    }
    return std::nullopt;
}

[[nodiscard]] StaticMeshResult<std::vector<MeshSection>>
read_sections(format::BinaryReader& reader, const StaticMeshLimits limits,
              const std::size_t vertex_count)
{
    auto count = read_count(reader, limits.maximum_section_count, "sm.sections.count");
    if (!count.has_value())
    {
        return StaticMeshResult<std::vector<MeshSection>>::failure(count.error());
    }
    std::vector<MeshSection> sections;
    sections.reserve(count.value());
    std::uint64_t first_index = 0;
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        const auto offset = reader.absolute_position();
        const auto context = "sm.sections[" + std::to_string(index) + "]";
        const auto triangles = reader.read_i32();
        if (!triangles.has_value())
        {
            return StaticMeshResult<std::vector<MeshSection>>::failure(
                read_error(triangles.error(), context + ".triangle_count"));
        }
        const auto minimum = reader.read_i32();
        if (!minimum.has_value())
        {
            return StaticMeshResult<std::vector<MeshSection>>::failure(
                read_error(minimum.error(), context + ".minimum_vertex_index"));
        }
        const auto maximum = reader.read_i32();
        if (!maximum.has_value())
        {
            return StaticMeshResult<std::vector<MeshSection>>::failure(
                read_error(maximum.error(), context + ".maximum_vertex_index"));
        }
        const auto two_sided = reader.read_u8();
        if (!two_sided.has_value())
        {
            return StaticMeshResult<std::vector<MeshSection>>::failure(
                read_error(two_sided.error(), context + ".two_sided"));
        }
        if (triangles.value() < 0 || minimum.value() < 0 || maximum.value() < minimum.value() ||
            std::cmp_greater_equal(maximum.value(), vertex_count))
        {
            return StaticMeshResult<std::vector<MeshSection>>::failure(
                make_error(StaticMeshErrorCode::invalid_section, offset, context));
        }
        if (two_sided.value() > 1U)
        {
            return StaticMeshResult<std::vector<MeshSection>>::failure(
                make_error(StaticMeshErrorCode::invalid_boolean, reader.absolute_position() - 1U,
                           "sm.sections.two_sided"));
        }
        sections.push_back({.triangle_count = static_cast<std::uint32_t>(triangles.value()),
                            .minimum_vertex_index = static_cast<std::uint32_t>(minimum.value()),
                            .maximum_vertex_index = static_cast<std::uint32_t>(maximum.value()),
                            .two_sided = two_sided.value() != 0U,
                            .first_index = first_index});
        first_index += (static_cast<std::uint64_t>(triangles.value()) * 3U);
    }
    return StaticMeshResult<std::vector<MeshSection>>::success(std::move(sections));
}

[[nodiscard]] std::optional<StaticMeshError>
validate_sections(const std::vector<MeshSection>& sections,
                  const std::vector<std::uint16_t>& indices, const std::uint64_t offset)
{
    std::uint64_t expected_indices = 0;
    for (const auto& section : sections)
    {
        expected_indices += (static_cast<std::uint64_t>(section.triangle_count) * 3U);
    }
    if (expected_indices != indices.size())
    {
        return make_error(StaticMeshErrorCode::section_index_count_mismatch, offset,
                          "sm.sections.index_coverage");
    }
    for (std::size_t section_index = 0; section_index < sections.size(); ++section_index)
    {
        const auto& section = sections[section_index];
        const auto end =
            section.first_index + (static_cast<std::uint64_t>(section.triangle_count) * 3U);
        for (std::uint64_t index = section.first_index; index < end; ++index)
        {
            const auto value = indices[static_cast<std::size_t>(index)];
            if (value < section.minimum_vertex_index || value > section.maximum_vertex_index)
            {
                return make_error(StaticMeshErrorCode::invalid_section, offset,
                                  "sm.sections[" + std::to_string(section_index) + "].indices");
            }
        }
    }
    return std::nullopt;
}

[[nodiscard]] StaticMeshResult<std::vector<OctreeNode>>
read_octree_nodes(format::BinaryReader& reader, const StaticMeshLimits limits)
{
    auto count = read_count(reader, limits.maximum_octree_node_count, "sm.octree.count");
    if (!count.has_value())
    {
        return StaticMeshResult<std::vector<OctreeNode>>::failure(count.error());
    }
    std::vector<OctreeNode> nodes;
    nodes.reserve(count.value());
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        auto maximum = read_vec3(reader, "sm.octree.maximum");
        auto minimum = read_vec3(reader, "sm.octree.minimum");
        const auto face_count = reader.read_i32();
        const auto first_face = reader.read_i32();
        if (!maximum.has_value())
        {
            return StaticMeshResult<std::vector<OctreeNode>>::failure(maximum.error());
        }
        if (!minimum.has_value())
        {
            return StaticMeshResult<std::vector<OctreeNode>>::failure(minimum.error());
        }
        if (!face_count.has_value() || !first_face.has_value())
        {
            const auto& error = !face_count.has_value() ? face_count.error() : first_face.error();
            return StaticMeshResult<std::vector<OctreeNode>>::failure(
                read_error(error, "sm.octree.face_range"));
        }
        if (face_count.value() < 0 || first_face.value() < 0 ||
            minimum.value().x > maximum.value().x || minimum.value().y > maximum.value().y ||
            minimum.value().z > maximum.value().z)
        {
            return StaticMeshResult<std::vector<OctreeNode>>::failure(
                make_error(StaticMeshErrorCode::invalid_octree_face_range,
                           reader.absolute_position() - 8U, "sm.octree.face_range"));
        }
        OctreeNode node{.bounds = {.minimum = minimum.value(), .maximum = maximum.value()},
                        .face_index_count = static_cast<std::uint32_t>(face_count.value()),
                        .first_face_index = static_cast<std::uint32_t>(first_face.value())};
        for (auto& child_id : node.child_ids)
        {
            const auto child = reader.read_i32();
            if (!child.has_value())
            {
                return StaticMeshResult<std::vector<OctreeNode>>::failure(
                    read_error(child.error(), "sm.octree.child"));
            }
            child_id = child.value();
        }
        nodes.push_back(node);
    }
    return StaticMeshResult<std::vector<OctreeNode>>::success(std::move(nodes));
}

[[nodiscard]] std::optional<StaticMeshError> validate_octree(const StaticMesh& mesh,
                                                             const std::uint64_t offset)
{
    const auto active_vertex_count =
        mesh.collision_octree ? mesh.collision_positions.size() : mesh.positions.size();
    for (const auto index : mesh.octree_indices)
    {
        if (index >= active_vertex_count)
        {
            return make_error(StaticMeshErrorCode::index_out_of_range, offset, "sm.octree.indices");
        }
    }
    for (std::size_t index = 0; index < mesh.octree_nodes.size(); ++index)
    {
        const auto& node = mesh.octree_nodes[index];
        const auto is_leaf = std::ranges::all_of(node.child_ids, [](const std::int32_t child)
                                                 { return child == -1; });
        const auto end = static_cast<std::uint64_t>(node.first_face_index) + node.face_index_count;
        if (is_leaf && end > mesh.octree_indices.size())
        {
            return make_error(StaticMeshErrorCode::invalid_octree_face_range, offset,
                              "sm.octree.nodes[" + std::to_string(index) + "].face_range");
        }
        for (const auto child : node.child_ids)
        {
            if (child < -1 ||
                (child >= 0 && static_cast<std::size_t>(child) >= mesh.octree_nodes.size()))
            {
                return make_error(StaticMeshErrorCode::invalid_octree_node_reference, offset,
                                  "sm.octree.nodes[" + std::to_string(index) + "].child");
            }
        }
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<StaticMeshError> validate_attributes(const StaticMesh& mesh,
                                                                 const std::uint64_t offset)
{
    const auto vertex_count = mesh.positions.size();
    if (mesh.normals.size() != vertex_count || mesh.uv0.size() != vertex_count ||
        mesh.tangents.size() != vertex_count || mesh.binormals.size() != vertex_count ||
        (mesh.uv1_field_present && mesh.uv1.size() != vertex_count))
    {
        return make_error(StaticMeshErrorCode::attribute_count_mismatch, offset,
                          "sm.render_attributes");
    }
    if (mesh.shadow_normals.size() != mesh.shadow_positions.size())
    {
        return make_error(StaticMeshErrorCode::attribute_count_mismatch, offset,
                          "sm.shadow_attributes");
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<StaticMeshError>
read_render_data(format::BinaryReader& reader, const StaticMeshLimits limits, StaticMesh& mesh)
{
    auto positions = read_vec3_array(reader, limits.maximum_vertex_count, "sm.positions");
    if (!positions.has_value())
    {
        return positions.error();
    }
    mesh.positions = std::move(positions).take_value();

    auto normals = read_vec3_array(reader, limits.maximum_vertex_count, "sm.normals");
    if (!normals.has_value())
    {
        return normals.error();
    }
    mesh.normals = std::move(normals).take_value();

    auto uv0 = read_vec2_array(reader, limits.maximum_vertex_count, "sm.uv0");
    if (!uv0.has_value())
    {
        return uv0.error();
    }
    mesh.uv0 = std::move(uv0).take_value();

    auto tangents = read_vec3_array(reader, limits.maximum_vertex_count, "sm.tangents");
    if (!tangents.has_value())
    {
        return tangents.error();
    }
    mesh.tangents = std::move(tangents).take_value();

    auto binormals = read_vec3_array(reader, limits.maximum_vertex_count, "sm.binormals");
    if (!binormals.has_value())
    {
        return binormals.error();
    }
    mesh.binormals = std::move(binormals).take_value();

    auto indices = read_index_array(reader, limits.maximum_index_count, "sm.indices");
    if (!indices.has_value())
    {
        return indices.error();
    }
    mesh.indices = std::move(indices).take_value();
    return std::nullopt;
}

[[nodiscard]] std::optional<StaticMeshError>
read_auxiliary_data(format::BinaryReader& reader, const StaticMeshLimits limits, StaticMesh& mesh)
{
    auto sections = read_sections(reader, limits, mesh.positions.size());
    if (!sections.has_value())
    {
        return sections.error();
    }
    mesh.sections = std::move(sections).take_value();

    auto shadow_positions =
        read_vec3_array(reader, limits.maximum_vertex_count, "sm.shadow.positions");
    if (!shadow_positions.has_value())
    {
        return shadow_positions.error();
    }
    mesh.shadow_positions = std::move(shadow_positions).take_value();

    auto shadow_normals = read_vec3_array(reader, limits.maximum_vertex_count, "sm.shadow.normals");
    if (!shadow_normals.has_value())
    {
        return shadow_normals.error();
    }
    mesh.shadow_normals = std::move(shadow_normals).take_value();

    auto shadow_indices = read_index_array(reader, limits.maximum_index_count, "sm.shadow.indices");
    if (!shadow_indices.has_value())
    {
        return shadow_indices.error();
    }
    mesh.shadow_indices = std::move(shadow_indices).take_value();

    auto collision_positions =
        read_vec3_array(reader, limits.maximum_vertex_count, "sm.collision.positions");
    if (!collision_positions.has_value())
    {
        return collision_positions.error();
    }
    mesh.collision_positions = std::move(collision_positions).take_value();

    auto collision_indices =
        read_index_array(reader, limits.maximum_index_count, "sm.collision.indices");
    if (!collision_indices.has_value())
    {
        return collision_indices.error();
    }
    mesh.collision_indices = std::move(collision_indices).take_value();
    return std::nullopt;
}

[[nodiscard]] std::optional<StaticMeshError>
read_octree_and_tail(format::BinaryReader& reader, const StaticMeshLimits limits, StaticMesh& mesh,
                     std::uint64_t& collision_flag_offset)
{
    collision_flag_offset = reader.absolute_position();
    const auto collision_flag = reader.read_i32();
    if (!collision_flag.has_value())
    {
        return read_error(collision_flag.error(), "sm.collision_octree_flag");
    }
    if (collision_flag.value() != 0 && collision_flag.value() != 1)
    {
        return make_error(StaticMeshErrorCode::invalid_collision_flag, collision_flag_offset,
                          "sm.collision_octree_flag");
    }
    mesh.collision_octree = collision_flag.value() == 1;

    auto octree_nodes = read_octree_nodes(reader, limits);
    if (!octree_nodes.has_value())
    {
        return octree_nodes.error();
    }
    mesh.octree_nodes = std::move(octree_nodes).take_value();
    if (!mesh.octree_nodes.empty())
    {
        auto octree_indices =
            read_index_array(reader, limits.maximum_index_count, "sm.octree.indices");
        if (!octree_indices.has_value())
        {
            return octree_indices.error();
        }
        mesh.octree_indices = std::move(octree_indices).take_value();
    }
    if (reader.remaining() != 0U)
    {
        mesh.emitter_points_field_present = true;
        auto emitter_points =
            read_vec3_array(reader, limits.maximum_emitter_point_count, "sm.emitter_points");
        if (!emitter_points.has_value())
        {
            return emitter_points.error();
        }
        mesh.emitter_points = std::move(emitter_points).take_value();
    }
    if (reader.remaining() != 0U)
    {
        mesh.uv1_field_present = true;
        auto uv1 = read_vec2_array(reader, limits.maximum_vertex_count, "sm.uv1");
        if (!uv1.has_value())
        {
            return uv1.error();
        }
        mesh.uv1 = std::move(uv1).take_value();
    }
    if (reader.remaining() != 0U)
    {
        return make_error(StaticMeshErrorCode::trailing_bytes, reader.absolute_position(),
                          "sm.trailing");
    }
    return std::nullopt;
}

struct MeshValidationContext final
{
    std::uint64_t base_offset{0};
    std::uint64_t collision_flag_offset{0};
};

[[nodiscard]] std::optional<StaticMeshError> validate_mesh(const StaticMesh& mesh,
                                                           const MeshValidationContext validation)
{
    if (const auto error = validate_attributes(mesh, validation.base_offset))
    {
        return error;
    }
    if (const auto error =
            validate_index_buffer(mesh.indices, {.vertex_count = mesh.positions.size(),
                                                 .offset = validation.base_offset,
                                                 .context = "sm.indices"}))
    {
        return error;
    }
    if (const auto error = validate_sections(mesh.sections, mesh.indices, validation.base_offset))
    {
        return error;
    }
    if (const auto error = validate_index_buffer(mesh.shadow_indices,
                                                 {.vertex_count = mesh.shadow_positions.size(),
                                                  .offset = validation.base_offset,
                                                  .context = "sm.shadow.indices"}))
    {
        return error;
    }
    if (const auto error = validate_index_buffer(mesh.collision_indices,
                                                 {.vertex_count = mesh.collision_positions.size(),
                                                  .offset = validation.base_offset,
                                                  .context = "sm.collision.indices"}))
    {
        return error;
    }
    if (mesh.collision_octree && mesh.collision_positions.empty())
    {
        return make_error(StaticMeshErrorCode::invalid_collision_flag,
                          validation.collision_flag_offset, "sm.collision_octree_without_vertices");
    }
    return validate_octree(mesh, validation.base_offset);
}

} // namespace

SmReader::SmReader(const StaticMeshLimits limits) : limits_(limits) {}

StaticMeshResult<StaticMesh> SmReader::parse(const std::span<const std::byte> bytes,
                                             const std::uint64_t base_offset) const
{
    format::BinaryReader reader(bytes, format::ByteOrder::little_endian, base_offset, "sm");
    StaticMesh mesh;
    if (const auto error = read_render_data(reader, limits_, mesh))
    {
        return StaticMeshResult<StaticMesh>::failure(*error);
    }
    if (const auto error = read_auxiliary_data(reader, limits_, mesh))
    {
        return StaticMeshResult<StaticMesh>::failure(*error);
    }
    std::uint64_t collision_flag_offset = 0;
    if (const auto error = read_octree_and_tail(reader, limits_, mesh, collision_flag_offset))
    {
        return StaticMeshResult<StaticMesh>::failure(*error);
    }
    if (const auto error = validate_mesh(
            mesh, {.base_offset = base_offset, .collision_flag_offset = collision_flag_offset}))
    {
        return StaticMeshResult<StaticMesh>::failure(*error);
    }

    mesh.render_bounds = calculate_bounds(mesh.positions);
    if (!mesh.collision_positions.empty())
    {
        mesh.collision_bounds = calculate_bounds(mesh.collision_positions);
    }
    return StaticMeshResult<StaticMesh>::success(std::move(mesh));
}

const Aabb& effective_legacy_bounds(const StaticMesh& mesh) noexcept
{
    return mesh.collision_bounds.has_value() ? *mesh.collision_bounds : mesh.render_bounds;
}

} // namespace tmxy::static_mesh
