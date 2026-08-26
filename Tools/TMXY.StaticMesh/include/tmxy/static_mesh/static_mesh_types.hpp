#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::static_mesh
{

struct Vec2 final
{
    float u{0.0F};
    float v{0.0F};
};

struct Vec3 final
{
    float x{0.0F};
    float y{0.0F};
    float z{0.0F};
};

struct Aabb final
{
    Vec3 minimum;
    Vec3 maximum;
};

struct MeshSection final
{
    std::uint32_t triangle_count{0};
    std::uint32_t minimum_vertex_index{0};
    std::uint32_t maximum_vertex_index{0};
    bool two_sided{false};
    std::uint64_t first_index{0};
};

struct OctreeNode final
{
    Aabb bounds;
    std::uint32_t face_index_count{0};
    std::uint32_t first_face_index{0};
    std::array<std::int32_t, 8> child_ids{};
};

struct StaticMesh final
{
    std::vector<Vec3> positions;
    std::vector<Vec3> normals;
    std::vector<Vec2> uv0;
    std::vector<Vec3> tangents;
    std::vector<Vec3> binormals;
    std::vector<std::uint16_t> indices;
    std::vector<MeshSection> sections;
    std::vector<Vec3> shadow_positions;
    std::vector<Vec3> shadow_normals;
    std::vector<std::uint16_t> shadow_indices;
    std::vector<Vec3> collision_positions;
    std::vector<std::uint16_t> collision_indices;
    bool collision_octree{false};
    std::vector<OctreeNode> octree_nodes;
    std::vector<std::uint16_t> octree_indices;
    bool emitter_points_field_present{false};
    std::vector<Vec3> emitter_points;
    bool uv1_field_present{false};
    std::vector<Vec2> uv1;
    Aabb render_bounds;
    std::optional<Aabb> collision_bounds;
};

struct UnknownProperty final
{
    std::string name_bytes;
    std::uint64_t value_offset{0};
    std::vector<std::byte> value;
};

struct StaticMeshDescriptor final
{
    std::vector<std::string> material_object_names;
    std::optional<Aabb> declared_bounds;
    std::optional<bool> use_light_map;
    std::vector<UnknownProperty> unknown_properties;
};

struct PackageStaticMeshDescriptor final
{
    std::string object_name_bytes;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    StaticMeshDescriptor descriptor;
};

enum class DeclaredBoundsRelation : std::uint8_t
{
    absent = 0,
    exact = 1,
    contains = 2,
    mismatch = 3,
};

struct StaticMeshBinding final
{
    StaticMesh mesh;
    PackageStaticMeshDescriptor package;
    Aabb effective_bounds;
    DeclaredBoundsRelation declared_bounds_relation{DeclaredBoundsRelation::absent};
};

[[nodiscard]] constexpr std::string_view to_string(const DeclaredBoundsRelation relation) noexcept
{
    switch (relation)
    {
    case DeclaredBoundsRelation::absent:
        return "absent";
    case DeclaredBoundsRelation::exact:
        return "exact";
    case DeclaredBoundsRelation::contains:
        return "contains";
    case DeclaredBoundsRelation::mismatch:
        return "mismatch";
    }
    return "unknown";
}

} // namespace tmxy::static_mesh
