#pragma once

#include "tmxy/static_mesh/static_mesh_result.hpp"
#include "tmxy/static_mesh/static_mesh_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace tmxy::static_mesh
{

[[nodiscard]] StaticMeshResult<StaticMeshDescriptor>
read_static_mesh_descriptor(std::span<const std::byte> object_body, std::uint64_t base_offset = 0);

[[nodiscard]] StaticMeshResult<PackageStaticMeshDescriptor>
read_package_static_mesh_descriptor(std::span<const std::byte> package_bytes,
                                    std::string_view full_object_name);

[[nodiscard]] StaticMeshResult<StaticMeshBinding>
bind_static_mesh(std::span<const std::byte> package_bytes, std::string_view full_object_name,
                 std::span<const std::byte> sm_bytes);

[[nodiscard]] StaticMeshResult<StaticMeshBinding>
bind_static_mesh_with_payload_section_prefix(std::span<const std::byte> package_bytes,
                                             std::string_view full_object_name,
                                             std::span<const std::byte> sm_bytes);

} // namespace tmxy::static_mesh
