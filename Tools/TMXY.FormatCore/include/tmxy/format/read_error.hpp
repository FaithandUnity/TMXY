#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace tmxy::format
{

enum class ReadErrorCode : std::uint8_t
{
    out_of_bounds = 1,
    invalid_seek = 2,
    offset_overflow = 3,
};

struct ReadError final
{
    static constexpr std::uint32_t kSchemaVersion = 1;

    ReadErrorCode code{ReadErrorCode::out_of_bounds};
    std::uint64_t absolute_offset{0};
    std::uint64_t requested_bytes{0};
    std::uint64_t available_bytes{0};
    std::string context;
};

[[nodiscard]] std::string_view to_string(ReadErrorCode code) noexcept;

} // namespace tmxy::format
