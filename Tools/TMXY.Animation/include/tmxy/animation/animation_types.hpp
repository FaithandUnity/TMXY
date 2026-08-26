#pragma once

#include "tmxy/skeletal_mesh/skeletal_mesh_types.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace tmxy::animation
{

struct UnknownProperty final
{
    std::string name_bytes;
    std::uint64_t value_offset{0};
    std::vector<std::byte> value;
};

struct AnimationDescriptor final
{
    std::string object_name_bytes;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    std::string animation_name_bytes;
    std::string skeleton_root_name_bytes;
    std::int32_t frame_count{0};
    float frame_delta_seconds{0.0F};
    bool self_loop{false};
    std::vector<std::string> notify_object_names;
    std::vector<UnknownProperty> unknown_properties;
};

struct PackageAnimationSetDescriptor final
{
    skeletal_mesh::PackageSkeletalMeshDescriptor skeletal_mesh;
    std::vector<AnimationDescriptor> animations;
};

struct AnimationKey final
{
    skeletal_mesh::Quaternion rotation;
    skeletal_mesh::Vec3 translation;
};

struct AnimationTrack final
{
    std::uint32_t bone_id{0};
    std::vector<AnimationKey> keys;
};

struct RootMotionSummary final
{
    bool has_root_track{false};
    bool classified_moving{false};
    skeletal_mesh::Vec3 translation_delta_legacy_meters;
    skeletal_mesh::Vec3 translation_delta_ue_centimeters;
    double translation_distance_legacy_meters{0.0};
    double maximum_excursion_legacy_meters{0.0};
    double angular_delta_degrees{0.0};
};

struct AnimationClip final
{
    AnimationDescriptor descriptor;
    std::uint32_t track_count{0};
    std::vector<AnimationTrack> tracks;
    double sampled_duration_seconds{0.0};
    double legacy_loop_period_seconds{0.0};
    RootMotionSummary root_motion;
};

struct AnimationPayload final
{
    std::vector<AnimationClip> clips;
    std::vector<skeletal_mesh::Vec3> emitter_points;
    std::uint64_t total_track_count{0};
    std::uint64_t total_key_count{0};
};

struct AnimationBinding final
{
    PackageAnimationSetDescriptor package;
    AnimationPayload payload;
};

} // namespace tmxy::animation
