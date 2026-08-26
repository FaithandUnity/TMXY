#pragma once

#include "tmxy/skeletal_mesh/skeletal_mesh_types.hpp"

#include <array>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::skeletal_mesh::detail
{

struct ByteRange final
{
    std::size_t offset{0};
    std::size_t size{0};
    int target{0};
};

struct Primitive final
{
    ByteRange indices;
    std::string name;
    std::string legacy_material;
    bool two_sided{false};
};

struct BinaryLayout final
{
    std::vector<std::byte> bytes;
    std::array<ByteRange, 6> attributes;
    std::vector<Primitive> primitives;
    std::array<float, 3> minimum{};
    std::array<float, 3> maximum{};
    std::size_t vertex_count{0};
};

[[nodiscard]] std::string build_gltf_json(const SkeletalMeshBinding& binding,
                                          const BinaryLayout& layout, std::string_view buffer_uri);

} // namespace tmxy::skeletal_mesh::detail
