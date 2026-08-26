using UnrealBuildTool;

public class TMXYCore : ModuleRules
{
    public TMXYCore(ReadOnlyTargetRules target) : base(target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        CppStandard = CppStandardVersion.Cpp20;

        PublicDependencyModuleNames.Add("Core");
    }
}
