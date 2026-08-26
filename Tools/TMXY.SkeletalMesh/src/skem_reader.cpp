#include "tmxy/skeletal_mesh/skem_reader.hpp"

#include "tmxy/format/binary_reader.hpp"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::skeletal_mesh
{
namespace
{

constexpr std::uint16_t kMaximumSectionNameBytes = 4096;
constexpr float kWeightTolerance = 0.01F;
constexpr float kIntegerTolerance = 0.00001F;
constexpr float kMaximumEncodedBoneIndex = 65'535.0F;

[[nodiscard]] bool is_legacy_unweighted_sentinel(const Vec4& weights,
                                                 const Vec4& bone_indices) noexcept
{
    return weights.x == -1.0F && weights.y == -1.0F && weights.z == -1.0F && weights.w == -1.0F &&
           bone_indices.x == 0.0F && bone_indices.y == 0.0F && bone_indices.z == 0.0F &&
           bone_indices.w == 0.0F;
}

[[nodiscard]] SkeletalMeshError read_error(const format::ReadError& error, std::string context)
{
    return {.code = SkeletalMeshErrorCode::read_failure,
            .absolute_offset = error.absolute_offset,
            .context = std::move(context),
            .read_error_code = error.code};
}

[[nodiscard]] SkeletalMeshError make_error(const SkeletalMeshErrorCode code,
                                           const std::uint64_t offset, std::string context)
{
    return {.code = code,
            .absolute_offset = offset,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] SkeletalMeshResult<std::uint32_t>
read_count(format::BinaryReader& reader, const std::uint32_t maximum, const std::string& context)
{
    const auto offset = reader.absolute_position();
    const auto count = reader.read_i32();
    if (!count.has_value())
    {
        return SkeletalMeshResult<std::uint32_t>::failure(read_error(count.error(), context));
    }
    if (count.value() < 0)
    {
        return SkeletalMeshResult<std::uint32_t>::failure(
            make_error(SkeletalMeshErrorCode::negative_count, offset, context));
    }
    const auto value = static_cast<std::uint32_t>(count.value());
    if (value > maximum)
    {
        return SkeletalMeshResult<std::uint32_t>::failure(
            make_error(SkeletalMeshErrorCode::count_limit_exceeded, offset, context));
    }
    return SkeletalMeshResult<std::uint32_t>::success(value);
}

[[nodiscard]] SkeletalMeshResult<float> read_finite_f32(format::BinaryReader& reader,
                                                        const std::string& context)
{
    const auto offset = reader.absolute_position();
    const auto value = reader.read_f32();
    if (!value.has_value())
    {
        return SkeletalMeshResult<float>::failure(read_error(value.error(), context));
    }
    if (!std::isfinite(value.value()))
    {
        return SkeletalMeshResult<float>::failure(
            make_error(SkeletalMeshErrorCode::non_finite_component, offset, context));
    }
    return SkeletalMeshResult<float>::success(value.value());
}

[[nodiscard]] SkeletalMeshResult<Vec2> read_vec2(format::BinaryReader& reader,
                                                 const std::string& context)
{
    auto u = read_finite_f32(reader, context + ".u");
    if (!u.has_value())
    {
        return SkeletalMeshResult<Vec2>::failure(u.error());
    }
    auto v = read_finite_f32(reader, context + ".v");
    if (!v.has_value())
    {
        return SkeletalMeshResult<Vec2>::failure(v.error());
    }
    return SkeletalMeshResult<Vec2>::success({.u = u.value(), .v = v.value()});
}

[[nodiscard]] SkeletalMeshResult<Vec3> read_vec3(format::BinaryReader& reader,
                                                 const std::string& context)
{
    auto x = read_finite_f32(reader, context + ".x");
    if (!x.has_value())
    {
        return SkeletalMeshResult<Vec3>::failure(x.error());
    }
    auto y = read_finite_f32(reader, context + ".y");
    if (!y.has_value())
    {
        return SkeletalMeshResult<Vec3>::failure(y.error());
    }
    auto z = read_finite_f32(reader, context + ".z");
    if (!z.has_value())
    {
        return SkeletalMeshResult<Vec3>::failure(z.error());
    }
    return SkeletalMeshResult<Vec3>::success({.x = x.value(), .y = y.value(), .z = z.value()});
}

[[nodiscard]] SkeletalMeshResult<Vec4> read_vec4(format::BinaryReader& reader,
                                                 const std::string& context)
{
    auto x = read_finite_f32(reader, context + ".x");
    if (!x.has_value())
    {
        return SkeletalMeshResult<Vec4>::failure(x.error());
    }
    auto y = read_finite_f32(reader, context + ".y");
    if (!y.has_value())
    {
        return SkeletalMeshResult<Vec4>::failure(y.error());
    }
    auto z = read_finite_f32(reader, context + ".z");
    if (!z.has_value())
    {
        return SkeletalMeshResult<Vec4>::failure(z.error());
    }
    auto w = read_finite_f32(reader, context + ".w");
    if (!w.has_value())
    {
        return SkeletalMeshResult<Vec4>::failure(w.error());
    }
    return SkeletalMeshResult<Vec4>::success(
        {.x = x.value(), .y = y.value(), .z = z.value(), .w = w.value()});
}

template <typename Value, typename ReadValue>
[[nodiscard]] SkeletalMeshResult<std::vector<Value>>
read_array(format::BinaryReader& reader, const std::uint32_t maximum, const std::string& context,
           ReadValue read_value)
{
    auto count = read_count(reader, maximum, context + ".count");
    if (!count.has_value())
    {
        return SkeletalMeshResult<std::vector<Value>>::failure(count.error());
    }
    std::vector<Value> values;
    values.reserve(count.value());
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        auto value = read_value(reader, context + "[" + std::to_string(index) + "]");
        if (!value.has_value())
        {
            return SkeletalMeshResult<std::vector<Value>>::failure(value.error());
        }
        values.push_back(value.value());
    }
    return SkeletalMeshResult<std::vector<Value>>::success(std::move(values));
}

[[nodiscard]] SkeletalMeshResult<std::vector<std::uint16_t>>
read_u16_array(format::BinaryReader& reader, const std::uint32_t maximum,
               const std::string& context)
{
    auto count = read_count(reader, maximum, context + ".count");
    if (!count.has_value())
    {
        return SkeletalMeshResult<std::vector<std::uint16_t>>::failure(count.error());
    }
    std::vector<std::uint16_t> values;
    values.reserve(count.value());
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        const auto value = reader.read_u16();
        if (!value.has_value())
        {
            return SkeletalMeshResult<std::vector<std::uint16_t>>::failure(
                read_error(value.error(), context + "[" + std::to_string(index) + "]"));
        }
        values.push_back(value.value());
    }
    return SkeletalMeshResult<std::vector<std::uint16_t>>::success(std::move(values));
}

[[nodiscard]] SkeletalMeshResult<std::string> read_string(format::BinaryReader& reader,
                                                          const std::string& context)
{
    const auto offset = reader.absolute_position();
    const auto length = reader.read_u16();
    if (!length.has_value())
    {
        return SkeletalMeshResult<std::string>::failure(read_error(length.error(), context));
    }
    if (length.value() > kMaximumSectionNameBytes)
    {
        return SkeletalMeshResult<std::string>::failure(
            make_error(SkeletalMeshErrorCode::count_limit_exceeded, offset, context));
    }
    const auto bytes = reader.read_bytes(length.value());
    if (!bytes.has_value())
    {
        return SkeletalMeshResult<std::string>::failure(read_error(bytes.error(), context));
    }
    return SkeletalMeshResult<std::string>::success(
        std::string(reinterpret_cast<const char*>(bytes.value().data()), bytes.value().size()));
}

struct SectionReadContext final
{
    std::uint32_t maximum{0};
    std::size_t vertex_count{0};
};

[[nodiscard]] SkeletalMeshResult<std::vector<MeshSection>>
read_sections(format::BinaryReader& reader, const SectionReadContext validation)
{
    auto count = read_count(reader, validation.maximum, "skem.sections.count");
    if (!count.has_value())
    {
        return SkeletalMeshResult<std::vector<MeshSection>>::failure(count.error());
    }
    std::vector<MeshSection> sections;
    sections.reserve(count.value());
    std::uint64_t first_index = 0;
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        const auto offset = reader.absolute_position();
        const auto triangles = reader.read_i32();
        const auto minimum = reader.read_i32();
        const auto maximum_index = reader.read_i32();
        const auto two_sided = reader.read_u8();
        if (!triangles.has_value() || !minimum.has_value() || !maximum_index.has_value() ||
            !two_sided.has_value())
        {
            const auto context = "skem.sections[" + std::to_string(index) + "]";
            return SkeletalMeshResult<std::vector<MeshSection>>::failure(
                make_error(SkeletalMeshErrorCode::read_failure, offset, context));
        }
        if (triangles.value() < 0 || minimum.value() < 0 ||
            maximum_index.value() < minimum.value() ||
            std::cmp_greater_equal(maximum_index.value(), validation.vertex_count))
        {
            return SkeletalMeshResult<std::vector<MeshSection>>::failure(
                make_error(SkeletalMeshErrorCode::invalid_section, offset, "skem.sections"));
        }
        if (two_sided.value() > 1U)
        {
            return SkeletalMeshResult<std::vector<MeshSection>>::failure(
                make_error(SkeletalMeshErrorCode::invalid_boolean, reader.absolute_position() - 1U,
                           "skem.sections.two_sided"));
        }
        sections.push_back(
            {.triangle_count = static_cast<std::uint32_t>(triangles.value()),
             .minimum_vertex_index = static_cast<std::uint32_t>(minimum.value()),
             .maximum_vertex_index = static_cast<std::uint32_t>(maximum_index.value()),
             .two_sided = two_sided.value() != 0U,
             .first_index = first_index});
        first_index += static_cast<std::uint64_t>(triangles.value()) * 3U;
    }
    return SkeletalMeshResult<std::vector<MeshSection>>::success(std::move(sections));
}

[[nodiscard]] SkeletalMeshResult<std::vector<AdjacentFaces>>
read_adjacency(format::BinaryReader& reader, const std::uint32_t maximum)
{
    auto count = read_count(reader, maximum, "skem.adjacency.count");
    if (!count.has_value())
    {
        return SkeletalMeshResult<std::vector<AdjacentFaces>>::failure(count.error());
    }
    std::vector<AdjacentFaces> values;
    values.reserve(count.value());
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        const auto edge0 = reader.read_i32();
        const auto edge1 = reader.read_i32();
        const auto edge2 = reader.read_i32();
        if (!edge0.has_value() || !edge1.has_value() || !edge2.has_value())
        {
            return SkeletalMeshResult<std::vector<AdjacentFaces>>::failure(make_error(
                SkeletalMeshErrorCode::read_failure, reader.absolute_position(), "skem.adjacency"));
        }
        values.push_back({.edge0 = edge0.value(), .edge1 = edge1.value(), .edge2 = edge2.value()});
    }
    return SkeletalMeshResult<std::vector<AdjacentFaces>>::success(std::move(values));
}

[[nodiscard]] std::optional<SkeletalMeshError> validate_attributes(const SkeletalSubmesh& mesh,
                                                                   const std::uint64_t offset)
{
    const auto count = mesh.positions.size();
    if (mesh.normals.size() != count || mesh.uv0.size() != count || mesh.tangents.size() != count ||
        mesh.binormals.size() != count || mesh.weights.size() != count ||
        mesh.bone_indices.size() != count)
    {
        return make_error(SkeletalMeshErrorCode::attribute_count_mismatch, offset,
                          "skem.vertex_attributes");
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> validate_weights(const SkeletalSubmesh& mesh,
                                                                const std::uint64_t offset)
{
    for (std::size_t vertex = 0; vertex < mesh.weights.size(); ++vertex)
    {
        const auto& weight = mesh.weights[vertex];
        if (is_legacy_unweighted_sentinel(weight, mesh.bone_indices[vertex]))
        {
            continue;
        }
        const auto values = {weight.x, weight.y, weight.z, weight.w};
        float sum = 0.0F;
        for (const auto value : values)
        {
            if (value < -kWeightTolerance || value > 1.0F + kWeightTolerance)
            {
                return make_error(SkeletalMeshErrorCode::invalid_weight, offset,
                                  "skem.weights[" + std::to_string(vertex) + "]");
            }
            sum += value;
        }
        if (std::abs(sum - 1.0F) > kWeightTolerance)
        {
            return make_error(SkeletalMeshErrorCode::invalid_weight, offset,
                              "skem.weights[" + std::to_string(vertex) + "].sum");
        }
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError>
validate_encoded_bone_indices(const SkeletalSubmesh& mesh, const std::uint64_t offset)
{
    for (std::size_t vertex = 0; vertex < mesh.bone_indices.size(); ++vertex)
    {
        const auto& bone = mesh.bone_indices[vertex];
        for (const auto value : {bone.x, bone.y, bone.z, bone.w})
        {
            if (value < 0.0F || value > kMaximumEncodedBoneIndex ||
                std::abs(value - std::round(value)) > kIntegerTolerance)
            {
                return make_error(SkeletalMeshErrorCode::invalid_bone_index, offset,
                                  "skem.bone_indices[" + std::to_string(vertex) + "]");
            }
        }
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> validate_indices(const SkeletalSubmesh& mesh,
                                                                const std::uint64_t offset)
{
    if ((mesh.indices.size() % 3U) != 0U)
    {
        return make_error(SkeletalMeshErrorCode::index_count_not_triangles, offset, "skem.indices");
    }
    for (const auto index : mesh.indices)
    {
        if (index >= mesh.positions.size())
        {
            return make_error(SkeletalMeshErrorCode::index_out_of_range, offset, "skem.indices");
        }
    }
    for (const auto index : mesh.shadow_indices)
    {
        if (index >= mesh.positions.size())
        {
            return make_error(SkeletalMeshErrorCode::invalid_shadow_index, offset,
                              "skem.shadow_indices");
        }
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> validate_sections(const SkeletalSubmesh& mesh,
                                                                 const std::uint64_t offset)
{
    std::uint64_t covered = 0;
    for (const auto& section : mesh.sections)
    {
        covered += static_cast<std::uint64_t>(section.triangle_count) * 3U;
        const auto end =
            section.first_index + (static_cast<std::uint64_t>(section.triangle_count) * 3U);
        for (std::uint64_t index = section.first_index; index < end; ++index)
        {
            const auto vertex = mesh.indices[static_cast<std::size_t>(index)];
            if (vertex < section.minimum_vertex_index || vertex > section.maximum_vertex_index)
            {
                return make_error(SkeletalMeshErrorCode::invalid_section, offset,
                                  "skem.sections.indices");
            }
        }
    }
    if (covered != mesh.indices.size())
    {
        return make_error(SkeletalMeshErrorCode::section_index_count_mismatch, offset,
                          "skem.sections.index_coverage");
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> validate_adjacency(const SkeletalSubmesh& mesh,
                                                                  const std::uint64_t offset)
{
    const auto triangle_count = mesh.indices.size() / 3U;
    if (mesh.adjacent_faces.size() != triangle_count)
    {
        return make_error(SkeletalMeshErrorCode::invalid_adjacency, offset, "skem.adjacency.count");
    }
    for (const auto& adjacent : mesh.adjacent_faces)
    {
        for (const auto face : {adjacent.edge0, adjacent.edge1, adjacent.edge2})
        {
            if (face < -1 || (face >= 0 && std::cmp_greater_equal(face, triangle_count)))
            {
                return make_error(SkeletalMeshErrorCode::invalid_adjacency, offset,
                                  "skem.adjacency.face");
            }
        }
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> validate_submesh(const SkeletalSubmesh& mesh,
                                                                const std::uint64_t offset)
{
    const std::array validations{validate_attributes(mesh, offset),
                                 validate_weights(mesh, offset),
                                 validate_encoded_bone_indices(mesh, offset),
                                 validate_indices(mesh, offset),
                                 validate_sections(mesh, offset),
                                 validate_adjacency(mesh, offset)};
    for (const auto& validation : validations)
    {
        if (validation.has_value())
        {
            return validation;
        }
    }
    return std::nullopt;
}

struct VertexArrays final
{
    std::vector<Vec3> positions;
    std::vector<Vec3> normals;
    std::vector<Vec2> uv0;
    std::vector<Vec3> tangents;
    std::vector<Vec3> binormals;
    std::vector<Vec4> weights;
    std::vector<Vec4> bone_indices;
};

[[nodiscard]] SkeletalMeshResult<VertexArrays> read_vertex_arrays(format::BinaryReader& reader,
                                                                  const SkeletalMeshLimits limits)
{
    auto positions = read_array<Vec3>(reader, limits.maximum_vertex_count_per_submesh,
                                      "skem.positions", read_vec3);
    if (!positions.has_value())
    {
        return SkeletalMeshResult<VertexArrays>::failure(positions.error());
    }
    auto normals = read_array<Vec3>(reader, limits.maximum_vertex_count_per_submesh, "skem.normals",
                                    read_vec3);
    if (!normals.has_value())
    {
        return SkeletalMeshResult<VertexArrays>::failure(normals.error());
    }
    auto uv0 =
        read_array<Vec2>(reader, limits.maximum_vertex_count_per_submesh, "skem.uv0", read_vec2);
    if (!uv0.has_value())
    {
        return SkeletalMeshResult<VertexArrays>::failure(uv0.error());
    }
    auto tangents = read_array<Vec3>(reader, limits.maximum_vertex_count_per_submesh,
                                     "skem.tangents", read_vec3);
    if (!tangents.has_value())
    {
        return SkeletalMeshResult<VertexArrays>::failure(tangents.error());
    }
    auto binormals = read_array<Vec3>(reader, limits.maximum_vertex_count_per_submesh,
                                      "skem.binormals", read_vec3);
    if (!binormals.has_value())
    {
        return SkeletalMeshResult<VertexArrays>::failure(binormals.error());
    }
    auto weights = read_array<Vec4>(reader, limits.maximum_vertex_count_per_submesh, "skem.weights",
                                    read_vec4);
    if (!weights.has_value())
    {
        return SkeletalMeshResult<VertexArrays>::failure(weights.error());
    }
    auto bones = read_array<Vec4>(reader, limits.maximum_vertex_count_per_submesh,
                                  "skem.bone_indices", read_vec4);
    if (!bones.has_value())
    {
        return SkeletalMeshResult<VertexArrays>::failure(bones.error());
    }
    return SkeletalMeshResult<VertexArrays>::success(
        {.positions = std::move(positions).take_value(),
         .normals = std::move(normals).take_value(),
         .uv0 = std::move(uv0).take_value(),
         .tangents = std::move(tangents).take_value(),
         .binormals = std::move(binormals).take_value(),
         .weights = std::move(weights).take_value(),
         .bone_indices = std::move(bones).take_value()});
}

struct TopologyArrays final
{
    std::vector<std::uint16_t> indices;
    std::vector<MeshSection> sections;
    std::vector<std::uint16_t> shadow_indices;
    std::vector<AdjacentFaces> adjacent_faces;
};

[[nodiscard]] SkeletalMeshResult<TopologyArrays>
read_topology_arrays(format::BinaryReader& reader, const SkeletalMeshLimits limits,
                     const std::size_t vertex_count)
{
    auto indices = read_u16_array(reader, limits.maximum_index_count_per_submesh, "skem.indices");
    if (!indices.has_value())
    {
        return SkeletalMeshResult<TopologyArrays>::failure(indices.error());
    }
    auto sections = read_sections(
        reader, {.maximum = limits.maximum_submesh_count, .vertex_count = vertex_count});
    if (!sections.has_value())
    {
        return SkeletalMeshResult<TopologyArrays>::failure(sections.error());
    }
    auto shadow =
        read_u16_array(reader, limits.maximum_index_count_per_submesh, "skem.shadow_indices");
    if (!shadow.has_value())
    {
        return SkeletalMeshResult<TopologyArrays>::failure(shadow.error());
    }
    auto adjacency = read_adjacency(reader, limits.maximum_index_count_per_submesh / 3U);
    if (!adjacency.has_value())
    {
        return SkeletalMeshResult<TopologyArrays>::failure(adjacency.error());
    }
    return SkeletalMeshResult<TopologyArrays>::success(
        {.indices = std::move(indices).take_value(),
         .sections = std::move(sections).take_value(),
         .shadow_indices = std::move(shadow).take_value(),
         .adjacent_faces = std::move(adjacency).take_value()});
}

struct SubmeshReader final
{
    format::BinaryReader& reader;
    SkeletalMeshLimits limits;

    [[nodiscard]] SkeletalMeshResult<SkeletalSubmesh> read(std::uint32_t expected_index) const;
};

SkeletalMeshResult<SkeletalSubmesh> SubmeshReader::read(const std::uint32_t expected_index) const
{
    const auto offset = reader.absolute_position();
    auto name = read_string(reader, "skem.section_name");
    const auto global_index = reader.read_i32();
    if (!name.has_value())
    {
        return SkeletalMeshResult<SkeletalSubmesh>::failure(name.error());
    }
    if (!global_index.has_value())
    {
        return SkeletalMeshResult<SkeletalSubmesh>::failure(
            read_error(global_index.error(), "skem.global_submesh_index"));
    }
    if (global_index.value() < 0 || std::cmp_not_equal(global_index.value(), expected_index))
    {
        return SkeletalMeshResult<SkeletalSubmesh>::failure(
            make_error(SkeletalMeshErrorCode::invalid_global_submesh_index, offset,
                       "skem.global_submesh_index"));
    }
    auto vertices = read_vertex_arrays(reader, limits);
    if (!vertices.has_value())
    {
        return SkeletalMeshResult<SkeletalSubmesh>::failure(vertices.error());
    }
    auto topology = read_topology_arrays(reader, limits, vertices.value().positions.size());
    if (!topology.has_value())
    {
        return SkeletalMeshResult<SkeletalSubmesh>::failure(topology.error());
    }
    auto vertex_arrays = std::move(vertices).take_value();
    auto topology_arrays = std::move(topology).take_value();
    SkeletalSubmesh mesh{.section_name_bytes = std::move(name).take_value(),
                         .global_index = global_index.value(),
                         .positions = std::move(vertex_arrays.positions),
                         .normals = std::move(vertex_arrays.normals),
                         .uv0 = std::move(vertex_arrays.uv0),
                         .tangents = std::move(vertex_arrays.tangents),
                         .binormals = std::move(vertex_arrays.binormals),
                         .weights = std::move(vertex_arrays.weights),
                         .bone_indices = std::move(vertex_arrays.bone_indices),
                         .indices = std::move(topology_arrays.indices),
                         .sections = std::move(topology_arrays.sections),
                         .shadow_indices = std::move(topology_arrays.shadow_indices),
                         .adjacent_faces = std::move(topology_arrays.adjacent_faces)};
    if (const auto error = validate_submesh(mesh, offset); error.has_value())
    {
        return SkeletalMeshResult<SkeletalSubmesh>::failure(error.value());
    }
    return SkeletalMeshResult<SkeletalSubmesh>::success(std::move(mesh));
}

[[nodiscard]] SkeletalMeshResult<SkeletalGroup> read_group(format::BinaryReader& reader,
                                                           const SkeletalMeshLimits limits,
                                                           std::uint32_t& global_submesh_index)
{
    const auto id = reader.read_i32();
    if (!id.has_value())
    {
        return SkeletalMeshResult<SkeletalGroup>::failure(read_error(id.error(), "skem.group.id"));
    }
    auto count = read_count(reader, limits.maximum_submesh_count, "skem.group.submesh_count");
    if (!count.has_value())
    {
        return SkeletalMeshResult<SkeletalGroup>::failure(count.error());
    }
    if (count.value() > limits.maximum_submesh_count - global_submesh_index)
    {
        return SkeletalMeshResult<SkeletalGroup>::failure(
            make_error(SkeletalMeshErrorCode::count_limit_exceeded, reader.absolute_position(),
                       "skem.total_submesh_count"));
    }
    SkeletalGroup group{.id = id.value(), .submeshes = {}};
    group.submeshes.reserve(count.value());
    for (std::uint32_t index = 0; index < count.value(); ++index)
    {
        auto submesh = SubmeshReader{.reader = reader, .limits = limits}.read(global_submesh_index);
        if (!submesh.has_value())
        {
            return SkeletalMeshResult<SkeletalGroup>::failure(submesh.error());
        }
        group.submeshes.push_back(std::move(submesh).take_value());
        ++global_submesh_index;
    }
    return SkeletalMeshResult<SkeletalGroup>::success(std::move(group));
}

[[nodiscard]] std::optional<SkeletalMeshError> accumulate_totals(SkeletalMeshPayload& payload,
                                                                 const SkeletalGroup& group,
                                                                 const SkeletalMeshLimits limits,
                                                                 const std::uint64_t offset)
{
    for (const auto& mesh : group.submeshes)
    {
        payload.total_vertex_count += mesh.positions.size();
        payload.total_index_count += mesh.indices.size();
        payload.total_triangle_count += mesh.indices.size() / 3U;
        payload.total_shadow_index_count += mesh.shadow_indices.size();
        if (payload.total_vertex_count > limits.maximum_total_vertex_count ||
            payload.total_index_count > limits.maximum_total_index_count)
        {
            return make_error(SkeletalMeshErrorCode::count_limit_exceeded, offset,
                              "skem.aggregate_count");
        }
    }
    return std::nullopt;
}

} // namespace

SkemReader::SkemReader(const SkeletalMeshLimits limits) : limits_(limits) {}

SkeletalMeshResult<SkeletalMeshPayload> SkemReader::parse(const std::span<const std::byte> bytes,
                                                          const std::uint64_t base_offset) const
{
    format::BinaryReader reader(bytes, format::ByteOrder::little_endian, base_offset, "skem");
    auto group_count = read_count(reader, limits_.maximum_group_count, "skem.group_count");
    if (!group_count.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshPayload>::failure(group_count.error());
    }
    SkeletalMeshPayload payload;
    payload.groups.reserve(group_count.value());
    std::uint32_t global_submesh_index = 0;
    for (std::uint32_t index = 0; index < group_count.value(); ++index)
    {
        auto group = read_group(reader, limits_, global_submesh_index);
        if (!group.has_value())
        {
            return SkeletalMeshResult<SkeletalMeshPayload>::failure(group.error());
        }
        if (const auto error =
                accumulate_totals(payload, group.value(), limits_, reader.absolute_position());
            error.has_value())
        {
            return SkeletalMeshResult<SkeletalMeshPayload>::failure(error.value());
        }
        payload.groups.push_back(std::move(group).take_value());
    }
    payload.total_submesh_count = global_submesh_index;
    if (reader.remaining() != 0U)
    {
        return SkeletalMeshResult<SkeletalMeshPayload>::failure(make_error(
            SkeletalMeshErrorCode::trailing_bytes, reader.absolute_position(), "skem.trailing"));
    }
    return SkeletalMeshResult<SkeletalMeshPayload>::success(std::move(payload));
}

} // namespace tmxy::skeletal_mesh
