[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$reportPath = Join-Path $root 'Data\BuildBaseline\p0-08-ue-packaging-waiver.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$waiverPath = Join-Path $root 'Docs\Build\MSVC-14.51-WAIVER.md'
$engineVersionPath = 'C:\Program Files\Epic Games\UE_5.8\Engine\Build\Build.version'
$compilerPath = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\cl.exe'
$sdkPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\rc.exe'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-CurrentSourceBinding {
    $projectPath = Join-Path $root 'Apps\UEClient\TMXY.uproject'
    $files = @(
        Get-Item -LiteralPath $projectPath
        Get-ChildItem -LiteralPath (Join-Path $root 'Apps\UEClient\Config') -Recurse -File
        Get-ChildItem -LiteralPath (Join-Path $root 'Apps\UEClient\Source') -Recurse -File |
            Where-Object { $_.Extension -in @('.cs', '.cpp', '.h') }
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
    $entries = foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative`t$hash"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($entries -join "`n") + "`n")
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $hasher.ComputeHash($bytes) } finally { $hasher.Dispose() }
    [pscustomobject]@{
        file_count = $files.Count
        manifest_sha256 = ([Convert]::ToHexString($digest)).ToLowerInvariant()
    }
}

foreach ($path in @($reportPath, $lockPath, $waiverPath, $engineVersionPath, $compilerPath, $sdkPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure -Message "Required waiver evidence is missing: $path"
    }
}

if ($failures.Count -eq 0) {
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $engine = Get-Content -LiteralPath $engineVersionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sourceBinding = Get-CurrentSourceBinding
    $expires = [DateTimeOffset]::Parse([string]$report.waiver.expires_local)
    $effective = [DateTimeOffset]::Parse([string]$report.waiver.effective_local)

    if ([string]$report.result -ne 'PASS' -or [string]$report.waiver.status -ne 'active') {
        Add-Failure -Message 'The packaging qualification report is not an active PASS.'
    }
    if ($expires -le [DateTimeOffset]::Now -or ($expires - $effective).TotalDays -gt 61) {
        Add-Failure -Message 'The MSVC waiver is expired or exceeds its bounded duration.'
    }
    if ([string]$report.waiver.issuer -ne 'Codex engineering execution owner') {
        Add-Failure -Message 'The waiver issuer is missing or has changed.'
    }
    if ([int]$engine.MajorVersion -ne 5 -or [int]$engine.MinorVersion -ne 8 -or
        [int]$engine.PatchVersion -ne 2 -or [int64]$engine.Changelist -ne 56702186) {
        Add-Failure -Message 'The installed Unreal Engine no longer matches the qualified tuple.'
    }
    if ((Get-FileHash -LiteralPath $compilerPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        [string]$report.toolchain.compiler_sha256) {
        Add-Failure -Message 'The qualified compiler binary hash has changed.'
    }
    if ((Get-FileHash -LiteralPath $sdkPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        [string]$report.toolchain.sdk_resource_compiler_sha256) {
        Add-Failure -Message 'The qualified Windows SDK binary hash has changed.'
    }
    if ($sourceBinding.file_count -ne [int]$report.boundaries.source_binding.file_count -or
        $sourceBinding.manifest_sha256 -ne [string]$report.boundaries.source_binding.manifest_sha256) {
        Add-Failure -Message 'The UE project input fingerprint changed after packaging qualification.'
    }
    $builds = @($report.build_cook_run)
    $packages = @($report.packages)
    if ($builds.Count -ne 2 -or @($builds | Where-Object { -not $_.passed }).Count -gt 0 -or
        @($builds.configuration | Sort-Object) -join ',' -ne 'Development,Shipping') {
        Add-Failure -Message 'Development and Shipping BuildCookRun evidence is incomplete.'
    }
    if ($packages.Count -ne 2 -or @($packages | Where-Object { -not $_.passed }).Count -gt 0) {
        Add-Failure -Message 'Development and Shipping package evidence is incomplete.'
    }
    if (-not [bool]$report.smoke.development.passed -or -not [bool]$report.smoke.shipping.passed) {
        Add-Failure -Message 'Packaged executable smoke evidence is incomplete.'
    }
    if ([int]$report.boundaries.security_token_file_count -ne 0 -or
        [bool]$report.boundaries.legacy_input_write_required) {
        Add-Failure -Message 'The packaging qualification crossed a security or read-only boundary.'
    }
    $qualifiedContent = @($report.boundaries.source_content_assets | Sort-Object)
    $expectedContent = @(
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
    if (-not [bool]$report.boundaries.source_content_policy_passed -or
        [int]$report.boundaries.source_content_asset_count -ne $expectedContent.Count -or
        $qualifiedContent.Count -ne $expectedContent.Count -or
        @(Compare-Object $qualifiedContent $expectedContent).Count -ne 0) {
        Add-Failure -Message 'The packaging qualification content allowlist is not the fixed Golden set.'
    }
    $reportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$lock.client_toolchain.msvc_qualification.status -ne 'waiver_active_time_bounded' -or
        [string]$lock.client_toolchain.msvc_qualification.waiver.report_sha256 -ne $reportHash -or
        [string]$lock.client_toolchain.msvc_qualification.waiver.expires_local -ne [string]$report.waiver.expires_local) {
        Add-Failure -Message 'The toolchain lock does not bind the active waiver report and expiry.'
    }
}

$result = [pscustomobject][ordered]@{
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    waiver_status = if ($failures.Count -eq 0) { 'active_time_bounded' } else { 'invalid' }
    expires_local = if ($failures.Count -eq 0) { $expires.ToString('o') } else { $null }
    source_file_count = if ($failures.Count -eq 0) { $sourceBinding.file_count } else { 0 }
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($result | ConvertTo-Json -Depth 5).Replace("`r`n", "`n").Replace("`r", "`n")
$json
if ($failures.Count -gt 0) { throw 'UE packaging waiver contract failed.' }
