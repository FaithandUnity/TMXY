#include "Logging/LogMacros.h"
#include "Modules/ModuleManager.h"
#include "TMXYBuildInfo.h"

DEFINE_LOG_CATEGORY_STATIC(LogTMXYClient, Log, All);

class FTMXYClientModule final : public IModuleInterface
{
  public:
    void StartupModule() override
    {
        const TMXY::Core::FBuildInfo& buildInfo = TMXY::Core::GetBuildInfo();
        UE_LOG(LogTMXYClient, Display,
               TEXT("event=client_module_started product=%s version=%u.%u.%u"),
               buildInfo.ProductName, buildInfo.VersionMajor, buildInfo.VersionMinor,
               buildInfo.VersionPatch);
    }
};

IMPLEMENT_PRIMARY_GAME_MODULE(FTMXYClientModule, TMXYClient, "TMXYClient")
