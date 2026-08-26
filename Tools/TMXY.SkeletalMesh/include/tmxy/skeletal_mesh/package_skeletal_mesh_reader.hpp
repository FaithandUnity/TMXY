#pragma once

#include "tmxy/skeletal_mesh/skeletal_mesh_result.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace tmxy::skeletal_mesh
{

[[nodiscard]] SkeletalMeshResult<SkeletalMeshDescriptor>
read_skeletal_mesh_descriptor(std::span<const std::byte> object_body,
                              std::uint64_t base_offset = 0);

[[nodiscard]] SkeletalMeshResult<PackageSkeletalMeshDescriptor>
read_package_skeletal_mesh_descriptor(std::span<const std::byte> package_bytes,
                                      std::string_view full_object_name);

[[nodiscard]] SkeletalMeshResult<SkeletalMeshBinding>
bind_skeletal_mesh(std::span<const std::byte> package_bytes, std::string_view full_object_name,
                   std::span<const std::byte> skem_bytes);

} // namespace tmxy::skeletal_mesh
