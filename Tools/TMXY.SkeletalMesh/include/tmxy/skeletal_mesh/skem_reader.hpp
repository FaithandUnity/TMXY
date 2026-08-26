#pragma once

#include "tmxy/skeletal_mesh/skeletal_mesh_result.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace tmxy::skeletal_mesh
{

struct SkeletalMeshLimits final
{
    std::uint32_t maximum_group_count{4096};
    std::uint32_t maximum_submesh_count{1'000'000};
    std::uint32_t maximum_vertex_count_per_submesh{4'000'000};
    std::uint32_t maximum_index_count_per_submesh{50'000'000};
    std::uint64_t maximum_total_vertex_count{10'000'000};
    std::uint64_t maximum_total_index_count{100'000'000};
};

class SkemReader final
{
  public:
    explicit SkemReader(SkeletalMeshLimits limits = {});

    [[nodiscard]] SkeletalMeshResult<SkeletalMeshPayload>
    parse(std::span<const std::byte> bytes, std::uint64_t base_offset = 0) const;

  private:
    SkeletalMeshLimits limits_;
};

} // namespace tmxy::skeletal_mesh
