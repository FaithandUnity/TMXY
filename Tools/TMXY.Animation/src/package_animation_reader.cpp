#include "tmxy/animation/package_animation_reader.hpp"

#include "package_object_index.hpp"
#include "tmxy/animation/anim_reader.hpp"
#include "tmxy/format/binary_reader.hpp"
#include "tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::animation
{
namespace
{

constexpr std::uint16_t kMaximumDescriptorItems = 4096;
constexpr std::uint16_t kMaximumPropertyNameBytes = 2048;
constexpr std::uint16_t kMaximumNotifyReferences = 4096;
constexpr std::int32_t kMaximumFrames = 1'000'000;

struct PropertyRecord final
{
    std::string name;
    std::uint64_t value_offset{0};
    std::span<const std::byte> value;
};

struct IndexedString final
{
    std::uint16_t index{0};
    std::string value;
};

struct DescriptorState final
{
    AnimationDescriptor descriptor;
    std::optional<std::uint16_t> notify_count;
    std::vector<IndexedString> notifies;
    bool animation_name_seen{false};
    bool skeleton_name_seen{false};
    bool frame_count_seen{false};
    bool frame_delta_seen{false};
    bool self_loop_seen{false};
};

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

[[nodiscard]] AnimationResult<PropertyRecord> read_record(format::BinaryReader& reader)
{
    const auto name_offset = reader.absolute_position();
    const auto name_length = reader.read_u16();
    if (!name_length.has_value())
    {
        return AnimationResult<PropertyRecord>::failure(
            read_error(name_length.error(), "animation.property.name_length"));
    }
    if (name_length.value() > kMaximumPropertyNameBytes)
    {
        return AnimationResult<PropertyRecord>::failure(
            make_error(AnimationErrorCode::descriptor_name_limit_exceeded, name_offset,
                       "animation.property.name_length"));
    }
    const auto name = reader.read_bytes(name_length.value());
    const auto size = reader.read_u16();
    if (!name.has_value() || !size.has_value())
    {
        return AnimationResult<PropertyRecord>::failure(read_error(
            !name.has_value() ? name.error() : size.error(), "animation.property.header"));
    }
    const auto value_offset = reader.absolute_position();
    const auto value = reader.read_bytes(size.value());
    if (!value.has_value())
    {
        return AnimationResult<PropertyRecord>::failure(
            read_error(value.error(), "animation.property.value"));
    }
    return AnimationResult<PropertyRecord>::success(
        {.name =
             std::string(reinterpret_cast<const char*>(name.value().data()), name.value().size()),
         .value_offset = value_offset,
         .value = value.value()});
}

template <typename Value, typename ReadValue>
[[nodiscard]] AnimationResult<Value> read_scalar(const PropertyRecord& record,
                                                 const std::size_t expected_size,
                                                 const std::string& context, ReadValue read_value)
{
    if (record.value.size() != expected_size)
    {
        return AnimationResult<Value>::failure(
            make_error(AnimationErrorCode::invalid_property_size, record.value_offset, context));
    }
    format::BinaryReader reader(record.value, format::ByteOrder::little_endian, record.value_offset,
                                context);
    const auto value = read_value(reader);
    return value.has_value() ? AnimationResult<Value>::success(value.value())
                             : AnimationResult<Value>::failure(read_error(value.error(), context));
}

[[nodiscard]] AnimationResult<std::string> read_string(const PropertyRecord& record,
                                                       const std::string& context)
{
    format::BinaryReader reader(record.value, format::ByteOrder::little_endian, record.value_offset,
                                context);
    const auto length = reader.read_u16();
    if (!length.has_value())
    {
        return AnimationResult<std::string>::failure(read_error(length.error(), context));
    }
    const auto bytes = reader.read_bytes(length.value());
    if (!bytes.has_value() || reader.remaining() != 0U)
    {
        return AnimationResult<std::string>::failure(
            make_error(AnimationErrorCode::invalid_property_size, record.value_offset, context));
    }
    return AnimationResult<std::string>::success(
        std::string(reinterpret_cast<const char*>(bytes.value().data()), bytes.value().size()));
}

[[nodiscard]] std::optional<std::uint16_t> notify_index(const std::string_view name)
{
    constexpr std::string_view prefix = "notify[";
    if (!name.starts_with(prefix) || !name.ends_with(']'))
    {
        return std::nullopt;
    }
    const auto digits = name.substr(prefix.size(), name.size() - prefix.size() - 1U);
    std::uint32_t index = 0;
    const auto parsed = std::from_chars(digits.data(), digits.data() + digits.size(), index);
    if (parsed.ec != std::errc{} || parsed.ptr != digits.data() + digits.size() ||
        index > kMaximumNotifyReferences)
    {
        return std::nullopt;
    }
    return static_cast<std::uint16_t>(index);
}

[[nodiscard]] std::optional<AnimationError> set_string(std::string& target, bool& seen,
                                                       const PropertyRecord& record,
                                                       const std::string& context)
{
    if (seen)
    {
        return make_error(AnimationErrorCode::duplicate_property, record.value_offset, context);
    }
    auto value = read_string(record, context);
    if (!value.has_value())
    {
        return value.error();
    }
    target = std::move(value).take_value();
    seen = true;
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError>
handle_name_property(DescriptorState& state, const PropertyRecord& record, bool& handled)
{
    handled = true;
    if (record.name == "_animName")
    {
        return set_string(state.descriptor.animation_name_bytes, state.animation_name_seen, record,
                          "animation.name");
    }
    if (record.name == "_skeName")
    {
        return set_string(state.descriptor.skeleton_root_name_bytes, state.skeleton_name_seen,
                          record, "animation.skeleton_name");
    }
    handled = false;
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError> handle_frame_count(DescriptorState& state,
                                                               const PropertyRecord& record)
{
    if (state.frame_count_seen)
    {
        return make_error(AnimationErrorCode::duplicate_property, record.value_offset,
                          "animation.frame_count");
    }
    auto value =
        read_scalar<std::int32_t>(record, 4U, "animation.frame_count",
                                  [](format::BinaryReader& reader) { return reader.read_i32(); });
    if (!value.has_value())
    {
        return value.error();
    }
    if (value.value() <= 0 || value.value() > kMaximumFrames)
    {
        return make_error(AnimationErrorCode::invalid_frame_count, record.value_offset,
                          "animation.frame_count");
    }
    state.descriptor.frame_count = value.value();
    state.frame_count_seen = true;
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError> handle_frame_delta(DescriptorState& state,
                                                               const PropertyRecord& record)
{
    if (state.frame_delta_seen)
    {
        return make_error(AnimationErrorCode::duplicate_property, record.value_offset,
                          "animation.frame_delta");
    }
    auto value = read_scalar<float>(record, 4U, "animation.frame_delta",
                                    [](format::BinaryReader& reader) { return reader.read_f32(); });
    if (!value.has_value())
    {
        return value.error();
    }
    if (!std::isfinite(value.value()) || value.value() <= 0.0F)
    {
        return make_error(AnimationErrorCode::invalid_frame_delta, record.value_offset,
                          "animation.frame_delta");
    }
    state.descriptor.frame_delta_seconds = value.value();
    state.frame_delta_seen = true;
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError> handle_self_loop(DescriptorState& state,
                                                             const PropertyRecord& record)
{
    if (state.self_loop_seen)
    {
        return make_error(AnimationErrorCode::duplicate_property, record.value_offset,
                          "animation.self_loop");
    }
    auto value =
        read_scalar<std::uint8_t>(record, 1U, "animation.self_loop",
                                  [](format::BinaryReader& reader) { return reader.read_u8(); });
    if (!value.has_value())
    {
        return value.error();
    }
    if (value.value() > 1U)
    {
        return make_error(AnimationErrorCode::invalid_boolean, record.value_offset,
                          "animation.self_loop");
    }
    state.descriptor.self_loop = value.value() != 0U;
    state.self_loop_seen = true;
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError>
handle_timing_property(DescriptorState& state, const PropertyRecord& record, bool& handled)
{
    handled = true;
    if (record.name == "_frame")
    {
        return handle_frame_count(state, record);
    }
    if (record.name == "_frameDelta")
    {
        return handle_frame_delta(state, record);
    }
    if (record.name == "_selfLoop")
    {
        return handle_self_loop(state, record);
    }
    handled = false;
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError> handle_notify_count(DescriptorState& state,
                                                                const PropertyRecord& record)
{
    if (state.notify_count.has_value())
    {
        return make_error(AnimationErrorCode::duplicate_property, record.value_offset,
                          "animation.notify_count");
    }
    auto value =
        read_scalar<std::uint16_t>(record, 2U, "animation.notify_count",
                                   [](format::BinaryReader& reader) { return reader.read_u16(); });
    if (!value.has_value())
    {
        return value.error();
    }
    if (value.value() > kMaximumNotifyReferences)
    {
        return make_error(AnimationErrorCode::descriptor_item_limit_exceeded, record.value_offset,
                          "animation.notify_count");
    }
    state.notify_count = value.value();
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError> handle_notify_reference(DescriptorState& state,
                                                                    const PropertyRecord& record,
                                                                    const std::uint16_t index)
{
    if (std::ranges::any_of(state.notifies,
                            [index](const IndexedString& item) { return item.index == index; }))
    {
        return make_error(AnimationErrorCode::duplicate_property, record.value_offset,
                          "animation.notifies");
    }
    auto value = read_string(record, "animation.notifies");
    if (!value.has_value())
    {
        return value.error();
    }
    state.notifies.push_back({.index = index, .value = std::move(value).take_value()});
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError>
handle_notify_property(DescriptorState& state, const PropertyRecord& record, bool& handled)
{
    handled = true;
    if (record.name == "notify")
    {
        return handle_notify_count(state, record);
    }
    if (const auto index = notify_index(record.name); index.has_value())
    {
        return handle_notify_reference(state, record, index.value());
    }
    handled = false;
    return std::nullopt;
}

[[nodiscard]] std::optional<AnimationError>
handle_known_property(DescriptorState& state, const PropertyRecord& record, bool& handled)
{
    if (auto error = handle_name_property(state, record, handled); handled || error.has_value())
    {
        return error;
    }
    if (auto error = handle_timing_property(state, record, handled); handled || error.has_value())
    {
        return error;
    }
    return handle_notify_property(state, record, handled);
}

[[nodiscard]] AnimationResult<AnimationDescriptor> finalize_descriptor(DescriptorState state)
{
    if (!state.animation_name_seen || !state.skeleton_name_seen || !state.frame_count_seen ||
        !state.frame_delta_seen)
    {
        return AnimationResult<AnimationDescriptor>::failure(
            make_error(AnimationErrorCode::missing_property, state.descriptor.body_offset,
                       "animation.required_metadata"));
    }
    const auto expected = state.notify_count.value_or(0U);
    if (state.notifies.size() != expected)
    {
        return AnimationResult<AnimationDescriptor>::failure(
            make_error(AnimationErrorCode::missing_property, state.descriptor.body_offset,
                       "animation.notifies"));
    }
    std::ranges::sort(state.notifies, {}, &IndexedString::index);
    state.descriptor.notify_object_names.reserve(expected);
    for (std::uint16_t index = 0; index < expected; ++index)
    {
        if (state.notifies[index].index != index)
        {
            return AnimationResult<AnimationDescriptor>::failure(
                make_error(AnimationErrorCode::missing_property, state.descriptor.body_offset,
                           "animation.notifies"));
        }
        state.descriptor.notify_object_names.push_back(std::move(state.notifies[index].value));
    }
    return AnimationResult<AnimationDescriptor>::success(std::move(state.descriptor));
}

} // namespace

AnimationResult<AnimationDescriptor>
read_animation_descriptor(const std::span<const std::byte> object_body,
                          const std::string_view object_name_bytes, const std::uint64_t base_offset)
{
    format::BinaryReader reader(object_body, format::ByteOrder::little_endian, base_offset,
                                "animation.descriptor");
    const auto count_offset = reader.absolute_position();
    const auto count = reader.read_u16();
    if (!count.has_value())
    {
        return AnimationResult<AnimationDescriptor>::failure(
            read_error(count.error(), "animation.property_count"));
    }
    if (count.value() > kMaximumDescriptorItems)
    {
        return AnimationResult<AnimationDescriptor>::failure(
            make_error(AnimationErrorCode::descriptor_item_limit_exceeded, count_offset,
                       "animation.property_count"));
    }
    DescriptorState state;
    state.descriptor.object_name_bytes = object_name_bytes;
    state.descriptor.body_offset = base_offset;
    state.descriptor.body_size = object_body.size();
    for (std::uint16_t index = 0; index < count.value(); ++index)
    {
        auto record = read_record(reader);
        if (!record.has_value())
        {
            return AnimationResult<AnimationDescriptor>::failure(record.error());
        }
        bool handled = false;
        if (const auto error = handle_known_property(state, record.value(), handled);
            error.has_value())
        {
            return AnimationResult<AnimationDescriptor>::failure(error.value());
        }
        if (!handled)
        {
            const auto& property = record.value();
            state.descriptor.unknown_properties.push_back(
                {.name_bytes = property.name,
                 .value_offset = property.value_offset,
                 .value = std::vector<std::byte>(property.value.begin(), property.value.end())});
        }
    }
    if (reader.remaining() != 0U)
    {
        return AnimationResult<AnimationDescriptor>::failure(
            make_error(AnimationErrorCode::trailing_bytes, reader.absolute_position(),
                       "animation.descriptor.trailing"));
    }
    return finalize_descriptor(std::move(state));
}

AnimationResult<PackageAnimationSetDescriptor>
read_package_animation_set_descriptor(const std::span<const std::byte> package_bytes,
                                      const std::string_view skeletal_mesh_object_name)
{
    auto skeletal = skeletal_mesh::read_package_skeletal_mesh_descriptor(package_bytes,
                                                                         skeletal_mesh_object_name);
    if (!skeletal.has_value())
    {
        return AnimationResult<PackageAnimationSetDescriptor>::failure(
            make_error(AnimationErrorCode::skeletal_mesh_descriptor_failure,
                       skeletal.error().absolute_offset, skeletal.error().context));
    }
    auto objects = read_package_objects(package_bytes);
    if (!objects.has_value())
    {
        return AnimationResult<PackageAnimationSetDescriptor>::failure(objects.error());
    }
    PackageAnimationSetDescriptor result{.skeletal_mesh = std::move(skeletal).take_value(),
                                         .animations = {}};
    const auto& references = result.skeletal_mesh.descriptor.animation_object_names;
    result.animations.reserve(references.size());
    for (const auto& reference : references)
    {
        const auto found = std::ranges::find(objects.value(), reference, &ObjectSpan::name);
        if (found == objects.value().end())
        {
            return AnimationResult<PackageAnimationSetDescriptor>::failure(
                make_error(AnimationErrorCode::animation_object_not_found, 0, reference));
        }
        if (found->class_name != "QSkelAnim")
        {
            return AnimationResult<PackageAnimationSetDescriptor>::failure(
                make_error(AnimationErrorCode::wrong_object_class, found->offset, reference));
        }
        if (found->offset > package_bytes.size() ||
            found->size > package_bytes.size() - found->offset)
        {
            return AnimationResult<PackageAnimationSetDescriptor>::failure(
                make_error(AnimationErrorCode::object_range_out_of_file, found->offset, reference));
        }
        auto descriptor =
            read_animation_descriptor(package_bytes.subspan(static_cast<std::size_t>(found->offset),
                                                            static_cast<std::size_t>(found->size)),
                                      found->name, found->offset);
        if (!descriptor.has_value())
        {
            return AnimationResult<PackageAnimationSetDescriptor>::failure(descriptor.error());
        }
        result.animations.push_back(std::move(descriptor).take_value());
    }
    return AnimationResult<PackageAnimationSetDescriptor>::success(std::move(result));
}

AnimationResult<AnimationBinding>
bind_animation_set(const std::span<const std::byte> package_bytes,
                   const std::string_view skeletal_mesh_object_name,
                   const std::span<const std::byte> animation_bytes)
{
    auto package = read_package_animation_set_descriptor(package_bytes, skeletal_mesh_object_name);
    if (!package.has_value())
    {
        return AnimationResult<AnimationBinding>::failure(package.error());
    }
    auto payload = AnimReader::parse(
        animation_bytes, package.value().animations,
        static_cast<std::uint32_t>(package.value().skeletal_mesh.descriptor.bones.size()));
    if (!payload.has_value())
    {
        return AnimationResult<AnimationBinding>::failure(payload.error());
    }
    return AnimationResult<AnimationBinding>::success(
        {.package = std::move(package).take_value(), .payload = std::move(payload).take_value()});
}

AnimationResult<AnimationBinding>
bind_animation_set_with_payload_frame_counts(const std::span<const std::byte> package_bytes,
                                             const std::string_view skeletal_mesh_object_name,
                                             const std::span<const std::byte> animation_bytes)
{
    auto package = read_package_animation_set_descriptor(package_bytes, skeletal_mesh_object_name);
    if (!package.has_value())
    {
        return AnimationResult<AnimationBinding>::failure(package.error());
    }
    auto payload = AnimReader::parse_with_payload_frame_counts(
        animation_bytes, package.value().animations,
        static_cast<std::uint32_t>(package.value().skeletal_mesh.descriptor.bones.size()));
    if (!payload.has_value())
    {
        return AnimationResult<AnimationBinding>::failure(payload.error());
    }
    return AnimationResult<AnimationBinding>::success(
        {.package = std::move(package).take_value(), .payload = std::move(payload).take_value()});
}

} // namespace tmxy::animation
