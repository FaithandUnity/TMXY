#include "texture_decode_internal.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace tmxy::texture::detail
{
namespace
{

struct Rgba final
{
    std::uint8_t r{0};
    std::uint8_t g{0};
    std::uint8_t b{0};
    std::uint8_t a{255};
};

[[nodiscard]] std::uint8_t byte_at(const std::span<const std::byte> bytes,
                                   const std::size_t index) noexcept
{
    return std::to_integer<std::uint8_t>(bytes[index]);
}

[[nodiscard]] std::uint16_t read_u16(const std::span<const std::byte> bytes,
                                     const std::size_t offset) noexcept
{
    return static_cast<std::uint16_t>(byte_at(bytes, offset)) |
           static_cast<std::uint16_t>(static_cast<std::uint16_t>(byte_at(bytes, offset + 1U))
                                      << 8U);
}

[[nodiscard]] std::uint32_t read_u32(const std::span<const std::byte> bytes,
                                     const std::size_t offset) noexcept
{
    return static_cast<std::uint32_t>(byte_at(bytes, offset)) |
           (static_cast<std::uint32_t>(byte_at(bytes, offset + 1U)) << 8U) |
           (static_cast<std::uint32_t>(byte_at(bytes, offset + 2U)) << 16U) |
           (static_cast<std::uint32_t>(byte_at(bytes, offset + 3U)) << 24U);
}

[[nodiscard]] Rgba decode_565(const std::uint16_t value) noexcept
{
    const auto red = static_cast<std::uint8_t>((value >> 11U) & 31U);
    const auto green = static_cast<std::uint8_t>((value >> 5U) & 63U);
    const auto blue = static_cast<std::uint8_t>(value & 31U);
    return {.r = static_cast<std::uint8_t>((static_cast<unsigned int>(red) * 255U + 15U) / 31U),
            .g = static_cast<std::uint8_t>((static_cast<unsigned int>(green) * 255U + 31U) / 63U),
            .b = static_cast<std::uint8_t>((static_cast<unsigned int>(blue) * 255U + 15U) / 31U),
            .a = 255U};
}

[[nodiscard]] Rgba interpolate(const Rgba left, const Rgba right, const unsigned int left_weight,
                               const unsigned int right_weight,
                               const unsigned int denominator) noexcept
{
    return {.r = static_cast<std::uint8_t>((left_weight * left.r + right_weight * right.r) /
                                           denominator),
            .g = static_cast<std::uint8_t>((left_weight * left.g + right_weight * right.g) /
                                           denominator),
            .b = static_cast<std::uint8_t>((left_weight * left.b + right_weight * right.b) /
                                           denominator),
            .a = 255U};
}

[[nodiscard]] std::array<Rgba, 4> color_palette(const std::span<const std::byte> block,
                                                const bool allow_transparency,
                                                const bool force_four_color) noexcept
{
    const auto color0 = read_u16(block, 0U);
    const auto color1 = read_u16(block, 2U);
    std::array<Rgba, 4> colors{};
    colors[0] = decode_565(color0);
    colors[1] = decode_565(color1);
    if (force_four_color || color0 > color1)
    {
        colors[2] = interpolate(colors[0], colors[1], 2U, 1U, 3U);
        colors[3] = interpolate(colors[0], colors[1], 1U, 2U, 3U);
    }
    else
    {
        colors[2] = interpolate(colors[0], colors[1], 1U, 1U, 2U);
        colors[3] = {.r = 0U,
                     .g = 0U,
                     .b = 0U,
                     .a = static_cast<std::uint8_t>(allow_transparency ? 0U : 255U)};
    }
    return colors;
}

void store_pixel(std::vector<std::byte>& output, const std::uint32_t width,
                 const std::uint32_t height, const std::uint32_t x, const std::uint32_t y,
                 const Rgba color)
{
    if (x >= width || y >= height)
    {
        return;
    }
    const auto index = (static_cast<std::size_t>(y) * width + x) * 4U;
    output[index] = static_cast<std::byte>(color.r);
    output[index + 1U] = static_cast<std::byte>(color.g);
    output[index + 2U] = static_cast<std::byte>(color.b);
    output[index + 3U] = static_cast<std::byte>(color.a);
}

[[nodiscard]] std::array<std::uint8_t, 8>
dxt5_alpha_palette(const std::span<const std::byte> block) noexcept
{
    std::array<std::uint8_t, 8> alpha{};
    alpha[0] = byte_at(block, 0U);
    alpha[1] = byte_at(block, 1U);
    if (alpha[0] > alpha[1])
    {
        for (unsigned int index = 2U; index < 8U; ++index)
        {
            alpha[index] =
                static_cast<std::uint8_t>(((8U - index) * alpha[0] + (index - 1U) * alpha[1]) / 7U);
        }
    }
    else
    {
        for (unsigned int index = 2U; index < 6U; ++index)
        {
            alpha[index] =
                static_cast<std::uint8_t>(((6U - index) * alpha[0] + (index - 1U) * alpha[1]) / 5U);
        }
        alpha[6] = 0U;
        alpha[7] = 255U;
    }
    return alpha;
}

void decode_color_block(const TextureFormat format, const std::span<const std::byte> block,
                        const std::uint32_t block_x, const std::uint32_t block_y,
                        const std::uint32_t width, const std::uint32_t height,
                        std::vector<std::byte>& output)
{
    const bool is_dxt1 = format == TextureFormat::dxt1 || format == TextureFormat::dxt1a;
    const bool allow_transparency = format == TextureFormat::dxt1a;
    const std::size_t color_offset = is_dxt1 ? 0U : 8U;
    const auto color_bytes = block.subspan(color_offset, 8U);
    const auto colors = color_palette(color_bytes, allow_transparency, !is_dxt1);
    const auto color_indices = read_u32(color_bytes, 4U);
    const auto dxt5_alpha =
        format == TextureFormat::dxt5 ? dxt5_alpha_palette(block) : std::array<std::uint8_t, 8>{};
    std::uint64_t dxt5_indices = 0;
    if (format == TextureFormat::dxt5)
    {
        for (std::size_t index = 0; index < 6U; ++index)
        {
            dxt5_indices |= static_cast<std::uint64_t>(byte_at(block, 2U + index)) << (index * 8U);
        }
    }

    for (std::uint32_t pixel = 0; pixel < 16U; ++pixel)
    {
        Rgba color = colors[(color_indices >> (pixel * 2U)) & 3U];
        if (format == TextureFormat::dxt3)
        {
            const auto alpha_bits = read_u16(block, static_cast<std::size_t>(pixel / 4U) * 2U);
            color.a = static_cast<std::uint8_t>(((alpha_bits >> ((pixel % 4U) * 4U)) & 15U) * 17U);
        }
        else if (format == TextureFormat::dxt5)
        {
            color.a = dxt5_alpha[(dxt5_indices >> (pixel * 3U)) & 7U];
        }
        store_pixel(output, width, height, (block_x * 4U) + (pixel % 4U),
                    (block_y * 4U) + (pixel / 4U), color);
    }
}

} // namespace

TextureResult<std::vector<std::byte>>
decode_block_compressed(const TextureFormat format, const std::uint32_t width,
                        const std::uint32_t height, const std::span<const std::byte> payload)
{
    const std::size_t block_bytes =
        format == TextureFormat::dxt1 || format == TextureFormat::dxt1a ? 8U : 16U;
    const std::uint32_t blocks_wide = (width + 3U) / 4U;
    const std::uint32_t blocks_high = (height + 3U) / 4U;
    std::vector<std::byte> output(static_cast<std::size_t>(width) * height * 4U);
    std::size_t offset = 0;
    for (std::uint32_t y = 0; y < blocks_high; ++y)
    {
        for (std::uint32_t x = 0; x < blocks_wide; ++x)
        {
            decode_color_block(format, payload.subspan(offset, block_bytes), x, y, width, height,
                               output);
            offset += block_bytes;
        }
    }
    return TextureResult<std::vector<std::byte>>::success(std::move(output));
}

} // namespace tmxy::texture::detail
