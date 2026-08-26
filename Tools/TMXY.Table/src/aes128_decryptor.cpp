#include "aes128_decryptor.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>

namespace tmxy::table::detail
{

namespace
{

using State = std::array<std::uint8_t, kLegacyTableBlockSize>;

struct GfOperands final
{
    std::uint8_t left{0};
    std::uint8_t right{0};
};

[[nodiscard]] constexpr std::uint8_t gf_multiply(GfOperands operands) noexcept
{
    std::uint8_t product = 0;
    for (unsigned int bit = 0; bit < 8U; ++bit)
    {
        if ((operands.right & 1U) != 0U)
        {
            product = static_cast<std::uint8_t>(product ^ operands.left);
        }
        const bool high_bit = (operands.left & 0x80U) != 0U;
        operands.left = static_cast<std::uint8_t>(operands.left << 1U);
        if (high_bit)
        {
            operands.left = static_cast<std::uint8_t>(operands.left ^ 0x1BU);
        }
        operands.right = static_cast<std::uint8_t>(operands.right >> 1U);
    }
    return product;
}

[[nodiscard]] constexpr std::uint8_t multiplicative_inverse(const std::uint8_t value) noexcept
{
    if (value == 0U)
    {
        return 0U;
    }
    std::uint8_t result = 1U;
    std::uint8_t factor = value;
    unsigned int exponent = 254U;
    while (exponent != 0U)
    {
        if ((exponent & 1U) != 0U)
        {
            result = gf_multiply({.left = result, .right = factor});
        }
        factor = gf_multiply({.left = factor, .right = factor});
        exponent >>= 1U;
    }
    return result;
}

[[nodiscard]] constexpr std::uint8_t substitute(const std::uint8_t value) noexcept
{
    const auto inverse = multiplicative_inverse(value);
    return static_cast<std::uint8_t>(inverse ^ std::rotl(inverse, 1) ^ std::rotl(inverse, 2) ^
                                     std::rotl(inverse, 3) ^ std::rotl(inverse, 4) ^ 0x63U);
}

[[nodiscard]] constexpr std::array<std::uint8_t, 256> make_substitution_box() noexcept
{
    std::array<std::uint8_t, 256> result{};
    for (std::size_t index = 0; index < result.size(); ++index)
    {
        result[index] = substitute(static_cast<std::uint8_t>(index));
    }
    return result;
}

[[nodiscard]] constexpr std::array<std::uint8_t, 256> make_inverse_substitution_box() noexcept
{
    std::array<std::uint8_t, 256> result{};
    for (std::size_t index = 0; index < result.size(); ++index)
    {
        result[substitute(static_cast<std::uint8_t>(index))] = static_cast<std::uint8_t>(index);
    }
    return result;
}

inline constexpr auto kSubstitutionBox = make_substitution_box();
inline constexpr auto kInverseSubstitutionBox = make_inverse_substitution_box();

template <std::size_t ExpandedKeyBytes>
void add_round_key(State& state, const std::array<std::uint8_t, ExpandedKeyBytes>& round_keys,
                   const std::size_t round) noexcept
{
    const auto key_offset = round * kLegacyTableBlockSize;
    for (std::size_t index = 0; index < state.size(); ++index)
    {
        state[index] = static_cast<std::uint8_t>(state[index] ^ round_keys[key_offset + index]);
    }
}

void inverse_shift_rows(State& state) noexcept
{
    const auto original = state;
    constexpr std::size_t kSide = 4;
    for (std::size_t row = 0; row < kSide; ++row)
    {
        for (std::size_t column = 0; column < kSide; ++column)
        {
            const auto source_column = (column + kSide - row) % kSide;
            state[(column * kSide) + row] = original[(source_column * kSide) + row];
        }
    }
}

void inverse_substitute_bytes(State& state) noexcept
{
    for (auto& value : state)
    {
        value = kInverseSubstitutionBox[value];
    }
}

void inverse_mix_columns(State& state) noexcept
{
    constexpr std::size_t kColumnWidth = 4;
    for (std::size_t column = 0; column < kColumnWidth; ++column)
    {
        const auto offset = column * kColumnWidth;
        const auto first = state[offset];
        const auto second = state[offset + 1U];
        const auto third = state[offset + 2U];
        const auto fourth = state[offset + 3U];
        state[offset] = static_cast<std::uint8_t>(gf_multiply({.left = 0x0EU, .right = first}) ^
                                                  gf_multiply({.left = 0x0BU, .right = second}) ^
                                                  gf_multiply({.left = 0x0DU, .right = third}) ^
                                                  gf_multiply({.left = 0x09U, .right = fourth}));
        state[offset + 1U] =
            static_cast<std::uint8_t>(gf_multiply({.left = 0x09U, .right = first}) ^
                                      gf_multiply({.left = 0x0EU, .right = second}) ^
                                      gf_multiply({.left = 0x0BU, .right = third}) ^
                                      gf_multiply({.left = 0x0DU, .right = fourth}));
        state[offset + 2U] =
            static_cast<std::uint8_t>(gf_multiply({.left = 0x0DU, .right = first}) ^
                                      gf_multiply({.left = 0x09U, .right = second}) ^
                                      gf_multiply({.left = 0x0EU, .right = third}) ^
                                      gf_multiply({.left = 0x0BU, .right = fourth}));
        state[offset + 3U] =
            static_cast<std::uint8_t>(gf_multiply({.left = 0x0BU, .right = first}) ^
                                      gf_multiply({.left = 0x0DU, .right = second}) ^
                                      gf_multiply({.left = 0x09U, .right = third}) ^
                                      gf_multiply({.left = 0x0EU, .right = fourth}));
    }
}

} // namespace

Aes128Decryptor::Aes128Decryptor(
    const std::span<const std::byte, kLegacyTableBlockSize> key) noexcept
{
    for (std::size_t index = 0; index < key.size(); ++index)
    {
        round_keys_[index] = std::to_integer<std::uint8_t>(key[index]);
    }

    std::size_t generated = kLegacyTableBlockSize;
    std::uint8_t round_constant = 1U;
    std::array<std::uint8_t, 4> temporary{};
    while (generated < round_keys_.size())
    {
        std::copy_n(round_keys_.begin() + static_cast<std::ptrdiff_t>(generated - temporary.size()),
                    temporary.size(), temporary.begin());
        if (generated % kLegacyTableBlockSize == 0U)
        {
            std::ranges::rotate(temporary, temporary.begin() + 1);
            for (auto& value : temporary)
            {
                value = kSubstitutionBox[value];
            }
            temporary[0] = static_cast<std::uint8_t>(temporary[0] ^ round_constant);
            round_constant = gf_multiply({.left = round_constant, .right = 0x02U});
        }
        for (const auto value : temporary)
        {
            round_keys_[generated] =
                static_cast<std::uint8_t>(round_keys_[generated - kLegacyTableBlockSize] ^ value);
            ++generated;
        }
    }
}

Aes128Decryptor::~Aes128Decryptor()
{
    std::ranges::fill(round_keys_, 0U);
}

void Aes128Decryptor::decrypt_block(
    const std::span<std::byte, kLegacyTableBlockSize> block) const noexcept
{
    State state{};
    for (std::size_t index = 0; index < block.size(); ++index)
    {
        state[index] = std::to_integer<std::uint8_t>(block[index]);
    }

    constexpr std::size_t kRoundCount = 10;
    add_round_key(state, round_keys_, kRoundCount);
    for (std::size_t round = kRoundCount - 1U; round > 0U; --round)
    {
        inverse_shift_rows(state);
        inverse_substitute_bytes(state);
        add_round_key(state, round_keys_, round);
        inverse_mix_columns(state);
    }
    inverse_shift_rows(state);
    inverse_substitute_bytes(state);
    add_round_key(state, round_keys_, 0U);

    for (std::size_t index = 0; index < block.size(); ++index)
    {
        block[index] = static_cast<std::byte>(state[index]);
    }
}

} // namespace tmxy::table::detail
