#include "package_object_index.hpp"

#include "tmxy/package/package_v1.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3.hpp"
#include "tmxy/package/package_v3_reader.hpp"

#include <algorithm>
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

enum class PackageKind : std::uint8_t
{
    unknown = 0,
    v1 = 1,
    v2 = 2,
    v3 = 3,
};

[[nodiscard]] AnimationError make_error(const std::uint64_t offset, std::string context)
{
    return {.code = AnimationErrorCode::invalid_package,
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
    return length == version.size() &&
           std::ranges::equal(bytes.subspan(2U, length), version,
                              [](const std::byte left, const char right)
                              {
                                  return std::to_integer<unsigned char>(left) ==
                                         static_cast<unsigned char>(right);
                              });
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

template <typename Header> [[nodiscard]] std::vector<ObjectSpan> copy_objects(const Header& header)
{
    std::vector<ObjectSpan> objects;
    objects.reserve(header.records.size());
    for (const auto& record : header.records)
    {
        objects.push_back({.name = record.name_bytes,
                           .class_name = record.class_name_bytes,
                           .offset = record.offset,
                           .size = record.size});
    }
    return objects;
}

} // namespace

AnimationResult<std::vector<ObjectSpan>>
read_package_objects(const std::span<const std::byte> bytes)
{
    switch (detect_package(bytes))
    {
    case PackageKind::v1:
    {
        const auto parsed = package::PackageV1Reader{}.parse(bytes);
        return parsed.has_value()
                   ? AnimationResult<std::vector<ObjectSpan>>::success(copy_objects(parsed.value()))
                   : AnimationResult<std::vector<ObjectSpan>>::failure(
                         make_error(parsed.error().absolute_offset, "package.v1"));
    }
    case PackageKind::v2:
    {
        const auto parsed = package::PackageV2Reader{}.parse(bytes);
        return parsed.has_value()
                   ? AnimationResult<std::vector<ObjectSpan>>::success(copy_objects(parsed.value()))
                   : AnimationResult<std::vector<ObjectSpan>>::failure(
                         make_error(parsed.error().absolute_offset, "package.v2"));
    }
    case PackageKind::v3:
    {
        const auto parsed = package::PackageV3Reader{}.parse(bytes);
        return parsed.has_value()
                   ? AnimationResult<std::vector<ObjectSpan>>::success(copy_objects(parsed.value()))
                   : AnimationResult<std::vector<ObjectSpan>>::failure(
                         make_error(parsed.error().absolute_offset, "package.v3"));
    }
    case PackageKind::unknown:
        break;
    }
    return AnimationResult<std::vector<ObjectSpan>>::failure(make_error(0, "package.version"));
}

} // namespace tmxy::animation
