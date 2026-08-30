#include "tmxy/texture/qtx_reader.hpp"

#include "texture_decode_internal.hpp"

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

[[nodiscard]] bool is_known_format(const TextureFormat format) noexcept
{
    switch (format)
    {
    case TextureFormat::rgba8:
    case TextureFormat::rgba16f:
    case TextureFormat::r32f:
    case TextureFormat::dxt1:
    case TextureFormat::dxt1a:
    case TextureFormat::dxt3:
    case TextureFormat::dxt5:
        return true;
    }
    return false;
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

[[nodiscard]] std::uint32_t maximum_natural_mips(std::uint32_t width, std::uint32_t height) noexcept
{
    std::uint32_t count = 1U;
    while (width > 1U || height > 1U)
    {
        width = std::max(1U, width / 2U);
        height = std::max(1U, height / 2U);
        ++count;
    }
    return count;
}

[[nodiscard]] TextureResult<std::uint32_t>
infer_complete_payload_mip_count_impl(const TextureDescriptor& descriptor,
                                      const std::span<const std::byte> payload)
{
    std::uint32_t width = descriptor.width;
    std::uint32_t height = descriptor.height;
    std::uint64_t cumulative = 0U;
    const auto maximum = maximum_natural_mips(width, height);
    for (std::uint32_t level = 0U; level < maximum; ++level)
    {
        auto size = mip_size(descriptor.format, width, height);
        if (!size.has_value())
        {
            return TextureResult<std::uint32_t>::failure(size.error());
        }
        if (size.value() > std::numeric_limits<std::uint64_t>::max() - cumulative)
        {
            return TextureResult<std::uint32_t>::failure(
                {.code = TextureErrorCode::mip_size_overflow,
                 .context = "qtx.mip.range",
                 .read_error_code = std::nullopt});
        }
        cumulative += size.value();
        if (cumulative == payload.size())
        {
            return TextureResult<std::uint32_t>::success(level + 1U);
        }
        if (cumulative > payload.size())
        {
            break;
        }
        width = std::max(1U, width / 2U);
        height = std::max(1U, height / 2U);
    }
    return TextureResult<std::uint32_t>::failure(
        {.code = TextureErrorCode::payload_size_mismatch,
         .absolute_offset = std::min<std::uint64_t>(cumulative, payload.size()),
         .context = "qtx.payload_size",
         .read_error_code = std::nullopt});
}

[[nodiscard]] TextureResult<bool>
validate_mip_count_resolution(const TextureDescriptor& descriptor,
                              const std::span<const std::byte> payload,
                              const QtxMipCountResolution resolution)
{
    if (resolution.effective_mip_count == 0U)
    {
        return TextureResult<bool>::failure({.code = TextureErrorCode::invalid_mip_count,
                                             .context = "qtx.effective_mip_count",
                                             .read_error_code = std::nullopt});
    }
    if (resolution.basis == MipCountBasis::package_descriptor)
    {
        if (resolution.effective_mip_count != descriptor.mip_count)
        {
            return TextureResult<bool>::failure({.code = TextureErrorCode::invalid_mip_count,
                                                 .context = "qtx.effective_mip_count",
                                                 .read_error_code = std::nullopt});
        }
    }
    else if (resolution.basis == MipCountBasis::payload_complete_chain_contract)
    {
        if (descriptor.stored_mip_count == 0U ||
            descriptor.stored_mip_count != descriptor.mip_count)
        {
            return TextureResult<bool>::failure({.code = TextureErrorCode::invalid_mip_count,
                                                 .context = "qtx.declared_mip_count",
                                                 .read_error_code = std::nullopt});
        }
        auto inferred = infer_complete_payload_mip_count_impl(descriptor, payload);
        if (!inferred.has_value())
        {
            return TextureResult<bool>::failure(inferred.error());
        }
        if (resolution.effective_mip_count >= descriptor.mip_count ||
            resolution.effective_mip_count != inferred.value())
        {
            return TextureResult<bool>::failure({.code = TextureErrorCode::invalid_mip_count,
                                                 .context = "qtx.effective_mip_count",
                                                 .read_error_code = std::nullopt});
        }
    }
    else
    {
        return TextureResult<bool>::failure({.code = TextureErrorCode::invalid_mip_count,
                                             .context = "qtx.mip_count_basis",
                                             .read_error_code = std::nullopt});
    }
    return TextureResult<bool>::success(true);
}

[[nodiscard]] TextureResult<bool> validate_payload_extent(
    const TextureDescriptor& descriptor, const std::span<const std::byte> payload,
    const QtxMipCountResolution resolution, const PayloadExtentBasis payload_extent_basis)
{
    if (payload_extent_basis == PayloadExtentBasis::complete_input_payload)
    {
        return TextureResult<bool>::success(true);
    }
    if (payload_extent_basis != PayloadExtentBasis::declared_mip_payload_prefix_contract)
    {
        return TextureResult<bool>::failure({.code = TextureErrorCode::payload_size_mismatch,
                                             .context = "qtx.payload_extent_basis",
                                             .read_error_code = std::nullopt});
    }
    if (!is_known_format(descriptor.format))
    {
        return TextureResult<bool>::failure({.code = TextureErrorCode::invalid_format,
                                             .context = "qtx.format",
                                             .read_error_code = std::nullopt});
    }
    if (resolution.basis != MipCountBasis::package_descriptor ||
        descriptor.stored_mip_count == 0U || descriptor.stored_mip_count != descriptor.mip_count)
    {
        return TextureResult<bool>::failure({.code = TextureErrorCode::invalid_mip_count,
                                             .context = "qtx.declared_mip_count",
                                             .read_error_code = std::nullopt});
    }
    auto inferred = infer_complete_payload_mip_count_impl(descriptor, payload);
    if (!inferred.has_value())
    {
        return TextureResult<bool>::failure(inferred.error());
    }
    if (inferred.value() <= descriptor.mip_count)
    {
        return TextureResult<bool>::failure({.code = TextureErrorCode::payload_size_mismatch,
                                             .absolute_offset = payload.size(),
                                             .context = "qtx.payload_prefix_extent",
                                             .read_error_code = std::nullopt});
    }
    return TextureResult<bool>::success(true);
}

[[nodiscard]] bool canonical_mip_extent(const QtxTextureView& texture, std::uint64_t& extent)
{
    if (texture.effective_mip_count >
        maximum_natural_mips(texture.descriptor.width, texture.descriptor.height))
    {
        return false;
    }
    std::uint32_t width = texture.descriptor.width;
    std::uint32_t height = texture.descriptor.height;
    std::uint64_t offset = 0U;
    for (std::uint32_t level = 0U; level < texture.effective_mip_count; ++level)
    {
        const auto size = mip_size(texture.descriptor.format, width, height);
        if (!size.has_value() || size.value() > std::numeric_limits<std::uint64_t>::max() - offset)
        {
            return false;
        }
        const auto& mip = texture.mips[level];
        if (mip.level != level || mip.width != width || mip.height != height ||
            mip.offset != offset || mip.size != size.value())
        {
            return false;
        }
        offset += size.value();
        width = std::max(1U, width / 2U);
        height = std::max(1U, height / 2U);
    }
    extent = offset;
    return true;
}

} // namespace

namespace detail
{

bool valid_qtx_texture_view(const QtxTextureView& texture, const std::span<const std::byte> payload)
{
    const auto input_bytes = static_cast<std::uint64_t>(payload.size());
    if (!is_known_format(texture.descriptor.format) || texture.descriptor.width == 0U ||
        texture.descriptor.height == 0U || texture.effective_mip_count == 0U ||
        texture.payload_size != texture.input_payload_bytes ||
        texture.input_payload_bytes != input_bytes || texture.mips.empty() ||
        texture.mips.size() != texture.effective_mip_count ||
        texture.consumed_payload_bytes > texture.input_payload_bytes ||
        texture.ignored_payload_bytes !=
            texture.input_payload_bytes - texture.consumed_payload_bytes)
    {
        return false;
    }

    const bool package_mips = texture.mip_count_basis == MipCountBasis::package_descriptor;
    const bool recovered_mips =
        texture.mip_count_basis == MipCountBasis::payload_complete_chain_contract;
    const bool declared_mips_consistent =
        texture.descriptor.stored_mip_count == 0U
            ? texture.descriptor.mip_count == 1U
            : texture.descriptor.stored_mip_count == texture.descriptor.mip_count;
    if (!declared_mips_consistent || (!package_mips && !recovered_mips) ||
        (package_mips && texture.effective_mip_count != texture.descriptor.mip_count) ||
        (recovered_mips && (texture.descriptor.stored_mip_count == 0U ||
                            texture.descriptor.stored_mip_count != texture.descriptor.mip_count ||
                            texture.effective_mip_count >= texture.descriptor.mip_count)))
    {
        return false;
    }

    std::uint64_t declared_extent = 0U;
    if (!canonical_mip_extent(texture, declared_extent) ||
        texture.consumed_payload_bytes != declared_extent)
    {
        return false;
    }

    if (texture.payload_extent_basis == PayloadExtentBasis::complete_input_payload)
    {
        if (texture.consumed_payload_bytes != input_bytes || texture.ignored_payload_bytes != 0U)
        {
            return false;
        }
        const auto inferred = infer_complete_payload_mip_count_impl(texture.descriptor, payload);
        return package_mips ||
               (inferred.has_value() && inferred.value() == texture.effective_mip_count);
    }
    if (texture.payload_extent_basis != PayloadExtentBasis::declared_mip_payload_prefix_contract ||
        !package_mips || texture.descriptor.stored_mip_count == 0U ||
        texture.descriptor.stored_mip_count != texture.descriptor.mip_count ||
        texture.consumed_payload_bytes >= input_bytes)
    {
        return false;
    }
    const auto inferred = infer_complete_payload_mip_count_impl(texture.descriptor, payload);
    return inferred.has_value() && inferred.value() > texture.descriptor.mip_count;
}

} // namespace detail

QtxReader::QtxReader(const QtxLimits limits) : limits_(limits) {}

TextureResult<QtxTextureView> QtxReader::parse(TextureDescriptor descriptor,
                                               const std::span<const std::byte> payload) const
{
    const auto declared_mip_count = descriptor.mip_count;
    return parse_with_mip_count_resolution(
        std::move(descriptor), payload,
        {.effective_mip_count = declared_mip_count, .basis = MipCountBasis::package_descriptor});
}

TextureResult<std::uint32_t>
infer_complete_payload_mip_count(const TextureDescriptor& descriptor,
                                 const std::span<const std::byte> payload)
{
    return infer_complete_payload_mip_count_impl(descriptor, payload);
}

TextureResult<QtxTextureView>
QtxReader::parse_with_mip_count_resolution(TextureDescriptor descriptor,
                                           const std::span<const std::byte> payload,
                                           const QtxMipCountResolution resolution) const
{
    return parse_with_resolutions(std::move(descriptor), payload, resolution,
                                  PayloadExtentBasis::complete_input_payload);
}

TextureResult<QtxTextureView>
QtxReader::parse_with_declared_mip_payload_prefix(TextureDescriptor descriptor,
                                                  const std::span<const std::byte> payload) const
{
    const auto declared_mip_count = descriptor.mip_count;
    return parse_with_resolutions(
        std::move(descriptor), payload,
        {.effective_mip_count = declared_mip_count, .basis = MipCountBasis::package_descriptor},
        PayloadExtentBasis::declared_mip_payload_prefix_contract);
}

TextureResult<QtxTextureView> QtxReader::parse_with_resolutions(
    TextureDescriptor descriptor, const std::span<const std::byte> payload,
    const QtxMipCountResolution resolution, const PayloadExtentBasis payload_extent_basis) const
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

    auto mip_validation = validate_mip_count_resolution(descriptor, payload, resolution);
    if (!mip_validation.has_value())
    {
        return TextureResult<QtxTextureView>::failure(mip_validation.error());
    }
    auto extent_validation =
        validate_payload_extent(descriptor, payload, resolution, payload_extent_basis);
    if (!extent_validation.has_value())
    {
        return TextureResult<QtxTextureView>::failure(extent_validation.error());
    }

    QtxTextureView texture;
    texture.descriptor = std::move(descriptor);
    texture.alpha_encoding = alpha_encoding(texture.descriptor.format);
    texture.payload_size = payload.size();
    texture.input_payload_bytes = payload.size();
    texture.effective_mip_count = resolution.effective_mip_count;
    texture.mip_count_basis = resolution.basis;
    texture.payload_extent_basis = payload_extent_basis;
    std::uint32_t width = texture.descriptor.width;
    std::uint32_t height = texture.descriptor.height;
    std::uint64_t offset = 0;
    for (std::uint32_t level = 0; level < texture.effective_mip_count; ++level)
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
    const bool complete_input = payload_extent_basis == PayloadExtentBasis::complete_input_payload;
    if ((complete_input && offset != payload.size()) ||
        (!complete_input && offset >= payload.size()))
    {
        return TextureResult<QtxTextureView>::failure(
            {.code = TextureErrorCode::payload_size_mismatch,
             .absolute_offset = std::min<std::uint64_t>(offset, payload.size()),
             .context = "qtx.payload_size",
             .read_error_code = std::nullopt});
    }
    texture.consumed_payload_bytes = complete_input ? payload.size() : offset;
    texture.ignored_payload_bytes = payload.size() - texture.consumed_payload_bytes;
    auto decoded = decode_mip_zero_rgba8(texture, payload);
    if (!decoded.has_value())
    {
        return TextureResult<QtxTextureView>::failure(decoded.error());
    }
    texture.alpha_coverage = classify_alpha(decoded.value());
    return TextureResult<QtxTextureView>::success(std::move(texture));
}

} // namespace tmxy::texture
