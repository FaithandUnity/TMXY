#pragma once

#include "tmxy/package/package_v2.hpp"

#include <cstddef>
#include <span>
#include <variant>

namespace tmxy::package
{

struct PackageV2Limits final
{
    std::size_t maximum_directory_bytes{std::size_t{64} * 1024U * 1024U};
    std::size_t maximum_object_count{1'000'000};
};

class [[nodiscard]] PackageV2ParseResult final
{
  public:
    [[nodiscard]] static PackageV2ParseResult success(PackageV2Header header);
    [[nodiscard]] static PackageV2ParseResult failure(PackageV2Error error);
    [[nodiscard]] bool has_value() const noexcept;
    [[nodiscard]] const PackageV2Header& value() const& noexcept;
    [[nodiscard]] const PackageV2Error& error() const& noexcept;

  private:
    explicit PackageV2ParseResult(PackageV2Header header);
    explicit PackageV2ParseResult(PackageV2Error error);

    std::variant<PackageV2Header, PackageV2Error> storage_;
};

class PackageV2Reader final
{
  public:
    explicit PackageV2Reader(PackageV2Limits limits = {});

    [[nodiscard]] PackageV2ParseResult parse(std::span<const std::byte> bytes) const;

  private:
    PackageV2Limits limits_;
};

} // namespace tmxy::package
