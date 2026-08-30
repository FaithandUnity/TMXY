#include "texture_decode_internal.hpp"
#include "tmxy/texture/texture_export.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace tmxy::texture
{
namespace
{

constexpr std::uint32_t kDdsCaps = 0x00001000U;
constexpr std::uint32_t kDdsCapsComplex = 0x00000008U;
constexpr std::uint32_t kDdsCapsMipmap = 0x00400000U;
constexpr std::uint32_t kDdsPixelFourCc = 0x00000004U;
constexpr std::uint32_t kDdsPixelRgbAlpha = 0x00000041U;

void store_u32(std::vector<std::byte>& bytes, const std::size_t offset, const std::uint32_t value)
{
    bytes[offset] = static_cast<std::byte>(value & 0xFFU);
    bytes[offset + 1U] = static_cast<std::byte>((value >> 8U) & 0xFFU);
    bytes[offset + 2U] = static_cast<std::byte>((value >> 16U) & 0xFFU);
    bytes[offset + 3U] = static_cast<std::byte>((value >> 24U) & 0xFFU);
}

[[nodiscard]] constexpr std::uint32_t four_cc(const char a, const char b, const char c,
                                              const char d) noexcept
{
    return static_cast<std::uint32_t>(static_cast<unsigned char>(a)) |
           (static_cast<std::uint32_t>(static_cast<unsigned char>(b)) << 8U) |
           (static_cast<std::uint32_t>(static_cast<unsigned char>(c)) << 16U) |
           (static_cast<std::uint32_t>(static_cast<unsigned char>(d)) << 24U);
}

[[nodiscard]] bool is_compressed(const TextureFormat format) noexcept
{
    return format == TextureFormat::dxt1 || format == TextureFormat::dxt1a ||
           format == TextureFormat::dxt3 || format == TextureFormat::dxt5;
}

[[nodiscard]] bool uses_dx10(const TextureFormat format) noexcept
{
    return format == TextureFormat::rgba16f || format == TextureFormat::r32f;
}

[[nodiscard]] std::uint32_t dds_flags(const QtxTextureView& texture) noexcept
{
    std::uint32_t flags = is_compressed(texture.descriptor.format) ? 0x00081007U : 0x0000100FU;
    return texture.effective_mip_count > 1U ? flags | 0x00020000U : flags;
}

[[nodiscard]] std::uint32_t pitch_or_size(const QtxTextureView& texture) noexcept
{
    if (is_compressed(texture.descriptor.format))
    {
        return static_cast<std::uint32_t>(texture.mips.front().size);
    }
    const std::uint32_t bytes_per_pixel =
        texture.descriptor.format == TextureFormat::rgba16f ? 8U : 4U;
    return texture.descriptor.width * bytes_per_pixel;
}

[[nodiscard]] std::uint32_t compressed_four_cc(const TextureFormat format) noexcept
{
    switch (format)
    {
    case TextureFormat::dxt3:
        return four_cc('D', 'X', 'T', '3');
    case TextureFormat::dxt5:
        return four_cc('D', 'X', 'T', '5');
    default:
        return four_cc('D', 'X', 'T', '1');
    }
}

void write_pixel_format(std::vector<std::byte>& output, const TextureFormat format)
{
    if (format == TextureFormat::rgba8)
    {
        store_u32(output, 80U, kDdsPixelRgbAlpha);
        store_u32(output, 88U, 32U);
        store_u32(output, 92U, 0x00FF0000U);
        store_u32(output, 96U, 0x0000FF00U);
        store_u32(output, 100U, 0x000000FFU);
        store_u32(output, 104U, 0xFF000000U);
        return;
    }
    store_u32(output, 80U, kDdsPixelFourCc);
    store_u32(output, 84U,
              uses_dx10(format) ? four_cc('D', 'X', '1', '0') : compressed_four_cc(format));
}

void write_dx10_header(std::vector<std::byte>& output, const TextureFormat format)
{
    if (!uses_dx10(format))
    {
        return;
    }
    const bool has_alpha = format == TextureFormat::rgba16f;
    store_u32(output, 128U, has_alpha ? 10U : 41U);
    store_u32(output, 132U, 3U);
    store_u32(output, 140U, 1U);
    store_u32(output, 144U, has_alpha ? 1U : 3U);
}

} // namespace

TextureResult<std::vector<std::byte>> build_dds(const QtxTextureView& texture,
                                                const std::span<const std::byte> payload)
{
    if (!detail::valid_qtx_texture_view(texture, payload))
    {
        return TextureResult<std::vector<std::byte>>::failure(
            {.code = TextureErrorCode::payload_size_mismatch,
             .context = "dds.payload",
             .read_error_code = std::nullopt});
    }
    const bool dx10 = uses_dx10(texture.descriptor.format);
    std::vector<std::byte> output(dx10 ? 148U : 128U, std::byte{0});
    output[0] = std::byte{'D'};
    output[1] = std::byte{'D'};
    output[2] = std::byte{'S'};
    output[3] = std::byte{' '};
    store_u32(output, 4U, 124U);
    store_u32(output, 8U, dds_flags(texture));
    store_u32(output, 12U, texture.descriptor.height);
    store_u32(output, 16U, texture.descriptor.width);
    store_u32(output, 20U, pitch_or_size(texture));
    store_u32(output, 28U, texture.effective_mip_count);
    store_u32(output, 76U, 32U);

    write_pixel_format(output, texture.descriptor.format);

    std::uint32_t caps = kDdsCaps;
    if (texture.effective_mip_count > 1U)
    {
        caps |= kDdsCapsComplex | kDdsCapsMipmap;
    }
    store_u32(output, 108U, caps);
    write_dx10_header(output, texture.descriptor.format);
    const auto consumed = payload.first(static_cast<std::size_t>(texture.consumed_payload_bytes));
    output.insert(output.end(), consumed.begin(), consumed.end());
    return TextureResult<std::vector<std::byte>>::success(std::move(output));
}

} // namespace tmxy::texture
