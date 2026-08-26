#include "tmxy/static_mesh/package_static_mesh_reader.hpp"

#include "tmxy/format/binary_reader.hpp"
#include "tmxy/package/package_v1.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3.hpp"
#include "tmxy/package/package_v3_reader.hpp"
#include "tmxy/static_mesh/sm_reader.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::static_mesh
{
namespace
{

constexpr std::uint16_t kMaximumDescriptorItems = 8192;
constexpr std::uint16_t kMaximumPropertyNameBytes = 1024;
constexpr std::uint16_t kMaximumMaterialSlots = 4096;

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

struct IndexedMaterial final
{
    std::uint16_t index{0};
    std::uint64_t offset{0};
    std::string name;
};

struct DescriptorState final
{
    StaticMeshDescriptor descriptor;
    std::optional<std::uint16_t> material_count;
    std::vector<IndexedMaterial> indexed_materials;
    std::array<bool, 6> bound_seen{};
    bool any_bound{false};
    Aabb declared_bounds;
    bool use_light_map_seen{false};
};

[[nodiscard]] StaticMeshError read_error(const format::ReadError& error, std::string context)
{
    return {.code = StaticMeshErrorCode::read_failure,
            .absolute_offset = error.absolute_offset,
            .context = std::move(context),
            .read_error_code = error.code};
}

[[nodiscard]] StaticMeshError make_error(const StaticMeshErrorCode code, const std::uint64_t offset,
                                         std::string context)
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
    for (std::size_t index = 0; index < length; ++index)
    {
        if (std::to_integer<unsigned char>(bytes[index + 2U]) !=
            static_cast<unsigned char>(version[index]))
        {
            return false;
        }
    }
    return true;
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
[[nodiscard]] StaticMeshResult<ObjectSpan> find_object(const Header& header,
                                                       const std::string_view object_name)
{
    for (const auto& record : header.records)
    {
        if (record.name_bytes == object_name)
        {
            return StaticMeshResult<ObjectSpan>::success({.name = record.name_bytes,
                                                          .class_name = record.class_name_bytes,
                                                          .offset = record.offset,
                                                          .size = record.size});
        }
    }
    return StaticMeshResult<ObjectSpan>::failure(
        make_error(StaticMeshErrorCode::mesh_object_not_found, 0, "package.static_mesh_object"));
}

[[nodiscard]] StaticMeshResult<ObjectSpan> parse_object(const std::span<const std::byte> bytes,
                                                        const PackageKind kind,
                                                        const std::string_view object_name)
{
    if (kind == PackageKind::v1)
    {
        const auto result = package::PackageV1Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : StaticMeshResult<ObjectSpan>::failure(
                                        make_error(StaticMeshErrorCode::invalid_package,
                                                   result.error().absolute_offset, "package.v1"));
    }
    if (kind == PackageKind::v2)
    {
        const auto result = package::PackageV2Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : StaticMeshResult<ObjectSpan>::failure(
                                        make_error(StaticMeshErrorCode::invalid_package,
                                                   result.error().absolute_offset, "package.v2"));
    }
    if (kind == PackageKind::v3)
    {
        const auto result = package::PackageV3Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : StaticMeshResult<ObjectSpan>::failure(
                                        make_error(StaticMeshErrorCode::invalid_package,
                                                   result.error().absolute_offset, "package.v3"));
    }
    return StaticMeshResult<ObjectSpan>::failure(
        make_error(StaticMeshErrorCode::invalid_package, 0, "package.version"));
}

[[nodiscard]] StaticMeshResult<PropertyRecord> read_record(format::BinaryReader& reader)
{
    const auto name_length_offset = reader.absolute_position();
    const auto name_length = reader.read_u16();
    if (!name_length.has_value())
    {
        return StaticMeshResult<PropertyRecord>::failure(
            read_error(name_length.error(), "static_mesh.property.name_length"));
    }
    if (name_length.value() > kMaximumPropertyNameBytes)
    {
        return StaticMeshResult<PropertyRecord>::failure(
            make_error(StaticMeshErrorCode::descriptor_name_limit_exceeded, name_length_offset,
                       "static_mesh.property.name_length"));
    }
    const auto name = reader.read_bytes(name_length.value());
    const auto size = reader.read_u16();
    if (!name.has_value() || !size.has_value())
    {
        const auto& error = !name.has_value() ? name.error() : size.error();
        return StaticMeshResult<PropertyRecord>::failure(
            read_error(error, "static_mesh.property.header"));
    }
    const auto value_offset = reader.absolute_position();
    const auto value = reader.read_bytes(size.value());
    if (!value.has_value())
    {
        return StaticMeshResult<PropertyRecord>::failure(
            read_error(value.error(), "static_mesh.property.value"));
    }
    return StaticMeshResult<PropertyRecord>::success(
        {.name =
             std::string(reinterpret_cast<const char*>(name.value().data()), name.value().size()),
         .value_offset = value_offset,
         .value = value.value()});
}

[[nodiscard]] StaticMeshResult<std::uint16_t> read_u16_property(const PropertyRecord& record,
                                                                const std::string& context)
{
    if (record.value.size() != 2U)
    {
        return StaticMeshResult<std::uint16_t>::failure(
            make_error(StaticMeshErrorCode::invalid_property_size, record.value_offset, context));
    }
    format::BinaryReader reader(record.value, format::ByteOrder::little_endian, record.value_offset,
                                context);
    const auto value = reader.read_u16();
    return value.has_value()
               ? StaticMeshResult<std::uint16_t>::success(value.value())
               : StaticMeshResult<std::uint16_t>::failure(read_error(value.error(), context));
}

[[nodiscard]] StaticMeshResult<float> read_float_property(const PropertyRecord& record,
                                                          const std::string& context)
{
    if (record.value.size() != 4U)
    {
        return StaticMeshResult<float>::failure(
            make_error(StaticMeshErrorCode::invalid_property_size, record.value_offset, context));
    }
    format::BinaryReader reader(record.value, format::ByteOrder::little_endian, record.value_offset,
                                context);
    const auto value = reader.read_f32();
    if (!value.has_value())
    {
        return StaticMeshResult<float>::failure(read_error(value.error(), context));
    }
    if (!std::isfinite(value.value()))
    {
        return StaticMeshResult<float>::failure(
            make_error(StaticMeshErrorCode::non_finite_component, record.value_offset, context));
    }
    return StaticMeshResult<float>::success(value.value());
}

[[nodiscard]] StaticMeshResult<std::string> read_string_property(const PropertyRecord& record)
{
    format::BinaryReader reader(record.value, format::ByteOrder::little_endian, record.value_offset,
                                "static_mesh.material");
    const auto length = reader.read_u16();
    if (!length.has_value())
    {
        return StaticMeshResult<std::string>::failure(
            read_error(length.error(), "static_mesh.material.length"));
    }
    const auto name = reader.read_bytes(length.value());
    if (!name.has_value())
    {
        return StaticMeshResult<std::string>::failure(
            read_error(name.error(), "static_mesh.material.name"));
    }
    if (reader.remaining() != 0U || name.value().empty())
    {
        return StaticMeshResult<std::string>::failure(
            make_error(StaticMeshErrorCode::invalid_material_slot, record.value_offset,
                       "static_mesh.material"));
    }
    return StaticMeshResult<std::string>::success(
        std::string(reinterpret_cast<const char*>(name.value().data()), name.value().size()));
}

[[nodiscard]] std::optional<std::uint16_t> material_index(const std::string_view name) noexcept
{
    constexpr std::string_view prefix = "skins[";
    if (!name.starts_with(prefix) || name.size() <= prefix.size() + 1U || name.back() != ']')
    {
        return std::nullopt;
    }
    std::uint32_t value = 0;
    for (std::size_t position = prefix.size(); position + 1U < name.size(); ++position)
    {
        const auto character = name[position];
        if (character < '0' || character > '9')
        {
            return std::nullopt;
        }
        value = (value * 10U) + static_cast<std::uint32_t>(character - '0');
        if (value > kMaximumMaterialSlots)
        {
            return std::nullopt;
        }
    }
    return static_cast<std::uint16_t>(value);
}

[[nodiscard]] std::optional<std::size_t> bound_component(const std::string_view name) noexcept
{
    constexpr std::array<std::string_view, 6> names = {"bBox.min.x", "bBox.min.y", "bBox.min.z",
                                                       "bBox.max.x", "bBox.max.y", "bBox.max.z"};
    for (std::size_t index = 0; index < names.size(); ++index)
    {
        if (name == names[index])
        {
            return index;
        }
    }
    return std::nullopt;
}

void assign_bound_component(Aabb& bounds, const std::size_t component, const float value) noexcept
{
    std::array<float*, 6> values = {&bounds.minimum.x, &bounds.minimum.y, &bounds.minimum.z,
                                    &bounds.maximum.x, &bounds.maximum.y, &bounds.maximum.z};
    *values[component] = value;
}

[[nodiscard]] std::optional<StaticMeshError> handle_material_count(const PropertyRecord& record,
                                                                   DescriptorState& state)
{
    if (state.material_count.has_value())
    {
        return make_error(StaticMeshErrorCode::duplicate_property, record.value_offset,
                          "static_mesh.skins");
    }
    auto value = read_u16_property(record, "static_mesh.skins");
    if (!value.has_value())
    {
        return value.error();
    }
    if (value.value() > kMaximumMaterialSlots)
    {
        return make_error(StaticMeshErrorCode::invalid_material_slot, record.value_offset,
                          "static_mesh.skins");
    }
    state.material_count = value.value();
    return std::nullopt;
}

[[nodiscard]] std::optional<StaticMeshError> handle_indexed_material(const PropertyRecord& record,
                                                                     const std::uint16_t index,
                                                                     DescriptorState& state)
{
    auto value = read_string_property(record);
    if (!value.has_value())
    {
        return value.error();
    }
    state.indexed_materials.push_back(
        {.index = index, .offset = record.value_offset, .name = std::move(value).take_value()});
    return std::nullopt;
}

[[nodiscard]] std::optional<StaticMeshError>
handle_bound(const PropertyRecord& record, const std::size_t component, DescriptorState& state)
{
    if (state.bound_seen[component])
    {
        return make_error(StaticMeshErrorCode::duplicate_property, record.value_offset,
                          "static_mesh.bounds");
    }
    auto value = read_float_property(record, "static_mesh.bounds");
    if (!value.has_value())
    {
        return value.error();
    }
    state.bound_seen[component] = true;
    state.any_bound = true;
    assign_bound_component(state.declared_bounds, component, value.value());
    return std::nullopt;
}

[[nodiscard]] std::optional<StaticMeshError> handle_use_light_map(const PropertyRecord& record,
                                                                  DescriptorState& state)
{
    if (state.use_light_map_seen)
    {
        return make_error(StaticMeshErrorCode::duplicate_property, record.value_offset,
                          "static_mesh.useLightMap");
    }
    if (record.value.size() != 1U)
    {
        return make_error(StaticMeshErrorCode::invalid_property_size, record.value_offset,
                          "static_mesh.useLightMap");
    }
    const auto value = std::to_integer<std::uint8_t>(record.value.front());
    if (value > 1U)
    {
        return make_error(StaticMeshErrorCode::invalid_boolean, record.value_offset,
                          "static_mesh.useLightMap");
    }
    state.use_light_map_seen = true;
    state.descriptor.use_light_map = value != 0U;
    return std::nullopt;
}

[[nodiscard]] std::optional<StaticMeshError> process_descriptor_record(const PropertyRecord& record,
                                                                       DescriptorState& state)
{
    if (record.name == "skins")
    {
        return handle_material_count(record, state);
    }
    if (const auto index = material_index(record.name))
    {
        return handle_indexed_material(record, *index, state);
    }
    if (const auto component = bound_component(record.name))
    {
        return handle_bound(record, *component, state);
    }
    if (record.name == "useLightMap")
    {
        return handle_use_light_map(record, state);
    }
    state.descriptor.unknown_properties.push_back(
        {.name_bytes = record.name,
         .value_offset = record.value_offset,
         .value = std::vector<std::byte>(record.value.begin(), record.value.end())});
    return std::nullopt;
}

[[nodiscard]] StaticMeshResult<StaticMeshDescriptor>
finalize_descriptor(DescriptorState state, const std::uint64_t base_offset)
{
    if (!state.material_count.has_value() && !state.indexed_materials.empty())
    {
        return StaticMeshResult<StaticMeshDescriptor>::failure(
            make_error(StaticMeshErrorCode::invalid_material_slot, base_offset,
                       "static_mesh.skins.count_missing"));
    }
    state.descriptor.material_object_names.resize(state.material_count.value_or(0));
    std::vector<bool> material_seen(state.descriptor.material_object_names.size(), false);
    for (auto& material : state.indexed_materials)
    {
        if (material.index >= state.descriptor.material_object_names.size())
        {
            return StaticMeshResult<StaticMeshDescriptor>::failure(
                make_error(StaticMeshErrorCode::invalid_material_slot, material.offset,
                           "static_mesh.skins[index]"));
        }
        if (material_seen[material.index])
        {
            return StaticMeshResult<StaticMeshDescriptor>::failure(
                make_error(StaticMeshErrorCode::duplicate_property, material.offset,
                           "static_mesh.skins[index]"));
        }
        material_seen[material.index] = true;
        state.descriptor.material_object_names[material.index] = std::move(material.name);
    }
    if (std::ranges::find(material_seen, false) != material_seen.end())
    {
        return StaticMeshResult<StaticMeshDescriptor>::failure(
            make_error(StaticMeshErrorCode::invalid_material_slot, base_offset,
                       "static_mesh.skins.incomplete"));
    }
    if (state.any_bound)
    {
        if (state.declared_bounds.minimum.x > state.declared_bounds.maximum.x ||
            state.declared_bounds.minimum.y > state.declared_bounds.maximum.y ||
            state.declared_bounds.minimum.z > state.declared_bounds.maximum.z)
        {
            return StaticMeshResult<StaticMeshDescriptor>::failure(make_error(
                StaticMeshErrorCode::invalid_declared_bounds, base_offset, "static_mesh.bounds"));
        }
        state.descriptor.declared_bounds = state.declared_bounds;
    }
    return StaticMeshResult<StaticMeshDescriptor>::success(std::move(state.descriptor));
}

[[nodiscard]] StaticMeshResult<StaticMeshDescriptor>
parse_descriptor_body(const std::span<const std::byte> body, const std::uint64_t base_offset)
{
    format::BinaryReader reader(body, format::ByteOrder::little_endian, base_offset,
                                "static_mesh.object_body");
    const auto count_offset = reader.absolute_position();
    const auto count = reader.read_u16();
    if (!count.has_value())
    {
        return StaticMeshResult<StaticMeshDescriptor>::failure(
            read_error(count.error(), "static_mesh.item_count"));
    }
    if (count.value() > kMaximumDescriptorItems)
    {
        return StaticMeshResult<StaticMeshDescriptor>::failure(
            make_error(StaticMeshErrorCode::descriptor_item_limit_exceeded, count_offset,
                       "static_mesh.item_count"));
    }

    DescriptorState state;
    for (std::uint16_t item = 0; item < count.value(); ++item)
    {
        auto record = read_record(reader);
        if (!record.has_value())
        {
            return StaticMeshResult<StaticMeshDescriptor>::failure(record.error());
        }
        if (const auto error = process_descriptor_record(record.value(), state))
        {
            return StaticMeshResult<StaticMeshDescriptor>::failure(*error);
        }
    }
    if (reader.remaining() != 0U)
    {
        return StaticMeshResult<StaticMeshDescriptor>::failure(
            make_error(StaticMeshErrorCode::trailing_bytes, reader.absolute_position(),
                       "static_mesh.object_body.trailing"));
    }
    return finalize_descriptor(std::move(state), base_offset);
}

[[nodiscard]] bool near(const float left, const float right) noexcept
{
    constexpr float relative_tolerance = 1.0e-5F;
    const auto scale = std::max({1.0F, std::abs(left), std::abs(right)});
    return std::abs(left - right) <= relative_tolerance * scale;
}

[[nodiscard]] bool bounds_match(const Aabb& left, const Aabb& right) noexcept
{
    return near(left.minimum.x, right.minimum.x) && near(left.minimum.y, right.minimum.y) &&
           near(left.minimum.z, right.minimum.z) && near(left.maximum.x, right.maximum.x) &&
           near(left.maximum.y, right.maximum.y) && near(left.maximum.z, right.maximum.z);
}

[[nodiscard]] bool bounds_contain(const Aabb& outer, const Aabb& inner) noexcept
{
    constexpr float relative_tolerance = 1.0e-5F;
    const auto lower = [](const float outer_value, const float inner_value)
    {
        const auto scale = std::max({1.0F, std::abs(outer_value), std::abs(inner_value)});
        return outer_value <= inner_value + (relative_tolerance * scale);
    };
    const auto upper = [](const float outer_value, const float inner_value)
    {
        const auto scale = std::max({1.0F, std::abs(outer_value), std::abs(inner_value)});
        return outer_value >= inner_value - (relative_tolerance * scale);
    };
    return lower(outer.minimum.x, inner.minimum.x) && lower(outer.minimum.y, inner.minimum.y) &&
           lower(outer.minimum.z, inner.minimum.z) && upper(outer.maximum.x, inner.maximum.x) &&
           upper(outer.maximum.y, inner.maximum.y) && upper(outer.maximum.z, inner.maximum.z);
}

[[nodiscard]] DeclaredBoundsRelation declared_bounds_relation(const std::optional<Aabb>& declared,
                                                              const Aabb& effective) noexcept
{
    if (!declared.has_value())
    {
        return DeclaredBoundsRelation::absent;
    }
    if (bounds_match(*declared, effective))
    {
        return DeclaredBoundsRelation::exact;
    }
    return bounds_contain(*declared, effective) ? DeclaredBoundsRelation::contains
                                                : DeclaredBoundsRelation::mismatch;
}

} // namespace

StaticMeshResult<StaticMeshDescriptor>
read_static_mesh_descriptor(const std::span<const std::byte> object_body,
                            const std::uint64_t base_offset)
{
    return parse_descriptor_body(object_body, base_offset);
}

StaticMeshResult<PackageStaticMeshDescriptor>
read_package_static_mesh_descriptor(const std::span<const std::byte> package_bytes,
                                    const std::string_view full_object_name)
{
    auto object = parse_object(package_bytes, detect_package(package_bytes), full_object_name);
    if (!object.has_value())
    {
        return StaticMeshResult<PackageStaticMeshDescriptor>::failure(object.error());
    }
    if (object.value().class_name != "QStaticMesh")
    {
        return StaticMeshResult<PackageStaticMeshDescriptor>::failure(
            make_error(StaticMeshErrorCode::wrong_object_class, object.value().offset,
                       "package.static_mesh_object.class"));
    }
    if (object.value().offset > package_bytes.size() ||
        object.value().size > package_bytes.size() - object.value().offset)
    {
        return StaticMeshResult<PackageStaticMeshDescriptor>::failure(
            make_error(StaticMeshErrorCode::object_range_out_of_file, object.value().offset,
                       "package.static_mesh_object.body"));
    }
    const auto body = package_bytes.subspan(static_cast<std::size_t>(object.value().offset),
                                            static_cast<std::size_t>(object.value().size));
    auto descriptor = read_static_mesh_descriptor(body, object.value().offset);
    if (!descriptor.has_value())
    {
        return StaticMeshResult<PackageStaticMeshDescriptor>::failure(descriptor.error());
    }
    return StaticMeshResult<PackageStaticMeshDescriptor>::success(
        {.object_name_bytes = object.value().name,
         .body_offset = object.value().offset,
         .body_size = object.value().size,
         .descriptor = std::move(descriptor).take_value()});
}

StaticMeshResult<StaticMeshBinding> bind_static_mesh(const std::span<const std::byte> package_bytes,
                                                     const std::string_view full_object_name,
                                                     const std::span<const std::byte> sm_bytes)
{
    auto package = read_package_static_mesh_descriptor(package_bytes, full_object_name);
    if (!package.has_value())
    {
        return StaticMeshResult<StaticMeshBinding>::failure(package.error());
    }
    auto mesh = SmReader{}.parse(sm_bytes);
    if (!mesh.has_value())
    {
        return StaticMeshResult<StaticMeshBinding>::failure(mesh.error());
    }
    if (package.value().descriptor.material_object_names.size() != mesh.value().sections.size())
    {
        return StaticMeshResult<StaticMeshBinding>::failure(
            make_error(StaticMeshErrorCode::material_slot_mismatch, package.value().body_offset,
                       "static_mesh.material_section_binding"));
    }
    const auto effective_bounds = effective_legacy_bounds(mesh.value());
    const auto relation =
        declared_bounds_relation(package.value().descriptor.declared_bounds, effective_bounds);
    return StaticMeshResult<StaticMeshBinding>::success({.mesh = std::move(mesh).take_value(),
                                                         .package = std::move(package).take_value(),
                                                         .effective_bounds = effective_bounds,
                                                         .declared_bounds_relation = relation});
}

} // namespace tmxy::static_mesh
