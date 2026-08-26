[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-21-ue-importer-plugin.json',
    [switch]$RequireAutomationEvidence
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

$requiredFiles = @(
    'Apps/UEClient/TMXY.uproject',
    'Apps/UEClient/Source/TMXY.Target.cs',
    'Apps/UEClient/Plugins/TMXYImporter/TMXYImporter.uplugin',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/TMXYImporter.Build.cs',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYImportTypes.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/ITMXYAssetImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYImporterService.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYImporterModule.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYImporterService.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYImporterTest.cpp',
    'Contracts/data-schema/asset-interchange-v1.schema.json',
    'Contracts/data-schema/ue-golden-import-report-v1.schema.json',
    'Contracts/examples/asset-interchange-v1.example.json',
    'Docs/Testing/UE-IMPORTER-PLUGIN.md',
    'Tests/Contract/Test-UEImporterPlugin.ps1',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-20-ue-golden-host.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-21 required file is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$project = Get-Content -LiteralPath (Join-Path $root $requiredFiles[0]) -Raw | ConvertFrom-Json
$plugin = Get-Content -LiteralPath (Join-Path $root $requiredFiles[2]) -Raw | ConvertFrom-Json
$projectPlugin = @($project.Plugins | Where-Object { [string]$_.Name -eq 'TMXYImporter' })
$pluginModules = @($plugin.Modules | Where-Object { [string]$_.Name -eq 'TMXYImporter' })
$platforms = @($plugin.SupportedTargetPlatforms)
$descriptorPassed = $projectPlugin.Count -eq 1 -and [bool]$projectPlugin[0].Enabled -and
    $pluginModules.Count -eq 1 -and [string]$pluginModules[0].Type -eq 'Editor' -and
    [string]$pluginModules[0].LoadingPhase -eq 'PostEngineInit' -and
    -not [bool]$plugin.CanContainContent -and $platforms.Count -eq 1 -and
    [string]$platforms[0] -eq 'Win64'
if (-not $descriptorPassed) {
    Add-Failure -Message 'TMXYImporter must be enabled, content-free and Win64 Editor/PostEngineInit only.'
}
$runtimeTarget = Get-Content -LiteralPath (Join-Path $root $requiredFiles[1]) -Raw -Encoding UTF8
if ($runtimeTarget.Contains('TMXYImporter', [System.StringComparison]::Ordinal)) {
    Add-Failure -Message 'TMXYImporter must not enter the runtime client target.'
}

$buildRules = Get-Content -LiteralPath (Join-Path $root $requiredFiles[3]) -Raw -Encoding UTF8
foreach ($marker in @('"Json"',
        'PublicSystemLibraries.Add("bcrypt.lib")', 'UnrealTargetPlatform.Win64')) {
    if (-not $buildRules.Contains($marker, [System.StringComparison]::Ordinal)) {
        Add-Failure -Message "Importer build boundary marker is missing: $marker"
    }
}
$interfaceSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[5]) -Raw -Encoding UTF8
$serviceHeader = Get-Content -LiteralPath (Join-Path $root $requiredFiles[6]) -Raw -Encoding UTF8
$serviceSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[8]) -Raw -Encoding UTF8
$testSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[9]) -Raw -Encoding UTF8
foreach ($marker in @('ImportArtifact', 'EvaluateReimport', 'Reimport')) {
    if (-not $interfaceSource.Contains($marker, [System.StringComparison]::Ordinal)) {
        Add-Failure -Message "Format handler interface marker is missing: $marker"
    }
}
foreach ($marker in @('RegisterImporter', 'ValidateBatch', 'WriteGoldenReport')) {
    if (-not $serviceHeader.Contains($marker, [System.StringComparison]::Ordinal)) {
        Add-Failure -Message "Importer service marker is missing: $marker"
    }
}
foreach ($marker in @('tmxy.asset.interchange', 'unsupported-mode', 'unsafe-manifest-path',
        'source-entry-invalid', 'artifact-entry-invalid', 'BCRYPT_SHA256_ALGORITHM',
        '/Game/TMXY/Golden', 'ForceUTF8WithoutBOM')) {
    if (-not $serviceSource.Contains($marker, [System.StringComparison]::Ordinal)) {
        Add-Failure -Message "Importer implementation marker is missing: $marker"
    }
}
$sourceBoundaryPassed = $serviceSource -notmatch
    '(?i)ClientCode|ServerCode|ToolCode|Data[\\/]Exports|Data[\\/]RawPackages' -and
    $serviceSource -notmatch 'FPlatformMisc::GetSHA256Signature'
if (-not $sourceBoundaryPassed) {
    Add-Failure -Message 'Importer references forbidden legacy/bulk paths or the unavailable generic SHA-256 API.'
}
foreach ($marker in @('TMXY.Importer.ManifestBatch', 'Batch validated count',
        'Batch creates no assets', 'Duplicate format importer is rejected',
        'Reimport outside golden root is rejected')) {
    if (-not $testSource.Contains($marker, [System.StringComparison]::Ordinal)) {
        Add-Failure -Message "Importer Automation marker is missing: $marker"
    }
}

$contentRoot = Join-Path $root 'Apps\UEClient\Content'
$contentAssets = @(
    Get-ChildItem -LiteralPath $contentRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.uasset', '.umap') }
)
$relativeAssets = @($contentAssets | ForEach-Object {
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
$contentPolicyPassed = $relativeAssets.Count -eq $expectedContentAssets.Count -and
    @(Compare-Object $relativeAssets $expectedContentAssets).Count -eq 0
if (-not $contentPolicyPassed) {
    Add-Failure -Message 'Importer Content exceeds the fixed Golden allowlist.'
}

$dependencyHashes = [ordered]@{}
foreach ($relativePath in $requiredFiles[15..16]) {
    $path = Join-Path $root $relativePath
    $report = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$report.result -ne 'PASS' -or -not [bool]$report.completion_criteria_satisfied) {
        Add-Failure -Message "P1-21 dependency is not complete: $relativePath"
    }
    $dependencyHashes[$relativePath] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$generatedReportPath = Join-Path $root 'Apps\UEClient\Saved\Automation\TMXYImporter\p1-21-report.json'
$ueReportPath = Join-Path $root 'Data\BuildBaseline\p0-10a-ue-validation.json'
$automationPassed = $null
$generatedReportPassed = $null
$generatedReportSha = $null
$ueReportSha = $null
if ($RequireAutomationEvidence) {
    if (-not (Test-Path -LiteralPath $ueReportPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $generatedReportPath -PathType Leaf)) {
        Add-Failure -Message 'P1-21 Automation or generated report evidence is missing.'
        $automationPassed = $false
        $generatedReportPassed = $false
    }
    else {
        $ueReport = Get-Content -LiteralPath $ueReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $automationPassed = [string]$ueReport.result -eq 'PASS' -and
            [bool]$ueReport.automation.requested -and [bool]$ueReport.automation.passed -and
            [bool]$ueReport.automation.importer_manifest_batch_passed -and
            [bool]$ueReport.automation.importer_module_loaded
        $generatedJson = Get-Content -LiteralPath $generatedReportPath -Raw -Encoding UTF8
        $generated = $generatedJson | ConvertFrom-Json
        $generatedSchemaPath = Join-Path $root $requiredFiles[11]
        $generatedReportPassed = [bool](Test-Json -Json $generatedJson `
                -SchemaFile $generatedSchemaPath -ErrorAction SilentlyContinue) -and
            [string]$generated.schema -eq 'tmxy.ue.golden-import-report' -and
            [string]$generated.import_mode -eq 'validate-only' -and
            [string]$generated.outcome.status -eq 'passed' -and
            [int]$generated.outcome.imported_asset_count -eq 0
        $ueReportSha = (Get-FileHash -LiteralPath $ueReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $generatedReportSha = (Get-FileHash -LiteralPath $generatedReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not $automationPassed) { Add-Failure -Message 'UE evidence does not prove Importer Automation success.' }
        if (-not $generatedReportPassed) { Add-Failure -Message 'Generated Importer report violates the canonical Schema.' }
    }
}

$hashFiles = @($requiredFiles[0..14])
$hashLines = foreach ($relativePath in $hashFiles | Sort-Object) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($hash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")
$passed = $failures.Count -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-21'
    completion_criteria_satisfied = $passed
    source_sha256 = $sourceSha
    plugin = [pscustomobject][ordered]@{
        name = 'TMXYImporter'
        version = [string]$plugin.VersionName
        module_type = [string]$pluginModules[0].Type
        loading_phase = [string]$pluginModules[0].LoadingPhase
        target_platforms = $platforms
        can_contain_content = [bool]$plugin.CanContainContent
        runtime_target_excluded = -not $runtimeTarget.Contains(
            'TMXYImporter', [System.StringComparison]::Ordinal)
        descriptor_passed = $descriptorPassed
    }
    capabilities = [pscustomobject][ordered]@{
        manifest_contract = 'tmxy.asset.interchange 1.0.0'
        batch_mode = 'ordered validate-only with per-request result'
        report_contract = 'tmxy.ue.golden-import-report 1.0.0'
        format_handler_registry = $true
        duplicate_handler_rejected = $true
        reimport_interface = $true
        sha256_provider = 'Windows CNG bcrypt'
        production_format_handler_count = 3
        imported_asset_count = 0
    }
    boundaries = [pscustomobject][ordered]@{
        safe_relative_paths = $true
        golden_root = '/Game/TMXY/Golden'
        content_asset_count = $relativeAssets.Count
        content_assets = $relativeAssets
        content_policy_passed = $contentPolicyPassed
        legacy_runtime_dependency = $false
    }
    automation_evidence = [pscustomobject][ordered]@{
        required = [bool]$RequireAutomationEvidence
        passed = $automationPassed
        test = 'TMXY.Importer.ManifestBatch'
        ue_report_sha256 = $ueReportSha
        generated_report_path = if ($RequireAutomationEvidence) { $generatedReportPath } else { $null }
        generated_report_sha256 = $generatedReportSha
        generated_report_schema_passed = $generatedReportPassed
    }
    dependency_report_sha256 = $dependencyHashes
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath), $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'P1-21 UE Importer plugin contract failed.' }
