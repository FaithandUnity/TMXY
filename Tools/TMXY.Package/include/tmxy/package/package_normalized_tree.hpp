#pragma once

#include "tmxy/package/package_v1.hpp"
#include "tmxy/package/package_v2.hpp"
#include "tmxy/package/package_v3.hpp"

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::package
{

struct NormalizedPackageObject final
{
    std::uint64_t index{0};
    std::string name_bytes;
    std::string class_name_bytes;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
};

struct NormalizedPackageTree final
{
    static constexpr std::uint32_t kSchemaVersion = 1;

    std::string source_label;
    std::string format_version;
    std::uint64_t file_size{0};
    std::uint64_t header_size{0};
    std::uint64_t directory_offset{0};
    std::uint64_t directory_size{0};
    std::vector<NormalizedPackageObject> objects;
};

[[nodiscard]] NormalizedPackageTree normalize_package_tree(const PackageV1Header& header,
                                                           std::string source_label);
[[nodiscard]] NormalizedPackageTree normalize_package_tree(const PackageV2Header& header,
                                                           std::string source_label);
[[nodiscard]] NormalizedPackageTree normalize_package_tree(const PackageV3Header& header,
                                                           std::string source_label);

[[nodiscard]] std::string package_tree_to_json(const NormalizedPackageTree& tree);

} // namespace tmxy::package
