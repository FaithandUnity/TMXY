#pragma once

#include "tmxy/skeletal_mesh/skeletal_mesh_result.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_types.hpp"

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::skeletal_mesh
{

struct SkeletalGltfArtifacts final
{
    std::string json;
    std::vector<std::byte> binary;
};

[[nodiscard]] SkeletalMeshResult<SkeletalGltfArtifacts>
build_default_gltf2(const SkeletalMeshBinding& binding, std::string_view buffer_uri);

} // namespace tmxy::skeletal_mesh
