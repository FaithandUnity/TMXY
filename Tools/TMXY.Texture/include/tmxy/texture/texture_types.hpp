#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace tmxy::texture
{

enum class TextureFormat : std::uint8_t
{
    rgba8 = 0,
    rgba16f = 1,
    r32f = 2,
    dxt1 = 3,
    dxt1a = 4,
    dxt3 = 5,
    dxt5 = 6,
};

enum class ClampMode : std::uint8_t
{
    wrap = 0,
    clamp = 1,
};

enum class AlphaEncoding : std::uint8_t
{
    none = 0,
    straight_8 = 1,
    straight_16f = 2,
    binary_1bit = 3,
    explicit_4bit = 4,
    interpolated_8bit = 5,
};

enum class AlphaCoverage : std::uint8_t
{
    opaque = 0,
    transparent = 1,
    binary_mask = 2,
    translucent = 3,
};

enum class MipCountBasis : std::uint8_t
{
    package_descriptor = 0,
    payload_complete_chain_contract = 1,
    unknown = 255,
};

enum class PayloadExtentBasis : std::uint8_t
{
    complete_input_payload = 0,
    declared_mip_payload_prefix_contract = 1,
    unknown = 255,
};

struct UnknownTextureProperty final
{
    std::string name_bytes;
    std::uint64_t value_offset{0};
    std::vector<std::byte> value;
};

struct TextureDescriptor final
{
    TextureFormat format{TextureFormat::rgba8};
    ClampMode u_clamp{ClampMode::wrap};
    ClampMode v_clamp{ClampMode::wrap};
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stored_mip_count{0};
    std::uint32_t mip_count{1};
    std::vector<UnknownTextureProperty> unknown_properties;
};

struct TextureMip final
{
    std::uint32_t level{0};
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint64_t offset{0};
    std::uint64_t size{0};
};

struct QtxTextureView final
{
    TextureDescriptor descriptor;
    std::vector<TextureMip> mips;
    AlphaEncoding alpha_encoding{AlphaEncoding::none};
    AlphaCoverage alpha_coverage{AlphaCoverage::opaque};
    std::uint32_t effective_mip_count{0};
    MipCountBasis mip_count_basis{MipCountBasis::package_descriptor};
    std::uint64_t payload_size{0};
    std::uint64_t input_payload_bytes{0};
    std::uint64_t consumed_payload_bytes{0};
    std::uint64_t ignored_payload_bytes{0};
    PayloadExtentBasis payload_extent_basis{PayloadExtentBasis::complete_input_payload};
};

[[nodiscard]] const char* to_string(TextureFormat value) noexcept;
[[nodiscard]] const char* to_string(ClampMode value) noexcept;
[[nodiscard]] const char* to_string(AlphaEncoding value) noexcept;
[[nodiscard]] const char* to_string(AlphaCoverage value) noexcept;
[[nodiscard]] const char* to_string(MipCountBasis value) noexcept;
[[nodiscard]] const char* to_string(PayloadExtentBasis value) noexcept;

} // namespace tmxy::texture
