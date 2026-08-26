#pragma once

#include "tmxy/format/read_error.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace tmxy::animation
{

enum class AnimationErrorCode : std::uint8_t
{
    read_failure = 1,
    invalid_package = 2,
    skeletal_mesh_descriptor_failure = 3,
    animation_object_not_found = 4,
    wrong_object_class = 5,
    object_range_out_of_file = 6,
    descriptor_item_limit_exceeded = 7,
    descriptor_name_limit_exceeded = 8,
    invalid_property_size = 9,
    duplicate_property = 10,
    missing_property = 11,
    invalid_frame_count = 12,
    invalid_frame_delta = 13,
    invalid_boolean = 14,
    animation_count_mismatch = 15,
    invalid_track_count = 16,
    frame_count_mismatch = 17,
    key_count_limit_exceeded = 18,
    non_finite_key = 19,
    invalid_quaternion = 20,
    invalid_emitter_count = 21,
    trailing_bytes = 22,
    gltf_contract_failure = 23,
};

struct AnimationError final
{
    static constexpr std::uint32_t kSchemaVersion = 1;

    AnimationErrorCode code{AnimationErrorCode::read_failure};
    std::uint64_t absolute_offset{0};
    std::string context;
    std::optional<format::ReadErrorCode> read_error_code;
};

[[nodiscard]] std::string_view to_string(AnimationErrorCode code) noexcept;

} // namespace tmxy::animation
