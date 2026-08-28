[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$UnrealEngineRoot = 'C:\Program Files\Epic Games\UE_5.8',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p0-08-ue-packaging-waiver.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$ueRoot = [System.IO.Path]::GetFullPath($UnrealEngineRoot).TrimEnd([char[]]'\/')
$projectPath = Join-Path $root 'Apps\UEClient\TMXY.uproject'
$uatPath = Join-Path $ueRoot 'Engine\Build\BatchFiles\RunUAT.bat'
$compilerPath = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\cl.exe'
$sdkResourceCompilerPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\rc.exe'
$runId = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmssfff')
$generatedRoot = Join-Path $root "Apps\UEClient\Saved\P0-08Qualification\$runId"
$logRoot = Join-Path $root 'Apps\UEClient\Saved\P0-08QualificationLogs'

function Write-Utf8Lf {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $directory = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

function Get-SourceBinding {
    $inputFiles = @(
        Get-Item -LiteralPath $projectPath
        Get-ChildItem -LiteralPath (Join-Path $root 'Apps\UEClient\Config') -Recurse -File
        Get-ChildItem -LiteralPath (Join-Path $root 'Apps\UEClient\Source') -Recurse -File |
            Where-Object { $_.Extension -in @('.cs', '.cpp', '.h') }
        Get-ChildItem -LiteralPath (Join-Path $root 'Contracts\generated\ue') -Recurse -File |
            Where-Object { $_.Extension -in @('.h', '.hpp') }
        Get-ChildItem -LiteralPath (Join-Path $root 'Apps\UEClient\Plugins') -Recurse -File |
            Where-Object {
                $_.Extension -in @('.uplugin', '.cs', '.cpp', '.h') -and
                $_.FullName -notmatch '[\\/](Binaries|Intermediate|Saved|DerivedDataCache)[\\/]'
            }
        Get-ChildItem -LiteralPath (Join-Path $root 'Apps\UEClient\Content') -Recurse -File |
            Where-Object { $_.Extension -in @('.uasset', '.umap') }
        Get-Item -LiteralPath (Join-Path $root 'Apps\UEClient\Scripts\CreateTextureGoldenFixtures.ps1')
        Get-Item -LiteralPath (Join-Path $root 'Apps\UEClient\Scripts\CreateStaticMeshGoldenFixtures.ps1')
        Get-Item -LiteralPath (Join-Path $root 'Apps\UEClient\Scripts\CreateSkeletalMeshGoldenFixtures.ps1')
        Get-Item -LiteralPath (Join-Path $root 'Apps\UEClient\Scripts\CreateAnimationGoldenFixtures.ps1')
        Get-Item -LiteralPath (Join-Path $root 'Apps\UEClient\Scripts\CreateTerrainGoldenFixtures.ps1')
        Get-ChildItem -LiteralPath (Join-Path $root 'Tests\Fixtures\UE\Texture') -Recurse -File |
            Where-Object { $_.Extension -in @('.json', '.dds', '.png', '.tga') }
        Get-ChildItem -LiteralPath (Join-Path $root 'Tests\Fixtures\UE\StaticMesh') -Recurse -File |
            Where-Object { $_.Extension -in @('.json', '.gltf', '.bin', '.obj') }
        Get-ChildItem -LiteralPath (Join-Path $root 'Tests\Fixtures\UE\SkeletalMesh') -Recurse -File |
            Where-Object { $_.Extension -in @('.json', '.gltf', '.bin', '.obj') }
        Get-ChildItem -LiteralPath (Join-Path $root 'Tests\Fixtures\UE\Animation') -Recurse -File |
            Where-Object { $_.Extension -in @('.json', '.gltf', '.bin') }
        Get-ChildItem -LiteralPath (Join-Path $root 'Tests\Fixtures\UE\Terrain') -Recurse -File |
            Where-Object { $_.Extension -in @('.json', '.f32le', '.rgba8', '.csv') }
    ) | Sort-Object FullName -Unique
    $entries = foreach ($file in $inputFiles) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative`t$hash"
    }
    $manifestText = ($entries -join "`n") + "`n"
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($manifestText))
    }
    finally {
        $hasher.Dispose()
    }
    [pscustomobject][ordered]@{
        file_count = $inputFiles.Count
        manifest_sha256 = ([Convert]::ToHexString($digest)).ToLowerInvariant()
            scope = 'TMXY.uproject; Config/**; Source/**/*.{cs,cpp,h}; Contracts/generated/ue/**/*.{h,hpp}; Plugins/**/*.{uplugin,cs,cpp,h}; Content/**/*.{uasset,umap}; Apps/UEClient/Scripts/Create*GoldenFixtures.ps1; Tests/Fixtures/UE/Texture/**/*.{json,dds,png,tga}; Tests/Fixtures/UE/{StaticMesh,SkeletalMesh}/**/*.{json,gltf,bin,obj}; Tests/Fixtures/UE/Animation/**/*.{json,gltf,bin}; Tests/Fixtures/UE/Terrain/**/*.{json,f32le,rgba8,csv}'
    }
}

function Invoke-UatPackage {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Development', 'Shipping')][string]$Configuration,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )
    $arguments = @(
        'BuildCookRun', "-project=$projectPath", '-noP4', '-utf8output',
        '-platform=Win64', "-clientconfig=$Configuration", '-build', '-cook',
        '-stage', '-pak', '-package', '-archive', "-archivedirectory=$ArchivePath",
        '-unattended'
    )
    $started = [DateTimeOffset]::UtcNow
    $nativeOutput = @(& $uatPath @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($nativeOutput | ForEach-Object { $_.ToString() }) -join "`n"
    $logPath = Join-Path $logRoot "UAT-$Configuration-$runId.log"
    Write-Utf8Lf -Path $logPath -Content ($text + "`n")
    [pscustomobject][ordered]@{
        configuration = $Configuration
        exit_code = $exitCode
        passed = $exitCode -eq 0 -and $text -match 'BUILD SUCCESSFUL'
        duration_seconds = [Math]::Round(([DateTimeOffset]::UtcNow - $started).TotalSeconds, 3)
        editor_target_observed = $text -match 'TMXYEditor Win64 Development'
        client_target_observed = $text -match "TMXY Win64 $Configuration"
        compiler_version_observed = $text -match '14\.51\.36256'
        sdk_version_observed = $text -match 'Windows 10\.0\.26100\.0 SDK'
        compiler_preference_warning_observed = $text -match 'not a preferred version|newer than latest preferred version'
        build_success_marker_observed = $text -match 'BUILD SUCCESSFUL'
        log_line_count = @($text -split "`n").Count
        log_sha256 = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()
        generated_log = $logPath.Substring($root.Length + 1).Replace('\', '/')
    }
}

function Get-PackageEvidence {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Development', 'Shipping')][string]$Configuration,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )
    $runtimeName = if ($Configuration -eq 'Shipping') { 'TMXY-Win64-Shipping.exe' } else { 'TMXY.exe' }
    $runtimePath = Join-Path $ArchivePath "Windows\TMXY\Binaries\Win64\$runtimeName"
    $bootstrapPath = Join-Path $ArchivePath 'Windows\TMXY.exe'
    $files = @(Get-ChildItem -LiteralPath $ArchivePath -Recurse -File -ErrorAction SilentlyContinue)
    $containers = @($files | Where-Object { $_.Extension -in @('.pak', '.utoc', '.ucas') })
    $requiredPaths = @($runtimePath, $bootstrapPath)
    $requiredPresent = @($requiredPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -eq 2
    $containerShapePassed = @($containers | Where-Object Extension -eq '.pak').Count -ge 1 -and
        @($containers | Where-Object Extension -eq '.utoc').Count -ge 2 -and
        @($containers | Where-Object Extension -eq '.ucas').Count -ge 2
    [pscustomobject][ordered]@{
        configuration = $Configuration
        passed = $requiredPresent -and $containerShapePassed
        archive = $ArchivePath.Substring($root.Length + 1).Replace('\', '/')
        file_count = $files.Count
        total_bytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)
        runtime_executable = $runtimePath
        runtime_bytes = if (Test-Path -LiteralPath $runtimePath) { (Get-Item -LiteralPath $runtimePath).Length } else { 0 }
        runtime_sha256 = if (Test-Path -LiteralPath $runtimePath) { (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        bootstrap_present = Test-Path -LiteralPath $bootstrapPath -PathType Leaf
        pak_count = @($containers | Where-Object Extension -eq '.pak').Count
        utoc_count = @($containers | Where-Object Extension -eq '.utoc').Count
        ucas_count = @($containers | Where-Object Extension -eq '.ucas').Count
    }
}

function Invoke-DevelopmentSmoke {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $ExecutablePath
    $info.WorkingDirectory = Split-Path -Parent $ExecutablePath
    $info.Arguments = '-nullrhi -unattended -nosound -nosplash -ExecCmds="quit"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $started = [DateTimeOffset]::UtcNow
    $process = [System.Diagnostics.Process]::Start($info)
    $exited = $process.WaitForExit(60000)
    if (-not $exited) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    [pscustomobject][ordered]@{
        policy = 'clean_exit'
        passed = $exited -and $process.ExitCode -eq 0
        exited_within_seconds = 60
        exit_code = $process.ExitCode
        controlled_termination = -not $exited
        duration_milliseconds = [Math]::Round(([DateTimeOffset]::UtcNow - $started).TotalMilliseconds)
    }
}

function Invoke-ShippingSmoke {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $ExecutablePath
    $info.WorkingDirectory = Split-Path -Parent $ExecutablePath
    $info.Arguments = '-nullrhi -unattended -nosound -nosplash'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $started = [DateTimeOffset]::UtcNow
    $process = [System.Diagnostics.Process]::Start($info)
    $exitedEarly = $process.WaitForExit(15000)
    if (-not $exitedEarly) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    [pscustomobject][ordered]@{
        policy = 'stable_liveness_then_controlled_termination'
        passed = -not $exitedEarly
        liveness_seconds = 15
        exited_early = $exitedEarly
        early_exit_code = if ($exitedEarly) { $process.ExitCode } else { $null }
        controlled_termination = -not $exitedEarly
        duration_milliseconds = [Math]::Round(([DateTimeOffset]::UtcNow - $started).TotalMilliseconds)
    }
}

foreach ($requiredPath in @($projectPath, $uatPath, $compilerPath, $sdkResourceCompilerPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required UE packaging path is missing: $requiredPath"
    }
}

$developmentArchive = Join-Path $generatedRoot 'Development'
$shippingArchive = Join-Path $generatedRoot 'Shipping'
$developmentBuild = Invoke-UatPackage -Configuration Development -ArchivePath $developmentArchive
$shippingBuild = Invoke-UatPackage -Configuration Shipping -ArchivePath $shippingArchive
$developmentPackage = Get-PackageEvidence -Configuration Development -ArchivePath $developmentArchive
$shippingPackage = Get-PackageEvidence -Configuration Shipping -ArchivePath $shippingArchive
$developmentSmoke = Invoke-DevelopmentSmoke -ExecutablePath $developmentPackage.runtime_executable
$shippingSmoke = Invoke-ShippingSmoke -ExecutablePath $shippingPackage.runtime_executable
$securityTokenFiles = @(
    Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'SecurityToken' }
)
$contentAssets = @(
    Get-ChildItem -LiteralPath (Join-Path $root 'Apps\UEClient\Content') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.uasset', '.umap') }
)
$contentAssetPaths = @($contentAssets | ForEach-Object {
    $_.FullName.Substring((Join-Path $root 'Apps\UEClient\Content').Length).
        TrimStart([char[]]'\/').Replace('\', '/')
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
$contentPolicyPassed = $contentAssetPaths.Count -eq $expectedContentAssets.Count -and
    @(Compare-Object $contentAssetPaths $expectedContentAssets).Count -eq 0
$sourceBinding = Get-SourceBinding
$compilerItem = Get-Item -LiteralPath $compilerPath
$sdkResourceCompilerItem = Get-Item -LiteralPath $sdkResourceCompilerPath
$hostToolchainPassed = $compilerItem.VersionInfo.ProductVersion -match '^14\.51\.36256' -and
    $sdkResourceCompilerItem.VersionInfo.ProductVersion -match '^10\.0\.26100\.'
$passed = $developmentBuild.passed -and $shippingBuild.passed -and
    $developmentBuild.editor_target_observed -and $shippingBuild.editor_target_observed -and
    $developmentBuild.client_target_observed -and $shippingBuild.client_target_observed -and
    $developmentBuild.compiler_version_observed -and $shippingBuild.compiler_version_observed -and
    $developmentBuild.compiler_preference_warning_observed -and
    $shippingBuild.compiler_preference_warning_observed -and $hostToolchainPassed -and
    $developmentPackage.passed -and $shippingPackage.passed -and
    $developmentSmoke.passed -and $shippingSmoke.passed -and
    $securityTokenFiles.Count -eq 0 -and $contentPolicyPassed

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    qualification = 'UE_5_8_2_MSVC_14_51_TIME_BOUNDED_WAIVER'
    waiver = [pscustomobject][ordered]@{
        status = if ($passed) { 'active' } else { 'inactive' }
        effective_local = '2026-08-26T00:00:00+08:00'
        expires_local = '2026-10-25T23:59:59+08:00'
        issuer = 'Codex engineering execution owner'
        scope = 'TMXY UE 5.8.2 Windows x64 baseline only'
        superseded_by = 'Qualification with UE preferred MSVC 14.50.35717'
    }
    toolchain = [pscustomobject][ordered]@{
        unreal_engine = '5.8.2'
        unreal_changelist = 56702186
        msvc_toolset = '14.51.36231'
        reported_compiler = '14.51.36256'
        ue_preferred_compiler = '14.50.35717'
        windows_sdk = '10.0.26100.0'
        host_binaries_passed = $hostToolchainPassed
        compiler_product_version = $compilerItem.VersionInfo.ProductVersion
        compiler_sha256 = (Get-FileHash -LiteralPath $compilerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        sdk_resource_compiler_product_version = $sdkResourceCompilerItem.VersionInfo.ProductVersion
        sdk_resource_compiler_sha256 = (Get-FileHash -LiteralPath $sdkResourceCompilerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    build_cook_run = @($developmentBuild, $shippingBuild)
    packages = @($developmentPackage, $shippingPackage)
    smoke = [pscustomobject][ordered]@{
        development = $developmentSmoke
        shipping = $shippingSmoke
    }
    boundaries = [pscustomobject][ordered]@{
        source_binding = $sourceBinding
        source_content_asset_count = $contentAssets.Count
        source_content_assets = $contentAssetPaths
        source_content_policy_passed = $contentPolicyPassed
        security_token_file_count = $securityTokenFiles.Count
        generated_outputs_under_rebuild = $generatedRoot.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
        legacy_input_write_required = $false
    }
}

$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
Write-Utf8Lf -Path ([System.IO.Path]::GetFullPath($OutputPath)) -Content ($json + "`n")
$json
if (-not $passed) { throw 'UE packaging qualification failed. See the generated report.' }
