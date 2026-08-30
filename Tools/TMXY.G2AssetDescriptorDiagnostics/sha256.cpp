#include "sha256.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cstdint>
#include <limits>
#include <stdexcept>

namespace tmxy::g2_asset_descriptor_diagnostics
{
namespace
{

constexpr std::size_t block_size = 64;
constexpr std::size_t digest_size = 32;
constexpr std::uint64_t max_message_bytes =
    std::numeric_limits<std::uint64_t>::max() / 8U;

constexpr std::array<std::uint32_t, 8> initial_hash{
    0x6a09e667U,
    0xbb67ae85U,
    0x3c6ef372U,
    0xa54ff53aU,
    0x510e527fU,
    0x9b05688cU,
    0x1f83d9abU,
    0x5be0cd19U,
};

constexpr std::array<std::uint32_t, 64> round_constants{
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U,
    0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
    0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
    0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU,
    0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
    0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
    0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
    0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U,
    0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U,
    0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
    0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
};

class Sha256State final
{
public:
    [[nodiscard]] bool update(const std::span<const std::byte> bytes) noexcept
    {
        if (!valid_ || bytes.size() > max_message_bytes - total_bytes_)
        {
            valid_ = false;
            return false;
        }

        total_bytes_ += static_cast<std::uint64_t>(bytes.size());
        std::size_t offset = 0;

        if (buffered_bytes_ != 0)
        {
            const std::size_t copy_count =
                std::min(block_size - buffered_bytes_, bytes.size());
            std::copy_n(bytes.begin(), copy_count, buffer_.begin() + buffered_bytes_);
            buffered_bytes_ += copy_count;
            offset += copy_count;

            if (buffered_bytes_ == block_size)
            {
                transform(buffer_);
                buffered_bytes_ = 0;
            }
        }

        while (bytes.size() - offset >= block_size)
        {
            std::array<std::byte, block_size> block{};
            std::copy_n(bytes.begin() + static_cast<std::ptrdiff_t>(offset),
                        block_size, block.begin());
            transform(block);
            offset += block_size;
        }

        const std::size_t remaining = bytes.size() - offset;
        if (remaining != 0)
        {
            std::copy_n(bytes.begin() + static_cast<std::ptrdiff_t>(offset),
                        remaining, buffer_.begin());
            buffered_bytes_ = remaining;
        }

        return true;
    }

    [[nodiscard]] std::array<std::byte, digest_size> finish()
    {
        if (!valid_)
        {
            throw std::length_error("SHA-256 input exceeds its 64-bit bit-length field");
        }

        const std::uint64_t bit_length = total_bytes_ * 8U;
        buffer_[buffered_bytes_++] = std::byte{0x80U};

        if (buffered_bytes_ > 56)
        {
            std::fill(buffer_.begin() + static_cast<std::ptrdiff_t>(buffered_bytes_),
                      buffer_.end(), std::byte{0U});
            transform(buffer_);
            buffered_bytes_ = 0;
        }

        std::fill(buffer_.begin() + static_cast<std::ptrdiff_t>(buffered_bytes_),
                  buffer_.begin() + 56, std::byte{0U});
        for (std::size_t index = 0; index < 8; ++index)
        {
            const unsigned shift = static_cast<unsigned>((7U - index) * 8U);
            buffer_[56 + index] =
                std::byte{static_cast<unsigned char>((bit_length >> shift) & 0xffU)};
        }
        transform(buffer_);

        std::array<std::byte, digest_size> digest{};
        for (std::size_t word_index = 0; word_index < hash_.size(); ++word_index)
        {
            const std::uint32_t word = hash_[word_index];
            for (std::size_t byte_index = 0; byte_index < 4; ++byte_index)
            {
                const unsigned shift = static_cast<unsigned>((3U - byte_index) * 8U);
                digest[(word_index * 4) + byte_index] =
                    std::byte{static_cast<unsigned char>((word >> shift) & 0xffU)};
            }
        }
        return digest;
    }

private:
    void transform(const std::array<std::byte, block_size>& block) noexcept
    {
        std::array<std::uint32_t, 64> schedule{};
        for (std::size_t index = 0; index < 16; ++index)
        {
            const std::size_t offset = index * 4;
            schedule[index] =
                (std::to_integer<std::uint32_t>(block[offset]) << 24U) |
                (std::to_integer<std::uint32_t>(block[offset + 1]) << 16U) |
                (std::to_integer<std::uint32_t>(block[offset + 2]) << 8U) |
                std::to_integer<std::uint32_t>(block[offset + 3]);
        }

        for (std::size_t index = 16; index < schedule.size(); ++index)
        {
            const std::uint32_t s0 = std::rotr(schedule[index - 15], 7) ^
                                     std::rotr(schedule[index - 15], 18) ^
                                     (schedule[index - 15] >> 3U);
            const std::uint32_t s1 = std::rotr(schedule[index - 2], 17) ^
                                     std::rotr(schedule[index - 2], 19) ^
                                     (schedule[index - 2] >> 10U);
            schedule[index] = schedule[index - 16] + s0 + schedule[index - 7] + s1;
        }

        std::uint32_t a = hash_[0];
        std::uint32_t b = hash_[1];
        std::uint32_t c = hash_[2];
        std::uint32_t d = hash_[3];
        std::uint32_t e = hash_[4];
        std::uint32_t f = hash_[5];
        std::uint32_t g = hash_[6];
        std::uint32_t h = hash_[7];

        for (std::size_t index = 0; index < schedule.size(); ++index)
        {
            const std::uint32_t sum1 = std::rotr(e, 6) ^ std::rotr(e, 11) ^ std::rotr(e, 25);
            const std::uint32_t choose = (e & f) ^ (~e & g);
            const std::uint32_t temporary1 =
                h + sum1 + choose + round_constants[index] + schedule[index];
            const std::uint32_t sum0 = std::rotr(a, 2) ^ std::rotr(a, 13) ^ std::rotr(a, 22);
            const std::uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
            const std::uint32_t temporary2 = sum0 + majority;

            h = g;
            g = f;
            f = e;
            e = d + temporary1;
            d = c;
            c = b;
            b = a;
            a = temporary1 + temporary2;
        }

        hash_[0] += a;
        hash_[1] += b;
        hash_[2] += c;
        hash_[3] += d;
        hash_[4] += e;
        hash_[5] += f;
        hash_[6] += g;
        hash_[7] += h;
    }

    std::array<std::uint32_t, 8> hash_{initial_hash};
    std::array<std::byte, block_size> buffer_{};
    std::uint64_t total_bytes_{0};
    std::size_t buffered_bytes_{0};
    bool valid_{true};
};

[[nodiscard]] std::string to_hex(const std::array<std::byte, digest_size>& digest)
{
    constexpr char digits[] = "0123456789abcdef";
    std::string result(digest_size * 2, '0');
    for (std::size_t index = 0; index < digest.size(); ++index)
    {
        const unsigned value = std::to_integer<unsigned>(digest[index]);
        result[index * 2] = digits[value >> 4U];
        result[(index * 2) + 1] = digits[value & 0x0fU];
    }
    return result;
}

[[nodiscard]] std::span<const std::byte> as_bytes(const std::string_view text) noexcept
{
    return std::as_bytes(std::span<const char>{text.data(), text.size()});
}

[[nodiscard]] bool check_incremental_long_vector()
{
    constexpr std::string_view value =
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    constexpr std::string_view expected =
        "248d6a61d20638b8e5c026930c3e6039"
        "a33ce45964ff2167f6ecedd419db06c1";
    constexpr std::array<std::size_t, 7> chunk_sizes{1, 2, 7, 3, 16, 5, 11};

    const auto bytes = as_bytes(value);
    Sha256State state;
    std::size_t offset = 0;
    std::size_t chunk_index = 0;
    while (offset < bytes.size())
    {
        const std::size_t count =
            std::min(chunk_sizes[chunk_index % chunk_sizes.size()], bytes.size() - offset);
        if (!state.update(bytes.subspan(offset, count)))
        {
            return false;
        }
        offset += count;
        ++chunk_index;
    }

    return to_hex(state.finish()) == expected;
}

[[nodiscard]] bool check_million_a_incremental()
{
    constexpr std::string_view expected =
        "cdc76e5c9914fb9281a1c7e284d73e67"
        "f1809a48a497200e046d39ccc7112cd0";
    std::array<std::byte, 1000> chunk{};
    chunk.fill(std::byte{static_cast<unsigned char>('a')});

    Sha256State state;
    for (std::size_t index = 0; index < 1000; ++index)
    {
        if (!state.update(chunk))
        {
            return false;
        }
    }
    return to_hex(state.finish()) == expected;
}

} // namespace

std::string sha256_hex(const std::span<const std::byte> bytes)
{
    Sha256State state;
    if (!state.update(bytes))
    {
        throw std::length_error("SHA-256 input exceeds its 64-bit bit-length field");
    }
    return to_hex(state.finish());
}

std::string sha256_hex(const std::string_view text)
{
    return sha256_hex(as_bytes(text));
}

bool sha256_self_test()
{
    constexpr std::string_view empty_expected =
        "e3b0c44298fc1c149afbf4c8996fb924"
        "27ae41e4649b934ca495991b7852b855";
    constexpr std::string_view abc_expected =
        "ba7816bf8f01cfea414140de5dae2223"
        "b00361a396177a9cb410ff61f20015ad";
    constexpr std::string_view long_value =
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    constexpr std::string_view long_expected =
        "248d6a61d20638b8e5c026930c3e6039"
        "a33ce45964ff2167f6ecedd419db06c1";
    constexpr std::array<std::byte, 6> binary_value{
        std::byte{0x00U}, std::byte{0x61U}, std::byte{0x62U},
        std::byte{0x63U}, std::byte{0x00U}, std::byte{0xffU},
    };
    constexpr std::string_view binary_expected =
        "bd05028c200bd1a585123f4d6884beee"
        "ed987e0804d1d90ad3b7480bd7d6c02c";
    constexpr std::array<char, 6> binary_chars{'\0', 'a', 'b', 'c', '\0', static_cast<char>(0xff)};

    return sha256_hex(std::string_view{}) == empty_expected &&
           sha256_hex("abc") == abc_expected &&
           sha256_hex(long_value) == long_expected &&
           check_incremental_long_vector() &&
           check_million_a_incremental() &&
           sha256_hex(binary_value) == binary_expected &&
           sha256_hex(std::string_view{binary_chars.data(), binary_chars.size()}) ==
               binary_expected;
}

} // namespace tmxy::g2_asset_descriptor_diagnostics
