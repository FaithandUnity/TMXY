#include "tmxy/animation/animation_gltf.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <numbers>
#include <ranges>
#include <set>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::animation
{
namespace
{

struct Range final
{
    std::size_t offset{0};
    std::size_t size{0};
    std::size_t count{0};
    std::string_view type;
    bool time{false};
    double maximum_time{0.0};
};

struct TrackLayout final
{
    std::size_t translation_accessor{0};
    std::size_t rotation_accessor{0};
};

struct ClipLayout final
{
    const AnimationClip* clip{nullptr};
    std::size_t source_index{0};
    std::size_t time_accessor{0};
    std::vector<TrackLayout> tracks;
};

struct Layout final
{
    std::vector<std::byte> bytes;
    std::vector<Range> ranges;
    std::vector<ClipLayout> clips;
};

[[nodiscard]] AnimationError gltf_error(std::string context)
{
    return {.code = AnimationErrorCode::gltf_contract_failure,
            .absolute_offset = 0,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] bool safe_uri(const std::string_view value) noexcept
{
    return !value.empty() && value != "." && value != ".." &&
           std::ranges::all_of(value,
                               [](const char character)
                               {
                                   return std::isalnum(static_cast<unsigned char>(character)) !=
                                              0 ||
                                          character == '.' || character == '_' || character == '-';
                               });
}

[[nodiscard]] std::string json_string(const std::string_view value)
{
    std::ostringstream output;
    output << '"';
    for (const char raw : value)
    {
        const auto character = static_cast<unsigned char>(raw);
        if (character == '"' || character == '\\')
        {
            output << '\\' << raw;
        }
        else if (character >= 0x20U && character < 0x7FU)
        {
            output << raw;
        }
        else
        {
            output << "\\u00" << std::hex << std::setw(2) << std::setfill('0')
                   << static_cast<unsigned int>(character) << std::dec;
        }
    }
    output << '"';
    return output.str();
}

void align_four(std::vector<std::byte>& bytes)
{
    while ((bytes.size() & 3U) != 0U)
    {
        bytes.push_back(std::byte{0});
    }
}

void append_f32(std::vector<std::byte>& bytes, const float value)
{
    const auto bits = std::bit_cast<std::uint32_t>(value);
    for (std::uint32_t shift = 0; shift < 32U; shift += 8U)
    {
        bytes.push_back(static_cast<std::byte>((bits >> shift) & 0xFFU));
    }
}

template <typename Writer>
[[nodiscard]] std::size_t append_range(Layout& layout, const std::size_t count,
                                       const std::string_view type, const bool time,
                                       const double maximum_time, Writer writer)
{
    align_four(layout.bytes);
    const auto offset = layout.bytes.size();
    writer();
    layout.ranges.push_back({.offset = offset,
                             .size = layout.bytes.size() - offset,
                             .count = count,
                             .type = type,
                             .time = time,
                             .maximum_time = maximum_time});
    return layout.ranges.size() - 1U;
}

[[nodiscard]] std::array<float, 3> to_gltf(const skeletal_mesh::Vec3& value) noexcept
{
    return {value.y, value.z, value.x};
}

[[nodiscard]] std::array<float, 4> to_gltf(const skeletal_mesh::Quaternion& value) noexcept
{
    std::array result{value.y, value.z, value.x, value.w};
    float length_squared = 0.0F;
    for (const float component : result)
    {
        length_squared += component * component;
    }
    const float length = std::sqrt(length_squared);
    for (float& component : result)
    {
        component /= length;
    }
    return result;
}

[[nodiscard]] double translation_distance(const AnimationKey& first,
                                          const AnimationKey& last) noexcept
{
    const double x = static_cast<double>(last.translation.x) - first.translation.x;
    const double y = static_cast<double>(last.translation.y) - first.translation.y;
    const double z = static_cast<double>(last.translation.z) - first.translation.z;
    return std::sqrt((x * x) + (y * y) + (z * z));
}

[[nodiscard]] double rotation_distance_degrees(const AnimationKey& first,
                                               const AnimationKey& last) noexcept
{
    const auto left = to_gltf(first.rotation);
    const auto right = to_gltf(last.rotation);
    double dot = 0.0;
    for (std::size_t index = 0; index < 4U; ++index)
    {
        dot += static_cast<double>(left[index]) * right[index];
    }
    dot = std::clamp(std::abs(dot), 0.0, 1.0);
    return 2.0 * std::acos(dot) * (180.0 / std::numbers::pi);
}

[[nodiscard]] AnimationGltfClipEvidence make_evidence(const AnimationClip& clip,
                                                      const std::size_t source_index)
{
    double translation = 0.0;
    double rotation = 0.0;
    for (const auto& track : clip.tracks)
    {
        translation =
            std::max(translation, translation_distance(track.keys.front(), track.keys.back()));
        rotation =
            std::max(rotation, rotation_distance_degrees(track.keys.front(), track.keys.back()));
    }
    return {.source_index = source_index,
            .name = clip.descriptor.animation_name_bytes,
            .frame_count = static_cast<std::uint32_t>(clip.effective_frame_count),
            .track_count = clip.track_count,
            .sampled_duration_seconds = clip.sampled_duration_seconds,
            .legacy_loop_period_seconds = clip.legacy_loop_period_seconds,
            .self_loop = clip.descriptor.self_loop,
            .root_classified_moving = clip.root_motion.classified_moving,
            .root_translation_distance_meters = clip.root_motion.translation_distance_legacy_meters,
            .maximum_endpoint_translation_delta_meters = translation,
            .maximum_endpoint_rotation_delta_degrees = rotation};
}

[[nodiscard]] std::size_t append_times(Layout& layout, const AnimationClip& clip)
{
    return append_range(layout, static_cast<std::size_t>(clip.effective_frame_count), "SCALAR",
                        true, clip.sampled_duration_seconds,
                        [&]
                        {
                            for (std::int32_t frame = 0; frame < clip.effective_frame_count;
                                 ++frame)
                            {
                                append_f32(layout.bytes, static_cast<float>(frame) *
                                                             clip.descriptor.frame_delta_seconds);
                            }
                        });
}

[[nodiscard]] std::size_t append_translations(Layout& layout, const AnimationTrack& track)
{
    return append_range(layout, track.keys.size(), "VEC3", false, 0.0,
                        [&]
                        {
                            for (const auto& key : track.keys)
                            {
                                for (const float component : to_gltf(key.translation))
                                {
                                    append_f32(layout.bytes, component);
                                }
                            }
                        });
}

void preserve_hemisphere(std::array<float, 4>& value, const std::array<float, 4>& previous,
                         const bool has_previous)
{
    float dot = 0.0F;
    for (std::size_t index = 0; index < 4U; ++index)
    {
        dot += previous[index] * value[index];
    }
    if (has_previous && dot < 0.0F)
    {
        for (float& component : value)
        {
            component = -component;
        }
    }
}

[[nodiscard]] std::size_t append_rotations(Layout& layout, const AnimationTrack& track)
{
    return append_range(layout, track.keys.size(), "VEC4", false, 0.0,
                        [&]
                        {
                            std::array<float, 4> previous{};
                            bool has_previous = false;
                            for (const auto& key : track.keys)
                            {
                                auto value = to_gltf(key.rotation);
                                preserve_hemisphere(value, previous, has_previous);
                                for (const float component : value)
                                {
                                    append_f32(layout.bytes, component);
                                }
                                previous = value;
                                has_previous = true;
                            }
                        });
}

[[nodiscard]] bool append_clip(Layout& layout, const AnimationClip& clip,
                               const std::size_t source_index)
{
    if (clip.effective_frame_count <= 0 || clip.tracks.empty() ||
        clip.tracks.size() != clip.track_count)
    {
        return false;
    }
    ClipLayout clip_layout{.clip = &clip, .source_index = source_index, .tracks = {}};
    clip_layout.time_accessor = append_times(layout, clip);
    for (const auto& track : clip.tracks)
    {
        if (track.keys.size() != static_cast<std::size_t>(clip.effective_frame_count))
        {
            return false;
        }
        clip_layout.tracks.push_back({.translation_accessor = append_translations(layout, track),
                                      .rotation_accessor = append_rotations(layout, track)});
    }
    layout.clips.push_back(std::move(clip_layout));
    return true;
}

void write_nodes(std::ostringstream& output, const AnimationBinding& binding)
{
    const auto& descriptor = binding.package.skeletal_mesh.descriptor;
    output << "  \"nodes\": [\n";
    for (std::size_t index = 0; index < descriptor.bones.size(); ++index)
    {
        const auto& bone = descriptor.bones[index];
        const auto translation = to_gltf(bone.translation);
        const auto rotation = to_gltf(bone.rotation);
        output << R"(    {"name": )" << json_string(bone.name_bytes) << R"(, "translation": [)"
               << translation[0] << ", " << translation[1] << ", " << translation[2]
               << R"(], "rotation": [)" << rotation[0] << ", " << rotation[1] << ", " << rotation[2]
               << ", " << rotation[3] << ']';
        if (!bone.children.empty())
        {
            output << R"(, "children": [)";
            for (std::size_t child = 0; child < bone.children.size(); ++child)
            {
                output << bone.children[child] << (child + 1U == bone.children.size() ? "" : ", ");
            }
            output << ']';
        }
        output << '}' << (index + 1U == descriptor.bones.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

void write_animations(std::ostringstream& output, const Layout& layout)
{
    output << "  \"animations\": [\n";
    for (std::size_t clip_index = 0; clip_index < layout.clips.size(); ++clip_index)
    {
        const auto& item = layout.clips[clip_index];
        output << R"(    {"name": )" << json_string(item.clip->descriptor.animation_name_bytes)
               << ",\n      \"samplers\": [\n";
        for (std::size_t track = 0; track < item.tracks.size(); ++track)
        {
            const auto& accessors = item.tracks[track];
            output << R"(        {"input": )" << item.time_accessor << R"(, "output": )"
                   << accessors.translation_accessor << R"(, "interpolation": "LINEAR"},)" << '\n'
                   << R"(        {"input": )" << item.time_accessor << R"(, "output": )"
                   << accessors.rotation_accessor << R"(, "interpolation": "LINEAR"})"
                   << (track + 1U == item.tracks.size() ? "\n" : ",\n");
        }
        output << "      ],\n      \"channels\": [\n";
        for (std::size_t track = 0; track < item.tracks.size(); ++track)
        {
            const auto sampler = track * 2U;
            output << R"(        {"sampler": )" << sampler << R"(, "target": {"node": )" << track
                   << R"(, "path": "translation"}},)" << '\n'
                   << R"(        {"sampler": )" << sampler + 1U << R"(, "target": {"node": )"
                   << track << R"(, "path": "rotation"}})"
                   << (track + 1U == item.tracks.size() ? "\n" : ",\n");
        }
        output << R"(      ], "extras": {"tmxySourceClipIndex": )" << item.source_index
               << R"(, "tmxyLegacySelfLoop": )"
               << (item.clip->descriptor.self_loop ? "true" : "false") << "}}"
               << (clip_index + 1U == layout.clips.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

void write_scene_and_buffer(std::ostringstream& output, const AnimationBinding& binding,
                            const Layout& layout, const std::string_view buffer_uri)
{
    const auto& descriptor = binding.package.skeletal_mesh.descriptor;
    for (std::size_t index = 0; index < descriptor.root_bone_ids.size(); ++index)
    {
        output << descriptor.root_bone_ids[index]
               << (index + 1U == descriptor.root_bone_ids.size() ? "" : ", ");
    }
    output << "]}],\n";
    write_nodes(output, binding);
    output << R"(  "buffers": [{"uri": )" << json_string(buffer_uri) << R"(, "byteLength": )"
           << layout.bytes.size() << "}],\n";
}

void write_views(std::ostringstream& output, const Layout& layout)
{
    output << "  \"bufferViews\": [\n";
    for (std::size_t index = 0; index < layout.ranges.size(); ++index)
    {
        const auto& range = layout.ranges[index];
        output << R"(    {"buffer": 0, "byteOffset": )" << range.offset << R"(, "byteLength": )"
               << range.size << '}' << (index + 1U == layout.ranges.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

void write_accessors(std::ostringstream& output, const Layout& layout)
{
    output << "  \"accessors\": [\n";
    for (std::size_t accessor = 0; accessor < layout.ranges.size(); ++accessor)
    {
        const auto& range = layout.ranges[accessor];
        output << R"(    {"bufferView": )" << accessor << R"(, "componentType": 5126, "count": )"
               << range.count << R"(, "type": )" << json_string(range.type);
        if (range.time)
        {
            output << R"(, "min": [0], "max": [)" << range.maximum_time << ']';
        }
        output << '}' << (accessor + 1U == layout.ranges.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

[[nodiscard]] std::string build_json(const AnimationBinding& binding, const Layout& layout,
                                     const std::string_view buffer_uri)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<float>::max_digits10) << "{\n"
           << R"(  "asset": {"version": "2.0", "generator": "TMXY.Animation 0.2.0"},)" << '\n'
           << R"(  "scene": 0,)" << '\n'
           << R"(  "scenes": [{"nodes": [)";
    write_scene_and_buffer(output, binding, layout, buffer_uri);
    write_views(output, layout);
    write_accessors(output, layout);
    write_animations(output, layout);
    output
        << R"tmxy(  "extras": {"tmxyAssetKind": "animation_set", "tmxyCoordinateMapping": "legacy(x,y,z)-to-gltf(y,z,x)", "tmxyQuaternionPolicy": "normalized-adjacent-hemisphere-continuity", "tmxyRootMotionPolicy": "preserved-root-track-not-extracted"})tmxy"
        << "\n}\n";
    return output.str();
}

[[nodiscard]] std::string build_metadata(const AnimationBinding& binding,
                                         const std::vector<AnimationGltfClipEvidence>& clips)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<double>::max_digits10) << "{\n"
           << "  \"schema_version\": 1,\n"
           << "  \"asset_kind\": \"animation_set\",\n"
           << "  \"skeleton_root_name\": "
           << json_string(binding.package.skeletal_mesh.descriptor.bones.front().name_bytes)
           << ",\n  \"skeleton_bone_count\": "
           << binding.package.skeletal_mesh.descriptor.bones.size()
           << ",\n  \"source_animation_count\": " << binding.payload.clips.size()
           << ",\n  \"selected_clip_count\": " << clips.size() << ",\n  \"sample_rate_hz\": 30,\n"
           << "  \"root_motion_policy\": \"preserved-root-track-not-extracted\",\n"
           << "  \"quaternion_policy\": \"normalized-adjacent-hemisphere-continuity\",\n"
           << "  \"clips\": [\n";
    for (std::size_t index = 0; index < clips.size(); ++index)
    {
        const auto& clip = clips[index];
        output << "    {\"source_index\": " << clip.source_index
               << ", \"name\": " << json_string(clip.name)
               << ", \"frame_count\": " << clip.frame_count
               << ", \"track_count\": " << clip.track_count
               << ", \"sampled_duration_seconds\": " << clip.sampled_duration_seconds
               << ", \"legacy_loop_period_seconds\": " << clip.legacy_loop_period_seconds
               << ", \"self_loop\": " << (clip.self_loop ? "true" : "false")
               << ", \"root_classified_moving\": "
               << (clip.root_classified_moving ? "true" : "false")
               << ", \"root_translation_distance_meters\": "
               << clip.root_translation_distance_meters
               << ", \"maximum_endpoint_translation_delta_meters\": "
               << clip.maximum_endpoint_translation_delta_meters
               << ", \"maximum_endpoint_rotation_delta_degrees\": "
               << clip.maximum_endpoint_rotation_delta_degrees << '}'
               << (index + 1U == clips.size() ? "\n" : ",\n");
    }
    output << "  ]\n}\n";
    return output.str();
}

} // namespace

AnimationResult<AnimationGltfArtifacts>
build_selected_gltf2(const AnimationBinding& binding, const std::string_view buffer_uri,
                     const std::span<const std::string_view> selected_clip_names)
{
    const auto& descriptor = binding.package.skeletal_mesh.descriptor;
    if (!safe_uri(buffer_uri) || selected_clip_names.empty() || descriptor.bones.empty() ||
        descriptor.root_bone_ids.empty())
    {
        return AnimationResult<AnimationGltfArtifacts>::failure(gltf_error("gltf.contract"));
    }
    std::set<std::string, std::less<>> unique;
    Layout layout;
    AnimationGltfArtifacts artifacts;
    for (const std::string_view name : selected_clip_names)
    {
        const auto found =
            std::ranges::find_if(binding.payload.clips, [name](const AnimationClip& clip)
                                 { return clip.descriptor.animation_name_bytes == name; });
        if (name.empty() || !unique.emplace(name).second || found == binding.payload.clips.end() ||
            found->track_count > descriptor.bones.size())
        {
            return AnimationResult<AnimationGltfArtifacts>::failure(
                gltf_error("gltf.clip-selection"));
        }
        const auto source_index =
            static_cast<std::size_t>(std::distance(binding.payload.clips.begin(), found));
        if (!append_clip(layout, *found, source_index))
        {
            return AnimationResult<AnimationGltfArtifacts>::failure(gltf_error("gltf.clip-layout"));
        }
        artifacts.clips.push_back(make_evidence(*found, source_index));
    }
    artifacts.json = build_json(binding, layout, buffer_uri);
    artifacts.metadata_json = build_metadata(binding, artifacts.clips);
    artifacts.binary = std::move(layout.bytes);
    return AnimationResult<AnimationGltfArtifacts>::success(std::move(artifacts));
}

} // namespace tmxy::animation
