#include "tmxy/texture/qtx_reader.hpp"
#include "tmxy/texture/texture_export.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace tmxy::texture
{

TextureResult<std::vector<std::byte>> build_tga(const QtxTextureView& texture,
                                                const std::span<const std::byte> payload)
{
    if (texture.descriptor.width > 65535U || texture.descriptor.height > 65535U)
    {
        return TextureResult<std::vector<std::byte>>::failure(
            {.code = TextureErrorCode::output_limit_exceeded,
             .context = "tga.dimensions",
             .read_error_code = std::nullopt});
    }
    auto rgba = decode_mip_zero_rgba8(texture, payload);
    if (!rgba.has_value())
    {
        return TextureResult<std::vector<std::byte>>::failure(rgba.error());
    }
    std::vector<std::byte> output(18U, std::byte{0});
    output[2] = std::byte{2};
    output[12] = static_cast<std::byte>(texture.descriptor.width & 0xFFU);
    output[13] = static_cast<std::byte>((texture.descriptor.width >> 8U) & 0xFFU);
    output[14] = static_cast<std::byte>(texture.descriptor.height & 0xFFU);
    output[15] = static_cast<std::byte>((texture.descriptor.height >> 8U) & 0xFFU);
    output[16] = std::byte{32};
    output[17] = std::byte{0x28};
    output.reserve(18U + rgba.value().size());
    for (std::size_t pixel = 0; pixel < rgba.value().size(); pixel += 4U)
    {
        output.push_back(rgba.value()[pixel + 2U]);
        output.push_back(rgba.value()[pixel + 1U]);
        output.push_back(rgba.value()[pixel]);
        output.push_back(rgba.value()[pixel + 3U]);
    }
    return TextureResult<std::vector<std::byte>>::success(std::move(output));
}

} // namespace tmxy::texture
