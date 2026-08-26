#pragma once

#include "tmxy/static_mesh/static_mesh_result.hpp"
#include "tmxy/static_mesh/static_mesh_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace tmxy::static_mesh
{

struct StaticMeshLimits final
{
    std::uint32_t maximum_vertex_count{4'000'000};
    std::uint32_t maximum_index_count{50'000'000};
    std::uint32_t maximum_section_count{4096};
    std::uint32_t maximum_octree_node_count{4'000'000};
    std::uint32_t maximum_emitter_point_count{4'000'000};
};

class SmReader final
{
  public:
    explicit SmReader(StaticMeshLimits limits = {});

    [[nodiscard]] StaticMeshResult<StaticMesh> parse(std::span<const std::byte> bytes,
                                                     std::uint64_t base_offset = 0) const;

  private:
    StaticMeshLimits limits_;
};

[[nodiscard]] const Aabb& effective_legacy_bounds(const StaticMesh& mesh) noexcept;

} // namespace tmxy::static_mesh
