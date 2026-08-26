#include "tmxy/package/package_directory_codec.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace tmxy::package
{

namespace
{

[[nodiscard]] std::byte invert_byte(const std::byte value) noexcept
{
    return static_cast<std::byte>(static_cast<std::uint8_t>(~std::to_integer<std::uint8_t>(value)));
}

void decode_v2_group(const std::span<const std::byte, 4> encoded,
                     const std::span<std::byte, 4> decoded) noexcept
{
    decoded[0] = invert_byte(encoded[2]);
    decoded[1] = invert_byte(encoded[3]);
    decoded[2] = invert_byte(encoded[0]);
    decoded[3] = invert_byte(encoded[1]);
}

void decode_v3_group(const std::span<const std::byte, 4> encoded,
                     const std::span<std::byte, 4> decoded) noexcept
{
    decoded[0] = invert_byte(encoded[2]);
    decoded[1] = invert_byte(encoded[3]);
    decoded[2] = encoded[0];
    decoded[3] = invert_byte(encoded[1]);
}

void decode_v3_tail(const std::span<const std::byte> encoded, const std::span<std::byte> decoded)
{
    if (encoded.size() == 1U)
    {
        decoded[0] = encoded[0];
    }
    else if (encoded.size() == 2U)
    {
        decoded[0] = encoded[0];
        decoded[1] = invert_byte(encoded[1]);
    }
    else if (encoded.size() == 3U)
    {
        decoded[0] = invert_byte(encoded[2]);
        decoded[1] = encoded[0];
        decoded[2] = invert_byte(encoded[1]);
    }
}

void encode_v3_group(const std::span<const std::byte, 4> decoded,
                     const std::span<std::byte, 4> encoded) noexcept
{
    encoded[0] = decoded[2];
    encoded[1] = invert_byte(decoded[3]);
    encoded[2] = invert_byte(decoded[0]);
    encoded[3] = invert_byte(decoded[1]);
}

void encode_v3_tail(const std::span<const std::byte> decoded, const std::span<std::byte> encoded)
{
    if (decoded.size() == 1U)
    {
        encoded[0] = decoded[0];
    }
    else if (decoded.size() == 2U)
    {
        encoded[0] = decoded[0];
        encoded[1] = invert_byte(decoded[1]);
    }
    else if (decoded.size() == 3U)
    {
        encoded[0] = decoded[1];
        encoded[1] = invert_byte(decoded[2]);
        encoded[2] = invert_byte(decoded[0]);
    }
}

template <typename Transform>
void transform_full_groups(const std::span<const std::byte> input,
                           const std::span<std::byte> output, Transform transform)
{
    const auto full_bytes = input.size() - (input.size() % 4U);
    for (std::size_t offset = 0; offset < full_bytes; offset += 4U)
    {
        transform(std::span<const std::byte, 4>{input.data() + offset, 4},
                  std::span<std::byte, 4>{output.data() + offset, 4});
    }
}

struct TailOffset final
{
    std::size_t remainder{0};
    std::size_t decoded_offset{0};
};

[[nodiscard]] std::size_t map_v3_tail_offset(const TailOffset offset) noexcept
{
    if (offset.remainder == 3U)
    {
        constexpr std::array<std::size_t, 3> kEncodedOffsets{2U, 0U, 1U};
        return kEncodedOffsets[offset.decoded_offset];
    }
    return offset.decoded_offset;
}

} // namespace

std::vector<std::byte> decode_package_directory(const PackageDirectoryVersion version,
                                                const std::span<const std::byte> encoded_directory)
{
    std::vector<std::byte> decoded(encoded_directory.size());
    const auto decoded_span = std::span<std::byte>(decoded);
    const auto full_bytes = encoded_directory.size() - (encoded_directory.size() % 4U);
    if (version == PackageDirectoryVersion::v2)
    {
        transform_full_groups(encoded_directory, decoded_span, decode_v2_group);
        for (std::size_t offset = full_bytes; offset < encoded_directory.size(); ++offset)
        {
            decoded[offset] = invert_byte(encoded_directory[offset]);
        }
    }
    else
    {
        transform_full_groups(encoded_directory, decoded_span, decode_v3_group);
        decode_v3_tail(encoded_directory.subspan(full_bytes), decoded_span.subspan(full_bytes));
    }
    return decoded;
}

std::vector<std::byte> encode_package_directory(const PackageDirectoryVersion version,
                                                const std::span<const std::byte> decoded_directory)
{
    if (version == PackageDirectoryVersion::v2)
    {
        return decode_package_directory(version, decoded_directory);
    }
    std::vector<std::byte> encoded(decoded_directory.size());
    const auto encoded_span = std::span<std::byte>(encoded);
    const auto full_bytes = decoded_directory.size() - (decoded_directory.size() % 4U);
    transform_full_groups(decoded_directory, encoded_span, encode_v3_group);
    encode_v3_tail(decoded_directory.subspan(full_bytes), encoded_span.subspan(full_bytes));
    return encoded;
}

std::uint64_t map_package_directory_offset(const PackageDirectoryOffset offset) noexcept
{
    if (offset.decoded_offset >= offset.directory_size)
    {
        return offset.file_offset + static_cast<std::uint64_t>(offset.directory_size);
    }
    const auto decoded = static_cast<std::size_t>(offset.decoded_offset);
    const auto remainder = offset.directory_size % 4U;
    const auto full_bytes = offset.directory_size - remainder;
    if (decoded >= full_bytes)
    {
        const auto tail_offset = decoded - full_bytes;
        const auto encoded_tail_offset = offset.version == PackageDirectoryVersion::v3
                                             ? map_v3_tail_offset({
                                                   .remainder = remainder,
                                                   .decoded_offset = tail_offset,
                                               })
                                             : tail_offset;
        return offset.file_offset + static_cast<std::uint64_t>(full_bytes + encoded_tail_offset);
    }
    const auto group = decoded - (decoded % 4U);
    const auto encoded_in_group = ((decoded % 4U) + 2U) % 4U;
    return offset.file_offset + static_cast<std::uint64_t>(group + encoded_in_group);
}

} // namespace tmxy::package
