#include "tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp"
#include "tmxy/skeletal_mesh/skem_reader.hpp"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <ranges>
#include <string>
#include <string_view>
#include <utility>

namespace tmxy::skeletal_mesh
{
namespace
{

constexpr float kActiveWeightThreshold = 0.00001F;

[[nodiscard]] SkeletalMeshError make_error(const SkeletalMeshErrorCode code, std::string context)
{
    return {.code = code,
            .absolute_offset = 0,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] std::optional<SkeletalMeshError>
validate_active_bone_indices(const SkeletalMeshBinding& binding)
{
    const auto bone_count = binding.package.descriptor.bones.size();
    for (const auto& group : binding.payload.groups)
    {
        for (const auto& mesh : group.submeshes)
        {
            for (std::size_t vertex = 0; vertex < mesh.weights.size(); ++vertex)
            {
                const auto& weights = mesh.weights[vertex];
                const auto& indices = mesh.bone_indices[vertex];
                const std::array weight_values{weights.x, weights.y, weights.z, weights.w};
                const std::array index_values{indices.x, indices.y, indices.z, indices.w};
                for (std::size_t influence = 0; influence < weight_values.size(); ++influence)
                {
                    if (weight_values[influence] <= kActiveWeightThreshold)
                    {
                        continue;
                    }
                    const auto legacy_bone_index =
                        static_cast<std::uint32_t>(std::lround(index_values[influence]));
                    if (legacy_bone_index == 0U || std::cmp_greater(legacy_bone_index, bone_count))
                    {
                        return make_error(SkeletalMeshErrorCode::invalid_bone_index,
                                          "skeletal_mesh.active_bone_index");
                    }
                }
            }
        }
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError>
build_default_selections(SkeletalMeshBinding& binding)
{
    const auto& descriptor = binding.package.descriptor;
    if (descriptor.material_object_names.size() != binding.payload.groups.size())
    {
        return make_error(SkeletalMeshErrorCode::material_group_mismatch,
                          "skeletal_mesh.material_groups");
    }
    if (descriptor.default_submesh_indices.size() != binding.payload.groups.size())
    {
        return make_error(SkeletalMeshErrorCode::default_selection_mismatch,
                          "skeletal_mesh.default_sections");
    }
    binding.default_selections.reserve(binding.payload.groups.size());
    for (std::size_t group_index = 0; group_index < binding.payload.groups.size(); ++group_index)
    {
        const auto selected = descriptor.default_submesh_indices[group_index];
        DefaultSubmeshSelection selection{.group_index = static_cast<std::uint32_t>(group_index),
                                          .global_submesh_index = selected,
                                          .submesh_index_in_group = std::nullopt,
                                          .material_object_name =
                                              descriptor.material_object_names[group_index]};
        if (selected >= 0)
        {
            const auto& submeshes = binding.payload.groups[group_index].submeshes;
            const auto found =
                std::ranges::find(submeshes, selected, &SkeletalSubmesh::global_index);
            if (found == submeshes.end())
            {
                return make_error(SkeletalMeshErrorCode::default_selection_mismatch,
                                  "skeletal_mesh.default_sections.group");
            }
            selection.submesh_index_in_group =
                static_cast<std::uint32_t>(std::distance(submeshes.begin(), found));
        }
        binding.default_selections.push_back(std::move(selection));
    }
    return std::nullopt;
}

} // namespace

SkeletalMeshResult<SkeletalMeshBinding>
bind_skeletal_mesh(const std::span<const std::byte> package_bytes,
                   const std::string_view full_object_name,
                   const std::span<const std::byte> skem_bytes)
{
    auto package = read_package_skeletal_mesh_descriptor(package_bytes, full_object_name);
    if (!package.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshBinding>::failure(package.error());
    }
    auto payload = SkemReader{}.parse(skem_bytes);
    if (!payload.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshBinding>::failure(payload.error());
    }
    SkeletalMeshBinding binding{.payload = std::move(payload).take_value(),
                                .package = std::move(package).take_value(),
                                .default_selections = {}};
    if (const auto error = validate_active_bone_indices(binding); error.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshBinding>::failure(error.value());
    }
    if (const auto error = build_default_selections(binding); error.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshBinding>::failure(error.value());
    }
    return SkeletalMeshResult<SkeletalMeshBinding>::success(std::move(binding));
}

} // namespace tmxy::skeletal_mesh
