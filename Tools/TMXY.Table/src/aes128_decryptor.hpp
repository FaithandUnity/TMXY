#pragma once

#include "tmxy/table/legacy_table.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>

namespace tmxy::table::detail
{

class Aes128Decryptor final
{
  public:
    explicit Aes128Decryptor(std::span<const std::byte, kLegacyTableBlockSize> key) noexcept;
    ~Aes128Decryptor();

    Aes128Decryptor(const Aes128Decryptor&) = delete;
    Aes128Decryptor& operator=(const Aes128Decryptor&) = delete;
    Aes128Decryptor(Aes128Decryptor&&) = delete;
    Aes128Decryptor& operator=(Aes128Decryptor&&) = delete;

    void decrypt_block(std::span<std::byte, kLegacyTableBlockSize> block) const noexcept;

  private:
    static constexpr std::size_t kExpandedKeyBytes = 176;
    std::array<std::uint8_t, kExpandedKeyBytes> round_keys_{};
};

} // namespace tmxy::table::detail
