#include "tmxy/foundation/build_info.hpp"

namespace tmxy::foundation
{
namespace
{
constexpr BuildInfo kCurrentBuildInfo{
    .product = "tmxy-backend",
    .version_major = 0,
    .version_minor = 1,
    .version_patch = 0,
};
}

const BuildInfo& current_build_info() noexcept
{
    return kCurrentBuildInfo;
}
} // namespace tmxy::foundation
