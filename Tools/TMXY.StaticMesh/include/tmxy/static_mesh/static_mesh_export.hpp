#pragma once

#include "tmxy/static_mesh/static_mesh_result.hpp"
#include "tmxy/static_mesh/static_mesh_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace tmxy::static_mesh
{

[[nodiscard]] StaticMeshResult<std::string> build_ue_obj(const StaticMeshBinding& binding);
[[nodiscard]] std::string build_static_mesh_json(const StaticMeshBinding& binding);
[[nodiscard]] std::uint64_t bytes_fingerprint(std::span<const std::byte> bytes) noexcept;
[[nodiscard]] std::uint64_t text_fingerprint(std::string_view text) noexcept;

} // namespace tmxy::static_mesh
