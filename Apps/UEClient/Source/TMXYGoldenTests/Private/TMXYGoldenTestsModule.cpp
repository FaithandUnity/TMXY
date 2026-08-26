#include "Modules/ModuleManager.h"

DEFINE_LOG_CATEGORY_STATIC(LogTMXYGoldenTests, Log, All);

class FTMXYGoldenTestsModule final : public IModuleInterface
{
  public:
    void StartupModule() override
    {
        UE_LOG(LogTMXYGoldenTests, Display,
               TEXT("event=golden_test_module_started root=/Game/TMXY/Golden"));
    }
};

IMPLEMENT_MODULE(FTMXYGoldenTestsModule, TMXYGoldenTests)
