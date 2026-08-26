#include "tmxy/transform/transform_error.hpp"

namespace tmxy::transform
{

std::string_view to_string(const TransformErrorCode code) noexcept
{
    switch (code)
    {
    case TransformErrorCode::non_finite_input:
        return "non_finite_input";
    case TransformErrorCode::zero_length_normal:
        return "zero_length_normal";
    case TransformErrorCode::non_affine_matrix:
        return "non_affine_matrix";
    case TransformErrorCode::degenerate_basis:
        return "degenerate_basis";
    }
    return "unknown";
}

} // namespace tmxy::transform
