#pragma once

#include "tmxy/package/package_v1.hpp"

#include <cstddef>
#include <span>
#include <variant>

namespace tmxy::package
{

struct PackageV1Limits final
{
    std::size_t maximum_object_count{1'000'000};
};

class [[nodiscard]] PackageV1ParseResult final
{
  public:
    [[nodiscard]] static PackageV1ParseResult success(PackageV1Header header);
    [[nodiscard]] static PackageV1ParseResult failure(PackageV1Error error);
    [[nodiscard]] bool has_value() const noexcept;
    [[nodiscard]] const PackageV1Header& value() const& noexcept;
    [[nodiscard]] const PackageV1Error& error() const& noexcept;

  private:
    explicit PackageV1ParseResult(PackageV1Header header);
    explicit PackageV1ParseResult(PackageV1Error error);

    std::variant<PackageV1Header, PackageV1Error> storage_;
};

class PackageV1Reader final
{
  public:
    explicit PackageV1Reader(PackageV1Limits limits = {});

    [[nodiscard]] PackageV1ParseResult parse(std::span<const std::byte> bytes) const;

  private:
    PackageV1Limits limits_;
};

} // namespace tmxy::package
