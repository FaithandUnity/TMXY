#pragma once

#include <cstddef>
#include <span>
#include <string>
#include <string_view>

namespace tmxy::g2_asset_descriptor_diagnostics
{

// Returns the lowercase hexadecimal SHA-256 digest. Inputs whose bit length
// cannot be represented by SHA-256's 64-bit length field are rejected with
// std::length_error.
[[nodiscard]] std::string sha256_hex(std::span<const std::byte> bytes);

[[nodiscard]] std::string sha256_hex(std::string_view text);

// Exercises standard known-answer vectors, incremental updates, and binary
// input containing embedded NUL bytes.
[[nodiscard]] bool sha256_self_test();

} // namespace tmxy::g2_asset_descriptor_diagnostics
