#pragma once

#include "tmxy/animation/animation_result.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace tmxy::animation
{

struct ObjectSpan final
{
    std::string name;
    std::string class_name;
    std::uint64_t offset{0};
    std::uint64_t size{0};
};

[[nodiscard]] AnimationResult<std::vector<ObjectSpan>>
read_package_objects(std::span<const std::byte> bytes);

} // namespace tmxy::animation
