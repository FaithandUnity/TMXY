#include "tmxy/transform/legacy_to_ue_transform.hpp"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string_view>

namespace
{

class TestContext final
{
  public:
    void expect(const bool condition, const std::string_view message)
    {
        if (!condition)
        {
            ++failure_count_;
            std::cerr << "FAILED: " << message << '\n';
        }
    }

    [[nodiscard]] int failure_count() const noexcept
    {
        return failure_count_;
    }

  private:
    int failure_count_{0};
};

[[nodiscard]] bool near(const double left, const double right,
                        const double tolerance = 1.0e-12) noexcept
{
    return std::abs(left - right) <= tolerance;
}

[[nodiscard]] tmxy::transform::Matrix4 identity_matrix()
{
    tmxy::transform::Matrix4 value;
    value.rows[0][0] = 1.0;
    value.rows[1][1] = 1.0;
    value.rows[2][2] = 1.0;
    value.rows[3][3] = 1.0;
    return value;
}

void test_position_and_direction(TestContext& test)
{
    const auto position = tmxy::transform::LegacyToUETransform::position(
        tmxy::transform::Vec3{.x = 1.25, .y = -2.0, .z = 0.5});
    const auto direction = tmxy::transform::LegacyToUETransform::direction(
        tmxy::transform::Vec3{.x = 1.0, .y = -2.0, .z = 3.0});

    test.expect(position.has_value(), "finite position converts");
    test.expect(position.has_value() && near(position.value().x, 125.0), "position X to cm");
    test.expect(position.has_value() && near(position.value().y, -200.0), "position Y to cm");
    test.expect(position.has_value() && near(position.value().z, 50.0), "position Z to cm");
    test.expect(direction.has_value() && near(direction.value().x, 1.0), "direction X identity");
    test.expect(direction.has_value() && near(direction.value().y, -2.0), "direction Y identity");
    test.expect(direction.has_value() && near(direction.value().z, 3.0), "direction Z identity");
}

void test_normal_and_uv(TestContext& test)
{
    const auto normal = tmxy::transform::LegacyToUETransform::normal(
        tmxy::transform::Vec3{.x = 3.0, .y = 0.0, .z = 4.0});
    const auto uv =
        tmxy::transform::LegacyToUETransform::uv(tmxy::transform::Vec2{.x = -0.25, .y = 1.75});

    test.expect(normal.has_value() && near(normal.value().x, 0.6), "normal X normalized");
    test.expect(normal.has_value() && near(normal.value().z, 0.8), "normal Z normalized");
    test.expect(uv.has_value() && near(uv.value().x, -0.25), "UV U preserved");
    test.expect(uv.has_value() && near(uv.value().y, 1.75), "UV V preserved");
}

void test_rotator_golden_values(TestContext& test)
{
    const auto quarter = tmxy::transform::LegacyToUETransform::rotator(
        tmxy::transform::LegacyRotator{.pitch = 16'384, .yaw = 16'384, .roll = 16'384});
    const auto wrapped = tmxy::transform::LegacyToUETransform::rotator(
        tmxy::transform::LegacyRotator{.pitch = 65'536, .yaw = -16'384, .roll = 32'768});

    test.expect(near(quarter.pitch, -90.0), "legacy pitch sign is inverted");
    test.expect(near(quarter.yaw, 90.0), "legacy yaw sign is preserved");
    test.expect(near(quarter.roll, -90.0), "legacy roll sign is inverted");
    test.expect(near(wrapped.pitch, 0.0), "full turn wraps to zero");
    test.expect(near(wrapped.yaw, -90.0), "negative yaw remains negative");
    test.expect(near(wrapped.roll, 180.0), "half-turn canonical sign converts");
}

void test_matrix_and_winding(TestContext& test)
{
    auto legacy = identity_matrix();
    legacy.rows[0][0] = -2.0;
    legacy.rows[1][1] = 3.0;
    legacy.rows[2][2] = 0.5;
    legacy.rows[3][0] = 1.25;
    legacy.rows[3][1] = -2.0;
    legacy.rows[3][2] = 0.5;
    const auto converted = tmxy::transform::LegacyToUETransform::matrix(legacy);
    const auto triangle = tmxy::transform::LegacyToUETransform::triangle(
        tmxy::transform::TriangleIndices{.first = 7U, .second = 3U, .third = 9U});
    const auto reverse =
        tmxy::transform::LegacyToUETransform::requires_winding_reversal_when_baked(legacy);

    test.expect(converted.has_value(), "affine matrix converts");
    test.expect(converted.has_value() && near(converted.value().rows[0][0], -2.0),
                "negative scale basis preserved");
    test.expect(converted.has_value() && near(converted.value().rows[3][0], 125.0),
                "matrix translation X to cm");
    test.expect(converted.has_value() && near(converted.value().rows[3][1], -200.0),
                "matrix translation Y to cm");
    test.expect(converted.has_value() && near(converted.value().rows[3][2], 50.0),
                "matrix translation Z to cm");
    test.expect(triangle.first == 7U && triangle.second == 3U && triangle.third == 9U,
                "serialized legacy winding is preserved");
    test.expect(reverse.has_value() && reverse.value(),
                "baking a negative basis requires one reversal");
}

void test_invalid_numeric_input(TestContext& test)
{
    const double infinity = std::numeric_limits<double>::infinity();
    const auto position = tmxy::transform::LegacyToUETransform::position(
        tmxy::transform::Vec3{.x = infinity, .y = 0.0, .z = 0.0});
    const auto normal = tmxy::transform::LegacyToUETransform::normal(
        tmxy::transform::Vec3{.x = 0.0, .y = 0.0, .z = 0.0});
    const auto uv =
        tmxy::transform::LegacyToUETransform::uv(tmxy::transform::Vec2{.x = 0.0, .y = infinity});
    auto projective = identity_matrix();
    projective.rows[0][3] = 1.0;
    const auto matrix = tmxy::transform::LegacyToUETransform::matrix(projective);
    auto degenerate = identity_matrix();
    degenerate.rows[2][2] = 0.0;
    const auto winding =
        tmxy::transform::LegacyToUETransform::requires_winding_reversal_when_baked(degenerate);

    test.expect(!position.has_value() &&
                    position.error().code == tmxy::transform::TransformErrorCode::non_finite_input,
                "non-finite position rejected");
    test.expect(!normal.has_value() &&
                    normal.error().code == tmxy::transform::TransformErrorCode::zero_length_normal,
                "zero normal rejected");
    test.expect(!uv.has_value(), "non-finite UV rejected");
    test.expect(!matrix.has_value() &&
                    matrix.error().code == tmxy::transform::TransformErrorCode::non_affine_matrix,
                "projective matrix rejected");
    test.expect(!winding.has_value() &&
                    winding.error().code == tmxy::transform::TransformErrorCode::degenerate_basis,
                "degenerate baked basis rejected");
    test.expect(tmxy::transform::TransformError::kSchemaVersion == 1U,
                "error schema version is frozen");
    test.expect(
        tmxy::transform::to_string(tmxy::transform::TransformErrorCode::zero_length_normal) ==
            "zero_length_normal",
        "stable error name");
}

} // namespace

int main()
{
    TestContext test;
    test_position_and_direction(test);
    test_normal_and_uv(test);
    test_rotator_golden_values(test);
    test_matrix_and_winding(test);
    test_invalid_numeric_input(test);
    return test.failure_count() == 0 ? 0 : 1;
}
