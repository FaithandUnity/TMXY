[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$UnrealEngineRoot = 'C:\Program Files\Epic Games\UE_5.8',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p0-10a-ue-validation.json',
    [switch]$RunAutomation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$ueRoot = [System.IO.Path]::GetFullPath($UnrealEngineRoot).TrimEnd([char[]]'\/')
$projectPath = Join-Path $root 'Apps\UEClient\TMXY.uproject'
$ubtPath = Join-Path $ueRoot 'Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.exe'
$editorPath = Join-Path $ueRoot 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
$engineVersionPath = Join-Path $ueRoot 'Engine\Build\Build.version'

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdout.Trim()
        stderr = $stderr.Trim()
    }
}

function Invoke-UnrealBuildTool {
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)
    $result = $null
    foreach ($attempt in 1..3) {
        $result = Invoke-NativeProcess -FilePath $ubtPath -ArgumentList $ArgumentList
        $conflictingInstance = $result.exit_code -eq 10 -or
            $result.stdout -match 'ConflictingInstance|conflicting instance'
        if (-not $conflictingInstance) { return $result }
        if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
    }
    return $result
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Get-ProcessSummary {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    $lines = @($Value -split "`r?`n" | Where-Object {
        $_ -match '^Result: ' -or
        $_ -match '^Total execution time: ' -or
        $_ -match '^Visual Studio compiler version .* preferred version'
    } | Select-Object -Unique)
    return $lines -join "`n"
}

$requiredPaths = @(
    $projectPath,
    $ubtPath,
    $editorPath,
    $engineVersionPath,
    (Join-Path $root 'Apps\UEClient\Source\TMXY.Target.cs'),
    (Join-Path $root 'Apps\UEClient\Source\TMXYEditor.Target.cs'),
    (Join-Path $root 'Apps\UEClient\Source\TMXYCore\TMXYCore.Build.cs'),
    (Join-Path $root 'Apps\UEClient\Source\TMXYClient\TMXYClient.Build.cs'),
    (Join-Path $root 'Apps\UEClient\Source\TMXYGoldenTests\TMXYGoldenTests.Build.cs'),
    (Join-Path $root 'Apps\UEClient\Plugins\TMXYImporter\TMXYImporter.uplugin'),
    (Join-Path $root 'Apps\UEClient\Plugins\TMXYImporter\Source\TMXYImporter\TMXYImporter.Build.cs'),
    (Join-Path $root 'Apps\UEClient\Content\TMXY\Golden\Maps\TMXYGoldenTestMap.umap')
)
$missingPaths = @($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })

$project = Get-Content -LiteralPath $projectPath -Raw | ConvertFrom-Json
$engineVersion = Get-Content -LiteralPath $engineVersionPath -Raw | ConvertFrom-Json
$moduleNames = @($project.Modules | ForEach-Object { [string]$_.Name })
$androidFileServer = @($project.Plugins | Where-Object { [string]$_.Name -eq 'AndroidFileServer' })
$importerPlugin = @($project.Plugins | Where-Object { [string]$_.Name -eq 'TMXYImporter' })
$goldenModule = @($project.Modules | Where-Object { [string]$_.Name -eq 'TMXYGoldenTests' })
$pluginPolicyPassed = $androidFileServer.Count -eq 1 -and -not [bool]$androidFileServer[0].Enabled
$importerDescriptorPath = Join-Path $root 'Apps\UEClient\Plugins\TMXYImporter\TMXYImporter.uplugin'
$importerDescriptor = Get-Content -LiteralPath $importerDescriptorPath -Raw | ConvertFrom-Json
$importerModules = @($importerDescriptor.Modules | Where-Object { [string]$_.Name -eq 'TMXYImporter' })
$importerPolicyPassed = $importerPlugin.Count -eq 1 -and [bool]$importerPlugin[0].Enabled -and
    $importerModules.Count -eq 1 -and [string]$importerModules[0].Type -eq 'Editor' -and
    [string]$importerModules[0].LoadingPhase -eq 'PostEngineInit' -and
    @($importerDescriptor.SupportedTargetPlatforms).Count -eq 1 -and
    [string]$importerDescriptor.SupportedTargetPlatforms[0] -eq 'Win64'
$goldenModulePassed = $goldenModule.Count -eq 1 -and
    [string]$goldenModule[0].Type -eq 'Editor' -and
    [string]$goldenModule[0].LoadingPhase -eq 'PostEngineInit'
$descriptorPassed = [string]$project.EngineAssociation -eq '5.8' -and
    $moduleNames -contains 'TMXYCore' -and
    $moduleNames -contains 'TMXYClient' -and
    $goldenModulePassed -and
    $importerPolicyPassed -and
    $pluginPolicyPassed
$enginePassed = [int]$engineVersion.MajorVersion -eq 5 -and
    [int]$engineVersion.MinorVersion -eq 8 -and
    [int]$engineVersion.PatchVersion -eq 2

$projectGeneration = if ($missingPaths.Count -eq 0) {
    Invoke-UnrealBuildTool -ArgumentList @(
        '-ProjectFiles', "-Project=$projectPath", '-Game', '-Rocket', '-Progress'
    )
}
else {
    [pscustomobject][ordered]@{ exit_code = -1; stdout = ''; stderr = 'Required paths are missing.' }
}

$build = if ($projectGeneration.exit_code -eq 0) {
    Invoke-UnrealBuildTool -ArgumentList @(
        'TMXYEditor', 'Win64', 'Development', "-Project=$projectPath",
        '-WaitMutex', '-NoHotReloadFromIDE', '-Progress'
    )
}
else {
    [pscustomobject][ordered]@{ exit_code = -1; stdout = ''; stderr = 'Project generation failed.' }
}

$clangFormatPath = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\Llvm\x64\bin\clang-format.exe'
$cppFiles = @(
    Get-ChildItem -LiteralPath @(
        (Join-Path $root 'Apps\UEClient\Source'),
        (Join-Path $root 'Apps\UEClient\Plugins')
    ) -Recurse -File |
        Where-Object {
            $_.Extension -in @('.cpp', '.h') -and
            $_.FullName -notmatch '[\\/](?:Binaries|Intermediate|Saved|DerivedDataCache)[\\/]'
        } |
        Select-Object -ExpandProperty FullName
)
$format = if (Test-Path -LiteralPath $clangFormatPath -PathType Leaf) {
    Invoke-NativeProcess -FilePath $clangFormatPath -ArgumentList (@(
        '--dry-run', '--Werror', '--style=file'
    ) + $cppFiles)
}
else {
    [pscustomobject][ordered]@{ exit_code = -1; stdout = ''; stderr = 'clang-format is missing.' }
}

$automation = $null
$automationLogPath = $null
$automationPassed = $null
$buildInfoPassed = $null
$goldenHostPassed = $null
$importerPassed = $null
$textureImporterPassed = $null
$staticMeshImporterPassed = $null
$skeletalMeshImporterPassed = $null
$animationImporterPassed = $null
$terrainImporterPassed = $null
$moduleLoaded = $null
$goldenModuleLoaded = $null
$importerModuleLoaded = $null
if ($RunAutomation -and $build.exit_code -eq 0) {
    $logDirectory = Join-Path $root 'Apps\UEClient\Saved\Logs'
    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
    $timestamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmssfff')
    $automationLogPath = Join-Path $logDirectory "TMXYAutomation-$timestamp.log"
    $automation = Invoke-NativeProcess -FilePath $editorPath -ArgumentList @(
        $projectPath, '-Unattended', '-NoP4', '-NoSplash', '-NullRHI', '-NoSound',
        '-ExecCmds=Automation RunTests TMXY',
        '-TestExit=Automation Test Queue Empty', "-AbsLog=$automationLogPath"
    )
    $automationLog = if (Test-Path -LiteralPath $automationLogPath -PathType Leaf) {
        Get-Content -LiteralPath $automationLogPath -Raw
    }
    else {
        ''
    }
    $buildInfoPassed = $automationLog -match
        'Test Completed\. Result=\{Success\} Name=\{BuildInfo\} Path=\{TMXY\.Core\.BuildInfo\}'
    $goldenHostPassed = $automationLog -match
        'Test Completed\. Result=\{Success\} Name=\{Host\} Path=\{TMXY\.Golden\.Host\}'
    $importerPassed = $automationLog -match
        'Test Completed\. Result=\{Success\} Name=\{ManifestBatch\} Path=\{TMXY\.Importer\.ManifestBatch\}'
    $textureImporterPassed = $automationLog -match
        'Test Completed\. Result=\{Success\} Name=\{Texture\} Path=\{TMXY\.Importer\.Texture\}'
    $staticMeshImporterPassed = $automationLog -match
        'Test Completed\. Result=\{Success\} Name=\{StaticMesh\} Path=\{TMXY\.Importer\.StaticMesh\}'
    $skeletalMeshImporterPassed = $automationLog -match
        'Test Completed\. Result=\{Success\} Name=\{SkeletalMesh\} Path=\{TMXY\.Importer\.SkeletalMesh\}'
    $animationImporterPassed = $automationLog -match
        'Test Completed\. Result=\{Success\} Name=\{Animation\} Path=\{TMXY\.Importer\.Animation\}'
    $terrainImporterPassed = $automationLog -match
        'Test Completed\. Result=\{Success\} Name=\{Terrain\} Path=\{TMXY\.Importer\.Terrain\}'
    $automationPassed = $automation.exit_code -eq 0 -and $buildInfoPassed -and
        $goldenHostPassed -and $importerPassed -and $textureImporterPassed -and
        $staticMeshImporterPassed -and $skeletalMeshImporterPassed -and $animationImporterPassed -and
        $terrainImporterPassed
    $moduleLoaded = $automationLog -match 'event=client_module_started product=tmxy-client version=0\.1\.0'
    $goldenModuleLoaded = $automationLog -match
        'event=golden_test_module_started root=/Game/TMXY/Golden'
    $importerModuleLoaded = $automationLog -match
        'event=importer_module_started mode=editor-only report_version=1\.0\.0'
}

$contentRoot = Join-Path $root 'Apps\UEClient\Content'
$contentAssets = @(
    Get-ChildItem -LiteralPath $contentRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.uasset', '.umap') }
)
$contentAssetPaths = @($contentAssets | ForEach-Object {
    $_.FullName.Substring($contentRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
} | Sort-Object)
$expectedContentAssets = @(
    'TMXY/Golden/Animations/A_Golden_Boy01_RoamIdle.uasset',
    'TMXY/Golden/Animations/A_Golden_Boy01_RunForward.uasset',
    'TMXY/Golden/Animations/A_Golden_Boy01_SelectIdle.uasset',
    'TMXY/Golden/Maps/TMXYGoldenTestMap.umap',
    'TMXY/Golden/SkeletalMeshes/SK_Golden_Boy01_Default.uasset',
    'TMXY/Golden/Skeletons/SKEL_Golden_Boy01.uasset',
    'TMXY/Golden/StaticMeshes/SM_Golden_Minimum_Real.uasset',
    'TMXY/Golden/StaticMeshes/SM_Golden_MultiSection_Real.uasset',
    'TMXY/Golden/Terrain/SMT_Golden_World_001_001.uasset',
    'TMXY/Golden/Terrain/SMT_Golden_World_001_002.uasset',
    'TMXY/Golden/Terrain/SMT_Golden_World_002_001.uasset',
    'TMXY/Golden/Textures/T_Golden_MultiMip_DXT1.uasset',
    'TMXY/Golden/Textures/T_Golden_Opaque_DXT1.uasset',
    'TMXY/Golden/Textures/T_Golden_Transparent_DXT5.uasset'
)
$contentPolicyPassed = $contentAssets.Count -eq $expectedContentAssets.Count -and
    $contentAssetPaths.Count -eq $expectedContentAssets.Count -and
    @(Compare-Object $contentAssetPaths $expectedContentAssets).Count -eq 0
$solutionExists = Test-Path -LiteralPath (Join-Path $root 'Apps\UEClient\TMXY.sln') -PathType Leaf
$requiredPassed = $missingPaths.Count -eq 0 -and
    $descriptorPassed -and
    $enginePassed -and
    $projectGeneration.exit_code -eq 0 -and
    $build.exit_code -eq 0 -and
    $format.exit_code -eq 0 -and
    $solutionExists -and
    $contentPolicyPassed
$passed = $requiredPassed -and
    (-not $RunAutomation -or ($automationPassed -and $moduleLoaded -and $goldenModuleLoaded -and
            $importerModuleLoaded))

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    project = [pscustomobject][ordered]@{
        path = $projectPath
        engine_association = [string]$project.EngineAssociation
        modules = $moduleNames
        descriptor_passed = $descriptorPassed
        golden_module_editor_only = $goldenModulePassed
        importer_plugin_editor_only = $importerPolicyPassed
        android_file_server_disabled = $pluginPolicyPassed
        solution_generated = $solutionExists
        cooked_asset_count = $contentAssets.Count
        content_asset_count = $contentAssets.Count
        content_assets = $contentAssetPaths
        content_policy_passed = $contentPolicyPassed
    }
    engine = [pscustomobject][ordered]@{
        version = "$($engineVersion.MajorVersion).$($engineVersion.MinorVersion).$($engineVersion.PatchVersion)"
        changelist = [int64]$engineVersion.Changelist
        compatible_changelist = [int64]$engineVersion.CompatibleChangelist
        passed = $enginePassed
    }
    project_generation = [pscustomobject][ordered]@{
        passed = $projectGeneration.exit_code -eq 0
        exit_code = $projectGeneration.exit_code
        output = Get-ProcessSummary -Value $projectGeneration.stdout
        output_sha256 = Get-TextSha256 -Value $projectGeneration.stdout
        error = $projectGeneration.stderr
    }
    editor_build = [pscustomobject][ordered]@{
        target = 'TMXYEditor Win64 Development'
        passed = $build.exit_code -eq 0
        exit_code = $build.exit_code
        compiler_not_preferred_warning = $build.stdout -match 'not a preferred version|newer than latest preferred version'
        output = Get-ProcessSummary -Value $build.stdout
        output_sha256 = Get-TextSha256 -Value $build.stdout
        error = $build.stderr
    }
    format = [pscustomobject][ordered]@{
        passed = $format.exit_code -eq 0
        checked_files = $cppFiles.Count
        error = $format.stderr
    }
    automation = [pscustomobject][ordered]@{
        requested = [bool]$RunAutomation
        passed = $automationPassed
        test_count = if ($RunAutomation) { 8 } else { 0 }
        build_info_passed = $buildInfoPassed
        golden_host_passed = $goldenHostPassed
        importer_manifest_batch_passed = $importerPassed
        importer_texture_passed = $textureImporterPassed
        importer_static_mesh_passed = $staticMeshImporterPassed
        importer_skeletal_mesh_passed = $skeletalMeshImporterPassed
        importer_animation_passed = $animationImporterPassed
        importer_terrain_passed = $terrainImporterPassed
        module_loaded = $moduleLoaded
        golden_module_loaded = $goldenModuleLoaded
        importer_module_loaded = $importerModuleLoaded
        log_path = $automationLogPath
        process_exit_code = if ($null -ne $automation) { $automation.exit_code } else { $null }
    }
    missing_paths = $missingPaths
}

$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
$fullOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $fullOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText($fullOutputPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json

if (-not $passed) {
    throw 'UE project baseline validation failed. See the generated JSON report.'
}
