#pragma once

#include "tmxy/texture/texture_result.hpp"
#include "tmxy/texture/texture_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace tmxy::texture
{

struct TextureDescriptorLimits final
{
    std::uint16_t maximum_item_count{256};
    std::uint16_t maximum_property_name_bytes{1024};
    std::uint32_t maximum_dimension{16384};
    std::uint32_t maximum_mip_count{15};
};

class LegacyTextureDescriptorReader final
{
  public:
    explicit LegacyTextureDescriptorReader(TextureDescriptorLimits limits = {});

    [[nodiscard]] TextureResult<TextureDescriptor> parse(std::span<const std::byte> object_body,
                                                         std::uint64_t base_offset = 0) const;

  private:
    TextureDescriptorLimits limits_;
};

} // namespace tmxy::texture
