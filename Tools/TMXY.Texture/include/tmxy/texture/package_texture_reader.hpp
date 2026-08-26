#pragma once

#include "tmxy/texture/texture_result.hpp"
#include "tmxy/texture/texture_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace tmxy::texture
{

struct PackageTextureDescriptor final
{
    std::string object_name_bytes;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    TextureDescriptor descriptor;
};

[[nodiscard]] TextureResult<PackageTextureDescriptor>
read_package_texture_descriptor(std::span<const std::byte> package_bytes,
                                std::string_view full_object_name);

} // namespace tmxy::texture
