#pragma once

#include "tmxy/package/package_v3.hpp"

#include <cstddef>
#include <span>
#include <variant>

namespace tmxy::package
{

struct PackageV3Limits final
{
    std::size_t maximum_directory_bytes{std::size_t{64} * 1024U * 1024U};
    std::size_t maximum_object_count{1'000'000};
};

class [[nodiscard]] PackageV3ParseResult final
{
  public:
    [[nodiscard]] static PackageV3ParseResult success(PackageV3Header header);
    [[nodiscard]] static PackageV3ParseResult failure(PackageV3Error error);
    [[nodiscard]] bool has_value() const noexcept;
    [[nodiscard]] const PackageV3Header& value() const& noexcept;
    [[nodiscard]] const PackageV3Error& error() const& noexcept;

  private:
    explicit PackageV3ParseResult(PackageV3Header header);
    explicit PackageV3ParseResult(PackageV3Error error);

    std::variant<PackageV3Header, PackageV3Error> storage_;
};

class PackageV3Reader final
{
  public:
    explicit PackageV3Reader(PackageV3Limits limits = {});

    [[nodiscard]] PackageV3ParseResult parse(std::span<const std::byte> bytes) const;

  private:
    PackageV3Limits limits_;
};

} // namespace tmxy::package
