#pragma once

#include "tmxy/format/read_error.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace tmxy::static_mesh
{

enum class StaticMeshErrorCode : std::uint8_t
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
    invalid_collision_flag = 11,
    invalid_octree_node_reference = 12,
    invalid_octree_face_range = 13,
    trailing_bytes = 14,
    invalid_package = 15,
    mesh_object_not_found = 16,
    wrong_object_class = 17,
    object_range_out_of_file = 18,
    descriptor_item_limit_exceeded = 19,
    descriptor_name_limit_exceeded = 20,
    invalid_property_size = 21,
    duplicate_property = 22,
    invalid_material_slot = 23,
    invalid_declared_bounds = 24,
    material_slot_mismatch = 25,
    declared_bounds_mismatch = 26,
    transform_failure = 27,
};

struct StaticMeshError final
{
    static constexpr std::uint32_t kSchemaVersion = 1;

    StaticMeshErrorCode code{StaticMeshErrorCode::read_failure};
    std::uint64_t absolute_offset{0};
    std::string context;
    std::optional<format::ReadErrorCode> read_error_code;
};

[[nodiscard]] std::string_view to_string(StaticMeshErrorCode code) noexcept;

} // namespace tmxy::static_mesh
