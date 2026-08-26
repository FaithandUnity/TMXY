#include "tmxy/skeletal_mesh/skeletal_mesh_error.hpp"

namespace tmxy::skeletal_mesh
{

std::string_view to_string(const SkeletalMeshErrorCode code) noexcept
{
    switch (code)
    {
    case SkeletalMeshErrorCode::read_failure:
        return "read_failure";
    case SkeletalMeshErrorCode::negative_count:
        return "negative_count";
    case SkeletalMeshErrorCode::count_limit_exceeded:
        return "count_limit_exceeded";
    case SkeletalMeshErrorCode::non_finite_component:
        return "non_finite_component";
    case SkeletalMeshErrorCode::attribute_count_mismatch:
        return "attribute_count_mismatch";
    case SkeletalMeshErrorCode::index_count_not_triangles:
        return "index_count_not_triangles";
    case SkeletalMeshErrorCode::index_out_of_range:
        return "index_out_of_range";
    case SkeletalMeshErrorCode::invalid_boolean:
        return "invalid_boolean";
    case SkeletalMeshErrorCode::invalid_section:
        return "invalid_section";
    case SkeletalMeshErrorCode::section_index_count_mismatch:
        return "section_index_count_mismatch";
    case SkeletalMeshErrorCode::invalid_shadow_index:
        return "invalid_shadow_index";
    case SkeletalMeshErrorCode::invalid_adjacency:
        return "invalid_adjacency";
    case SkeletalMeshErrorCode::invalid_weight:
        return "invalid_weight";
    case SkeletalMeshErrorCode::invalid_bone_index:
        return "invalid_bone_index";
    case SkeletalMeshErrorCode::invalid_global_submesh_index:
        return "invalid_global_submesh_index";
    case SkeletalMeshErrorCode::trailing_bytes:
        return "trailing_bytes";
    case SkeletalMeshErrorCode::invalid_package:
        return "invalid_package";
    case SkeletalMeshErrorCode::mesh_object_not_found:
        return "mesh_object_not_found";
    case SkeletalMeshErrorCode::wrong_object_class:
        return "wrong_object_class";
    case SkeletalMeshErrorCode::object_range_out_of_file:
        return "object_range_out_of_file";
    case SkeletalMeshErrorCode::descriptor_item_limit_exceeded:
        return "descriptor_item_limit_exceeded";
    case SkeletalMeshErrorCode::descriptor_name_limit_exceeded:
        return "descriptor_name_limit_exceeded";
    case SkeletalMeshErrorCode::invalid_property_size:
        return "invalid_property_size";
    case SkeletalMeshErrorCode::duplicate_property:
        return "duplicate_property";
    case SkeletalMeshErrorCode::incomplete_struct:
        return "incomplete_struct";
    case SkeletalMeshErrorCode::invalid_bone_id:
        return "invalid_bone_id";
    case SkeletalMeshErrorCode::invalid_bone_reference:
        return "invalid_bone_reference";
    case SkeletalMeshErrorCode::duplicate_bone_parent:
        return "duplicate_bone_parent";
    case SkeletalMeshErrorCode::cyclic_skeleton:
        return "cyclic_skeleton";
    case SkeletalMeshErrorCode::invalid_declared_bounds:
        return "invalid_declared_bounds";
    case SkeletalMeshErrorCode::material_group_mismatch:
        return "material_group_mismatch";
    case SkeletalMeshErrorCode::default_selection_mismatch:
        return "default_selection_mismatch";
    case SkeletalMeshErrorCode::transform_failure:
        return "transform_failure";
    }
    return "unknown";
}

} // namespace tmxy::skeletal_mesh
