#include "tmxy/texture/qtx_reader.hpp"
#include "tmxy/texture/texture_export.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace tmxy::texture
{
namespace
{

void append_u32_be(std::vector<std::byte>& bytes, const std::uint32_t value)
{
    bytes.push_back(static_cast<std::byte>((value >> 24U) & 0xFFU));
    bytes.push_back(static_cast<std::byte>((value >> 16U) & 0xFFU));
    bytes.push_back(static_cast<std::byte>((value >> 8U) & 0xFFU));
    bytes.push_back(static_cast<std::byte>(value & 0xFFU));
}

[[nodiscard]] std::uint32_t crc32(const std::span<const std::byte> bytes) noexcept
{
    std::uint32_t crc = 0xFFFFFFFFU;
    for (const auto byte : bytes)
    {
        crc ^= std::to_integer<std::uint8_t>(byte);
        for (unsigned int bit = 0; bit < 8U; ++bit)
        {
            crc = (crc >> 1U) ^ ((crc & 1U) != 0U ? 0xEDB88320U : 0U);
        }
    }
    return ~crc;
}

[[nodiscard]] std::uint32_t adler32(const std::span<const std::byte> bytes) noexcept
{
    constexpr std::uint32_t modulus = 65521U;
    std::uint32_t first = 1U;
    std::uint32_t second = 0U;
    for (const auto byte : bytes)
    {
        first = (first + std::to_integer<std::uint8_t>(byte)) % modulus;
        second = (second + first) % modulus;
    }
    return (second << 16U) | first;
}

void append_stored_zlib(std::vector<std::byte>& output, const std::span<const std::byte> raw)
{
    output.push_back(std::byte{0x78});
    output.push_back(std::byte{0x01});
    std::size_t offset = 0;
    while (offset < raw.size())
    {
        const auto remaining = raw.size() - offset;
        const auto count = std::min<std::size_t>(remaining, 65535U);
        const bool final = offset + count == raw.size();
        output.push_back(final ? std::byte{0x01} : std::byte{0x00});
        const auto length = static_cast<std::uint16_t>(count);
        const auto inverse = static_cast<std::uint16_t>(~length);
        output.push_back(static_cast<std::byte>(length & 0xFFU));
        output.push_back(static_cast<std::byte>((length >> 8U) & 0xFFU));
        output.push_back(static_cast<std::byte>(inverse & 0xFFU));
        output.push_back(static_cast<std::byte>((inverse >> 8U) & 0xFFU));
        output.insert(output.end(), raw.begin() + static_cast<std::ptrdiff_t>(offset),
                      raw.begin() + static_cast<std::ptrdiff_t>(offset + count));
        offset += count;
    }
    append_u32_be(output, adler32(raw));
}

void append_chunk(std::vector<std::byte>& output, const std::array<std::byte, 4>& type,
                  const std::span<const std::byte> data)
{
    append_u32_be(output, static_cast<std::uint32_t>(data.size()));
    const auto crc_start = output.size();
    output.insert(output.end(), type.begin(), type.end());
    output.insert(output.end(), data.begin(), data.end());
    append_u32_be(output, crc32(std::span<const std::byte>(output).subspan(crc_start)));
}

} // namespace

TextureResult<std::vector<std::byte>> build_png(const QtxTextureView& texture,
                                                const std::span<const std::byte> payload)
{
    auto rgba = decode_mip_zero_rgba8(texture, payload);
    if (!rgba.has_value())
    {
        return TextureResult<std::vector<std::byte>>::failure(rgba.error());
    }
    const auto row_bytes = static_cast<std::size_t>(texture.descriptor.width) * 4U;
    std::vector<std::byte> scanlines;
    scanlines.reserve((row_bytes + 1U) * texture.descriptor.height);
    for (std::uint32_t row = 0; row < texture.descriptor.height; ++row)
    {
        scanlines.push_back(std::byte{0});
        const auto begin = rgba.value().begin() + static_cast<std::ptrdiff_t>(row * row_bytes);
        scanlines.insert(scanlines.end(), begin, begin + static_cast<std::ptrdiff_t>(row_bytes));
    }
    std::vector<std::byte> zlib;
    zlib.reserve(scanlines.size() + ((scanlines.size() / 65535U) * 5U) + 11U);
    append_stored_zlib(zlib, scanlines);

    std::vector<std::byte> output{std::byte{0x89}, std::byte{'P'},  std::byte{'N'},
                                  std::byte{'G'},  std::byte{0x0D}, std::byte{0x0A},
                                  std::byte{0x1A}, std::byte{0x0A}};
    std::vector<std::byte> header;
    append_u32_be(header, texture.descriptor.width);
    append_u32_be(header, texture.descriptor.height);
    header.insert(header.end(),
                  {std::byte{8}, std::byte{6}, std::byte{0}, std::byte{0}, std::byte{0}});
    append_chunk(output, {std::byte{'I'}, std::byte{'H'}, std::byte{'D'}, std::byte{'R'}}, header);
    append_chunk(output, {std::byte{'I'}, std::byte{'D'}, std::byte{'A'}, std::byte{'T'}}, zlib);
    append_chunk(output, {std::byte{'I'}, std::byte{'E'}, std::byte{'N'}, std::byte{'D'}}, {});
    return TextureResult<std::vector<std::byte>>::success(std::move(output));
}

} // namespace tmxy::texture
