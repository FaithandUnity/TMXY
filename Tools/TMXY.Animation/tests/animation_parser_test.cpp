#include "tmxy/animation/anim_reader.hpp"
#include "tmxy/animation/animation_error.hpp"
#include "tmxy/animation/animation_export.hpp"
#include "tmxy/animation/package_animation_reader.hpp"

#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace
{

class TestContext final
{
  public:
    void expect(const bool condition, const std::string_view message)
    {
        if (!condition)
        {
            ++failures_;
            std::cerr << "FAILED: " << message << '\n';
        }
    }

    [[nodiscard]] int failures() const noexcept
    {
        return failures_;
    }

  private:
    int failures_{0};
};

void append_u8(std::vector<std::byte>& bytes, const std::uint8_t value)
{
    bytes.push_back(static_cast<std::byte>(value));
}

void append_u16(std::vector<std::byte>& bytes, const std::uint16_t value)
{
    append_u8(bytes, static_cast<std::uint8_t>(value & 0xFFU));
    append_u8(bytes, static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
}

void append_i32(std::vector<std::byte>& bytes, const std::int32_t value)
{
    const auto raw = std::bit_cast<std::uint32_t>(value);
    for (unsigned int shift = 0; shift < 32U; shift += 8U)
    {
        append_u8(bytes, static_cast<std::uint8_t>((raw >> shift) & 0xFFU));
    }
}

void append_f32(std::vector<std::byte>& bytes, const float value)
{
    append_i32(bytes, std::bit_cast<std::int32_t>(value));
}

[[nodiscard]] std::vector<std::byte> string_value(const std::string_view value)
{
    std::vector<std::byte> bytes;
    append_u16(bytes, static_cast<std::uint16_t>(value.size()));
    for (const char character : value)
    {
        append_u8(bytes, static_cast<std::uint8_t>(character));
    }
    return bytes;
}

[[nodiscard]] std::vector<std::byte> i32_value(const std::int32_t value)
{
    std::vector<std::byte> bytes;
    append_i32(bytes, value);
    return bytes;
}

[[nodiscard]] std::vector<std::byte> f32_value(const float value)
{
    std::vector<std::byte> bytes;
    append_f32(bytes, value);
    return bytes;
}

[[nodiscard]] std::vector<std::byte> u16_value(const std::uint16_t value)
{
    std::vector<std::byte> bytes;
    append_u16(bytes, value);
    return bytes;
}

void append_property(std::vector<std::byte>& properties, std::uint16_t& count,
                     const std::string_view name, const std::span<const std::byte> value)
{
    ++count;
    append_u16(properties, static_cast<std::uint16_t>(name.size()));
    for (const char character : name)
    {
        append_u8(properties, static_cast<std::uint8_t>(character));
    }
    append_u16(properties, static_cast<std::uint16_t>(value.size()));
    properties.insert(properties.end(), value.begin(), value.end());
}

[[nodiscard]] std::vector<std::byte> make_descriptor(const std::uint8_t loop_value = 1U)
{
    std::vector<std::byte> properties;
    std::uint16_t count = 0;
    append_property(properties, count, "_animName", string_value("walk"));
    append_property(properties, count, "_skeName", string_value("root"));
    append_property(properties, count, "_frame", i32_value(3));
    append_property(properties, count, "_frameDelta", f32_value(0.5F));
    const std::vector<std::byte> loop{static_cast<std::byte>(loop_value)};
    append_property(properties, count, "_selfLoop", loop);
    append_property(properties, count, "notify", u16_value(1U));
    append_property(properties, count, "notify[0]", string_value("sample.notify"));
    append_property(properties, count, "futureField", i32_value(7));
    std::vector<std::byte> body;
    append_u16(body, count);
    body.insert(body.end(), properties.begin(), properties.end());
    return body;
}

void append_key(std::vector<std::byte>& bytes, const float x, const bool zero_quaternion = false)
{
    append_f32(bytes, 0.0F);
    append_f32(bytes, 0.0F);
    append_f32(bytes, 0.0F);
    append_f32(bytes, zero_quaternion ? 0.0F : 1.0F);
    append_f32(bytes, x);
    append_f32(bytes, 0.0F);
    append_f32(bytes, 0.0F);
}

[[nodiscard]] std::vector<std::byte> make_payload(const bool bad_quaternion = false)
{
    std::vector<std::byte> bytes;
    append_i32(bytes, 1);
    append_i32(bytes, 2);
    append_i32(bytes, 3);
    for (std::int32_t bone = 0; bone < 2; ++bone)
    {
        for (std::int32_t frame = 0; frame < 3; ++frame)
        {
            append_key(bytes, bone == 0 ? static_cast<float>(frame) : 0.0F,
                       bad_quaternion && bone == 1 && frame == 2);
        }
    }
    append_i32(bytes, 1);
    append_f32(bytes, 1.0F);
    append_f32(bytes, 2.0F);
    append_f32(bytes, 3.0F);
    return bytes;
}

void test_descriptor(TestContext& test, tmxy::animation::AnimationDescriptor& descriptor)
{
    auto parsed = tmxy::animation::read_animation_descriptor(make_descriptor(), "sample.walk", 42U);
    test.expect(parsed.has_value(), "valid QSkelAnim metadata parses");
    if (!parsed.has_value())
    {
        return;
    }
    descriptor = parsed.value();
    test.expect(descriptor.animation_name_bytes == "walk", "animation name preserved");
    test.expect(descriptor.skeleton_root_name_bytes == "root", "skeleton name preserved");
    test.expect(descriptor.frame_count == 3, "frame count preserved");
    test.expect(descriptor.frame_delta_seconds == 0.5F, "frame delta preserved");
    test.expect(descriptor.self_loop, "self-loop preserved");
    test.expect(descriptor.notify_object_names == std::vector<std::string>{"sample.notify"},
                "notify reference order preserved");
    test.expect(descriptor.unknown_properties.size() == 1U, "unknown property preserved");

    const auto invalid_loop =
        tmxy::animation::read_animation_descriptor(make_descriptor(2U), "sample.walk");
    test.expect(!invalid_loop.has_value() &&
                    invalid_loop.error().code ==
                        tmxy::animation::AnimationErrorCode::invalid_boolean,
                "non-boolean self-loop rejected");
}

void test_payload(TestContext& test, const tmxy::animation::AnimationDescriptor& descriptor)
{
    const std::vector descriptors{descriptor};
    auto parsed = tmxy::animation::AnimReader::parse(make_payload(), descriptors, 4U);
    test.expect(parsed.has_value(), "valid dense-prefix animation payload parses");
    if (!parsed.has_value())
    {
        return;
    }
    const auto& payload = parsed.value();
    test.expect(payload.clips.size() == 1U && payload.total_track_count == 2U &&
                    payload.total_key_count == 6U,
                "clip track and key counts preserved");
    test.expect(payload.clips[0].tracks[1].bone_id == 1U,
                "track IDs are an ordered dense skeleton prefix");
    test.expect(payload.clips[0].sampled_duration_seconds == 1.0,
                "sampled duration uses frame count minus one");
    test.expect(payload.clips[0].legacy_loop_period_seconds == 1.0,
                "self-loop period skips duplicated terminal frame");
    test.expect(payload.clips[0].root_motion.classified_moving &&
                    payload.clips[0].root_motion.translation_delta_ue_centimeters.x == 200.0F,
                "root movement is measured and converted to UE centimeters");
    test.expect(payload.emitter_points.size() == 1U, "optional emitter tail preserved");

    tmxy::animation::AnimationBinding binding;
    binding.package.skeletal_mesh.object_name_bytes = "sample.mesh";
    binding.package.animations = descriptors;
    binding.payload = payload;
    const auto json = tmxy::animation::build_animation_json(binding);
    const auto csv = tmxy::animation::build_root_motion_csv(binding);
    test.expect(json.find(R"("dense_prefix_track_ids": true)") != std::string::npos,
                "JSON states dense-prefix semantics");
    test.expect(csv.find("200") != std::string::npos, "root CSV contains converted samples");
}

void test_corruption(TestContext& test, const tmxy::animation::AnimationDescriptor& descriptor)
{
    const std::vector descriptors{descriptor};
    auto mismatch = make_payload();
    mismatch[0] = std::byte{0x02};
    test.expect(tmxy::animation::AnimReader::parse(mismatch, descriptors, 4U).error().code ==
                    tmxy::animation::AnimationErrorCode::animation_count_mismatch,
                "animation count mismatch rejected");

    auto bad_tracks = make_payload();
    bad_tracks[4] = std::byte{0x05};
    const auto track_result = tmxy::animation::AnimReader::parse(bad_tracks, descriptors, 4U);
    test.expect(!track_result.has_value() &&
                    track_result.error().code ==
                        tmxy::animation::AnimationErrorCode::invalid_track_count,
                "track count beyond skeleton rejected");

    auto bad_frames = make_payload();
    bad_frames[8] = std::byte{0x02};
    const auto frame_result = tmxy::animation::AnimReader::parse(bad_frames, descriptors, 4U);
    test.expect(!frame_result.has_value() &&
                    frame_result.error().code ==
                        tmxy::animation::AnimationErrorCode::frame_count_mismatch,
                "Package and payload frame mismatch rejected");

    const auto quaternion_result =
        tmxy::animation::AnimReader::parse(make_payload(true), descriptors, 4U);
    test.expect(!quaternion_result.has_value() &&
                    quaternion_result.error().code ==
                        tmxy::animation::AnimationErrorCode::invalid_quaternion,
                "zero quaternion rejected");

    auto trailing = make_payload();
    trailing.push_back(std::byte{0xFF});
    const auto trailing_result = tmxy::animation::AnimReader::parse(trailing, descriptors, 4U);
    test.expect(!trailing_result.has_value() &&
                    trailing_result.error().code ==
                        tmxy::animation::AnimationErrorCode::trailing_bytes,
                "unexplained trailing bytes rejected");
}

} // namespace

int main()
{
    TestContext test;
    tmxy::animation::AnimationDescriptor descriptor;
    test_descriptor(test, descriptor);
    if (descriptor.frame_count != 0)
    {
        test_payload(test, descriptor);
        test_corruption(test, descriptor);
    }
    const std::vector<tmxy::animation::AnimationDescriptor> empty;
    std::vector<std::byte> empty_payload;
    append_i32(empty_payload, 0);
    test.expect(tmxy::animation::AnimReader::parse(empty_payload, empty, 0U).has_value(),
                "four-byte zero-animation file is valid");
    test.expect(tmxy::animation::AnimationError::kSchemaVersion == 1U,
                "error schema version is frozen");
    return test.failures() == 0 ? 0 : 1;
}
