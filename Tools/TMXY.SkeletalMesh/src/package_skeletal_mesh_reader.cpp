#include "tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp"

#include "tmxy/format/binary_reader.hpp"
#include "tmxy/package/package_v1.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3.hpp"
#include "tmxy/package/package_v3_reader.hpp"

#include <algorithm>
#include <array>
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

namespace tmxy::skeletal_mesh
{
namespace
{

using namespace std::string_view_literals;

constexpr std::uint16_t kMaximumDescriptorItems = 16'384;
constexpr std::uint16_t kMaximumPropertyNameBytes = 2048;
constexpr std::uint16_t kMaximumBones = 4096;
constexpr std::uint16_t kMaximumReferences = 8192;

enum class PackageKind : std::uint8_t
{
    unknown = 0,
    v1 = 1,
    v2 = 2,
    v3 = 3,
};

struct ObjectSpan final
{
    std::string name;
    std::string class_name;
    std::uint64_t offset{0};
    std::uint64_t size{0};
};

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

struct IndexedInt final
{
    std::uint16_t index{0};
    std::int32_t value{0};
};

struct BoneState final
{
    Bone bone;
    std::array<bool, 4> rotation_seen{};
    std::array<bool, 3> translation_seen{};
    std::optional<std::uint16_t> child_count;
    std::vector<IndexedInt> children;
    bool id_seen{false};
    bool name_seen{false};
};

struct DescriptorState final
{
    SkeletalMeshDescriptor descriptor;
    std::optional<std::uint16_t> bone_count;
    std::optional<std::uint16_t> animation_count;
    std::optional<std::uint16_t> default_count;
    std::optional<std::uint16_t> material_count;
    std::vector<BoneState> bones;
    std::vector<IndexedString> animations;
    std::vector<IndexedInt> defaults;
    std::vector<IndexedString> materials;
    std::array<bool, 6> bounds_seen{};
    std::array<bool, 3> offset_seen{};
    std::array<bool, 3> rotation_seen{};
    Aabb bounds;
    Vec3 offset;
    Vec3 rotation;
    bool default_animation_seen{false};
};

[[nodiscard]] SkeletalMeshError read_error(const format::ReadError& error, std::string context)
{
    return {.code = SkeletalMeshErrorCode::read_failure,
            .absolute_offset = error.absolute_offset,
            .context = std::move(context),
            .read_error_code = error.code};
}

[[nodiscard]] SkeletalMeshError make_error(const SkeletalMeshErrorCode code,
                                           const std::uint64_t offset, std::string context)
{
    return {.code = code,
            .absolute_offset = offset,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] bool has_version(const std::span<const std::byte> bytes,
                               const std::string_view version) noexcept
{
    if (bytes.size() < 2U + version.size())
    {
        return false;
    }
    const auto length = static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[0])) |
                        (static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[1])) << 8U);
    if (length != version.size())
    {
        return false;
    }
    return std::ranges::equal(
        bytes.subspan(2U, length), version, [](const std::byte left, const char right)
        { return std::to_integer<unsigned char>(left) == static_cast<unsigned char>(right); });
}

[[nodiscard]] PackageKind detect_package(const std::span<const std::byte> bytes) noexcept
{
    if (has_version(bytes, package::kPackageV1Version))
    {
        return PackageKind::v1;
    }
    if (has_version(bytes, package::kPackageV2Version))
    {
        return PackageKind::v2;
    }
    if (has_version(bytes, package::kPackageV3Version))
    {
        return PackageKind::v3;
    }
    return PackageKind::unknown;
}

template <typename Header>
[[nodiscard]] SkeletalMeshResult<ObjectSpan> find_object(const Header& header,
                                                         const std::string_view object_name)
{
    for (const auto& record : header.records)
    {
        if (record.name_bytes == object_name)
        {
            return SkeletalMeshResult<ObjectSpan>::success({.name = record.name_bytes,
                                                            .class_name = record.class_name_bytes,
                                                            .offset = record.offset,
                                                            .size = record.size});
        }
    }
    return SkeletalMeshResult<ObjectSpan>::failure(make_error(
        SkeletalMeshErrorCode::mesh_object_not_found, 0, "package.skeletal_mesh_object"));
}

[[nodiscard]] SkeletalMeshResult<ObjectSpan> parse_object(const std::span<const std::byte> bytes,
                                                          const PackageKind kind,
                                                          const std::string_view object_name)
{
    if (kind == PackageKind::v1)
    {
        const auto result = package::PackageV1Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : SkeletalMeshResult<ObjectSpan>::failure(
                                        make_error(SkeletalMeshErrorCode::invalid_package,
                                                   result.error().absolute_offset, "package.v1"));
    }
    if (kind == PackageKind::v2)
    {
        const auto result = package::PackageV2Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : SkeletalMeshResult<ObjectSpan>::failure(
                                        make_error(SkeletalMeshErrorCode::invalid_package,
                                                   result.error().absolute_offset, "package.v2"));
    }
    if (kind == PackageKind::v3)
    {
        const auto result = package::PackageV3Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : SkeletalMeshResult<ObjectSpan>::failure(
                                        make_error(SkeletalMeshErrorCode::invalid_package,
                                                   result.error().absolute_offset, "package.v3"));
    }
    return SkeletalMeshResult<ObjectSpan>::failure(
        make_error(SkeletalMeshErrorCode::invalid_package, 0, "package.version"));
}

[[nodiscard]] SkeletalMeshResult<PropertyRecord> read_record(format::BinaryReader& reader)
{
    const auto name_offset = reader.absolute_position();
    const auto name_length = reader.read_u16();
    if (!name_length.has_value())
    {
        return SkeletalMeshResult<PropertyRecord>::failure(
            read_error(name_length.error(), "skeletal_mesh.property.name_length"));
    }
    if (name_length.value() > kMaximumPropertyNameBytes)
    {
        return SkeletalMeshResult<PropertyRecord>::failure(
            make_error(SkeletalMeshErrorCode::descriptor_name_limit_exceeded, name_offset,
                       "skeletal_mesh.property.name_length"));
    }
    const auto name = reader.read_bytes(name_length.value());
    const auto size = reader.read_u16();
    if (!name.has_value() || !size.has_value())
    {
        const auto& error = !name.has_value() ? name.error() : size.error();
        return SkeletalMeshResult<PropertyRecord>::failure(
            read_error(error, "skeletal_mesh.property.header"));
    }
    const auto value_offset = reader.absolute_position();
    const auto value = reader.read_bytes(size.value());
    if (!value.has_value())
    {
        return SkeletalMeshResult<PropertyRecord>::failure(
            read_error(value.error(), "skeletal_mesh.property.value"));
    }
    return SkeletalMeshResult<PropertyRecord>::success(
        {.name =
             std::string(reinterpret_cast<const char*>(name.value().data()), name.value().size()),
         .value_offset = value_offset,
         .value = value.value()});
}

template <typename Value, typename ReadValue>
[[nodiscard]] SkeletalMeshResult<Value>
read_scalar(const PropertyRecord& record, const std::size_t expected_size,
            const std::string& context, ReadValue read_value)
{
    if (record.value.size() != expected_size)
    {
        return SkeletalMeshResult<Value>::failure(
            make_error(SkeletalMeshErrorCode::invalid_property_size, record.value_offset, context));
    }
    format::BinaryReader reader(record.value, format::ByteOrder::little_endian, record.value_offset,
                                context);
    const auto value = read_value(reader);
    if (!value.has_value())
    {
        return SkeletalMeshResult<Value>::failure(read_error(value.error(), context));
    }
    return SkeletalMeshResult<Value>::success(value.value());
}

[[nodiscard]] SkeletalMeshResult<std::uint16_t> read_u16_property(const PropertyRecord& record,
                                                                  const std::string& context)
{
    return read_scalar<std::uint16_t>(record, 2U, context, [](format::BinaryReader& reader)
                                      { return reader.read_u16(); });
}

[[nodiscard]] SkeletalMeshResult<std::int32_t> read_i32_property(const PropertyRecord& record,
                                                                 const std::string& context)
{
    return read_scalar<std::int32_t>(record, 4U, context, [](format::BinaryReader& reader)
                                     { return reader.read_i32(); });
}

[[nodiscard]] SkeletalMeshResult<float> read_float_property(const PropertyRecord& record,
                                                            const std::string& context)
{
    auto value = read_scalar<float>(record, 4U, context,
                                    [](format::BinaryReader& reader) { return reader.read_f32(); });
    if (value.has_value() && !std::isfinite(value.value()))
    {
        return SkeletalMeshResult<float>::failure(
            make_error(SkeletalMeshErrorCode::non_finite_component, record.value_offset, context));
    }
    return value;
}

[[nodiscard]] SkeletalMeshResult<std::string> read_string_property(const PropertyRecord& record,
                                                                   const std::string& context)
{
    format::BinaryReader reader(record.value, format::ByteOrder::little_endian, record.value_offset,
                                context);
    const auto length = reader.read_u16();
    if (!length.has_value())
    {
        return SkeletalMeshResult<std::string>::failure(read_error(length.error(), context));
    }
    const auto bytes = reader.read_bytes(length.value());
    if (!bytes.has_value() || reader.remaining() != 0U)
    {
        return SkeletalMeshResult<std::string>::failure(
            make_error(SkeletalMeshErrorCode::invalid_property_size, record.value_offset, context));
    }
    return SkeletalMeshResult<std::string>::success(
        std::string(reinterpret_cast<const char*>(bytes.value().data()), bytes.value().size()));
}

struct IndexedName final
{
    std::uint16_t index{0};
    std::string_view suffix;
};

[[nodiscard]] std::optional<IndexedName> parse_indexed_name(const std::string_view name,
                                                            const std::string_view prefix)
{
    if (!name.starts_with(prefix) || name.size() <= prefix.size() || name[prefix.size()] != '[')
    {
        return std::nullopt;
    }
    const auto close = name.find(']', prefix.size() + 1U);
    if (close == std::string_view::npos)
    {
        return std::nullopt;
    }
    std::uint32_t index = 0;
    const auto digits = name.substr(prefix.size() + 1U, close - prefix.size() - 1U);
    const auto result = std::from_chars(digits.data(), digits.data() + digits.size(), index);
    if (result.ec != std::errc{} || result.ptr != digits.data() + digits.size() ||
        index > kMaximumReferences)
    {
        return std::nullopt;
    }
    return IndexedName{.index = static_cast<std::uint16_t>(index),
                       .suffix = name.substr(close + 1U)};
}

[[nodiscard]] std::optional<SkeletalMeshError> set_count(std::optional<std::uint16_t>& target,
                                                         const PropertyRecord& record,
                                                         const std::uint16_t maximum,
                                                         const std::string& context)
{
    if (target.has_value())
    {
        return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset, context);
    }
    auto value = read_u16_property(record, context);
    if (!value.has_value())
    {
        return value.error();
    }
    if (value.value() > maximum)
    {
        return make_error(SkeletalMeshErrorCode::count_limit_exceeded, record.value_offset,
                          context);
    }
    target = value.value();
    return std::nullopt;
}

template <typename IndexedValue>
[[nodiscard]] bool contains_index(const std::vector<IndexedValue>& values,
                                  const std::uint16_t index)
{
    return std::ranges::any_of(values,
                               [index](const IndexedValue& value) { return value.index == index; });
}

[[nodiscard]] std::optional<SkeletalMeshError>
read_indexed_string(const PropertyRecord& record, const IndexedName indexed,
                    std::vector<IndexedString>& values, const std::string& context)
{
    if (!indexed.suffix.empty() || contains_index(values, indexed.index))
    {
        return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset, context);
    }
    auto value = read_string_property(record, context);
    if (!value.has_value())
    {
        return value.error();
    }
    values.push_back({.index = indexed.index, .value = std::move(value).take_value()});
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> read_indexed_int(const PropertyRecord& record,
                                                                const IndexedName indexed,
                                                                std::vector<IndexedInt>& values,
                                                                const std::string& context)
{
    if (!indexed.suffix.empty() || contains_index(values, indexed.index))
    {
        return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset, context);
    }
    auto value = read_i32_property(record, context);
    if (!value.has_value())
    {
        return value.error();
    }
    values.push_back({.index = indexed.index, .value = value.value()});
    return std::nullopt;
}

[[nodiscard]] std::optional<std::size_t>
component_index(const std::string_view suffix, const std::span<const std::string_view> names)
{
    const auto found = std::ranges::find(names, suffix);
    if (found == names.end())
    {
        return std::nullopt;
    }
    return static_cast<std::size_t>(std::distance(names.begin(), found));
}

[[nodiscard]] std::optional<SkeletalMeshError>
set_component(const PropertyRecord& record, std::array<bool, 4>& seen, Vec4& target,
              const std::string_view suffix, const std::string& context)
{
    constexpr std::array names{".x"sv, ".y"sv, ".z"sv, ".w"sv};
    const auto component = component_index(suffix, names);
    if (!component.has_value())
    {
        return make_error(SkeletalMeshErrorCode::incomplete_struct, record.value_offset, context);
    }
    if (seen[component.value()])
    {
        return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset, context);
    }
    auto value = read_float_property(record, context);
    if (!value.has_value())
    {
        return value.error();
    }
    std::array targets{&target.x, &target.y, &target.z, &target.w};
    *targets[component.value()] = value.value();
    seen[component.value()] = true;
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError>
set_component(const PropertyRecord& record, std::array<bool, 3>& seen, Vec3& target,
              const std::string_view suffix, const std::span<const std::string_view> names,
              const std::string& context)
{
    const auto component = component_index(suffix, names);
    if (!component.has_value())
    {
        return make_error(SkeletalMeshErrorCode::incomplete_struct, record.value_offset, context);
    }
    if (seen[component.value()])
    {
        return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset, context);
    }
    auto value = read_float_property(record, context);
    if (!value.has_value())
    {
        return value.error();
    }
    std::array targets{&target.x, &target.y, &target.z};
    *targets[component.value()] = value.value();
    seen[component.value()] = true;
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> ensure_bone_storage(DescriptorState& state,
                                                                   const PropertyRecord& record,
                                                                   const std::uint16_t bone_index)
{
    if (!state.bone_count.has_value() || bone_index >= state.bone_count.value())
    {
        return make_error(SkeletalMeshErrorCode::invalid_bone_id, record.value_offset,
                          "skeletal_mesh.bone.index");
    }
    if (state.bones.empty())
    {
        state.bones.resize(state.bone_count.value());
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> handle_bone_property(DescriptorState& state,
                                                                    const PropertyRecord& record,
                                                                    const IndexedName indexed)
{
    if (const auto error = ensure_bone_storage(state, record, indexed.index); error.has_value())
    {
        return error;
    }
    auto& bone = state.bones[indexed.index];
    const auto context = "skeletal_mesh.bones[" + std::to_string(indexed.index) + "]";
    if (indexed.suffix.empty())
    {
        return record.value.empty()
                   ? std::nullopt
                   : std::optional(make_error(SkeletalMeshErrorCode::invalid_property_size,
                                              record.value_offset, context));
    }
    if (indexed.suffix == "._ID")
    {
        if (bone.id_seen)
        {
            return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset,
                              context + ".id");
        }
        auto value = read_i32_property(record, context + ".id");
        if (!value.has_value())
        {
            return value.error();
        }
        bone.bone.id = value.value();
        bone.id_seen = true;
        return std::nullopt;
    }
    if (indexed.suffix == "._name")
    {
        if (bone.name_seen)
        {
            return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset,
                              context + ".name");
        }
        auto value = read_string_property(record, context + ".name");
        if (!value.has_value())
        {
            return value.error();
        }
        bone.bone.name_bytes = std::move(value).take_value();
        bone.name_seen = true;
        return std::nullopt;
    }
    if (indexed.suffix == "._rotPose" || indexed.suffix == "._tranPose")
    {
        return record.value.empty()
                   ? std::nullopt
                   : std::optional(make_error(SkeletalMeshErrorCode::invalid_property_size,
                                              record.value_offset, context));
    }
    if (indexed.suffix.starts_with("._rotPose."))
    {
        return set_component(record, bone.rotation_seen, bone.bone.rotation,
                             indexed.suffix.substr(9U), context + ".rotation");
    }
    if (indexed.suffix.starts_with("._tranPose."))
    {
        constexpr std::array names{".x"sv, ".y"sv, ".z"sv};
        return set_component(record, bone.translation_seen, bone.bone.translation,
                             indexed.suffix.substr(10U), names, context + ".translation");
    }
    if (indexed.suffix == "._children")
    {
        return set_count(bone.child_count, record, kMaximumBones, context + ".children");
    }
    constexpr std::string_view children_prefix = "._children";
    if (indexed.suffix.starts_with(children_prefix))
    {
        const auto child = parse_indexed_name(indexed.suffix, children_prefix);
        if (!child.has_value())
        {
            return make_error(SkeletalMeshErrorCode::invalid_bone_reference, record.value_offset,
                              context + ".children");
        }
        return read_indexed_int(record, child.value(), bone.children, context + ".children");
    }
    return make_error(SkeletalMeshErrorCode::incomplete_struct, record.value_offset, context);
}

[[nodiscard]] std::optional<SkeletalMeshError> handle_bounds_property(DescriptorState& state,
                                                                      const PropertyRecord& record)
{
    constexpr std::array names{"bBox.min.x"sv, "bBox.min.y"sv, "bBox.min.z"sv,
                               "bBox.max.x"sv, "bBox.max.y"sv, "bBox.max.z"sv};
    const auto component = component_index(record.name, names);
    if (!component.has_value())
    {
        return std::nullopt;
    }
    if (state.bounds_seen[component.value()])
    {
        return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset,
                          "skeletal_mesh.bounds");
    }
    auto value = read_float_property(record, "skeletal_mesh.bounds");
    if (!value.has_value())
    {
        return value.error();
    }
    std::array targets{&state.bounds.minimum.x, &state.bounds.minimum.y, &state.bounds.minimum.z,
                       &state.bounds.maximum.x, &state.bounds.maximum.y, &state.bounds.maximum.z};
    *targets[component.value()] = value.value();
    state.bounds_seen[component.value()] = true;
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError> handle_vector_property(DescriptorState& state,
                                                                      const PropertyRecord& record)
{
    constexpr std::array xyz{".x"sv, ".y"sv, ".z"sv};
    constexpr std::array rot_names{".pitch"sv, ".yaw"sv, ".roll"sv};
    if (record.name == "offset" || record.name == "rot")
    {
        return record.value.empty()
                   ? std::nullopt
                   : std::optional(make_error(SkeletalMeshErrorCode::invalid_property_size,
                                              record.value_offset, "skeletal_mesh.transform"));
    }
    if (record.name.starts_with("offset."))
    {
        return set_component(record, state.offset_seen, state.offset,
                             std::string_view(record.name).substr(6U), xyz, "skeletal_mesh.offset");
    }
    if (record.name.starts_with("rot."))
    {
        return set_component(record, state.rotation_seen, state.rotation,
                             std::string_view(record.name).substr(3U), rot_names,
                             "skeletal_mesh.rotation");
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError>
handle_known_property(DescriptorState& state, const PropertyRecord& record, bool& handled)
{
    handled = true;
    if (record.name == "_skel")
    {
        return set_count(state.bone_count, record, kMaximumBones, "skeletal_mesh.bones");
    }
    if (record.name == "_anim")
    {
        return set_count(state.animation_count, record, kMaximumReferences,
                         "skeletal_mesh.animations");
    }
    if (record.name == "defaultSecs")
    {
        return set_count(state.default_count, record, kMaximumReferences,
                         "skeletal_mesh.default_sections");
    }
    if (record.name == "skins")
    {
        return set_count(state.material_count, record, kMaximumReferences,
                         "skeletal_mesh.materials");
    }
    if (record.name == "defaultAnim")
    {
        if (state.default_animation_seen)
        {
            return make_error(SkeletalMeshErrorCode::duplicate_property, record.value_offset,
                              "skeletal_mesh.default_animation");
        }
        auto value = read_string_property(record, "skeletal_mesh.default_animation");
        if (!value.has_value())
        {
            return value.error();
        }
        state.descriptor.default_animation_name_bytes = std::move(value).take_value();
        state.default_animation_seen = true;
        return std::nullopt;
    }
    if (const auto indexed = parse_indexed_name(record.name, "_skel"); indexed.has_value())
    {
        return handle_bone_property(state, record, indexed.value());
    }
    if (const auto indexed = parse_indexed_name(record.name, "_anim"); indexed.has_value())
    {
        return read_indexed_string(record, indexed.value(), state.animations,
                                   "skeletal_mesh.animations");
    }
    if (const auto indexed = parse_indexed_name(record.name, "defaultSecs"); indexed.has_value())
    {
        return read_indexed_int(record, indexed.value(), state.defaults,
                                "skeletal_mesh.default_sections");
    }
    if (const auto indexed = parse_indexed_name(record.name, "skins"); indexed.has_value())
    {
        return read_indexed_string(record, indexed.value(), state.materials,
                                   "skeletal_mesh.materials");
    }
    if (record.name.starts_with("bBox."))
    {
        return handle_bounds_property(state, record);
    }
    if (record.name == "offset" || record.name == "rot" || record.name.starts_with("offset.") ||
        record.name.starts_with("rot."))
    {
        return handle_vector_property(state, record);
    }
    handled = false;
    return std::nullopt;
}

template <typename IndexedValue, typename Output, typename Convert>
[[nodiscard]] SkeletalMeshResult<std::vector<Output>>
finalize_indexed(std::vector<IndexedValue> values, const std::optional<std::uint16_t> count,
                 const std::string& context, Convert convert)
{
    const auto expected = count.value_or(0U);
    if (values.size() != expected)
    {
        return SkeletalMeshResult<std::vector<Output>>::failure(
            make_error(SkeletalMeshErrorCode::incomplete_struct, 0, context));
    }
    std::ranges::sort(values, {}, &IndexedValue::index);
    std::vector<Output> output;
    output.reserve(expected);
    for (std::uint16_t index = 0; index < expected; ++index)
    {
        if (values[index].index != index)
        {
            return SkeletalMeshResult<std::vector<Output>>::failure(
                make_error(SkeletalMeshErrorCode::incomplete_struct, 0, context));
        }
        output.push_back(convert(std::move(values[index])));
    }
    return SkeletalMeshResult<std::vector<Output>>::success(std::move(output));
}

[[nodiscard]] std::optional<SkeletalMeshError> finalize_bones(DescriptorState& state)
{
    const auto expected = state.bone_count.value_or(0U);
    if (state.bones.size() != expected)
    {
        return make_error(SkeletalMeshErrorCode::incomplete_struct, 0, "skeletal_mesh.bones");
    }
    state.descriptor.bones.reserve(expected);
    for (std::uint16_t index = 0; index < expected; ++index)
    {
        auto& bone = state.bones[index];
        if (!bone.id_seen || !bone.name_seen ||
            !std::ranges::all_of(bone.rotation_seen, [](const bool seen) { return seen; }) ||
            !std::ranges::all_of(bone.translation_seen, [](const bool seen) { return seen; }) ||
            !bone.child_count.has_value() || std::cmp_not_equal(bone.bone.id, index))
        {
            return make_error(SkeletalMeshErrorCode::incomplete_struct, 0,
                              "skeletal_mesh.bones[" + std::to_string(index) + "]");
        }
        auto children = finalize_indexed<IndexedInt, std::int32_t>(
            std::move(bone.children), bone.child_count,
            "skeletal_mesh.bones[" + std::to_string(index) + "].children",
            [](IndexedInt value) { return value.value; });
        if (!children.has_value())
        {
            return children.error();
        }
        bone.bone.children = std::move(children).take_value();
        state.descriptor.bones.push_back(std::move(bone.bone));
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SkeletalMeshError>
derive_skeleton_graph(SkeletalMeshDescriptor& descriptor)
{
    const auto bone_count = descriptor.bones.size();
    for (auto& parent : descriptor.bones)
    {
        for (const auto child_id : parent.children)
        {
            if (child_id < 0 || std::cmp_greater_equal(child_id, bone_count) ||
                child_id == parent.id)
            {
                return make_error(SkeletalMeshErrorCode::invalid_bone_reference, 0,
                                  "skeletal_mesh.bone.children");
            }
            auto& child = descriptor.bones[static_cast<std::size_t>(child_id)];
            if (child.parent_id != -1)
            {
                return make_error(SkeletalMeshErrorCode::duplicate_bone_parent, 0,
                                  "skeletal_mesh.bone.parent");
            }
            child.parent_id = parent.id;
        }
    }
    for (const auto& bone : descriptor.bones)
    {
        if (bone.parent_id == -1)
        {
            descriptor.root_bone_ids.push_back(bone.id);
        }
        std::size_t steps = 0;
        auto current = bone.parent_id;
        while (current != -1)
        {
            if (++steps > bone_count)
            {
                return make_error(SkeletalMeshErrorCode::cyclic_skeleton, 0,
                                  "skeletal_mesh.bone.graph");
            }
            current = descriptor.bones[static_cast<std::size_t>(current)].parent_id;
        }
    }
    if (!descriptor.bones.empty() && descriptor.root_bone_ids.empty())
    {
        return make_error(SkeletalMeshErrorCode::cyclic_skeleton, 0, "skeletal_mesh.bone.roots");
    }
    return std::nullopt;
}

[[nodiscard]] SkeletalMeshResult<SkeletalMeshDescriptor> finalize_descriptor(DescriptorState state)
{
    if (const auto error = finalize_bones(state); error.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(error.value());
    }
    auto animations = finalize_indexed<IndexedString, std::string>(
        std::move(state.animations), state.animation_count, "skeletal_mesh.animations",
        [](IndexedString value) { return std::move(value.value); });
    auto defaults = finalize_indexed<IndexedInt, std::int32_t>(
        std::move(state.defaults), state.default_count, "skeletal_mesh.default_sections",
        [](IndexedInt value) { return value.value; });
    auto materials = finalize_indexed<IndexedString, std::string>(
        std::move(state.materials), state.material_count, "skeletal_mesh.materials",
        [](IndexedString value) { return std::move(value.value); });
    if (!animations.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(animations.error());
    }
    if (!defaults.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(defaults.error());
    }
    if (!materials.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(materials.error());
    }
    state.descriptor.animation_object_names = std::move(animations).take_value();
    state.descriptor.default_submesh_indices = std::move(defaults).take_value();
    state.descriptor.material_object_names = std::move(materials).take_value();
    if (std::ranges::any_of(state.bounds_seen, [](const bool seen) { return seen; }))
    {
        if (state.bounds.minimum.x > state.bounds.maximum.x ||
            state.bounds.minimum.y > state.bounds.maximum.y ||
            state.bounds.minimum.z > state.bounds.maximum.z)
        {
            return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(make_error(
                SkeletalMeshErrorCode::invalid_declared_bounds, 0, "skeletal_mesh.bounds"));
        }
        state.descriptor.declared_bounds = state.bounds;
    }
    if (std::ranges::any_of(state.offset_seen, [](const bool seen) { return seen; }))
    {
        state.descriptor.instance_offset = state.offset;
    }
    if (std::ranges::any_of(state.rotation_seen, [](const bool seen) { return seen; }))
    {
        state.descriptor.instance_rotation_degrees = state.rotation;
    }
    if (const auto error = derive_skeleton_graph(state.descriptor); error.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(error.value());
    }
    return SkeletalMeshResult<SkeletalMeshDescriptor>::success(std::move(state.descriptor));
}

} // namespace

SkeletalMeshResult<SkeletalMeshDescriptor>
read_skeletal_mesh_descriptor(const std::span<const std::byte> object_body,
                              const std::uint64_t base_offset)
{
    format::BinaryReader reader(object_body, format::ByteOrder::little_endian, base_offset,
                                "skeletal_mesh.descriptor");
    const auto count_offset = reader.absolute_position();
    const auto count = reader.read_u16();
    if (!count.has_value())
    {
        return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(
            read_error(count.error(), "skeletal_mesh.property_count"));
    }
    if (count.value() > kMaximumDescriptorItems)
    {
        return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(
            make_error(SkeletalMeshErrorCode::descriptor_item_limit_exceeded, count_offset,
                       "skeletal_mesh.property_count"));
    }
    DescriptorState state;
    for (std::uint16_t index = 0; index < count.value(); ++index)
    {
        auto record = read_record(reader);
        if (!record.has_value())
        {
            return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(record.error());
        }
        bool handled = false;
        if (const auto error = handle_known_property(state, record.value(), handled);
            error.has_value())
        {
            return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(error.value());
        }
        if (!handled)
        {
            const auto& value = record.value();
            state.descriptor.unknown_properties.push_back(
                {.name_bytes = value.name,
                 .value_offset = value.value_offset,
                 .value = std::vector<std::byte>(value.value.begin(), value.value.end())});
        }
    }
    if (reader.remaining() != 0U)
    {
        return SkeletalMeshResult<SkeletalMeshDescriptor>::failure(
            make_error(SkeletalMeshErrorCode::trailing_bytes, reader.absolute_position(),
                       "skeletal_mesh.descriptor.trailing"));
    }
    return finalize_descriptor(std::move(state));
}

SkeletalMeshResult<PackageSkeletalMeshDescriptor>
read_package_skeletal_mesh_descriptor(const std::span<const std::byte> package_bytes,
                                      const std::string_view full_object_name)
{
    auto object = parse_object(package_bytes, detect_package(package_bytes), full_object_name);
    if (!object.has_value())
    {
        return SkeletalMeshResult<PackageSkeletalMeshDescriptor>::failure(object.error());
    }
    if (object.value().class_name != "QSkelMesh")
    {
        return SkeletalMeshResult<PackageSkeletalMeshDescriptor>::failure(
            make_error(SkeletalMeshErrorCode::wrong_object_class, object.value().offset,
                       "package.skeletal_mesh_object.class"));
    }
    const auto offset = object.value().offset;
    const auto size = object.value().size;
    if (offset > package_bytes.size() || size > package_bytes.size() - offset)
    {
        return SkeletalMeshResult<PackageSkeletalMeshDescriptor>::failure(
            make_error(SkeletalMeshErrorCode::object_range_out_of_file, offset,
                       "package.skeletal_mesh_object.range"));
    }
    auto descriptor = read_skeletal_mesh_descriptor(
        package_bytes.subspan(static_cast<std::size_t>(offset), static_cast<std::size_t>(size)),
        offset);
    if (!descriptor.has_value())
    {
        return SkeletalMeshResult<PackageSkeletalMeshDescriptor>::failure(descriptor.error());
    }
    return SkeletalMeshResult<PackageSkeletalMeshDescriptor>::success(
        {.object_name_bytes = object.value().name,
         .body_offset = offset,
         .body_size = size,
         .descriptor = std::move(descriptor).take_value()});
}

} // namespace tmxy::skeletal_mesh
