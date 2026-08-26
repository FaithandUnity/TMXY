#pragma once

#include "tmxy/static_mesh/static_mesh_result.hpp"
#include "tmxy/static_mesh/static_mesh_types.hpp"

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::static_mesh
{

struct GltfArtifacts final
{
    std::string json;
    std::vector<std::byte> binary;
};

[[nodiscard]] StaticMeshResult<GltfArtifacts> build_gltf2(const StaticMeshBinding& binding,
                                                          std::string_view buffer_uri);

} // namespace tmxy::static_mesh
