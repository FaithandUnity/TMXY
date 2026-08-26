#include "tmxy/static_mesh/static_mesh_error.hpp"

namespace tmxy::static_mesh
{

std::string_view to_string(const StaticMeshErrorCode code) noexcept
{
    switch (code)
    {
    case StaticMeshErrorCode::read_failure:
        return "read_failure";
    case StaticMeshErrorCode::negative_count:
        return "negative_count";
    case StaticMeshErrorCode::count_limit_exceeded:
        return "count_limit_exceeded";
    case StaticMeshErrorCode::non_finite_component:
        return "non_finite_component";
    case StaticMeshErrorCode::attribute_count_mismatch:
        return "attribute_count_mismatch";
    case StaticMeshErrorCode::index_count_not_triangles:
        return "index_count_not_triangles";
    case StaticMeshErrorCode::index_out_of_range:
        return "index_out_of_range";
    case StaticMeshErrorCode::invalid_boolean:
        return "invalid_boolean";
    case StaticMeshErrorCode::invalid_section:
        return "invalid_section";
    case StaticMeshErrorCode::section_index_count_mismatch:
        return "section_index_count_mismatch";
    case StaticMeshErrorCode::invalid_collision_flag:
        return "invalid_collision_flag";
    case StaticMeshErrorCode::invalid_octree_node_reference:
        return "invalid_octree_node_reference";
    case StaticMeshErrorCode::invalid_octree_face_range:
        return "invalid_octree_face_range";
    case StaticMeshErrorCode::trailing_bytes:
        return "trailing_bytes";
    case StaticMeshErrorCode::invalid_package:
        return "invalid_package";
    case StaticMeshErrorCode::mesh_object_not_found:
        return "mesh_object_not_found";
    case StaticMeshErrorCode::wrong_object_class:
        return "wrong_object_class";
    case StaticMeshErrorCode::object_range_out_of_file:
        return "object_range_out_of_file";
    case StaticMeshErrorCode::descriptor_item_limit_exceeded:
        return "descriptor_item_limit_exceeded";
    case StaticMeshErrorCode::descriptor_name_limit_exceeded:
        return "descriptor_name_limit_exceeded";
    case StaticMeshErrorCode::invalid_property_size:
        return "invalid_property_size";
    case StaticMeshErrorCode::duplicate_property:
        return "duplicate_property";
    case StaticMeshErrorCode::invalid_material_slot:
        return "invalid_material_slot";
    case StaticMeshErrorCode::invalid_declared_bounds:
        return "invalid_declared_bounds";
    case StaticMeshErrorCode::material_slot_mismatch:
        return "material_slot_mismatch";
    case StaticMeshErrorCode::declared_bounds_mismatch:
        return "declared_bounds_mismatch";
    case StaticMeshErrorCode::transform_failure:
        return "transform_failure";
    }
    return "unknown";
}

} // namespace tmxy::static_mesh
