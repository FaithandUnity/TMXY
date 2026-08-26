using UnrealBuildTool;

public class TMXYEditorTarget : TargetRules
{
    public TMXYEditorTarget(TargetInfo target) : base(target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_8;
        CppStandard = CppStandardVersion.Cpp20;
        ExtraModuleNames.AddRange(new[] { "TMXYClient", "TMXYGoldenTests" });
    }
}
