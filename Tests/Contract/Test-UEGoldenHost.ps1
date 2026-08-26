[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-20-ue-golden-host.json',
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

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)
    return ($Value | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json
}

function Test-AgainstSchema {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )
    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    return [bool](Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)
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
    'Apps/UEClient/Source/TMXYEditor.Target.cs',
    'Apps/UEClient/Source/TMXYGoldenTests/TMXYGoldenTests.Build.cs',
    'Apps/UEClient/Source/TMXYGoldenTests/Private/TMXYGoldenTestsModule.cpp',
    'Apps/UEClient/Source/TMXYGoldenTests/Private/Tests/TMXYGoldenHostTest.cpp',
    'Apps/UEClient/Scripts/CreateGoldenHostMap.py',
    'Apps/UEClient/Content/TMXY/Golden/Maps/TMXYGoldenTestMap.umap',
    'Contracts/data-schema/ue-golden-import-report-v1.schema.json',
    'Contracts/examples/ue-golden-import-report-v1.example.json',
    'Docs/Testing/UE-GOLDEN-HOST.md',
    'Tests/Contract/Test-UEGoldenHost.ps1',
    'Data/BuildBaseline/p1-19-asset-interchange.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-20 required file is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$schemaPath = Join-Path $root $requiredFiles[8]
$examplePath = Join-Path $root $requiredFiles[9]
$mapPath = Join-Path $root $requiredFiles[7]
$schemaText = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
$exampleText = Get-Content -LiteralPath $examplePath -Raw -Encoding UTF8
$schema = $schemaText | ConvertFrom-Json
$example = $exampleText | ConvertFrom-Json

if (-not (Test-Json -Json $schemaText -ErrorAction SilentlyContinue)) {
    Add-Failure -Message 'P1-20 report Schema is not valid JSON.'
}
$positiveExamplePassed = Test-AgainstSchema -Value $example -SchemaPath $schemaPath
if (-not $positiveExamplePassed) {
    Add-Failure -Message 'P1-20 report example does not validate against the Schema.'
}
$schemaIdentityPassed = [string]$schema.'$schema' -eq
    'https://json-schema.org/draft/2020-12/schema' -and
    [string]$schema.properties.schema.const -eq 'tmxy.ue.golden-import-report' -and
    [int]$schema.properties.schema_version.const -eq 1 -and
    [string]$schema.properties.report_version.const -eq '1.0.0' -and
    -not [bool]$schema.additionalProperties
if (-not $schemaIdentityPassed) {
    Add-Failure -Message 'P1-20 report Schema identity or closed root changed.'
}

$negativeCases = [ordered]@{}
$absoluteManifest = Copy-JsonObject -Value $example
$absoluteManifest.interchange_manifest = 'E:\unsafe\manifest.json'
$negativeCases.absolute_manifest = -not (Test-AgainstSchema -Value $absoluteManifest -SchemaPath $schemaPath)
$outsideRoot = Copy-JsonObject -Value $example
$outsideRoot.after_import.packages[0].package_name = '/Game/Imported/UnsafeAsset'
$negativeCases.package_outside_golden_root = -not (Test-AgainstSchema -Value $outsideRoot -SchemaPath $schemaPath)
$wrongPhase = Copy-JsonObject -Value $example
$wrongPhase.before_import.phase = 'after-import'
$negativeCases.reversed_phase = -not (Test-AgainstSchema -Value $wrongPhase -SchemaPath $schemaPath)
$unknownRoot = Copy-JsonObject -Value $example
$unknownRoot | Add-Member -NotePropertyName guessed_semantics -NotePropertyValue $true
$negativeCases.unknown_root_property = -not (Test-AgainstSchema -Value $unknownRoot -SchemaPath $schemaPath)
foreach ($case in $negativeCases.GetEnumerator()) {
    if (-not $case.Value) { Add-Failure -Message "P1-20 negative case was accepted: $($case.Key)" }
}

$project = Get-Content -LiteralPath (Join-Path $root $requiredFiles[0]) -Raw | ConvertFrom-Json
$goldenModules = @($project.Modules | Where-Object { [string]$_.Name -eq 'TMXYGoldenTests' })
$modulePolicyPassed = $goldenModules.Count -eq 1 -and
    [string]$goldenModules[0].Type -eq 'Editor' -and
    [string]$goldenModules[0].LoadingPhase -eq 'PostEngineInit'
if (-not $modulePolicyPassed) { Add-Failure -Message 'TMXYGoldenTests must be Editor/PostEngineInit.' }

$runtimeTarget = Get-Content -LiteralPath (Join-Path $root $requiredFiles[1]) -Raw -Encoding UTF8
$editorTarget = Get-Content -LiteralPath (Join-Path $root $requiredFiles[2]) -Raw -Encoding UTF8
if ($runtimeTarget.Contains('TMXYGoldenTests', [System.StringComparison]::Ordinal)) {
    Add-Failure -Message 'TMXYGoldenTests must not enter the runtime client target.'
}
if (-not $editorTarget.Contains('TMXYGoldenTests', [System.StringComparison]::Ordinal)) {
    Add-Failure -Message 'TMXYEditor target does not include TMXYGoldenTests.'
}

$testSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[5]) -Raw -Encoding UTF8
$moduleSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[4]) -Raw -Encoding UTF8
$generatorSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[6]) -Raw -Encoding UTF8
foreach ($marker in @('/Game/TMXY/Golden',
        '/Game/TMXY/Golden/Maps/TMXYGoldenTestMap', 'TMXY.Golden.Host',
        'DoesPackageExist', 'FindWorldInPackage', 'GetWorldPartition')) {
    if (-not $testSource.Contains($marker, [System.StringComparison]::Ordinal)) {
        Add-Failure -Message "Golden automation marker is missing: $marker"
    }
}
if (-not $moduleSource.Contains('event=golden_test_module_started root=/Game/TMXY/Golden',
        [System.StringComparison]::Ordinal)) {
    Add-Failure -Message 'Golden module startup evidence marker is missing.'
}
$generatorPolicyPassed = $generatorSource.Contains(
        'GOLDEN_MAP = "/Game/TMXY/Golden/Maps/TMXYGoldenTestMap"',
        [System.StringComparison]::Ordinal) -and
    $generatorSource.Contains('new_level(GOLDEN_MAP, False)',
        [System.StringComparison]::Ordinal) -and
    $generatorSource -notmatch '(?i)ClientCode|ServerCode|ToolCode|Data[\\/]Exports|Data[\\/]RawPackages'
if (-not $generatorPolicyPassed) {
    Add-Failure -Message 'Golden Map generator scope changed or references forbidden bulk inputs.'
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
    Add-Failure -Message 'Golden Content must match the fixed P1-25 asset allowlist.'
}

$mapBytes = [System.IO.File]::ReadAllBytes($mapPath)
$mapTag = if ($mapBytes.Length -ge 4) { [BitConverter]::ToUInt32($mapBytes, 0) } else { 0 }
$mapTagHex = '0x{0:x8}' -f $mapTag
$mapSha = (Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedMapSha = [string]$example.before_import.packages[0].content_sha256
$snapshotsStable = ($example.before_import | ConvertTo-Json -Depth 10 -Compress) -replace
    '"phase":"before-import"', '"phase":"snapshot"'
$afterStable = ($example.after_import | ConvertTo-Json -Depth 10 -Compress) -replace
    '"phase":"after-import"', '"phase":"snapshot"'
$noImportPassed = [string]$example.import_mode -eq 'validate-only' -and
    [string]$example.outcome.status -eq 'not-run' -and
    [int]$example.outcome.imported_asset_count -eq 0 -and
    [int]$example.before_import.imported_asset_count -eq 0 -and
    [int]$example.after_import.imported_asset_count -eq 0 -and
    $snapshotsStable -eq $afterStable
if ($mapTagHex -ne '0x9e2a83c1' -or $mapSha -ne $expectedMapSha) {
    Add-Failure -Message 'Golden Map package tag or locked SHA-256 changed.'
}
if (-not $noImportPassed) {
    Add-Failure -Message 'P1-20 must preserve identical before/after snapshots with zero imports.'
}

$interchangeReportPath = Join-Path $root $requiredFiles[12]
$interchangeReport = Get-Content -LiteralPath $interchangeReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$interchangeReport.result -ne 'PASS' -or
    -not [bool]$interchangeReport.completion_criteria_satisfied) {
    Add-Failure -Message 'P1-19 interchange dependency is not complete.'
}

$ueReportPath = Join-Path $root 'Data\BuildBaseline\p0-10a-ue-validation.json'
$automationEvidencePassed = $null
$automationEvidenceSha = $null
if ($RequireAutomationEvidence) {
    if (-not (Test-Path -LiteralPath $ueReportPath -PathType Leaf)) {
        Add-Failure -Message 'Required UE Automation evidence is missing.'
        $automationEvidencePassed = $false
    }
    else {
        $ueReport = Get-Content -LiteralPath $ueReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $automationEvidencePassed = [string]$ueReport.result -eq 'PASS' -and
            [bool]$ueReport.automation.requested -and
            [bool]$ueReport.automation.passed -and
            [bool]$ueReport.automation.golden_host_passed -and
            [bool]$ueReport.automation.golden_module_loaded
        $automationEvidenceSha = (Get-FileHash -LiteralPath $ueReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not $automationEvidencePassed) {
            Add-Failure -Message 'UE evidence does not prove TMXY.Golden.Host success.'
        }
    }
}

$hashFiles = @($requiredFiles[0..11])
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
    task = 'P1-20'
    completion_criteria_satisfied = $passed
    source_sha256 = $sourceSha
    module = [pscustomobject][ordered]@{
        name = 'TMXYGoldenTests'
        type = 'Editor'
        loading_phase = 'PostEngineInit'
        runtime_target_excluded = -not $runtimeTarget.Contains(
            'TMXYGoldenTests', [System.StringComparison]::Ordinal)
        policy_passed = $modulePolicyPassed
    }
    host = [pscustomobject][ordered]@{
        golden_root = '/Game/TMXY/Golden'
        map_package = '/Game/TMXY/Golden/Maps/TMXYGoldenTestMap'
        map_relative_path = 'TMXY/Golden/Maps/TMXYGoldenTestMap.umap'
        map_bytes = $mapBytes.Length
        map_sha256 = $mapSha
        unreal_package_tag = $mapTagHex
        content_asset_count = $relativeAssets.Count
        content_policy_passed = $contentPolicyPassed
        automation_entry = 'TMXY.Golden.Host'
    }
    import_report = [pscustomobject][ordered]@{
        schema = 'tmxy.ue.golden-import-report'
        report_version = '1.0.0'
        positive_example_passed = $positiveExamplePassed
        negative_cases = $negativeCases
        before_after_unchanged = $snapshotsStable -eq $afterStable
        imported_asset_count = [int]$example.outcome.imported_asset_count
        status = [string]$example.outcome.status
    }
    automation_evidence = [pscustomobject][ordered]@{
        required = [bool]$RequireAutomationEvidence
        passed = $automationEvidencePassed
        report_path = if ($RequireAutomationEvidence) { $ueReportPath } else { $null }
        report_sha256 = $automationEvidenceSha
    }
    dependency_report_sha256 = (Get-FileHash -LiteralPath $interchangeReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath), $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'P1-20 UE golden host contract failed.' }
