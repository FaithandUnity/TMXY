using UnrealBuildTool;
using System.IO;

public class TMXYCore : ModuleRules
{
    public TMXYCore(ReadOnlyTargetRules target) : base(target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        CppStandard = CppStandardVersion.Cpp20;

        PublicDependencyModuleNames.Add("Core");

        PublicIncludePaths.Add(
            Path.GetFullPath(
                Path.Combine(
                    ModuleDirectory,
                    "..", "..", "..", "..",
                    "Contracts", "generated", "ue")));
    }
}
