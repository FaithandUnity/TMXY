#pragma once

#include <string>
#include <string_view>

namespace tmxy::g2_asset_descriptor_diagnostics
{

[[nodiscard]] std::string semantic_sha256(std::string_view object_name, std::string_view signature);
[[nodiscard]] std::string descriptor_semantic_sha256(std::string_view signature);
[[nodiscard]] std::string normalized_semantic_sha256(std::string_view object_name,
                                                     std::string_view signature);

} // namespace tmxy::g2_asset_descriptor_diagnostics
