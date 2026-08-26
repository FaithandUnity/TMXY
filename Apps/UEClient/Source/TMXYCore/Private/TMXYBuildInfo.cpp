#include "TMXYBuildInfo.h"

namespace TMXY::Core
{
namespace
{
const FBuildInfo GBuildInfo{
    .ProductName = TEXT("tmxy-client"),
    .VersionMajor = 0,
    .VersionMinor = 1,
    .VersionPatch = 0,
};
}

const FBuildInfo& GetBuildInfo()
{
    return GBuildInfo;
}
} // namespace TMXY::Core
