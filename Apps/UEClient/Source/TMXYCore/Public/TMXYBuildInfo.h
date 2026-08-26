#pragma once

#include "CoreTypes.h"

namespace TMXY::Core
{
struct FBuildInfo final
{
    const TCHAR* ProductName;
    uint16 VersionMajor;
    uint16 VersionMinor;
    uint16 VersionPatch;
};

TMXYCORE_API const FBuildInfo& GetBuildInfo();
} // namespace TMXY::Core
