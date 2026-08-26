#include "tmxy/transform/legacy_to_ue_transform.hpp"

#include <cmath>
#include <cstdint>

namespace tmxy::transform
{
namespace
{

constexpr double kAffineTolerance = 1.0e-9;
constexpr double kNormalLengthSquaredMinimum = 1.0e-24;
constexpr double kBasisDeterminantMinimum = 1.0e-12;

[[nodiscard]] bool is_finite(const Vec2 value) noexcept
{
    return std::isfinite(value.x) && std::isfinite(value.y);
}

[[nodiscard]] bool is_finite(const Vec3 value) noexcept
{
    return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z);
}

[[nodiscard]] bool is_finite(const Matrix4& value) noexcept
{
    for (const auto& row : value.rows)
    {
        for (const double component : row)
        {
            if (!std::isfinite(component))
            {
                return false;
            }
        }
    }
    return true;
}

[[nodiscard]] bool nearly_equal(const double left, const double right) noexcept
{
    return std::abs(left - right) <= kAffineTolerance;
}

[[nodiscard]] bool is_affine_row_vector_matrix(const Matrix4& value) noexcept
{
    return nearly_equal(value.rows[0][3], 0.0) && nearly_equal(value.rows[1][3], 0.0) &&
           nearly_equal(value.rows[2][3], 0.0) && nearly_equal(value.rows[3][3], 1.0);
}

[[nodiscard]] std::int32_t canonical_angle_units(const std::int32_t value) noexcept
{
    constexpr std::uint32_t mask = 0xFFFFU;
    const auto wrapped = static_cast<std::uint32_t>(value) & mask;
    if (wrapped >= 32'768U)
    {
        return static_cast<std::int32_t>(wrapped) - 65'536;
    }
    return static_cast<std::int32_t>(wrapped);
}

[[nodiscard]] double angle_units_to_degrees(const std::int32_t value) noexcept
{
    constexpr double degrees_per_unit =
        360.0 / static_cast<double>(LegacyToUETransform::kAngleUnitsPerTurn);
    return static_cast<double>(canonical_angle_units(value)) * degrees_per_unit;
}

[[nodiscard]] double basis_determinant(const Matrix4& value) noexcept
{
    const auto& row0 = value.rows[0];
    const auto& row1 = value.rows[1];
    const auto& row2 = value.rows[2];
    return (row0[0] * (row1[1] * row2[2] - row1[2] * row2[1])) -
           (row0[1] * (row1[0] * row2[2] - row1[2] * row2[0])) +
           (row0[2] * (row1[0] * row2[1] - row1[1] * row2[0]));
}

} // namespace

TransformResult<Vec3> LegacyToUETransform::position(const Vec3 legacy_position) noexcept
{
    if (!is_finite(legacy_position))
    {
        return TransformResult<Vec3>::failure(
            TransformError{.code = TransformErrorCode::non_finite_input, .field = "position"});
    }
    return TransformResult<Vec3>::success(Vec3{.x = legacy_position.x * kCentimetersPerLegacyUnit,
                                               .y = legacy_position.y * kCentimetersPerLegacyUnit,
                                               .z = legacy_position.z * kCentimetersPerLegacyUnit});
}

TransformResult<Vec3> LegacyToUETransform::direction(const Vec3 legacy_direction) noexcept
{
    if (!is_finite(legacy_direction))
    {
        return TransformResult<Vec3>::failure(
            TransformError{.code = TransformErrorCode::non_finite_input, .field = "direction"});
    }
    return TransformResult<Vec3>::success(legacy_direction);
}

TransformResult<Vec3> LegacyToUETransform::normal(const Vec3 legacy_normal) noexcept
{
    if (!is_finite(legacy_normal))
    {
        return TransformResult<Vec3>::failure(
            TransformError{.code = TransformErrorCode::non_finite_input, .field = "normal"});
    }
    const double length_squared = (legacy_normal.x * legacy_normal.x) +
                                  (legacy_normal.y * legacy_normal.y) +
                                  (legacy_normal.z * legacy_normal.z);
    if (length_squared <= kNormalLengthSquaredMinimum)
    {
        return TransformResult<Vec3>::failure(
            TransformError{.code = TransformErrorCode::zero_length_normal, .field = "normal"});
    }
    const double inverse_length = 1.0 / std::sqrt(length_squared);
    return TransformResult<Vec3>::success(Vec3{.x = legacy_normal.x * inverse_length,
                                               .y = legacy_normal.y * inverse_length,
                                               .z = legacy_normal.z * inverse_length});
}

TransformResult<Vec2> LegacyToUETransform::uv(const Vec2 legacy_uv) noexcept
{
    if (!is_finite(legacy_uv))
    {
        return TransformResult<Vec2>::failure(
            TransformError{.code = TransformErrorCode::non_finite_input, .field = "uv"});
    }
    return TransformResult<Vec2>::success(legacy_uv);
}

UERotatorDegrees LegacyToUETransform::rotator(const LegacyRotator legacy_rotation) noexcept
{
    return UERotatorDegrees{.pitch = -angle_units_to_degrees(legacy_rotation.pitch),
                            .yaw = angle_units_to_degrees(legacy_rotation.yaw),
                            .roll = -angle_units_to_degrees(legacy_rotation.roll)};
}

TransformResult<Matrix4> LegacyToUETransform::matrix(const Matrix4& legacy_matrix) noexcept
{
    if (!is_finite(legacy_matrix))
    {
        return TransformResult<Matrix4>::failure(
            TransformError{.code = TransformErrorCode::non_finite_input, .field = "matrix"});
    }
    if (!is_affine_row_vector_matrix(legacy_matrix))
    {
        return TransformResult<Matrix4>::failure(
            TransformError{.code = TransformErrorCode::non_affine_matrix, .field = "matrix"});
    }
    Matrix4 converted = legacy_matrix;
    converted.rows[3][0] *= kCentimetersPerLegacyUnit;
    converted.rows[3][1] *= kCentimetersPerLegacyUnit;
    converted.rows[3][2] *= kCentimetersPerLegacyUnit;
    return TransformResult<Matrix4>::success(converted);
}

TriangleIndices LegacyToUETransform::triangle(const TriangleIndices legacy_triangle) noexcept
{
    return legacy_triangle;
}

TransformResult<bool>
LegacyToUETransform::requires_winding_reversal_when_baked(const Matrix4& converted_matrix) noexcept
{
    if (!is_finite(converted_matrix))
    {
        return TransformResult<bool>::failure(
            TransformError{.code = TransformErrorCode::non_finite_input, .field = "matrix"});
    }
    if (!is_affine_row_vector_matrix(converted_matrix))
    {
        return TransformResult<bool>::failure(
            TransformError{.code = TransformErrorCode::non_affine_matrix, .field = "matrix"});
    }
    const double determinant = basis_determinant(converted_matrix);
    if (std::abs(determinant) <= kBasisDeterminantMinimum)
    {
        return TransformResult<bool>::failure(
            TransformError{.code = TransformErrorCode::degenerate_basis, .field = "matrix.basis"});
    }
    return TransformResult<bool>::success(determinant < 0.0);
}

} // namespace tmxy::transform
