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

class QtxReader final
{
  public:
    explicit QtxReader(QtxLimits limits = {});

    [[nodiscard]] TextureResult<QtxTextureView> parse(TextureDescriptor descriptor,
                                                      std::span<const std::byte> payload) const;

  private:
    QtxLimits limits_;
};

[[nodiscard]] TextureResult<std::vector<std::byte>>
decode_mip_zero_rgba8(const QtxTextureView& texture, std::span<const std::byte> payload);

} // namespace tmxy::texture
