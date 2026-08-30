#include "tmxy/texture/texture_error.hpp"

#include "tmxy/texture/texture_types.hpp"

namespace tmxy::texture
{

std::string_view to_string(const TextureErrorCode code) noexcept
{
    switch (code)
    {
    case TextureErrorCode::read_failure:
        return "read_failure";
    case TextureErrorCode::item_count_limit_exceeded:
        return "item_count_limit_exceeded";
    case TextureErrorCode::property_name_limit_exceeded:
        return "property_name_limit_exceeded";
    case TextureErrorCode::duplicate_property:
        return "duplicate_property";
    case TextureErrorCode::invalid_property_size:
        return "invalid_property_size";
    case TextureErrorCode::invalid_format:
        return "invalid_format";
    case TextureErrorCode::invalid_clamp_mode:
        return "invalid_clamp_mode";
    case TextureErrorCode::invalid_dimension:
        return "invalid_dimension";
    case TextureErrorCode::invalid_mip_count:
        return "invalid_mip_count";
    case TextureErrorCode::trailing_descriptor_bytes:
        return "trailing_descriptor_bytes";
    case TextureErrorCode::mip_size_overflow:
        return "mip_size_overflow";
    case TextureErrorCode::payload_size_mismatch:
        return "payload_size_mismatch";
    case TextureErrorCode::non_finite_pixel:
        return "non_finite_pixel";
    case TextureErrorCode::output_limit_exceeded:
        return "output_limit_exceeded";
    case TextureErrorCode::invalid_package:
        return "invalid_package";
    case TextureErrorCode::texture_object_not_found:
        return "texture_object_not_found";
    case TextureErrorCode::wrong_object_class:
        return "wrong_object_class";
    case TextureErrorCode::object_range_out_of_file:
        return "object_range_out_of_file";
    }
    return "unknown";
}

const char* to_string(const TextureFormat value) noexcept
{
    switch (value)
    {
    case TextureFormat::rgba8:
        return "rgba8";
    case TextureFormat::rgba16f:
        return "rgba16f";
    case TextureFormat::r32f:
        return "r32f";
    case TextureFormat::dxt1:
        return "dxt1";
    case TextureFormat::dxt1a:
        return "dxt1a";
    case TextureFormat::dxt3:
        return "dxt3";
    case TextureFormat::dxt5:
        return "dxt5";
    }
    return "unknown";
}

const char* to_string(const ClampMode value) noexcept
{
    return value == ClampMode::clamp ? "clamp" : "wrap";
}

const char* to_string(const AlphaEncoding value) noexcept
{
    switch (value)
    {
    case AlphaEncoding::none:
        return "none";
    case AlphaEncoding::straight_8:
        return "straight_8";
    case AlphaEncoding::straight_16f:
        return "straight_16f";
    case AlphaEncoding::binary_1bit:
        return "binary_1bit";
    case AlphaEncoding::explicit_4bit:
        return "explicit_4bit";
    case AlphaEncoding::interpolated_8bit:
        return "interpolated_8bit";
    }
    return "unknown";
}

const char* to_string(const AlphaCoverage value) noexcept
{
    switch (value)
    {
    case AlphaCoverage::opaque:
        return "opaque";
    case AlphaCoverage::transparent:
        return "transparent";
    case AlphaCoverage::binary_mask:
        return "binary_mask";
    case AlphaCoverage::translucent:
        return "translucent";
    }
    return "unknown";
}

const char* to_string(const MipCountBasis value) noexcept
{
    switch (value)
    {
    case MipCountBasis::package_descriptor:
        return "package_descriptor";
    case MipCountBasis::payload_complete_chain_contract:
        return "payload_complete_chain_contract";
    case MipCountBasis::unknown:
        return "unknown";
    }
    return "unknown";
}

const char* to_string(const PayloadExtentBasis value) noexcept
{
    switch (value)
    {
    case PayloadExtentBasis::complete_input_payload:
        return "complete_input_payload";
    case PayloadExtentBasis::declared_mip_payload_prefix_contract:
        return "declared_mip_payload_prefix_contract";
    case PayloadExtentBasis::unknown:
        return "unknown";
    }
    return "unknown";
}

} // namespace tmxy::texture
