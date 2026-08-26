#include "tmxy/texture/legacy_texture_descriptor_reader.hpp"

#include "tmxy/format/binary_reader.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace tmxy::texture
{
namespace
{

[[nodiscard]] TextureError from_read_error(const format::ReadError& error, std::string context)
{
    return TextureError{.code = TextureErrorCode::read_failure,
                        .absolute_offset = error.absolute_offset,
                        .context = std::move(context),
                        .read_error_code = error.code};
}

[[nodiscard]] TextureError make_error(const TextureErrorCode code, const std::uint64_t offset,
                                      std::string context)
{
    return TextureError{.code = code,
                        .absolute_offset = offset,
                        .context = std::move(context),
                        .read_error_code = std::nullopt};
}

[[nodiscard]] std::uint32_t maximum_mips(const std::uint32_t width,
                                         const std::uint32_t height) noexcept
{
    std::uint32_t value = width > height ? width : height;
    std::uint32_t count = 1;
    while (value > 1U)
    {
        value /= 2U;
        ++count;
    }
    return count;
}

enum class KnownProperty : std::uint8_t
{
    format = 0,
    u_clamp = 1,
    v_clamp = 2,
    width = 3,
    height = 4,
    mip_count = 5,
};

struct PropertyRecord final
{
    std::string name;
    std::uint64_t value_offset{0};
    std::span<const std::byte> value;
};

struct KnownAssignment final
{
    KnownProperty property;
    std::int32_t value{0};
    std::uint64_t offset{0};
};

[[nodiscard]] std::optional<KnownProperty> known_property(const std::string_view name) noexcept
{
    if (name == "format")
    {
        return KnownProperty::format;
    }
    if (name == "uClamp")
    {
        return KnownProperty::u_clamp;
    }
    if (name == "vClamp")
    {
        return KnownProperty::v_clamp;
    }
    if (name == "uSize")
    {
        return KnownProperty::width;
    }
    if (name == "vSize")
    {
        return KnownProperty::height;
    }
    if (name == "mipLevel")
    {
        return KnownProperty::mip_count;
    }
    return std::nullopt;
}

[[nodiscard]] TextureResult<PropertyRecord> read_record(format::BinaryReader& reader,
                                                        const std::uint16_t maximum_name_bytes)
{
    const auto name_length = reader.read_u16();
    if (!name_length.has_value())
    {
        return TextureResult<PropertyRecord>::failure(
            from_read_error(name_length.error(), "texture.property.name_length"));
    }
    if (name_length.value() > maximum_name_bytes)
    {
        return TextureResult<PropertyRecord>::failure(
            make_error(TextureErrorCode::property_name_limit_exceeded,
                       reader.absolute_position() - 2U, "texture.property.name_length"));
    }
    const auto name_bytes = reader.read_bytes(name_length.value());
    if (!name_bytes.has_value())
    {
        return TextureResult<PropertyRecord>::failure(
            from_read_error(name_bytes.error(), "texture.property.name"));
    }
    const auto size = reader.read_u16();
    if (!size.has_value())
    {
        return TextureResult<PropertyRecord>::failure(
            from_read_error(size.error(), "texture.property.size"));
    }
    const auto value_offset = reader.absolute_position();
    const auto value = reader.read_bytes(size.value());
    if (!value.has_value())
    {
        return TextureResult<PropertyRecord>::failure(
            from_read_error(value.error(), "texture.property.value"));
    }
    return TextureResult<PropertyRecord>::success(
        {.name = std::string(reinterpret_cast<const char*>(name_bytes.value().data()),
                             name_bytes.value().size()),
         .value_offset = value_offset,
         .value = value.value()});
}

[[nodiscard]] TextureResult<std::int32_t>
read_property_value(const std::span<const std::byte> bytes, const std::uint64_t offset,
                    const std::string_view name)
{
    if (bytes.size() != 4U)
    {
        return TextureResult<std::int32_t>::failure(
            make_error(TextureErrorCode::invalid_property_size, offset,
                       "texture.property." + std::string(name)));
    }
    format::BinaryReader reader(bytes, format::ByteOrder::little_endian, offset,
                                "texture.property");
    const auto value = reader.read_i32();
    if (!value.has_value())
    {
        return TextureResult<std::int32_t>::failure(
            from_read_error(value.error(), "texture.property." + std::string(name)));
    }
    return TextureResult<std::int32_t>::success(value.value());
}

[[nodiscard]] std::optional<TextureError> assign_known(TextureDescriptor& descriptor,
                                                       const KnownAssignment assignment)
{
    switch (assignment.property)
    {
    case KnownProperty::format:
        if (assignment.value < 0 ||
            assignment.value > static_cast<std::int32_t>(TextureFormat::dxt5))
        {
            return make_error(TextureErrorCode::invalid_format, assignment.offset,
                              "texture.format");
        }
        descriptor.format = static_cast<TextureFormat>(assignment.value);
        break;
    case KnownProperty::u_clamp:
    case KnownProperty::v_clamp:
        if (assignment.value < 0 || assignment.value > static_cast<std::int32_t>(ClampMode::clamp))
        {
            return make_error(TextureErrorCode::invalid_clamp_mode, assignment.offset,
                              "texture.clamp");
        }
        if (assignment.property == KnownProperty::u_clamp)
        {
            descriptor.u_clamp = static_cast<ClampMode>(assignment.value);
        }
        else
        {
            descriptor.v_clamp = static_cast<ClampMode>(assignment.value);
        }
        break;
    case KnownProperty::width:
        descriptor.width = assignment.value > 0 ? static_cast<std::uint32_t>(assignment.value) : 0U;
        break;
    case KnownProperty::height:
        descriptor.height =
            assignment.value > 0 ? static_cast<std::uint32_t>(assignment.value) : 0U;
        break;
    case KnownProperty::mip_count:
        if (assignment.value < 0)
        {
            return make_error(TextureErrorCode::invalid_mip_count, assignment.offset,
                              "texture.mipLevel");
        }
        descriptor.stored_mip_count = static_cast<std::uint32_t>(assignment.value);
        break;
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<TextureError> validate_descriptor(TextureDescriptor& descriptor,
                                                              const TextureDescriptorLimits limits,
                                                              const std::uint64_t base_offset)
{
    if (descriptor.width == 0U || descriptor.height == 0U ||
        descriptor.width > limits.maximum_dimension || descriptor.height > limits.maximum_dimension)
    {
        return make_error(TextureErrorCode::invalid_dimension, base_offset, "texture.dimensions");
    }
    descriptor.mip_count = descriptor.stored_mip_count == 0U ? 1U : descriptor.stored_mip_count;
    if (descriptor.mip_count > limits.maximum_mip_count ||
        descriptor.mip_count > maximum_mips(descriptor.width, descriptor.height))
    {
        return make_error(TextureErrorCode::invalid_mip_count, base_offset, "texture.mipLevel");
    }
    return std::nullopt;
}

} // namespace

LegacyTextureDescriptorReader::LegacyTextureDescriptorReader(const TextureDescriptorLimits limits)
    : limits_(limits)
{
}

TextureResult<TextureDescriptor>
LegacyTextureDescriptorReader::parse(const std::span<const std::byte> object_body,
                                     const std::uint64_t base_offset) const
{
    format::BinaryReader reader(object_body, format::ByteOrder::little_endian, base_offset,
                                "texture.object_body");
    const auto count = reader.read_u16();
    if (!count.has_value())
    {
        return TextureResult<TextureDescriptor>::failure(
            from_read_error(count.error(), "texture.item_count"));
    }
    if (count.value() > limits_.maximum_item_count)
    {
        return TextureResult<TextureDescriptor>::failure(make_error(
            TextureErrorCode::item_count_limit_exceeded, base_offset, "texture.item_count"));
    }

    TextureDescriptor descriptor;
    std::array<bool, 6> seen{};
    for (std::uint16_t item = 0; item < count.value(); ++item)
    {
        auto record = read_record(reader, limits_.maximum_property_name_bytes);
        if (!record.has_value())
        {
            return TextureResult<TextureDescriptor>::failure(record.error());
        }
        const auto property = known_property(record.value().name);
        if (!property.has_value())
        {
            descriptor.unknown_properties.push_back(
                {.name_bytes = record.value().name,
                 .value_offset = record.value().value_offset,
                 .value = std::vector<std::byte>(record.value().value.begin(),
                                                 record.value().value.end())});
            continue;
        }
        const auto known_index = static_cast<std::size_t>(*property);
        if (seen[known_index])
        {
            return TextureResult<TextureDescriptor>::failure(
                make_error(TextureErrorCode::duplicate_property, record.value().value_offset,
                           "texture.property." + record.value().name));
        }
        seen[known_index] = true;
        auto property_value = read_property_value(record.value().value, record.value().value_offset,
                                                  record.value().name);
        if (!property_value.has_value())
        {
            return TextureResult<TextureDescriptor>::failure(property_value.error());
        }
        if (const auto error = assign_known(descriptor, {.property = *property,
                                                         .value = property_value.value(),
                                                         .offset = record.value().value_offset}))
        {
            return TextureResult<TextureDescriptor>::failure(*error);
        }
    }

    if (reader.remaining() != 0U)
    {
        return TextureResult<TextureDescriptor>::failure(
            make_error(TextureErrorCode::trailing_descriptor_bytes, reader.absolute_position(),
                       "texture.object_body.trailing"));
    }
    if (const auto error = validate_descriptor(descriptor, limits_, base_offset))
    {
        return TextureResult<TextureDescriptor>::failure(*error);
    }
    return TextureResult<TextureDescriptor>::success(std::move(descriptor));
}

} // namespace tmxy::texture
