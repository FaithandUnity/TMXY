#include "tmxy/texture/qtx_reader.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <utility>

namespace tmxy::texture
{
namespace
{

[[nodiscard]] bool multiply(const std::uint64_t left, const std::uint64_t right,
                            std::uint64_t& result) noexcept
{
    if (left != 0U && right > std::numeric_limits<std::uint64_t>::max() / left)
    {
        return false;
    }
    result = left * right;
    return true;
}

[[nodiscard]] TextureResult<std::uint64_t>
mip_size(const TextureFormat format, const std::uint32_t width, const std::uint32_t height)
{
    std::uint64_t pixels = 0;
    if (!multiply(width, height, pixels))
    {
        return TextureResult<std::uint64_t>::failure({.code = TextureErrorCode::mip_size_overflow,
                                                      .context = "qtx.mip.size",
                                                      .read_error_code = std::nullopt});
    }
    if (format == TextureFormat::rgba8 || format == TextureFormat::r32f)
    {
        std::uint64_t bytes = 0;
        if (!multiply(pixels, 4U, bytes))
        {
            return TextureResult<std::uint64_t>::failure(
                {.code = TextureErrorCode::mip_size_overflow,
                 .context = "qtx.mip.size",
                 .read_error_code = std::nullopt});
        }
        return TextureResult<std::uint64_t>::success(bytes);
    }
    if (format == TextureFormat::rgba16f)
    {
        std::uint64_t bytes = 0;
        if (!multiply(pixels, 8U, bytes))
        {
            return TextureResult<std::uint64_t>::failure(
                {.code = TextureErrorCode::mip_size_overflow,
                 .context = "qtx.mip.size",
                 .read_error_code = std::nullopt});
        }
        return TextureResult<std::uint64_t>::success(bytes);
    }
    const std::uint64_t blocks_wide = (static_cast<std::uint64_t>(width) + 3U) / 4U;
    const std::uint64_t blocks_high = (static_cast<std::uint64_t>(height) + 3U) / 4U;
    std::uint64_t blocks = 0;
    std::uint64_t bytes = 0;
    const std::uint64_t block_bytes =
        format == TextureFormat::dxt1 || format == TextureFormat::dxt1a ? 8U : 16U;
    if (!multiply(blocks_wide, blocks_high, blocks) || !multiply(blocks, block_bytes, bytes))
    {
        return TextureResult<std::uint64_t>::failure({.code = TextureErrorCode::mip_size_overflow,
                                                      .context = "qtx.mip.size",
                                                      .read_error_code = std::nullopt});
    }
    return TextureResult<std::uint64_t>::success(bytes);
}

[[nodiscard]] AlphaEncoding alpha_encoding(const TextureFormat format) noexcept
{
    switch (format)
    {
    case TextureFormat::rgba8:
        return AlphaEncoding::straight_8;
    case TextureFormat::rgba16f:
        return AlphaEncoding::straight_16f;
    case TextureFormat::r32f:
    case TextureFormat::dxt1:
        return AlphaEncoding::none;
    case TextureFormat::dxt1a:
        return AlphaEncoding::binary_1bit;
    case TextureFormat::dxt3:
        return AlphaEncoding::explicit_4bit;
    case TextureFormat::dxt5:
        return AlphaEncoding::interpolated_8bit;
    }
    return AlphaEncoding::none;
}

[[nodiscard]] AlphaCoverage classify_alpha(const std::span<const std::byte> rgba) noexcept
{
    bool has_zero = false;
    bool has_opaque = false;
    for (std::size_t index = 3; index < rgba.size(); index += 4U)
    {
        const auto alpha = std::to_integer<std::uint8_t>(rgba[index]);
        if (alpha == 0U)
        {
            has_zero = true;
        }
        else if (alpha == 255U)
        {
            has_opaque = true;
        }
        else
        {
            return AlphaCoverage::translucent;
        }
    }
    if (has_zero && !has_opaque)
    {
        return AlphaCoverage::transparent;
    }
    if (has_zero)
    {
        return AlphaCoverage::binary_mask;
    }
    return AlphaCoverage::opaque;
}

} // namespace

QtxReader::QtxReader(const QtxLimits limits) : limits_(limits) {}

TextureResult<QtxTextureView> QtxReader::parse(TextureDescriptor descriptor,
                                               const std::span<const std::byte> payload) const
{
    if (payload.size() > limits_.maximum_payload_bytes)
    {
        return TextureResult<QtxTextureView>::failure(
            {.code = TextureErrorCode::output_limit_exceeded,
             .context = "qtx.payload",
             .read_error_code = std::nullopt});
    }
    std::uint64_t decoded_bytes = 0;
    if (!multiply(descriptor.width, descriptor.height, decoded_bytes) ||
        !multiply(decoded_bytes, 4U, decoded_bytes) ||
        decoded_bytes > limits_.maximum_decoded_bytes)
    {
        return TextureResult<QtxTextureView>::failure(
            {.code = TextureErrorCode::output_limit_exceeded,
             .context = "qtx.decoded_mip_zero",
             .read_error_code = std::nullopt});
    }

    QtxTextureView texture;
    texture.descriptor = std::move(descriptor);
    texture.alpha_encoding = alpha_encoding(texture.descriptor.format);
    texture.payload_size = payload.size();
    std::uint32_t width = texture.descriptor.width;
    std::uint32_t height = texture.descriptor.height;
    std::uint64_t offset = 0;
    for (std::uint32_t level = 0; level < texture.descriptor.mip_count; ++level)
    {
        auto size = mip_size(texture.descriptor.format, width, height);
        if (!size.has_value())
        {
            return TextureResult<QtxTextureView>::failure(size.error());
        }
        if (size.value() > std::numeric_limits<std::uint64_t>::max() - offset)
        {
            return TextureResult<QtxTextureView>::failure(
                {.code = TextureErrorCode::mip_size_overflow,
                 .context = "qtx.mip.range",
                 .read_error_code = std::nullopt});
        }
        texture.mips.push_back({.level = level,
                                .width = width,
                                .height = height,
                                .offset = offset,
                                .size = size.value()});
        offset += size.value();
        width = std::max(1U, width / 2U);
        height = std::max(1U, height / 2U);
    }
    if (offset != payload.size())
    {
        return TextureResult<QtxTextureView>::failure(
            {.code = TextureErrorCode::payload_size_mismatch,
             .absolute_offset = std::min<std::uint64_t>(offset, payload.size()),
             .context = "qtx.payload_size",
             .read_error_code = std::nullopt});
    }
    auto decoded = decode_mip_zero_rgba8(texture, payload);
    if (!decoded.has_value())
    {
        return TextureResult<QtxTextureView>::failure(decoded.error());
    }
    texture.alpha_coverage = classify_alpha(decoded.value());
    return TextureResult<QtxTextureView>::success(std::move(texture));
}

} // namespace tmxy::texture
