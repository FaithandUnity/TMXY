#include "Modules/ModuleManager.h"

DEFINE_LOG_CATEGORY_STATIC(LogTMXYImporter, Log, All);

class FTMXYImporterModule final : public IModuleInterface
{
  public:
    void StartupModule() override
    {
        UE_LOG(LogTMXYImporter, Display,
               TEXT("event=importer_module_started mode=editor-only report_version=1.0.0"));
    }
};

IMPLEMENT_MODULE(FTMXYImporterModule, TMXYImporter)
