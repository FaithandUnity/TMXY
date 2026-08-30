#pragma once

#include "probe_types.hpp"
#include "recovery_plan.hpp"
#include "tmxy/texture/texture_types.hpp"

#include <cstddef>
#include <span>
#include <string_view>

namespace tmxy::g2_asset_descriptor_diagnostics
{

void apply_qtx_recovery(const texture::TextureDescriptor& descriptor,
                        std::span<const std::byte> payload, std::string_view object_name,
                        const RecoveryDirective& directive, CandidateResult& result);

[[nodiscard]] bool qtx_recovery_self_test() noexcept;

} // namespace tmxy::g2_asset_descriptor_diagnostics
