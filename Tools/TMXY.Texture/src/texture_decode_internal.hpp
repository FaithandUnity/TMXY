#pragma once

#include "tmxy/texture/texture_result.hpp"
#include "tmxy/texture/texture_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace tmxy::texture::detail
{

[[nodiscard]] bool valid_qtx_texture_view(const QtxTextureView& texture,
                                          std::span<const std::byte> payload);

[[nodiscard]] TextureResult<std::vector<std::byte>>
decode_block_compressed(TextureFormat format, std::uint32_t width, std::uint32_t height,
                        std::span<const std::byte> payload);

[[nodiscard]] TextureResult<std::vector<std::byte>>
decode_uncompressed(TextureFormat format, std::uint32_t width, std::uint32_t height,
                    std::span<const std::byte> payload);

} // namespace tmxy::texture::detail
