#pragma once

#include "tmxy/animation/animation_result.hpp"
#include "tmxy/animation/animation_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace tmxy::animation
{

[[nodiscard]] AnimationResult<AnimationDescriptor>
read_animation_descriptor(std::span<const std::byte> object_body,
                          std::string_view object_name_bytes, std::uint64_t base_offset = 0);

[[nodiscard]] AnimationResult<PackageAnimationSetDescriptor>
read_package_animation_set_descriptor(std::span<const std::byte> package_bytes,
                                      std::string_view skeletal_mesh_object_name);

[[nodiscard]] AnimationResult<AnimationBinding>
bind_animation_set(std::span<const std::byte> package_bytes,
                   std::string_view skeletal_mesh_object_name,
                   std::span<const std::byte> animation_bytes);

[[nodiscard]] AnimationResult<AnimationBinding>
bind_animation_set_with_payload_frame_counts(std::span<const std::byte> package_bytes,
                                             std::string_view skeletal_mesh_object_name,
                                             std::span<const std::byte> animation_bytes);

} // namespace tmxy::animation
