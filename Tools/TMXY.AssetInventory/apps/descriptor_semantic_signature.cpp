#include "descriptor_semantic_signature.hpp"

#include "tmxy/animation/animation_types.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_types.hpp"
#include "tmxy/static_mesh/static_mesh_types.hpp"
#include "tmxy/texture/texture_types.hpp"

#include <bit>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::asset_inventory
{
namespace
{

static_assert(sizeof(std::size_t) <= sizeof(std::uint64_t));
static_assert(sizeof(float) == sizeof(std::uint32_t));

enum class DescriptorKind : std::uint8_t
{
    texture = 1,
    static_mesh = 2,
    skeletal_mesh = 3,
    package_animation_set = 4,
};

class CanonicalWriter final
{
  public:
    explicit CanonicalWriter(const DescriptorKind kind)
    {
        append_string("TMXY-descriptor-semantic-signature");
        append_u32(1U);
        append_u8(static_cast<std::uint8_t>(kind));
    }

    void append_u8(const std::uint8_t value)
    {
        bytes_.push_back(static_cast<char>(value));
    }

    void append_u32(const std::uint32_t value)
    {
        append_unsigned(value);
    }

    void append_u64(const std::uint64_t value)
    {
        append_unsigned(value);
    }

    void append_i32(const std::int32_t value)
    {
        append_u32(std::bit_cast<std::uint32_t>(value));
    }

    void append_bool(const bool value)
    {
        append_u8(value ? 1U : 0U);
    }

    void append_float(const float value)
    {
        append_u32(std::bit_cast<std::uint32_t>(value));
    }

    void append_string(const std::string_view value)
    {
        append_u64(static_cast<std::uint64_t>(value.size()));
        bytes_.append(value);
    }

    void append_bytes(const std::vector<std::byte>& value)
    {
        append_u64(static_cast<std::uint64_t>(value.size()));
        for (const auto byte : value)
        {
            append_u8(std::to_integer<std::uint8_t>(byte));
        }
    }

    [[nodiscard]] std::string finish() &&
    {
        return std::move(bytes_);
    }

  private:
    template <typename Unsigned> void append_unsigned(const Unsigned value)
    {
        for (std::size_t byte_index = 0; byte_index < sizeof(Unsigned); ++byte_index)
        {
            const auto shift = static_cast<unsigned int>(byte_index * 8U);
            append_u8(static_cast<std::uint8_t>((value >> shift) & static_cast<Unsigned>(0xFFU)));
        }
    }

    std::string bytes_;
};

template <typename Value, typename Append>
void append_vector(CanonicalWriter& writer, const std::vector<Value>& values, Append append_value)
{
    writer.append_u64(static_cast<std::uint64_t>(values.size()));
    for (const auto& value : values)
    {
        append_value(writer, value);
    }
}

void append_string_vector(CanonicalWriter& writer, const std::vector<std::string>& values)
{
    append_vector(writer, values, [](CanonicalWriter& output, const std::string& value)
                  { output.append_string(value); });
}

void append_i32_vector(CanonicalWriter& writer, const std::vector<std::int32_t>& values)
{
    append_vector(writer, values, [](CanonicalWriter& output, const std::int32_t value)
                  { output.append_i32(value); });
}

void append_vec3(CanonicalWriter& writer, const static_mesh::Vec3& value)
{
    writer.append_float(value.x);
    writer.append_float(value.y);
    writer.append_float(value.z);
}

void append_aabb(CanonicalWriter& writer, const static_mesh::Aabb& value)
{
    append_vec3(writer, value.minimum);
    append_vec3(writer, value.maximum);
}

void append_vec3(CanonicalWriter& writer, const skeletal_mesh::Vec3& value)
{
    writer.append_float(value.x);
    writer.append_float(value.y);
    writer.append_float(value.z);
}

void append_vec4(CanonicalWriter& writer, const skeletal_mesh::Vec4& value)
{
    writer.append_float(value.x);
    writer.append_float(value.y);
    writer.append_float(value.z);
    writer.append_float(value.w);
}

void append_aabb(CanonicalWriter& writer, const skeletal_mesh::Aabb& value)
{
    append_vec3(writer, value.minimum);
    append_vec3(writer, value.maximum);
}

template <typename Value, typename Append>
void append_optional(CanonicalWriter& writer, const std::optional<Value>& value,
                     Append append_value)
{
    writer.append_bool(value.has_value());
    if (value.has_value())
    {
        append_value(writer, *value);
    }
}

template <typename Property>
void append_unknown_properties(CanonicalWriter& writer, const std::vector<Property>& properties)
{
    append_vector(writer, properties,
                  [](CanonicalWriter& output, const Property& property)
                  {
                      output.append_string(property.name_bytes);
                      output.append_bytes(property.value);
                  });
}

void append_texture_descriptor(CanonicalWriter& writer,
                               const texture::TextureDescriptor& descriptor)
{
    writer.append_u8(static_cast<std::uint8_t>(descriptor.format));
    writer.append_u8(static_cast<std::uint8_t>(descriptor.u_clamp));
    writer.append_u8(static_cast<std::uint8_t>(descriptor.v_clamp));
    writer.append_u32(descriptor.width);
    writer.append_u32(descriptor.height);
    writer.append_u32(descriptor.stored_mip_count);
    writer.append_u32(descriptor.mip_count);
    append_unknown_properties(writer, descriptor.unknown_properties);
}

void append_static_mesh_descriptor(CanonicalWriter& writer,
                                   const static_mesh::StaticMeshDescriptor& descriptor)
{
    append_string_vector(writer, descriptor.material_object_names);
    append_optional(writer, descriptor.declared_bounds,
                    [](CanonicalWriter& output, const static_mesh::Aabb& value)
                    { append_aabb(output, value); });
    append_optional(writer, descriptor.use_light_map,
                    [](CanonicalWriter& output, const bool value) { output.append_bool(value); });
    append_unknown_properties(writer, descriptor.unknown_properties);
}

void append_bone(CanonicalWriter& writer, const skeletal_mesh::Bone& bone)
{
    writer.append_i32(bone.id);
    writer.append_string(bone.name_bytes);
    append_vec4(writer, bone.rotation);
    append_vec3(writer, bone.translation);
    append_i32_vector(writer, bone.children);
    writer.append_i32(bone.parent_id);
}

void append_skeletal_mesh_descriptor(CanonicalWriter& writer,
                                     const skeletal_mesh::SkeletalMeshDescriptor& descriptor)
{
    append_vector(writer, descriptor.bones, append_bone);
    append_string_vector(writer, descriptor.animation_object_names);
    writer.append_string(descriptor.default_animation_name_bytes);
    append_i32_vector(writer, descriptor.default_submesh_indices);
    append_string_vector(writer, descriptor.material_object_names);
    append_optional(writer, descriptor.declared_bounds,
                    [](CanonicalWriter& output, const skeletal_mesh::Aabb& value)
                    { append_aabb(output, value); });
    append_optional(writer, descriptor.instance_offset,
                    [](CanonicalWriter& output, const skeletal_mesh::Vec3& value)
                    { append_vec3(output, value); });
    append_optional(writer, descriptor.instance_rotation_degrees,
                    [](CanonicalWriter& output, const skeletal_mesh::Vec3& value)
                    { append_vec3(output, value); });
    append_unknown_properties(writer, descriptor.unknown_properties);
    append_i32_vector(writer, descriptor.root_bone_ids);
}

void append_animation_descriptor(CanonicalWriter& writer,
                                 const animation::AnimationDescriptor& descriptor)
{
    writer.append_string(descriptor.object_name_bytes);
    writer.append_string(descriptor.animation_name_bytes);
    writer.append_string(descriptor.skeleton_root_name_bytes);
    writer.append_i32(descriptor.frame_count);
    writer.append_float(descriptor.frame_delta_seconds);
    writer.append_bool(descriptor.self_loop);
    append_string_vector(writer, descriptor.notify_object_names);
    append_unknown_properties(writer, descriptor.unknown_properties);
}

void append_package_animation_set_descriptor(
    CanonicalWriter& writer, const animation::PackageAnimationSetDescriptor& descriptor)
{
    writer.append_string(descriptor.skeletal_mesh.object_name_bytes);
    append_skeletal_mesh_descriptor(writer, descriptor.skeletal_mesh.descriptor);
    append_vector(writer, descriptor.animations, append_animation_descriptor);
}

template <typename Descriptor, typename Mutate>
[[nodiscard]] bool mutation_changes_signature(const Descriptor& source, Mutate mutate)
{
    auto changed = source;
    mutate(changed);
    return semantic_signature(source) != semantic_signature(changed);
}

template <typename Descriptor, typename Mutate>
[[nodiscard]] bool mutation_preserves_signature(const Descriptor& source, Mutate mutate)
{
    auto changed = source;
    mutate(changed);
    return semantic_signature(source) == semantic_signature(changed);
}

[[nodiscard]] texture::TextureDescriptor sample_texture()
{
    texture::TextureDescriptor result;
    result.format = texture::TextureFormat::dxt5;
    result.u_clamp = texture::ClampMode::clamp;
    result.v_clamp = texture::ClampMode::wrap;
    result.width = 16U;
    result.height = 8U;
    result.stored_mip_count = 4U;
    result.mip_count = 5U;
    result.unknown_properties = {
        {.name_bytes = "property-a",
         .value_offset = 17U,
         .value = {std::byte{0x01}, std::byte{0x02}}},
        {.name_bytes = "property-b", .value_offset = 29U, .value = {std::byte{0x03}}},
    };
    return result;
}

[[nodiscard]] static_mesh::StaticMeshDescriptor sample_static_mesh()
{
    static_mesh::StaticMeshDescriptor result;
    result.material_object_names = {"material-a", "material-b"};
    result.declared_bounds = static_mesh::Aabb{
        .minimum = {.x = -1.0F, .y = -2.0F, .z = -3.0F},
        .maximum = {.x = 4.0F, .y = 5.0F, .z = 6.0F},
    };
    result.use_light_map = false;
    result.unknown_properties = {
        {.name_bytes = "property-a", .value_offset = 31U, .value = {std::byte{0x04}}},
        {.name_bytes = "property-b",
         .value_offset = 37U,
         .value = {std::byte{0x05}, std::byte{0x06}}},
    };
    return result;
}

[[nodiscard]] skeletal_mesh::SkeletalMeshDescriptor sample_skeletal_mesh()
{
    skeletal_mesh::SkeletalMeshDescriptor result;
    result.bones = {
        {.id = 3,
         .name_bytes = "bone-a",
         .rotation = {.x = 0.1F, .y = 0.2F, .z = 0.3F, .w = 0.4F},
         .translation = {.x = 1.0F, .y = 2.0F, .z = 3.0F},
         .children = {4, 5},
         .parent_id = -1},
        {.id = 4,
         .name_bytes = "bone-b",
         .rotation = {.x = 0.5F, .y = 0.6F, .z = 0.7F, .w = 0.8F},
         .translation = {.x = 4.0F, .y = 5.0F, .z = 6.0F},
         .children = {},
         .parent_id = 3},
    };
    result.animation_object_names = {"animation-a", "animation-b"};
    result.default_animation_name_bytes = "idle";
    result.default_submesh_indices = {7, 8};
    result.material_object_names = {"material-a", "material-b"};
    result.declared_bounds = skeletal_mesh::Aabb{
        .minimum = {.x = -7.0F, .y = -8.0F, .z = -9.0F},
        .maximum = {.x = 10.0F, .y = 11.0F, .z = 12.0F},
    };
    result.instance_offset = skeletal_mesh::Vec3{.x = 13.0F, .y = 14.0F, .z = 15.0F};
    result.instance_rotation_degrees = skeletal_mesh::Vec3{.x = 16.0F, .y = 17.0F, .z = 18.0F};
    result.unknown_properties = {
        {.name_bytes = "property-a", .value_offset = 41U, .value = {std::byte{0x07}}},
        {.name_bytes = "property-b", .value_offset = 43U, .value = {std::byte{0x08}}},
    };
    result.root_bone_ids = {3, 4};
    return result;
}

[[nodiscard]] animation::PackageAnimationSetDescriptor sample_animation_set()
{
    animation::PackageAnimationSetDescriptor result;
    result.skeletal_mesh.object_name_bytes = "skeletal-object";
    result.skeletal_mesh.body_offset = 47U;
    result.skeletal_mesh.body_size = 53U;
    result.skeletal_mesh.descriptor = sample_skeletal_mesh();
    result.animations = {
        {.object_name_bytes = "animation-object-a",
         .body_offset = 59U,
         .body_size = 61U,
         .animation_name_bytes = "animation-a",
         .skeleton_root_name_bytes = "bone-a",
         .frame_count = 20,
         .frame_delta_seconds = 0.25F,
         .self_loop = true,
         .notify_object_names = {"notify-a", "notify-b"},
         .unknown_properties = {{.name_bytes = "property-a",
                                 .value_offset = 67U,
                                 .value = {std::byte{0x09}}}}},
        {.object_name_bytes = "animation-object-b",
         .body_offset = 71U,
         .body_size = 73U,
         .animation_name_bytes = "animation-b",
         .skeleton_root_name_bytes = "bone-a",
         .frame_count = 30,
         .frame_delta_seconds = 0.5F,
         .self_loop = false,
         .notify_object_names = {},
         .unknown_properties = {}},
    };
    return result;
}

} // namespace

std::string semantic_signature(const texture::TextureDescriptor& descriptor)
{
    CanonicalWriter writer(DescriptorKind::texture);
    append_texture_descriptor(writer, descriptor);
    return std::move(writer).finish();
}

std::string semantic_signature(const static_mesh::StaticMeshDescriptor& descriptor)
{
    CanonicalWriter writer(DescriptorKind::static_mesh);
    append_static_mesh_descriptor(writer, descriptor);
    return std::move(writer).finish();
}

std::string semantic_signature(const skeletal_mesh::SkeletalMeshDescriptor& descriptor)
{
    CanonicalWriter writer(DescriptorKind::skeletal_mesh);
    append_skeletal_mesh_descriptor(writer, descriptor);
    return std::move(writer).finish();
}

std::string semantic_signature(const animation::PackageAnimationSetDescriptor& descriptor)
{
    CanonicalWriter writer(DescriptorKind::package_animation_set);
    append_package_animation_set_descriptor(writer, descriptor);
    return std::move(writer).finish();
}

bool semantic_signature_self_test()
{
    bool valid = true;
    const auto require = [&valid](const bool condition) { valid = valid && condition; };

    const auto texture = sample_texture();
    require(mutation_changes_signature(texture, [](auto& value)
                                       { value.format = texture::TextureFormat::dxt1; }));
    require(mutation_changes_signature(texture, [](auto& value)
                                       { value.u_clamp = texture::ClampMode::wrap; }));
    require(mutation_changes_signature(texture, [](auto& value)
                                       { value.v_clamp = texture::ClampMode::clamp; }));
    require(mutation_changes_signature(texture, [](auto& value) { ++value.width; }));
    require(mutation_changes_signature(texture, [](auto& value) { ++value.height; }));
    require(mutation_changes_signature(texture, [](auto& value) { ++value.stored_mip_count; }));
    require(mutation_changes_signature(texture, [](auto& value) { ++value.mip_count; }));
    require(mutation_changes_signature(texture, [](auto& value)
                                       { value.unknown_properties[0].name_bytes += "-changed"; }));
    require(mutation_changes_signature(
        texture, [](auto& value) { value.unknown_properties[0].value[0] = std::byte{0xFF}; }));
    require(mutation_changes_signature(
        texture,
        [](auto& value) { std::swap(value.unknown_properties[0], value.unknown_properties[1]); }));
    require(mutation_preserves_signature(texture, [](auto& value)
                                         { value.unknown_properties[0].value_offset += 100U; }));

    auto texture_segmented_left = texture;
    texture_segmented_left.unknown_properties = {
        {.name_bytes = "a", .value = {std::byte{0x62}, std::byte{0x63}}}};
    auto texture_segmented_right = texture;
    texture_segmented_right.unknown_properties = {{.name_bytes = "ab", .value = {std::byte{0x63}}}};
    require(semantic_signature(texture_segmented_left) !=
            semantic_signature(texture_segmented_right));

    const auto static_mesh = sample_static_mesh();
    require(mutation_changes_signature(static_mesh, [](auto& value)
                                       { value.material_object_names[0] += "-changed"; }));
    require(mutation_changes_signature(
        static_mesh, [](auto& value)
        { std::swap(value.material_object_names[0], value.material_object_names[1]); }));
    require(mutation_changes_signature(static_mesh,
                                       [](auto& value) { value.declared_bounds.reset(); }));
    require(mutation_changes_signature(static_mesh, [](auto& value)
                                       { value.declared_bounds->minimum.x = -0.0F; }));
    require(mutation_changes_signature(static_mesh, [](auto& value)
                                       { value.declared_bounds->minimum.y += 1.0F; }));
    require(mutation_changes_signature(static_mesh, [](auto& value)
                                       { value.declared_bounds->minimum.z += 1.0F; }));
    require(mutation_changes_signature(static_mesh, [](auto& value)
                                       { value.declared_bounds->maximum.x += 1.0F; }));
    require(mutation_changes_signature(static_mesh, [](auto& value)
                                       { value.declared_bounds->maximum.y += 1.0F; }));
    require(mutation_changes_signature(static_mesh, [](auto& value)
                                       { value.declared_bounds->maximum.z += 1.0F; }));
    require(
        mutation_changes_signature(static_mesh, [](auto& value) { value.use_light_map.reset(); }));
    require(
        mutation_changes_signature(static_mesh, [](auto& value) { value.use_light_map = true; }));
    require(mutation_changes_signature(static_mesh, [](auto& value)
                                       { value.unknown_properties[0].name_bytes += "-changed"; }));
    require(mutation_changes_signature(
        static_mesh, [](auto& value) { value.unknown_properties[0].value[0] = std::byte{0xFF}; }));
    require(mutation_changes_signature(
        static_mesh,
        [](auto& value) { std::swap(value.unknown_properties[0], value.unknown_properties[1]); }));
    require(mutation_preserves_signature(static_mesh, [](auto& value)
                                         { value.unknown_properties[0].value_offset += 100U; }));

    auto static_segmented_left = static_mesh;
    static_segmented_left.material_object_names = {"ab", "c"};
    auto static_segmented_right = static_mesh;
    static_segmented_right.material_object_names = {"a", "bc"};
    require(semantic_signature(static_segmented_left) !=
            semantic_signature(static_segmented_right));

    auto static_positive_zero = static_mesh;
    static_positive_zero.declared_bounds->minimum.x = 0.0F;
    auto static_negative_zero = static_positive_zero;
    static_negative_zero.declared_bounds->minimum.x = -0.0F;
    require(semantic_signature(static_positive_zero) != semantic_signature(static_negative_zero));

    const auto skeletal_mesh = sample_skeletal_mesh();
    require(mutation_changes_signature(skeletal_mesh, [](auto& value) { ++value.bones[0].id; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.bones[0].name_bytes += "-changed"; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].rotation.x = -0.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].rotation.y += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].rotation.z += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].rotation.w += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].translation.x += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].translation.y += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].translation.z += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].children[0] += 1; }));
    require(mutation_changes_signature(
        skeletal_mesh,
        [](auto& value) { std::swap(value.bones[0].children[0], value.bones[0].children[1]); }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.bones[0].parent_id = 9; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { std::swap(value.bones[0], value.bones[1]); }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.animation_object_names[0] += "-changed"; }));
    require(mutation_changes_signature(
        skeletal_mesh, [](auto& value)
        { std::swap(value.animation_object_names[0], value.animation_object_names[1]); }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.default_animation_name_bytes += "-changed"; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.default_submesh_indices[0] += 1; }));
    require(mutation_changes_signature(
        skeletal_mesh, [](auto& value)
        { std::swap(value.default_submesh_indices[0], value.default_submesh_indices[1]); }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.material_object_names[0] += "-changed"; }));
    require(mutation_changes_signature(
        skeletal_mesh, [](auto& value)
        { std::swap(value.material_object_names[0], value.material_object_names[1]); }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.declared_bounds.reset(); }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.declared_bounds->minimum.x = -0.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.declared_bounds->minimum.y += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.declared_bounds->minimum.z += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.declared_bounds->maximum.x += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.declared_bounds->maximum.y += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.declared_bounds->maximum.z += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.instance_offset.reset(); }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.instance_offset->x = -0.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.instance_offset->y += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.instance_offset->z += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.instance_rotation_degrees.reset(); }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.instance_rotation_degrees->x = -0.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.instance_rotation_degrees->y += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.instance_rotation_degrees->z += 1.0F; }));
    require(mutation_changes_signature(skeletal_mesh, [](auto& value)
                                       { value.unknown_properties[0].name_bytes += "-changed"; }));
    require(
        mutation_changes_signature(skeletal_mesh, [](auto& value)
                                   { value.unknown_properties[0].value[0] = std::byte{0xFF}; }));
    require(mutation_changes_signature(
        skeletal_mesh,
        [](auto& value) { std::swap(value.unknown_properties[0], value.unknown_properties[1]); }));
    require(mutation_changes_signature(skeletal_mesh,
                                       [](auto& value) { value.root_bone_ids[0] += 1; }));
    require(
        mutation_changes_signature(skeletal_mesh, [](auto& value)
                                   { std::swap(value.root_bone_ids[0], value.root_bone_ids[1]); }));
    require(mutation_preserves_signature(skeletal_mesh, [](auto& value)
                                         { value.unknown_properties[0].value_offset += 100U; }));

    const auto animation_set = sample_animation_set();
    require(mutation_changes_signature(animation_set, [](auto& value)
                                       { value.skeletal_mesh.object_name_bytes += "-changed"; }));
    require(mutation_changes_signature(animation_set, [](auto& value)
                                       { value.skeletal_mesh.descriptor.bones[0].id += 1; }));
    require(mutation_changes_signature(animation_set, [](auto& value)
                                       { value.animations[0].object_name_bytes += "-changed"; }));
    require(
        mutation_changes_signature(animation_set, [](auto& value)
                                   { value.animations[0].animation_name_bytes += "-changed"; }));
    require(mutation_changes_signature(
        animation_set,
        [](auto& value) { value.animations[0].skeleton_root_name_bytes += "-changed"; }));
    require(mutation_changes_signature(animation_set,
                                       [](auto& value) { value.animations[0].frame_count += 1; }));
    require(mutation_changes_signature(animation_set, [](auto& value)
                                       { value.animations[0].frame_delta_seconds = -0.0F; }));
    require(mutation_changes_signature(animation_set,
                                       [](auto& value) { value.animations[0].self_loop = false; }));
    require(
        mutation_changes_signature(animation_set, [](auto& value)
                                   { value.animations[0].notify_object_names[0] += "-changed"; }));
    require(mutation_changes_signature(animation_set,
                                       [](auto& value)
                                       {
                                           std::swap(value.animations[0].notify_object_names[0],
                                                     value.animations[0].notify_object_names[1]);
                                       }));
    require(mutation_changes_signature(
        animation_set,
        [](auto& value) { value.animations[0].unknown_properties[0].name_bytes += "-changed"; }));
    require(mutation_changes_signature(
        animation_set,
        [](auto& value) { value.animations[0].unknown_properties[0].value[0] = std::byte{0xFF}; }));
    require(mutation_changes_signature(animation_set, [](auto& value)
                                       { std::swap(value.animations[0], value.animations[1]); }));
    require(mutation_preserves_signature(
        animation_set,
        [](auto& value)
        {
            value.skeletal_mesh.body_offset += 100U;
            value.skeletal_mesh.body_size += 100U;
            value.animations[0].body_offset += 100U;
            value.animations[0].body_size += 100U;
            value.skeletal_mesh.descriptor.unknown_properties[0].value_offset += 100U;
            value.animations[0].unknown_properties[0].value_offset += 100U;
        }));

    require(semantic_signature(texture) != semantic_signature(static_mesh));
    require(semantic_signature(static_mesh) != semantic_signature(skeletal_mesh));
    require(semantic_signature(skeletal_mesh) != semantic_signature(animation_set));

    return valid;
}

} // namespace tmxy::asset_inventory
