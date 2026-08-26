#pragma once

#include "tmxy/animation/animation_result.hpp"
#include "tmxy/animation/animation_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace tmxy::animation
{

class AnimReader final
{
  public:
    [[nodiscard]] static AnimationResult<AnimationPayload>
    parse(std::span<const std::byte> bytes, std::span<const AnimationDescriptor> descriptors,
          std::uint32_t skeleton_bone_count);
};

} // namespace tmxy::animation
