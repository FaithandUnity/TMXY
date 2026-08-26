#pragma once

#include <cstdint>
#include <string_view>

namespace tmxy::transform
{

enum class TransformErrorCode : std::uint8_t
{
    non_finite_input = 1,
    zero_length_normal = 2,
    non_affine_matrix = 3,
    degenerate_basis = 4,
};

struct TransformError final
{
    static constexpr std::uint32_t kSchemaVersion = 1;

    TransformErrorCode code{TransformErrorCode::non_finite_input};
    std::string_view field;
};

[[nodiscard]] std::string_view to_string(TransformErrorCode code) noexcept;

} // namespace tmxy::transform
