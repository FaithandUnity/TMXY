#if WITH_DEV_AUTOMATION_TESTS

#include "Engine/Level.h"
#include "Engine/World.h"
#include "Misc/AutomationTest.h"
#include "Misc/PackageName.h"
#include "UObject/Package.h"
#include "UObject/UObjectGlobals.h"

namespace TMXY::Golden
{
constexpr TCHAR RootPackage[] = TEXT("/Game/TMXY/Golden");
constexpr TCHAR HostMapPackage[] = TEXT("/Game/TMXY/Golden/Maps/TMXYGoldenTestMap");
} // namespace TMXY::Golden

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FTMXYGoldenHostTest, "TMXY.Golden.Host",
                                 EAutomationTestFlags::EditorContext |
                                     EAutomationTestFlags::EngineFilter)

bool FTMXYGoldenHostTest::RunTest(const FString& parameters)
{
    static_cast<void>(parameters);

    const FString rootPackage(TMXY::Golden::RootPackage);
    const FString hostMapPackage(TMXY::Golden::HostMapPackage);
    TestTrue(TEXT("Golden root is fixed below /Game"), rootPackage == TEXT("/Game/TMXY/Golden"));
    TestTrue(TEXT("Host map is contained by the golden root"),
             hostMapPackage.StartsWith(rootPackage + TEXT("/")));

    FString mapFilename;
    if (!TestTrue(TEXT("Golden host map package exists"),
                  FPackageName::DoesPackageExist(hostMapPackage, &mapFilename)))
    {
        return false;
    }
    TestTrue(TEXT("Golden host map resolves to an umap"),
             mapFilename.EndsWith(FPackageName::GetMapPackageExtension()));

    UPackage* mapPackage = LoadPackage(nullptr, *hostMapPackage, LOAD_None);
    if (!TestNotNull(TEXT("Golden host map package loads"), mapPackage))
    {
        return false;
    }

    UWorld* world = UWorld::FindWorldInPackage(mapPackage);
    if (!TestNotNull(TEXT("Golden host package contains a world"), world))
    {
        return false;
    }
    TestNotNull(TEXT("Golden host world has a persistent level"), world->PersistentLevel.Get());
    TestTrue(TEXT("Golden host map does not use World Partition"),
             world->GetWorldPartition() == nullptr);
    return !HasAnyErrors();
}

#endif
