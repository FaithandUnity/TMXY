#include "tmxy/animation/animation_error.hpp"

namespace tmxy::animation
{

std::string_view to_string(const AnimationErrorCode code) noexcept
{
    switch (code)
    {
    case AnimationErrorCode::read_failure:
        return "read_failure";
    case AnimationErrorCode::invalid_package:
        return "invalid_package";
    case AnimationErrorCode::skeletal_mesh_descriptor_failure:
        return "skeletal_mesh_descriptor_failure";
    case AnimationErrorCode::animation_object_not_found:
        return "animation_object_not_found";
    case AnimationErrorCode::wrong_object_class:
        return "wrong_object_class";
    case AnimationErrorCode::object_range_out_of_file:
        return "object_range_out_of_file";
    case AnimationErrorCode::descriptor_item_limit_exceeded:
        return "descriptor_item_limit_exceeded";
    case AnimationErrorCode::descriptor_name_limit_exceeded:
        return "descriptor_name_limit_exceeded";
    case AnimationErrorCode::invalid_property_size:
        return "invalid_property_size";
    case AnimationErrorCode::duplicate_property:
        return "duplicate_property";
    case AnimationErrorCode::missing_property:
        return "missing_property";
    case AnimationErrorCode::invalid_frame_count:
        return "invalid_frame_count";
    case AnimationErrorCode::invalid_frame_delta:
        return "invalid_frame_delta";
    case AnimationErrorCode::invalid_boolean:
        return "invalid_boolean";
    case AnimationErrorCode::animation_count_mismatch:
        return "animation_count_mismatch";
    case AnimationErrorCode::invalid_track_count:
        return "invalid_track_count";
    case AnimationErrorCode::frame_count_mismatch:
        return "frame_count_mismatch";
    case AnimationErrorCode::key_count_limit_exceeded:
        return "key_count_limit_exceeded";
    case AnimationErrorCode::non_finite_key:
        return "non_finite_key";
    case AnimationErrorCode::invalid_quaternion:
        return "invalid_quaternion";
    case AnimationErrorCode::invalid_emitter_count:
        return "invalid_emitter_count";
    case AnimationErrorCode::trailing_bytes:
        return "trailing_bytes";
    case AnimationErrorCode::gltf_contract_failure:
        return "gltf_contract_failure";
    }
    return "unknown";
}

} // namespace tmxy::animation
