#pragma once

#include "tmxy/animation/animation_types.hpp"

#include <string>

namespace tmxy::animation
{

[[nodiscard]] std::string build_animation_json(const AnimationBinding& binding);
[[nodiscard]] std::string build_root_motion_csv(const AnimationBinding& binding);

} // namespace tmxy::animation
