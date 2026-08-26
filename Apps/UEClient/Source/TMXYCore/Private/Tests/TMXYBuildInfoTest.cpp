#if WITH_DEV_AUTOMATION_TESTS

#include "TMXYBuildInfo.h"

#include "HAL/PlatformString.h"
#include "Misc/AutomationTest.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FTMXYBuildInfoTest, "TMXY.Core.BuildInfo",
                                 EAutomationTestFlags::EditorContext |
                                     EAutomationTestFlags::EngineFilter)

bool FTMXYBuildInfoTest::RunTest(const FString& parameters)
{
    static_cast<void>(parameters);
    const TMXY::Core::FBuildInfo& buildInfo = TMXY::Core::GetBuildInfo();

    TestTrue(TEXT("Product name is stable"),
             FCString::Strcmp(buildInfo.ProductName, TEXT("tmxy-client")) == 0);
    TestEqual(TEXT("Major version"), buildInfo.VersionMajor, static_cast<uint16>(0));
    TestEqual(TEXT("Minor version"), buildInfo.VersionMinor, static_cast<uint16>(1));
    TestEqual(TEXT("Patch version"), buildInfo.VersionPatch, static_cast<uint16>(0));
    return true;
}

#endif
