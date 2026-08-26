using UnrealBuildTool;

public class TMXYImporter : ModuleRules
{
    public TMXYImporter(ReadOnlyTargetRules target) : base(target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        CppStandard = CppStandardVersion.Cpp20;

        PublicDependencyModuleNames.Add("Core");
        PrivateDependencyModuleNames.AddRange(new[]
        {
            "CoreUObject",
            "Engine",
            "Json",
            "AnimationCore",
            "AnimationDataController",
            "MeshConversion",
            "MeshDescription",
            "SkeletalMeshDescription",
            "SkeletalMeshUtilitiesCommon",
            "StaticMeshDescription"
        });

        if (target.Platform == UnrealTargetPlatform.Win64)
        {
            PublicSystemLibraries.Add("bcrypt.lib");
        }
    }
}
