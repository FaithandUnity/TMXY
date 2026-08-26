#pragma once

#include "tmxy/animation/animation_result.hpp"
#include "tmxy/animation/animation_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::animation
{

struct AnimationGltfClipEvidence final
{
    std::size_t source_index{0};
    std::string name;
    std::uint32_t frame_count{0};
    std::uint32_t track_count{0};
    double sampled_duration_seconds{0.0};
    double legacy_loop_period_seconds{0.0};
    bool self_loop{false};
    bool root_classified_moving{false};
    double root_translation_distance_meters{0.0};
    double maximum_endpoint_translation_delta_meters{0.0};
    double maximum_endpoint_rotation_delta_degrees{0.0};
};

struct AnimationGltfArtifacts final
{
    std::string json;
    std::vector<std::byte> binary;
    std::string metadata_json;
    std::vector<AnimationGltfClipEvidence> clips;
};

[[nodiscard]] AnimationResult<AnimationGltfArtifacts>
build_selected_gltf2(const AnimationBinding& binding, std::string_view buffer_uri,
                     std::span<const std::string_view> selected_clip_names);

} // namespace tmxy::animation
