[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-26-ue-terrain-import.json',
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
    param([string]$BundleRoot, [object]$Entry, [string]$Label)
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

function Read-FloatPlane {
    param([Parameter(Mandatory = $true)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ne 16384) {
        Add-Failure -Message "Terrain height plane size changed: $Path"
        return @()
    }
    return @(0..4095 | ForEach-Object { [BitConverter]::ToSingle($bytes, $_ * 4) })
}

$requiredFiles = @(
    'Apps/UEClient/Scripts/CreateTerrainGoldenFixtures.ps1',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYTerrainImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainManifest.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainManifest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYTerrainImporterTest.cpp',
    'Contracts/data-schema/ue-terrain-import-report-v1.schema.json',
    'Contracts/data-schema/asset-interchange-v1.schema.json',
    'Docs/Testing/UE-GOLDEN-TERRAIN-IMPORT.md',
    'Tests/Fixtures/UE/Terrain/world-adjacency-real/manifest.json',
    'Tests/Fixtures/UE/Terrain/world-adjacency-real/manifest-invalid-hash.json',
    'Apps/UEClient/Content/TMXY/Golden/Terrain/SMT_Golden_World_001_001.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Terrain/SMT_Golden_World_001_002.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Terrain/SMT_Golden_World_002_001.uasset',
    'Tests/Contract/Test-UETerrainImport.ps1',
    'Data/BuildBaseline/p1-17-ter-terrain.json',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-21-ue-importer-plugin.json',
    'Data/BuildBaseline/p1-25-ue-animation-import.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-26 required file is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$manifestPath = Join-Path $root $requiredFiles[11]
$bundleRoot = Split-Path -Parent $manifestPath
$manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
$manifest = $manifestJson | ConvertFrom-Json
$interchangeSchema = Join-Path $root $requiredFiles[9]
if (-not (Test-Json -Json $manifestJson -SchemaFile $interchangeSchema -ErrorAction SilentlyContinue)) {
    Add-Failure -Message 'Terrain Manifest violates Asset Interchange v1.'
}
$settings = $manifest.extensions.'org.tmxy.ue-import'
$legacy = $manifest.extensions.'org.tmxy.legacy-terrain'
$tileSettings = @($settings.tile_meshes)
$adjacencySettings = @($settings.adjacency)
if ([string]$manifest.asset_kind -ne 'terrain_tile' -or $tileSettings.Count -ne 3 -or
    $adjacencySettings.Count -ne 2 -or [int]$settings.edge_vertex_count -ne 64 -or
    [int]$settings.cells_per_axis -ne 63 -or [double]$settings.source_units_per_cell -ne 4.0 -or
    [double]$settings.centimeters_per_source_unit -ne 100.0 -or
    [double]$settings.cell_spacing_cm -ne 400.0 -or [double]$settings.zone_size_cm -ne 25200.0 -or
    -not [bool]$settings.preserve_existing_edge_differences -or
    [string]$settings.coordinate_mapping -ne
    'legacy-x-forward-y-right-z-up-to-ue-x-forward-y-right-z-up' -or
    [double]$legacy.zone_size_source_units -ne 252.0 -or [int]$legacy.terrain_tile_num -ne 63 -or
    [string]$legacy.level_package_sha256 -ne
    '997627584cf4dfb55016be32b64e7d33763a17b980a05e0b580137193fb352f4') {
    Add-Failure -Message 'Terrain physical-scale or coordinate contract changed.'
}

foreach ($source in @($manifest.source_inputs)) {
    Test-BundleFile -BundleRoot $bundleRoot -Entry $source -Label 'Terrain source evidence'
}
$artifacts = @($manifest.artifacts)
if ($artifacts.Count -ne 12) { Add-Failure -Message 'Terrain fixture must declare exactly 12 artifacts.' }
foreach ($artifact in $artifacts) {
    Test-BundleFile -BundleRoot $bundleRoot -Entry $artifact -Label "Terrain artifact $($artifact.id)"
    $id = [string]$artifact.id
    $valid = if ($id.EndsWith('-metadata')) {
        [string]$artifact.format_id -eq 'tmxy.asset.metadata-json' -and
        [string]$artifact.authority -eq 'authoritative-interchange'
    }
    elseif ($id.EndsWith('-height')) {
        [string]$artifact.format_id -eq 'tmxy.terrain.height-f32le' -and
        [string]$artifact.authority -eq 'authoritative-interchange'
    }
    elseif ($id.EndsWith('-layers')) {
        [string]$artifact.format_id -eq 'tmxy.terrain.layers-rgba8' -and
        [string]$artifact.authority -eq 'authoritative-interchange'
    }
    else {
        $id.EndsWith('-edges') -and [string]$artifact.format_id -eq 'text.csv-rfc4180' -and
        [string]$artifact.authority -eq 'review'
    }
    if (-not $valid) { Add-Failure -Message "Terrain artifact semantics changed: $id" }
}

$expectedTiles = [ordered]@{
    base = [pscustomobject]@{ x = 1; y = 1; package = '/Game/TMXY/Golden/Terrain/SMT_Golden_World_001_001' }
    right = [pscustomobject]@{ x = 2; y = 1; package = '/Game/TMXY/Golden/Terrain/SMT_Golden_World_002_001' }
    bottom = [pscustomobject]@{ x = 1; y = 2; package = '/Game/TMXY/Golden/Terrain/SMT_Golden_World_001_002' }
}
$planes = [ordered]@{}
foreach ($entry in $expectedTiles.GetEnumerator()) {
    $tile = @($tileSettings | Where-Object fixture_id -eq $entry.Key)
    if ($tile.Count -ne 1 -or [int]$tile[0].tile_x -ne $entry.Value.x -or
        [int]$tile[0].tile_y -ne $entry.Value.y -or
        [string]$tile[0].package_name -ne $entry.Value.package -or
        [int]$tile[0].expected_vertex_count -ne 4096 -or
        [int]$tile[0].expected_triangle_count -ne 7938) {
        Add-Failure -Message "Terrain Tile contract changed: $($entry.Key)"
        continue
    }
    $heightId = [string]$tile[0].height_artifact_id
    $layerId = [string]$tile[0].layer_artifact_id
    $metadataId = [string]$tile[0].metadata_artifact_id
    $height = @($artifacts | Where-Object { [string]$_.id -eq $heightId })
    $layer = @($artifacts | Where-Object { [string]$_.id -eq $layerId })
    $metadataArtifact = @($artifacts | Where-Object { [string]$_.id -eq $metadataId })
    if ($height.Count -ne 1 -or $layer.Count -ne 1 -or $metadataArtifact.Count -ne 1 -or
        [int64]$height[0].bytes -ne 16384 -or [int64]$layer[0].bytes -ne 16384) {
        Add-Failure -Message "Terrain typed-plane binding changed: $($entry.Key)"
        continue
    }
    $metadata = Get-Content -LiteralPath (Join-Path $bundleRoot $metadataArtifact[0].relative_path) `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$metadata.vertex_count -ne 4096 -or [int]$metadata.edge_vertex_count -ne 64 -or
        [int]$metadata.tile_count_per_axis -ne 63 -or [string]$metadata.tile_identity.map_name -ne 'world' -or
        [int]$metadata.tile_identity.x -ne $entry.Value.x -or
        [int]$metadata.tile_identity.y -ne $entry.Value.y) {
        Add-Failure -Message "Terrain metadata identity changed: $($entry.Key)"
    }
    $planes[$entry.Key] = Read-FloatPlane -Path (Join-Path $bundleRoot $height[0].relative_path)
}

function Test-Adjacency {
    param([string]$Second, [string]$FirstEdge, [string]$SecondEdge, [int]$ExpectedDifferences,
        [double]$ExpectedMaximumCm)
    $contract = @($adjacencySettings | Where-Object {
            $_.first -eq 'base' -and $_.second -eq $Second -and $_.first_edge -eq $FirstEdge -and
            $_.second_edge -eq $SecondEdge })
    if ($contract.Count -ne 1) { Add-Failure -Message "Terrain adjacency missing: base/$Second"; return }
    $deltas = for ($sample = 0; $sample -lt 64; $sample++) {
        $firstIndex = if ($FirstEdge -eq 'right') { $sample * 64 + 63 } else { 63 * 64 + $sample }
        $secondIndex = if ($SecondEdge -eq 'left') { $sample * 64 } else { $sample }
        [Math]::Abs([double]$planes.base[$firstIndex] - [double]$planes[$Second][$secondIndex])
    }
    $differences = @($deltas | Where-Object { $_ -ne 0.0 }).Count
    $maximumCm = [double](($deltas | Measure-Object -Maximum).Maximum) * 400.0
    if ($differences -ne $ExpectedDifferences -or [Math]::Abs($maximumCm - $ExpectedMaximumCm) -gt 0.0001 -or
        [int]$contract[0].differing_sample_count -ne $differences -or
        [Math]::Abs([double]$contract[0].maximum_absolute_delta_cm - $maximumCm) -gt 0.0001) {
        Add-Failure -Message "Terrain adjacency values changed: base/$Second"
    }
}
if ($planes.Count -eq 3) {
    Test-Adjacency -Second right -FirstEdge right -SecondEdge left -ExpectedDifferences 16 `
        -ExpectedMaximumCm 12.80364990234375
    Test-Adjacency -Second bottom -FirstEdge bottom -SecondEdge top -ExpectedDifferences 10 `
        -ExpectedMaximumCm 1.9155502319335938
}

$invalidJson = Get-Content -LiteralPath (Join-Path $root $requiredFiles[12]) -Raw -Encoding UTF8
$invalid = $invalidJson | ConvertFrom-Json
$invalidHeight = @($invalid.artifacts | Where-Object id -eq 'base-height')
if (-not (Test-Json -Json $invalidJson -SchemaFile $interchangeSchema -ErrorAction SilentlyContinue) -or
    $invalidHeight.Count -ne 1 -or [string]$invalidHeight[0].sha256 -ne ('0' * 64)) {
    Add-Failure -Message 'Terrain invalid-hash fixture contract changed.'
}

$manifestSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[4]) -Raw -Encoding UTF8
$decoderSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[6]) -Raw -Encoding UTF8
$importerSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[2]) -Raw -Encoding UTF8
$testSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[7]) -Raw -Encoding UTF8
foreach ($marker in @('artifact-integrity-mismatch', 'preserve_existing_edge_differences',
        'tmxy.terrain.height-f32le', 'terrain-fixture-set-invalid')) {
    if (-not $manifestSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "Terrain Manifest reader marker is missing: $marker"
    }
}
foreach ($marker in @('BuildFromMeshDescriptions', 'SetInstanceColor', 'bRecomputeNormals = true',
        'terrain-existing-asset-mismatch', 'TMXY.Terrain.EdgePolicy')) {
    if (-not $importerSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "Terrain importer marker is missing: $marker"
    }
}
foreach ($marker in @('ReadFloat32LittleEndian', 'terrain-height-nonfinite',
        'terrain-metadata-contract-invalid')) {
    if (-not $decoderSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "Terrain decoder marker is missing: $marker"
    }
}
foreach ($marker in @('TMXY.Importer.Terrain', 'All 12,288 imported height samples',
        'Every terrain triangle faces', 'unchanged after reimport')) {
    if (-not $testSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "Terrain Automation marker is missing: $marker"
    }
}
if (($manifestSource + $decoderSource + $importerSource) -match
    '(?i)ClientCode|ServerCode|ToolCode|天命西游') {
    Add-Failure -Message 'Terrain runtime Handler contains a legacy source/runtime dependency.'
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
    Add-Failure -Message 'P1-26 Content does not match the fixed Golden allowlist.'
}
$assetEvidence = @($contentAssets | Where-Object { $_.FullName -match '[\\/]Terrain[\\/]' } |
    Sort-Object Name | ForEach-Object {
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
    if ([string]$dependency.result -ne 'PASS' -or -not [bool]$dependency.completion_criteria_satisfied) {
        Add-Failure -Message "P1-26 dependency is not complete: $relativePath"
    }
    $dependencyHashes[$relativePath] = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) `
            -Algorithm SHA256).Hash.ToLowerInvariant()
}

$generatedReportPath = Join-Path $root 'Apps\UEClient\Saved\Automation\TMXYImporter\p1-26-terrain-report.json'
$ueReportPath = Join-Path $root 'Data\BuildBaseline\p0-10a-ue-validation.json'
$automationPassed = $null
$generatedReportPassed = $null
$generatedReportSha = $null
$ueReportSha = $null
if ($RequireAutomationEvidence) {
    if (-not (Test-Path -LiteralPath $generatedReportPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ueReportPath -PathType Leaf)) {
        Add-Failure -Message 'P1-26 Automation evidence is missing.'
        $automationPassed = $false
        $generatedReportPassed = $false
    }
    else {
        $ueReport = Get-Content -LiteralPath $ueReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $automationPassed = [string]$ueReport.result -eq 'PASS' -and
            [bool]$ueReport.automation.requested -and [bool]$ueReport.automation.passed -and
            [bool]$ueReport.automation.importer_terrain_passed -and
            [int]$ueReport.automation.test_count -eq 8
        $generatedJson = Get-Content -LiteralPath $generatedReportPath -Raw -Encoding UTF8
        $generated = $generatedJson | ConvertFrom-Json
        $generatedReportPassed = [bool](Test-Json -Json $generatedJson `
                -SchemaFile (Join-Path $root $requiredFiles[8]) -ErrorAction SilentlyContinue) -and
            [bool]$generated.direction_verified -and [bool]$generated.physical_scale_verified -and
            [bool]$generated.adjacency_verified -and [bool]$generated.reimport_package_bytes_unchanged -and
            @($generated.terrain_tiles).Count -eq 3 -and @($generated.adjacencies).Count -eq 2
        if (-not $automationPassed) { Add-Failure -Message 'UE baseline does not prove Terrain Automation.' }
        if (-not $generatedReportPassed) { Add-Failure -Message 'Generated Terrain report violates P1-26.' }
        $generatedReportSha = (Get-FileHash -LiteralPath $generatedReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $ueReportSha = (Get-FileHash -LiteralPath $ueReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$hashLines = foreach ($relativePath in $requiredFiles[0..16] | Sort-Object) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($hash.ToLowerInvariant())"
}
$passed = $failures.Count -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-26'
    completion_criteria_satisfied = $passed
    source_sha256 = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")
    handler = [pscustomobject][ordered]@{
        format_id = 'tmxy.terrain.height-f32le'; mode = 'single-fixture-only'
        verifies_all_declared_hashes_before_write = $true; production_handler_count = 3
        representation = 'deterministic UStaticMesh proof assets; P3-11 runtime route remains open'
        content_addressed_reimport_noop = $true
    }
    physical_scale = [pscustomobject][ordered]@{
        zone_size_source_units = 252.0; terrain_tile_num = 63
        source_units_per_cell = 4.0; centimeters_per_cell = 400.0; centimeters_per_tile = 25200.0
    }
    adjacency = [pscustomobject][ordered]@{
        right_differing_samples = 16; right_maximum_delta_cm = 12.80364990234375
        bottom_differing_samples = 10; bottom_maximum_delta_cm = 1.9155502319335938
        source_differences_preserved = $true
    }
    fixture_manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    content = [pscustomobject][ordered]@{
        asset_count = $relativeAssets.Count; approved_assets = $relativeAssets
        imported_assets = $assetEvidence
    }
    automation_evidence = [pscustomobject][ordered]@{
        required = [bool]$RequireAutomationEvidence; passed = $automationPassed
        test = 'TMXY.Importer.Terrain'; generated_report_path = if ($RequireAutomationEvidence) { $generatedReportPath } else { $null }
        generated_report_sha256 = $generatedReportSha
        generated_report_schema_passed = $generatedReportPassed; ue_report_sha256 = $ueReportSha
    }
    dependency_report_sha256 = $dependencyHashes
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'P1-26 UE terrain import contract failed.' }
