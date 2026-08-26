#pragma once

#include "tmxy/texture/texture_result.hpp"
#include "tmxy/texture/texture_types.hpp"

#include <cstddef>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::texture
{

struct TextureJsonNames final
{
    std::string_view object_name;
    std::string_view dds_name;
    std::string_view png_name;
    std::string_view tga_name;
};

[[nodiscard]] TextureResult<std::vector<std::byte>> build_dds(const QtxTextureView& texture,
                                                              std::span<const std::byte> payload);

[[nodiscard]] TextureResult<std::vector<std::byte>> build_png(const QtxTextureView& texture,
                                                              std::span<const std::byte> payload);

[[nodiscard]] TextureResult<std::vector<std::byte>> build_tga(const QtxTextureView& texture,
                                                              std::span<const std::byte> payload);

[[nodiscard]] std::string build_texture_json(const QtxTextureView& texture, TextureJsonNames names);

[[nodiscard]] std::uint64_t texture_bytes_fingerprint(std::span<const std::byte> bytes) noexcept;

} // namespace tmxy::texture
