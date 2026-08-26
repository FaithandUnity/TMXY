#pragma once

#include "tmxy/skeletal_mesh/skeletal_mesh_result.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_types.hpp"

#include <string>

namespace tmxy::skeletal_mesh
{

[[nodiscard]] SkeletalMeshResult<std::string>
build_default_ue_obj(const SkeletalMeshBinding& binding);

[[nodiscard]] std::string build_skeletal_mesh_json(const SkeletalMeshBinding& binding);

} // namespace tmxy::skeletal_mesh
