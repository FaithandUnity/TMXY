#pragma once

#include "tmxy/texture/texture_result.hpp"
#include "tmxy/texture/texture_types.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace tmxy::texture
{

struct QtxLimits final
{
    std::uint64_t maximum_payload_bytes{512ULL * 1024ULL * 1024ULL};
    std::uint64_t maximum_decoded_bytes{1024ULL * 1024ULL * 1024ULL};
};

struct QtxMipCountResolution final
{
    std::uint32_t effective_mip_count{0};
    MipCountBasis basis{MipCountBasis::package_descriptor};
};

[[nodiscard]] TextureResult<std::uint32_t>
infer_complete_payload_mip_count(const TextureDescriptor& descriptor,
                                 std::span<const std::byte> payload);

class QtxReader final
{
  public:
    explicit QtxReader(QtxLimits limits = {});

    [[nodiscard]] TextureResult<QtxTextureView> parse(TextureDescriptor descriptor,
                                                      std::span<const std::byte> payload) const;

    [[nodiscard]] TextureResult<QtxTextureView>
    parse_with_mip_count_resolution(TextureDescriptor descriptor,
                                    std::span<const std::byte> payload,
                                    QtxMipCountResolution resolution) const;

  private:
    QtxLimits limits_;
};

[[nodiscard]] TextureResult<std::vector<std::byte>>
decode_mip_zero_rgba8(const QtxTextureView& texture, std::span<const std::byte> payload);

} // namespace tmxy::texture
