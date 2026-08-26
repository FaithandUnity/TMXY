[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-22-ue-texture-import.json',
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

function Test-BundleFile {
    param(
        [Parameter(Mandatory = $true)][string]$BundleRoot,
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $relative = [string]$Entry.relative_path
    if ($relative -notmatch '^(?!/)(?![A-Za-z]:)(?!.*(?:^|/)\.\.(?:/|$))[^\\\x00]+$') {
        Add-Failure -Message "$Label has an unsafe path: $relative"
        return
    }
    $path = Join-Path $BundleRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure -Message "$Label is missing: $relative"
        return
    }
    $file = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne [int64]$Entry.bytes -or $hash -ne [string]$Entry.sha256) {
        Add-Failure -Message "$Label byte contract changed: $relative"
    }
}

$requiredFiles = @(
    'Apps/UEClient/Scripts/CreateTextureGoldenFixtures.ps1',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYTextureImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTextureImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYDdsDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYDdsDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYTextureImporterTest.cpp',
    'Contracts/data-schema/ue-texture-import-report-v1.schema.json',
    'Contracts/data-schema/asset-interchange-v1.schema.json',
    'Docs/Testing/UE-GOLDEN-TEXTURE-IMPORT.md',
    'Tests/Fixtures/UE/Texture/opaque-dxt1/manifest.json',
    'Tests/Fixtures/UE/Texture/transparent-dxt5/manifest.json',
    'Tests/Fixtures/UE/Texture/multi-mip-dxt1/manifest.json',
    'Tests/Fixtures/UE/Texture/opaque-dxt1/manifest-invalid-hash.json',
    'Apps/UEClient/Content/TMXY/Golden/Textures/T_Golden_Opaque_DXT1.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Textures/T_Golden_Transparent_DXT5.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Textures/T_Golden_MultiMip_DXT1.uasset',
    'Tests/Contract/Test-UETextureImport.ps1',
    'Data/BuildBaseline/p1-13-qtx-texture.json',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-20-ue-golden-host.json',
    'Data/BuildBaseline/p1-21-ue-importer-plugin.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-22 required file is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$manifestSchema = Join-Path $root $requiredFiles[7]
$fixtureExpectations = [ordered]@{
    'opaque-dxt1' = [pscustomobject]@{
        manifest = $requiredFiles[9]; width = 8; height = 8; mips = 1; fourcc = 'DXT1'
        package = '/Game/TMXY/Golden/Textures/T_Golden_Opaque_DXT1'; alpha = 'opaque'
    }
    'transparent-dxt5' = [pscustomobject]@{
        manifest = $requiredFiles[10]; width = 16; height = 16; mips = 1; fourcc = 'DXT5'
        package = '/Game/TMXY/Golden/Textures/T_Golden_Transparent_DXT5'; alpha = 'transparent'
    }
    'multi-mip-dxt1' = [pscustomobject]@{
        manifest = $requiredFiles[11]; width = 8; height = 8; mips = 4; fourcc = 'DXT1'
        package = '/Game/TMXY/Golden/Textures/T_Golden_MultiMip_DXT1'; alpha = 'opaque'
    }
}
$fixtureEvidence = [ordered]@{}
foreach ($entry in $fixtureExpectations.GetEnumerator()) {
    $manifestPath = Join-Path $root $entry.Value.manifest
    $manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $manifest = $manifestJson | ConvertFrom-Json
    if (-not (Test-Json -Json $manifestJson -SchemaFile $manifestSchema -ErrorAction SilentlyContinue)) {
        Add-Failure -Message "Fixture Manifest violates Interchange v1: $($entry.Key)"
    }
    $settings = $manifest.extensions.'org.tmxy.ue-import'
    $dds = @($manifest.artifacts | Where-Object id -eq 'texture-payload')
    if ([string]$manifest.asset_kind -ne 'texture' -or $dds.Count -ne 1 -or
        [string]$dds[0].format_id -ne 'microsoft.dds' -or
        [string]$dds[0].authority -ne 'authoritative-interchange' -or
        [string]$settings.package_name -ne $entry.Value.package -or
        [int]$settings.expected_width -ne $entry.Value.width -or
        [int]$settings.expected_height -ne $entry.Value.height -or
        [int]$settings.expected_mips -ne $entry.Value.mips -or
        [string]$settings.expected_alpha_coverage -ne $entry.Value.alpha -or
        -not [bool]$settings.srgb) {
        Add-Failure -Message "Fixture semantic contract changed: $($entry.Key)"
    }
    $bundleRoot = Split-Path -Parent $manifestPath
    foreach ($source in @($manifest.source_inputs)) {
        Test-BundleFile -BundleRoot $bundleRoot -Entry $source -Label "$($entry.Key) source"
    }
    foreach ($artifact in @($manifest.artifacts)) {
        Test-BundleFile -BundleRoot $bundleRoot -Entry $artifact -Label "$($entry.Key) artifact"
    }
    $ddsPath = Join-Path $bundleRoot ([string]$dds[0].relative_path)
    $bytes = [System.IO.File]::ReadAllBytes($ddsPath)
    $fourcc = [System.Text.Encoding]::ASCII.GetString($bytes, 84, 4)
    if ([BitConverter]::ToUInt32($bytes, 0) -ne 0x20534444 -or
        [BitConverter]::ToUInt32($bytes, 16) -ne $entry.Value.width -or
        [BitConverter]::ToUInt32($bytes, 12) -ne $entry.Value.height -or
        [BitConverter]::ToUInt32($bytes, 28) -ne $entry.Value.mips -or
        $fourcc -ne $entry.Value.fourcc) {
        Add-Failure -Message "DDS header contract changed: $($entry.Key)"
    }
    $fixtureEvidence[$entry.Key] = [pscustomobject][ordered]@{
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        dds_sha256 = (Get-FileHash -LiteralPath $ddsPath -Algorithm SHA256).Hash.ToLowerInvariant()
        dds_bytes = $bytes.Length
    }
}

$invalidJson = Get-Content -LiteralPath (Join-Path $root $requiredFiles[12]) -Raw -Encoding UTF8
$invalid = $invalidJson | ConvertFrom-Json
if (-not (Test-Json -Json $invalidJson -SchemaFile $manifestSchema -ErrorAction SilentlyContinue) -or
    [string]$invalid.artifacts[0].sha256 -ne ('0' * 64)) {
    Add-Failure -Message 'The valid-contract invalid-hash fixture changed.'
}

$decoderSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[4]) -Raw -Encoding UTF8
$importerSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[2]) -Raw -Encoding UTF8
$testSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[5]) -Raw -Encoding UTF8
foreach ($marker in @('Dxt1', 'Dxt5', 'dds-payload-size-mismatch', 'DecodeMip')) {
    if (-not $decoderSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "DDS decoder marker is missing: $marker"
    }
}
foreach ($marker in @('artifact-integrity-mismatch', 'TSF_BGRA8', 'TMGS_LeaveExistingMips',
        'CompressionNoAlpha', 'SourceMatches', 'UPackage::SavePackage')) {
    if (-not $importerSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "Texture Handler marker is missing: $marker"
    }
}
foreach ($marker in @('TMXY.Importer.Texture', 'Artifact hash mismatch is rejected',
        'Complete source mip chain', 'Texture reimport succeeds',
        'Texture reimport preserves package bytes')) {
    if (-not $testSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "Texture Automation marker is missing: $marker"
    }
}
if (($decoderSource + $importerSource) -match '(?i)ClientCode|ServerCode|ToolCode|天命西游') {
    Add-Failure -Message 'Texture Handler or decoder contains a legacy runtime/source dependency.'
}

$contentRoot = Join-Path $root 'Apps\UEClient\Content'
$contentAssets = @(Get-ChildItem -LiteralPath $contentRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.uasset', '.umap') })
$relativeAssets = @($contentAssets | ForEach-Object {
    $_.FullName.Substring($contentRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
} | Sort-Object)
$expectedAssets = @(
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
if ($relativeAssets.Count -ne $expectedAssets.Count -or
    @(Compare-Object $relativeAssets $expectedAssets).Count -ne 0) {
    Add-Failure -Message 'P1-22 Content does not match the fixed Golden allowlist.'
}
$assetEvidence = @($contentAssets | Where-Object {
        $_.Extension -eq '.uasset' -and $_.FullName -match '[\\/]Textures[\\/]'
    } | Sort-Object Name |
    ForEach-Object {
        [pscustomobject][ordered]@{
            path = $_.FullName.Substring($contentRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })

$dependencyHashes = [ordered]@{}
foreach ($relativePath in $requiredFiles[17..20]) {
    $dependency = Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ([string]$dependency.result -ne 'PASS' -or
        -not [bool]$dependency.completion_criteria_satisfied) {
        Add-Failure -Message "P1-22 dependency is not complete: $relativePath"
    }
    $dependencyHashes[$relativePath] = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) `
            -Algorithm SHA256).Hash.ToLowerInvariant()
}

$generatedReportPath = Join-Path $root 'Apps\UEClient\Saved\Automation\TMXYImporter\p1-22-texture-report.json'
$ueReportPath = Join-Path $root 'Data\BuildBaseline\p0-10a-ue-validation.json'
$automationPassed = $null
$generatedReportPassed = $null
$generatedReportSha = $null
$ueReportSha = $null
if ($RequireAutomationEvidence) {
    if (-not (Test-Path -LiteralPath $generatedReportPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ueReportPath -PathType Leaf)) {
        Add-Failure -Message 'P1-22 Automation evidence is missing.'
        $automationPassed = $false
        $generatedReportPassed = $false
    }
    else {
        $ueReport = Get-Content -LiteralPath $ueReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $automationPassed = [string]$ueReport.result -eq 'PASS' -and
            [bool]$ueReport.automation.requested -and [bool]$ueReport.automation.passed -and
            [bool]$ueReport.automation.importer_texture_passed -and
            [int]$ueReport.automation.test_count -eq 8
        $generatedJson = Get-Content -LiteralPath $generatedReportPath -Raw -Encoding UTF8
        $generated = $generatedJson | ConvertFrom-Json
        $reportSchema = Join-Path $root $requiredFiles[6]
        $generatedReportPassed = [bool](Test-Json -Json $generatedJson -SchemaFile $reportSchema `
                -ErrorAction SilentlyContinue) -and [bool]$generated.invalid_hash_rejected -and
            -not [bool]$generated.invalid_hash_asset_created -and [bool]$generated.reimport_passed -and
            [bool]$generated.reimport_package_bytes_unchanged -and
            @($generated.textures).Count -eq 3
        foreach ($expectation in $fixtureExpectations.GetEnumerator()) {
            $observed = @($generated.textures | Where-Object fixture_id -eq $expectation.Key)
            $generatedReportPassed = $generatedReportPassed -and $observed.Count -eq 1 -and
                [int]$observed[0].width -eq $expectation.Value.width -and
                [int]$observed[0].height -eq $expectation.Value.height -and
                [int]$observed[0].source_mip_count -eq $expectation.Value.mips -and
                [string]$observed[0].package_name -eq $expectation.Value.package -and
                [string]$observed[0].source_format -eq 'TSF_BGRA8' -and [bool]$observed[0].srgb
        }
        if (-not $automationPassed) { Add-Failure -Message 'UE baseline does not prove texture Automation.' }
        if (-not $generatedReportPassed) { Add-Failure -Message 'Generated texture report violates P1-22.' }
        $generatedReportSha = (Get-FileHash -LiteralPath $generatedReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $ueReportSha = (Get-FileHash -LiteralPath $ueReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$hashFiles = @($requiredFiles[0..16])
$hashLines = foreach ($relativePath in $hashFiles | Sort-Object) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($hash.ToLowerInvariant())"
}
$passed = $failures.Count -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-22'
    completion_criteria_satisfied = $passed
    source_sha256 = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")
    handler = [pscustomobject][ordered]@{
        format_id = 'microsoft.dds'
        supported_dds_formats = @('dxt1', 'dxt5')
        decoded_source_format = 'TSF_BGRA8'
        mode = 'single-fixture-only'
        verifies_all_artifact_hashes_before_write = $true
        content_addressed_reimport_noop = $true
        production_handler_count = 3
    }
    fixtures = $fixtureEvidence
    content = [pscustomobject][ordered]@{
        asset_count = $relativeAssets.Count
        approved_assets = $relativeAssets
        texture_assets = $assetEvidence
    }
    automation_evidence = [pscustomobject][ordered]@{
        required = [bool]$RequireAutomationEvidence
        passed = $automationPassed
        test = 'TMXY.Importer.Texture'
        generated_report_path = if ($RequireAutomationEvidence) { $generatedReportPath } else { $null }
        generated_report_sha256 = $generatedReportSha
        generated_report_schema_passed = $generatedReportPassed
        ue_report_sha256 = $ueReportSha
    }
    dependency_report_sha256 = $dependencyHashes
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'P1-22 UE texture import contract failed.' }
