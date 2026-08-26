#include "tmxy/animation/anim_reader.hpp"

#include "tmxy/format/binary_reader.hpp"
#include "tmxy/transform/legacy_to_ue_transform.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <numbers>
#include <string>
#include <utility>

namespace tmxy::animation
{
namespace
{

constexpr std::uint64_t kMaximumTotalKeys = 50'000'000;
constexpr std::int32_t kMaximumEmitterPoints = 1'000'000;
constexpr double kQuaternionNormSquaredFloor = 1.0e-12;
constexpr double kRootTranslationMovingThresholdMeters = 1.0e-4;
constexpr double kRootRotationMovingThresholdDegrees = 0.01;

[[nodiscard]] AnimationError make_error(const AnimationErrorCode code, const std::uint64_t offset,
                                        std::string context)
{
    return {.code = code,
            .absolute_offset = offset,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] AnimationError read_error(const format::ReadError& error, std::string context)
{
    return {.code = AnimationErrorCode::read_failure,
            .absolute_offset = error.absolute_offset,
            .context = std::move(context),
            .read_error_code = error.code};
}

[[nodiscard]] AnimationResult<float> read_finite_f32(format::BinaryReader& reader,
                                                     const std::string& context)
{
    const auto offset = reader.absolute_position();
    const auto value = reader.read_f32();
    if (!value.has_value())
    {
        return AnimationResult<float>::failure(read_error(value.error(), context));
    }
    if (!std::isfinite(value.value()))
    {
        return AnimationResult<float>::failure(
            make_error(AnimationErrorCode::non_finite_key, offset, context));
    }
    return AnimationResult<float>::success(value.value());
}

[[nodiscard]] AnimationResult<AnimationKey> read_key(format::BinaryReader& reader,
                                                     const std::string& context)
{
    std::array<float, 7> values{};
    for (auto& value : values)
    {
        auto parsed = read_finite_f32(reader, context);
        if (!parsed.has_value())
        {
            return AnimationResult<AnimationKey>::failure(parsed.error());
        }
        value = parsed.value();
    }
    const double norm_squared = (static_cast<double>(values[0]) * values[0]) +
                                (static_cast<double>(values[1]) * values[1]) +
                                (static_cast<double>(values[2]) * values[2]) +
                                (static_cast<double>(values[3]) * values[3]);
    if (norm_squared <= kQuaternionNormSquaredFloor)
    {
        return AnimationResult<AnimationKey>::failure(
            make_error(AnimationErrorCode::invalid_quaternion,
                       reader.absolute_position() - (sizeof(float) * values.size()), context));
    }
    return AnimationResult<AnimationKey>::success(
        {.rotation = {.x = values[0], .y = values[1], .z = values[2], .w = values[3]},
         .translation = {.x = values[4], .y = values[5], .z = values[6]}});
}

[[nodiscard]] double distance(const skeletal_mesh::Vec3& left,
                              const skeletal_mesh::Vec3& right) noexcept
{
    const auto x = static_cast<double>(right.x) - left.x;
    const auto y = static_cast<double>(right.y) - left.y;
    const auto z = static_cast<double>(right.z) - left.z;
    return std::sqrt((x * x) + (y * y) + (z * z));
}

[[nodiscard]] double angular_delta_degrees(const skeletal_mesh::Quaternion& left,
                                           const skeletal_mesh::Quaternion& right) noexcept
{
    const auto left_norm =
        std::sqrt((static_cast<double>(left.x) * left.x) + (static_cast<double>(left.y) * left.y) +
                  (static_cast<double>(left.z) * left.z) + (static_cast<double>(left.w) * left.w));
    const auto right_norm = std::sqrt(
        (static_cast<double>(right.x) * right.x) + (static_cast<double>(right.y) * right.y) +
        (static_cast<double>(right.z) * right.z) + (static_cast<double>(right.w) * right.w));
    const auto dot = std::abs(
        ((static_cast<double>(left.x) * right.x) + (static_cast<double>(left.y) * right.y) +
         (static_cast<double>(left.z) * right.z) + (static_cast<double>(left.w) * right.w)) /
        (left_norm * right_norm));
    return 2.0 * std::acos(std::clamp(dot, 0.0, 1.0)) * 180.0 / std::numbers::pi;
}

[[nodiscard]] RootMotionSummary summarize_root_motion(const AnimationClip& clip) noexcept
{
    RootMotionSummary result;
    if (clip.tracks.empty() || clip.tracks.front().keys.empty())
    {
        return result;
    }
    result.has_root_track = true;
    const auto& keys = clip.tracks.front().keys;
    const auto& first = keys.front();
    const auto& last = keys.back();
    result.translation_delta_legacy_meters = {.x = last.translation.x - first.translation.x,
                                              .y = last.translation.y - first.translation.y,
                                              .z = last.translation.z - first.translation.z};
    const auto converted =
        transform::LegacyToUETransform::position({.x = result.translation_delta_legacy_meters.x,
                                                  .y = result.translation_delta_legacy_meters.y,
                                                  .z = result.translation_delta_legacy_meters.z});
    if (converted.has_value())
    {
        result.translation_delta_ue_centimeters = {.x = static_cast<float>(converted.value().x),
                                                   .y = static_cast<float>(converted.value().y),
                                                   .z = static_cast<float>(converted.value().z)};
    }
    result.translation_distance_legacy_meters = distance(first.translation, last.translation);
    for (const auto& key : keys)
    {
        result.maximum_excursion_legacy_meters = std::max(
            result.maximum_excursion_legacy_meters, distance(first.translation, key.translation));
    }
    result.angular_delta_degrees = angular_delta_degrees(first.rotation, last.rotation);
    result.classified_moving =
        result.maximum_excursion_legacy_meters > kRootTranslationMovingThresholdMeters ||
        result.angular_delta_degrees > kRootRotationMovingThresholdDegrees;
    return result;
}

[[nodiscard]] AnimationResult<AnimationClip> read_clip(format::BinaryReader& reader,
                                                       const AnimationDescriptor& descriptor,
                                                       const std::uint32_t skeleton_bone_count,
                                                       std::uint64_t& total_keys)
{
    const auto track_offset = reader.absolute_position();
    const auto track_count = reader.read_i32();
    if (!track_count.has_value())
    {
        return AnimationResult<AnimationClip>::failure(
            read_error(track_count.error(), descriptor.object_name_bytes + ".track_count"));
    }
    if (track_count.value() <= 0 || std::cmp_greater(track_count.value(), skeleton_bone_count))
    {
        return AnimationResult<AnimationClip>::failure(
            make_error(AnimationErrorCode::invalid_track_count, track_offset,
                       descriptor.object_name_bytes + ".track_count"));
    }
    const auto frame_offset = reader.absolute_position();
    const auto frame_count = reader.read_i32();
    if (!frame_count.has_value())
    {
        return AnimationResult<AnimationClip>::failure(
            read_error(frame_count.error(), descriptor.object_name_bytes + ".frame_count"));
    }
    if (frame_count.value() != descriptor.frame_count)
    {
        return AnimationResult<AnimationClip>::failure(
            make_error(AnimationErrorCode::frame_count_mismatch, frame_offset,
                       descriptor.object_name_bytes + ".frame_count"));
    }
    const auto clip_key_count = static_cast<std::uint64_t>(track_count.value()) *
                                static_cast<std::uint64_t>(frame_count.value());
    if (clip_key_count > kMaximumTotalKeys || total_keys > kMaximumTotalKeys - clip_key_count)
    {
        return AnimationResult<AnimationClip>::failure(
            make_error(AnimationErrorCode::key_count_limit_exceeded, track_offset,
                       descriptor.object_name_bytes + ".keys"));
    }
    constexpr std::uint64_t key_size = sizeof(float) * 7U;
    if (clip_key_count > reader.remaining() / key_size)
    {
        return AnimationResult<AnimationClip>::failure(
            make_error(AnimationErrorCode::read_failure, reader.absolute_position(),
                       descriptor.object_name_bytes + ".keys"));
    }
    AnimationClip clip{.descriptor = descriptor,
                       .track_count = static_cast<std::uint32_t>(track_count.value()),
                       .tracks = {},
                       .sampled_duration_seconds = static_cast<double>(frame_count.value() - 1) *
                                                   descriptor.frame_delta_seconds,
                       .legacy_loop_period_seconds =
                           static_cast<double>(descriptor.self_loop ? frame_count.value() - 1
                                                                    : frame_count.value()) *
                           descriptor.frame_delta_seconds,
                       .root_motion = {}};
    clip.tracks.reserve(clip.track_count);
    for (std::uint32_t bone = 0; bone < clip.track_count; ++bone)
    {
        AnimationTrack track{.bone_id = bone, .keys = {}};
        track.keys.reserve(static_cast<std::size_t>(frame_count.value()));
        for (std::int32_t frame = 0; frame < frame_count.value(); ++frame)
        {
            auto key = read_key(reader, descriptor.object_name_bytes + ".keys");
            if (!key.has_value())
            {
                return AnimationResult<AnimationClip>::failure(key.error());
            }
            track.keys.push_back(std::move(key).take_value());
        }
        clip.tracks.push_back(std::move(track));
    }
    total_keys += clip_key_count;
    clip.root_motion = summarize_root_motion(clip);
    return AnimationResult<AnimationClip>::success(std::move(clip));
}

[[nodiscard]] AnimationResult<std::vector<skeletal_mesh::Vec3>>
read_emitter_points(format::BinaryReader& reader)
{
    std::vector<skeletal_mesh::Vec3> points;
    if (reader.remaining() == 0U)
    {
        return AnimationResult<std::vector<skeletal_mesh::Vec3>>::success(std::move(points));
    }
    const auto count_offset = reader.absolute_position();
    const auto count = reader.read_i32();
    if (!count.has_value())
    {
        return AnimationResult<std::vector<skeletal_mesh::Vec3>>::failure(
            read_error(count.error(), "animation.emitter_points.count"));
    }
    if (count.value() < 0 || count.value() > kMaximumEmitterPoints ||
        std::cmp_greater(count.value(), reader.remaining() / (sizeof(float) * 3U)))
    {
        return AnimationResult<std::vector<skeletal_mesh::Vec3>>::failure(
            make_error(AnimationErrorCode::invalid_emitter_count, count_offset,
                       "animation.emitter_points.count"));
    }
    points.reserve(static_cast<std::size_t>(count.value()));
    for (std::int32_t index = 0; index < count.value(); ++index)
    {
        std::array<float, 3> values{};
        for (auto& value : values)
        {
            auto parsed = read_finite_f32(reader, "animation.emitter_points");
            if (!parsed.has_value())
            {
                return AnimationResult<std::vector<skeletal_mesh::Vec3>>::failure(parsed.error());
            }
            value = parsed.value();
        }
        points.push_back({.x = values[0], .y = values[1], .z = values[2]});
    }
    if (reader.remaining() != 0U)
    {
        return AnimationResult<std::vector<skeletal_mesh::Vec3>>::failure(make_error(
            AnimationErrorCode::trailing_bytes, reader.absolute_position(), "animation.trailing"));
    }
    return AnimationResult<std::vector<skeletal_mesh::Vec3>>::success(std::move(points));
}

} // namespace

AnimationResult<AnimationPayload>
AnimReader::parse(const std::span<const std::byte> bytes,
                  const std::span<const AnimationDescriptor> descriptors,
                  const std::uint32_t skeleton_bone_count)
{
    format::BinaryReader reader(bytes, format::ByteOrder::little_endian, 0, "animation.payload");
    const auto count_offset = reader.absolute_position();
    const auto animation_count = reader.read_i32();
    if (!animation_count.has_value())
    {
        return AnimationResult<AnimationPayload>::failure(
            read_error(animation_count.error(), "animation.count"));
    }
    if (animation_count.value() < 0 ||
        std::cmp_not_equal(animation_count.value(), descriptors.size()))
    {
        return AnimationResult<AnimationPayload>::failure(make_error(
            AnimationErrorCode::animation_count_mismatch, count_offset, "animation.count"));
    }
    AnimationPayload payload;
    payload.clips.reserve(descriptors.size());
    for (const auto& descriptor : descriptors)
    {
        auto clip = read_clip(reader, descriptor, skeleton_bone_count, payload.total_key_count);
        if (!clip.has_value())
        {
            return AnimationResult<AnimationPayload>::failure(clip.error());
        }
        payload.total_track_count += clip.value().track_count;
        payload.clips.push_back(std::move(clip).take_value());
    }
    auto emitter_points = read_emitter_points(reader);
    if (!emitter_points.has_value())
    {
        return AnimationResult<AnimationPayload>::failure(emitter_points.error());
    }
    payload.emitter_points = std::move(emitter_points).take_value();
    return AnimationResult<AnimationPayload>::success(std::move(payload));
}

} // namespace tmxy::animation
