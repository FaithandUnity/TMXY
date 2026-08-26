#pragma once

#include "tmxy/format/read_error.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace tmxy::texture
{

enum class TextureErrorCode : std::uint8_t
{
    read_failure = 1,
    item_count_limit_exceeded = 2,
    property_name_limit_exceeded = 3,
    duplicate_property = 4,
    invalid_property_size = 5,
    invalid_format = 6,
    invalid_clamp_mode = 7,
    invalid_dimension = 8,
    invalid_mip_count = 9,
    trailing_descriptor_bytes = 10,
    mip_size_overflow = 11,
    payload_size_mismatch = 12,
    non_finite_pixel = 13,
    output_limit_exceeded = 14,
    invalid_package = 15,
    texture_object_not_found = 16,
    wrong_object_class = 17,
    object_range_out_of_file = 18,
};

struct TextureError final
{
    static constexpr std::uint32_t kSchemaVersion = 1;

    TextureErrorCode code{TextureErrorCode::read_failure};
    std::uint64_t absolute_offset{0};
    std::string context;
    std::optional<format::ReadErrorCode> read_error_code;
};

[[nodiscard]] std::string_view to_string(TextureErrorCode code) noexcept;

} // namespace tmxy::texture
