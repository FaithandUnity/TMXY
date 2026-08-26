#pragma once

#include <array>
#include <cstdint>

namespace tmxy::transform
{

struct Vec2 final
{
    double x{0.0};
    double y{0.0};
};

struct Vec3 final
{
    double x{0.0};
    double y{0.0};
    double z{0.0};
};

struct LegacyRotator final
{
    std::int32_t pitch{0};
    std::int32_t yaw{0};
    std::int32_t roll{0};
};

struct UERotatorDegrees final
{
    double pitch{0.0};
    double yaw{0.0};
    double roll{0.0};
};

struct Matrix4 final
{
    std::array<std::array<double, 4>, 4> rows{};
};

struct TriangleIndices final
{
    std::uint32_t first{0};
    std::uint32_t second{0};
    std::uint32_t third{0};
};

} // namespace tmxy::transform
