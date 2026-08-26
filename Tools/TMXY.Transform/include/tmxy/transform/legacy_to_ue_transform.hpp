#pragma once

#include "tmxy/transform/transform_result.hpp"
#include "tmxy/transform/transform_types.hpp"

namespace tmxy::transform
{

class LegacyToUETransform final
{
  public:
    static constexpr double kCentimetersPerLegacyUnit = 100.0;
    static constexpr std::int32_t kAngleUnitsPerTurn = 65'536;

    [[nodiscard]] static TransformResult<Vec3> position(Vec3 legacy_position) noexcept;
    [[nodiscard]] static TransformResult<Vec3> direction(Vec3 legacy_direction) noexcept;
    [[nodiscard]] static TransformResult<Vec3> normal(Vec3 legacy_normal) noexcept;
    [[nodiscard]] static TransformResult<Vec2> uv(Vec2 legacy_uv) noexcept;
    [[nodiscard]] static UERotatorDegrees rotator(LegacyRotator legacy_rotation) noexcept;
    [[nodiscard]] static TransformResult<Matrix4> matrix(const Matrix4& legacy_matrix) noexcept;
    [[nodiscard]] static TriangleIndices triangle(TriangleIndices legacy_triangle) noexcept;
    [[nodiscard]] static TransformResult<bool>
    requires_winding_reversal_when_baked(const Matrix4& converted_matrix) noexcept;
};

} // namespace tmxy::transform
