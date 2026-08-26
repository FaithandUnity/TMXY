#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace tmxy::skeletal_mesh
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

struct Vec4 final
{
    float x{0.0F};
    float y{0.0F};
    float z{0.0F};
    float w{0.0F};
};

using Quaternion = Vec4;

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

struct AdjacentFaces final
{
    std::int32_t edge0{-1};
    std::int32_t edge1{-1};
    std::int32_t edge2{-1};
};

struct SkeletalSubmesh final
{
    std::string section_name_bytes;
    std::int32_t global_index{-1};
    std::vector<Vec3> positions;
    std::vector<Vec3> normals;
    std::vector<Vec2> uv0;
    std::vector<Vec3> tangents;
    std::vector<Vec3> binormals;
    std::vector<Vec4> weights;
    std::vector<Vec4> bone_indices;
    std::vector<std::uint16_t> indices;
    std::vector<MeshSection> sections;
    std::vector<std::uint16_t> shadow_indices;
    std::vector<AdjacentFaces> adjacent_faces;
};

struct SkeletalGroup final
{
    std::int32_t id{0};
    std::vector<SkeletalSubmesh> submeshes;
};

struct SkeletalMeshPayload final
{
    std::vector<SkeletalGroup> groups;
    std::uint64_t total_submesh_count{0};
    std::uint64_t total_vertex_count{0};
    std::uint64_t total_index_count{0};
    std::uint64_t total_triangle_count{0};
    std::uint64_t total_shadow_index_count{0};
};

struct Bone final
{
    std::int32_t id{-1};
    std::string name_bytes;
    Quaternion rotation;
    Vec3 translation;
    std::vector<std::int32_t> children;
    std::int32_t parent_id{-1};
};

struct UnknownProperty final
{
    std::string name_bytes;
    std::uint64_t value_offset{0};
    std::vector<std::byte> value;
};

struct SkeletalMeshDescriptor final
{
    std::vector<Bone> bones;
    std::vector<std::string> animation_object_names;
    std::string default_animation_name_bytes;
    std::vector<std::int32_t> default_submesh_indices;
    std::vector<std::string> material_object_names;
    std::optional<Aabb> declared_bounds;
    std::optional<Vec3> instance_offset;
    std::optional<Vec3> instance_rotation_degrees;
    std::vector<UnknownProperty> unknown_properties;
    std::vector<std::int32_t> root_bone_ids;
};

struct PackageSkeletalMeshDescriptor final
{
    std::string object_name_bytes;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    SkeletalMeshDescriptor descriptor;
};

struct DefaultSubmeshSelection final
{
    std::uint32_t group_index{0};
    std::int32_t global_submesh_index{-1};
    std::optional<std::uint32_t> submesh_index_in_group;
    std::string material_object_name;
};

struct SkeletalMeshBinding final
{
    SkeletalMeshPayload payload;
    PackageSkeletalMeshDescriptor package;
    std::vector<DefaultSubmeshSelection> default_selections;
};

} // namespace tmxy::skeletal_mesh
