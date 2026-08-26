#pragma once

#include "tmxy/format/read_error.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace tmxy::skeletal_mesh
{

enum class SkeletalMeshErrorCode : std::uint8_t
{
    read_failure = 1,
    negative_count = 2,
    count_limit_exceeded = 3,
    non_finite_component = 4,
    attribute_count_mismatch = 5,
    index_count_not_triangles = 6,
    index_out_of_range = 7,
    invalid_boolean = 8,
    invalid_section = 9,
    section_index_count_mismatch = 10,
    invalid_shadow_index = 11,
    invalid_adjacency = 12,
    invalid_weight = 13,
    invalid_bone_index = 14,
    invalid_global_submesh_index = 15,
    trailing_bytes = 16,
    invalid_package = 17,
    mesh_object_not_found = 18,
    wrong_object_class = 19,
    object_range_out_of_file = 20,
    descriptor_item_limit_exceeded = 21,
    descriptor_name_limit_exceeded = 22,
    invalid_property_size = 23,
    duplicate_property = 24,
    incomplete_struct = 25,
    invalid_bone_id = 26,
    invalid_bone_reference = 27,
    duplicate_bone_parent = 28,
    cyclic_skeleton = 29,
    invalid_declared_bounds = 30,
    material_group_mismatch = 31,
    default_selection_mismatch = 32,
    transform_failure = 33,
};

struct SkeletalMeshError final
{
    static constexpr std::uint32_t kSchemaVersion = 1;

    SkeletalMeshErrorCode code{SkeletalMeshErrorCode::read_failure};
    std::uint64_t absolute_offset{0};
    std::string context;
    std::optional<format::ReadErrorCode> read_error_code;
};

[[nodiscard]] std::string_view to_string(SkeletalMeshErrorCode code) noexcept;

} // namespace tmxy::skeletal_mesh
