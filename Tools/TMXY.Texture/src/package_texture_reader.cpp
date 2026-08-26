#include "tmxy/texture/package_texture_reader.hpp"

#include "tmxy/package/package_v1.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3.hpp"
#include "tmxy/package/package_v3_reader.hpp"
#include "tmxy/texture/legacy_texture_descriptor_reader.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>

namespace tmxy::texture
{
namespace
{

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
[[nodiscard]] TextureResult<ObjectSpan> find_object(const Header& header,
                                                    const std::string_view object_name)
{
    for (const auto& record : header.records)
    {
        if (record.name_bytes == object_name)
        {
            return TextureResult<ObjectSpan>::success({.name = record.name_bytes,
                                                       .class_name = record.class_name_bytes,
                                                       .offset = record.offset,
                                                       .size = record.size});
        }
    }
    return TextureResult<ObjectSpan>::failure({.code = TextureErrorCode::texture_object_not_found,
                                               .context = "package.texture_object",
                                               .read_error_code = std::nullopt});
}

[[nodiscard]] TextureResult<ObjectSpan> parse_object(const std::span<const std::byte> bytes,
                                                     const PackageKind kind,
                                                     const std::string_view object_name)
{
    if (kind == PackageKind::v1)
    {
        const auto result = package::PackageV1Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : TextureResult<ObjectSpan>::failure(
                                        {.code = TextureErrorCode::invalid_package,
                                         .absolute_offset = result.error().absolute_offset,
                                         .context = "package.v1",
                                         .read_error_code = std::nullopt});
    }
    if (kind == PackageKind::v2)
    {
        const auto result = package::PackageV2Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : TextureResult<ObjectSpan>::failure(
                                        {.code = TextureErrorCode::invalid_package,
                                         .absolute_offset = result.error().absolute_offset,
                                         .context = "package.v2",
                                         .read_error_code = std::nullopt});
    }
    if (kind == PackageKind::v3)
    {
        const auto result = package::PackageV3Reader{}.parse(bytes);
        return result.has_value() ? find_object(result.value(), object_name)
                                  : TextureResult<ObjectSpan>::failure(
                                        {.code = TextureErrorCode::invalid_package,
                                         .absolute_offset = result.error().absolute_offset,
                                         .context = "package.v3",
                                         .read_error_code = std::nullopt});
    }
    return TextureResult<ObjectSpan>::failure({.code = TextureErrorCode::invalid_package,
                                               .context = "package.version",
                                               .read_error_code = std::nullopt});
}

} // namespace

TextureResult<PackageTextureDescriptor>
read_package_texture_descriptor(const std::span<const std::byte> package_bytes,
                                const std::string_view full_object_name)
{
    auto object = parse_object(package_bytes, detect_package(package_bytes), full_object_name);
    if (!object.has_value())
    {
        return TextureResult<PackageTextureDescriptor>::failure(object.error());
    }
    if (object.value().class_name != "QTexture")
    {
        return TextureResult<PackageTextureDescriptor>::failure(
            {.code = TextureErrorCode::wrong_object_class,
             .absolute_offset = object.value().offset,
             .context = "package.texture_object.class",
             .read_error_code = std::nullopt});
    }
    if (object.value().offset > package_bytes.size() ||
        object.value().size > package_bytes.size() - object.value().offset)
    {
        return TextureResult<PackageTextureDescriptor>::failure(
            {.code = TextureErrorCode::object_range_out_of_file,
             .absolute_offset = object.value().offset,
             .context = "package.texture_object.body",
             .read_error_code = std::nullopt});
    }
    const auto body = package_bytes.subspan(static_cast<std::size_t>(object.value().offset),
                                            static_cast<std::size_t>(object.value().size));
    auto descriptor = LegacyTextureDescriptorReader{}.parse(body, object.value().offset);
    if (!descriptor.has_value())
    {
        return TextureResult<PackageTextureDescriptor>::failure(descriptor.error());
    }
    return TextureResult<PackageTextureDescriptor>::success(
        {.object_name_bytes = object.value().name,
         .body_offset = object.value().offset,
         .body_size = object.value().size,
         .descriptor = std::move(descriptor).value()});
}

} // namespace tmxy::texture
