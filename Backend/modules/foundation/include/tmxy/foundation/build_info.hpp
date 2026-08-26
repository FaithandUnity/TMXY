#pragma once

#include <cstdint>
#include <string_view>

namespace tmxy::foundation
{
struct BuildInfo final
{
    std::string_view product;
    std::uint16_t version_major;
    std::uint16_t version_minor;
    std::uint16_t version_patch;
};

[[nodiscard]] const BuildInfo& current_build_info() noexcept;
} // namespace tmxy::foundation
