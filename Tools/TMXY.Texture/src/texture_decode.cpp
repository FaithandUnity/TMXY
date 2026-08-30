#include "texture_decode_internal.hpp"
#include "tmxy/texture/qtx_reader.hpp"

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace tmxy::texture
{
namespace
{

[[nodiscard]] std::uint16_t read_u16(const std::span<const std::byte> bytes,
                                     const std::size_t offset) noexcept
{
    return static_cast<std::uint16_t>(std::to_integer<std::uint8_t>(bytes[offset])) |
           static_cast<std::uint16_t>(
               static_cast<std::uint16_t>(std::to_integer<std::uint8_t>(bytes[offset + 1U])) << 8U);
}

[[nodiscard]] std::uint32_t read_u32(const std::span<const std::byte> bytes,
                                     const std::size_t offset) noexcept
{
    return static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset])) |
           (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset + 1U])) << 8U) |
           (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset + 2U])) << 16U) |
           (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset + 3U])) << 24U);
}

[[nodiscard]] float half_to_float(const std::uint16_t value) noexcept
{
    const bool negative = (value & 0x8000U) != 0U;
    const auto exponent = static_cast<unsigned int>((value >> 10U) & 0x1FU);
    const auto fraction = static_cast<unsigned int>(value & 0x03FFU);
    float result = 0.0F;
    if (exponent == 0U)
    {
        result = std::ldexp(static_cast<float>(fraction), -24);
    }
    else if (exponent == 31U)
    {
        result = fraction == 0U ? INFINITY : NAN;
    }
    else
    {
        result = std::ldexp(static_cast<float>(1024U + fraction), static_cast<int>(exponent) - 25);
    }
    return negative ? -result : result;
}

[[nodiscard]] std::uint8_t normalized_byte(const float value) noexcept
{
    return static_cast<std::uint8_t>(std::lround(std::clamp(value, 0.0F, 1.0F) * 255.0F));
}

} // namespace

namespace detail
{

TextureResult<std::vector<std::byte>> decode_uncompressed(const TextureFormat format,
                                                          const std::uint32_t width,
                                                          const std::uint32_t height,
                                                          const std::span<const std::byte> payload)
{
    const auto pixel_count = static_cast<std::size_t>(width) * height;
    std::vector<std::byte> output(pixel_count * 4U);
    for (std::size_t pixel = 0; pixel < pixel_count; ++pixel)
    {
        const auto output_offset = pixel * 4U;
        if (format == TextureFormat::rgba8)
        {
            const auto input_offset = pixel * 4U;
            output[output_offset] = payload[input_offset + 2U];
            output[output_offset + 1U] = payload[input_offset + 1U];
            output[output_offset + 2U] = payload[input_offset];
            output[output_offset + 3U] = payload[input_offset + 3U];
            continue;
        }
        if (format == TextureFormat::r32f)
        {
            const auto input_offset = pixel * 4U;
            const auto value = std::bit_cast<float>(read_u32(payload, input_offset));
            if (!std::isfinite(value))
            {
                return TextureResult<std::vector<std::byte>>::failure(
                    {.code = TextureErrorCode::non_finite_pixel,
                     .absolute_offset = input_offset,
                     .context = "qtx.r32f",
                     .read_error_code = std::nullopt});
            }
            const auto channel = normalized_byte(value);
            output[output_offset] = static_cast<std::byte>(channel);
            output[output_offset + 1U] = static_cast<std::byte>(channel);
            output[output_offset + 2U] = static_cast<std::byte>(channel);
            output[output_offset + 3U] = std::byte{0xFF};
            continue;
        }

        const auto input_offset = pixel * 8U;
        for (std::size_t channel = 0; channel < 4U; ++channel)
        {
            const float value = half_to_float(read_u16(payload, input_offset + (channel * 2U)));
            if (!std::isfinite(value))
            {
                return TextureResult<std::vector<std::byte>>::failure(
                    {.code = TextureErrorCode::non_finite_pixel,
                     .absolute_offset = input_offset + (channel * 2U),
                     .context = "qtx.rgba16f",
                     .read_error_code = std::nullopt});
            }
            output[output_offset + channel] = static_cast<std::byte>(normalized_byte(value));
        }
    }
    return TextureResult<std::vector<std::byte>>::success(std::move(output));
}

} // namespace detail

TextureResult<std::vector<std::byte>>
decode_mip_zero_rgba8(const QtxTextureView& texture, const std::span<const std::byte> payload)
{
    if (!detail::valid_qtx_texture_view(texture, payload) || texture.mips.empty() ||
        texture.mips.front().size > texture.consumed_payload_bytes)
    {
        return TextureResult<std::vector<std::byte>>::failure(
            {.code = TextureErrorCode::payload_size_mismatch,
             .context = "qtx.mip_zero",
             .read_error_code = std::nullopt});
    }
    const auto& mip = texture.mips.front();
    const auto bytes = payload.first(static_cast<std::size_t>(mip.size));
    if (texture.descriptor.format == TextureFormat::rgba8 ||
        texture.descriptor.format == TextureFormat::rgba16f ||
        texture.descriptor.format == TextureFormat::r32f)
    {
        return detail::decode_uncompressed(texture.descriptor.format, mip.width, mip.height, bytes);
    }
    return detail::decode_block_compressed(texture.descriptor.format, mip.width, mip.height, bytes);
}

} // namespace tmxy::texture
