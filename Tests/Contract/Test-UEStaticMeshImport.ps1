[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-23-ue-static-mesh-import.json',
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
    'Apps/UEClient/Scripts/CreateStaticMeshGoldenFixtures.ps1',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYStaticMeshImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYStaticMeshImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYStaticMeshManifest.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYStaticMeshManifest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYGltfDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYGltfDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYStaticMeshImporterTest.cpp',
    'Contracts/data-schema/ue-static-mesh-import-report-v1.schema.json',
    'Contracts/data-schema/asset-interchange-v1.schema.json',
    'Docs/Testing/UE-GOLDEN-STATIC-MESH-IMPORT.md',
    'Tests/Fixtures/UE/StaticMesh/minimum-real/manifest.json',
    'Tests/Fixtures/UE/StaticMesh/multisection-real/manifest.json',
    'Tests/Fixtures/UE/StaticMesh/minimum-real/manifest-invalid-hash.json',
    'Apps/UEClient/Content/TMXY/Golden/StaticMeshes/SM_Golden_Minimum_Real.uasset',
    'Apps/UEClient/Content/TMXY/Golden/StaticMeshes/SM_Golden_MultiSection_Real.uasset',
    'Tests/Contract/Test-UEStaticMeshImport.ps1',
    'Data/BuildBaseline/p1-14-sm-static-mesh.json',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-20-ue-golden-host.json',
    'Data/BuildBaseline/p1-21-ue-importer-plugin.json',
    'Data/BuildBaseline/p1-22-ue-texture-import.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-23 required file is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$manifestSchema = Join-Path $root $requiredFiles[9]
$fixtureExpectations = [ordered]@{
    'minimum-real' = [pscustomobject]@{
        manifest = $requiredFiles[11]
        package = '/Game/TMXY/Golden/StaticMeshes/SM_Golden_Minimum_Real'
        vertices = 4; render_vertices = 4; triangles = 2; sections = 1; uv = 1; light_map = $false
        first_material = 'particle.ZFH_O_S_Tianpian100_Mat1'
        last_material = 'particle.ZFH_O_S_Tianpian100_Mat1'
    }
    'multisection-real' = [pscustomobject]@{
        manifest = $requiredFiles[12]
        package = '/Game/TMXY/Golden/StaticMeshes/SM_Golden_MultiSection_Real'
        vertices = 11847; render_vertices = 11851; triangles = 6511; sections = 43; uv = 2; light_map = $true
        first_material = 'scene09.GT_B_S_BangPai05_Mat0'
        last_material = 'scene09.GT_B_S_BangPai05_Mat42'
    }
}

$fixtureEvidence = [ordered]@{}
foreach ($entry in $fixtureExpectations.GetEnumerator()) {
    $manifestPath = Join-Path $root $entry.Value.manifest
    $manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $manifest = $manifestJson | ConvertFrom-Json
    if (-not (Test-Json -Json $manifestJson -SchemaFile $manifestSchema -ErrorAction SilentlyContinue)) {
        Add-Failure -Message "StaticMesh Manifest violates Interchange v1: $($entry.Key)"
    }
    $settings = $manifest.extensions.'org.tmxy.ue-import'
    $gltfArtifact = @($manifest.artifacts | Where-Object id -eq 'render-gltf')
    $binArtifact = @($manifest.artifacts | Where-Object id -eq 'buffer')
    $metadataArtifact = @($manifest.artifacts | Where-Object id -eq 'metadata')
    if ([string]$manifest.asset_kind -ne 'static_mesh' -or $gltfArtifact.Count -ne 1 -or
        $binArtifact.Count -ne 1 -or $metadataArtifact.Count -ne 1 -or
        [string]$gltfArtifact[0].format_id -ne 'khronos.gltf-json' -or
        [string]$gltfArtifact[0].authority -ne 'authoritative-interchange' -or
        [string]$binArtifact[0].format_id -ne 'khronos.gltf-bin' -or
        [string]$settings.package_name -ne $entry.Value.package -or
        [int]$settings.expected_vertex_count -ne $entry.Value.vertices -or
        [int]$settings.expected_triangle_count -ne $entry.Value.triangles -or
        [int]$settings.expected_material_slot_count -ne $entry.Value.sections -or
        [int]$settings.expected_uv_channel_count -ne $entry.Value.uv -or
        [bool]$settings.expected_use_light_map -ne $entry.Value.light_map -or
        [string]$settings.coordinate_mapping -ne 'gltf(y,z,x)-to-ue(x,y,z)-centimeters' -or
        -not [bool]$settings.preserve_winding -or -not [bool]$settings.recompute_tangents) {
        Add-Failure -Message "StaticMesh fixture semantic contract changed: $($entry.Key)"
    }
    if (@($settings.expected_render_bounds_cm.minimum).Count -ne 3 -or
        @($settings.expected_render_bounds_cm.maximum).Count -ne 3 -or
        @($settings.expected_effective_legacy_bounds_cm.minimum).Count -ne 3 -or
        @($settings.expected_effective_legacy_bounds_cm.maximum).Count -ne 3) {
        Add-Failure -Message "StaticMesh bounds contract changed: $($entry.Key)"
    }

    $bundleRoot = Split-Path -Parent $manifestPath
    foreach ($source in @($manifest.source_inputs)) {
        Test-BundleFile -BundleRoot $bundleRoot -Entry $source -Label "$($entry.Key) source"
    }
    foreach ($artifact in @($manifest.artifacts)) {
        Test-BundleFile -BundleRoot $bundleRoot -Entry $artifact -Label "$($entry.Key) artifact"
    }

    $gltfPath = Join-Path $bundleRoot ([string]$gltfArtifact[0].relative_path)
    $gltf = Get-Content -LiteralPath $gltfPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $primitives = @($gltf.meshes[0].primitives)
    $positionAccessor = $gltf.accessors[[int]$primitives[0].attributes.POSITION]
    $indexTotal = 0
    foreach ($primitive in $primitives) {
        $indexTotal += [int]$gltf.accessors[[int]$primitive.indices].count
    }
    $actualUvCount = if ($primitives[0].attributes.PSObject.Properties.Name -contains
        'TEXCOORD_1') { 2 } else { 1 }
    if ([string]$gltf.asset.version -ne '2.0' -or @($gltf.buffers).Count -ne 1 -or
        [string]$gltf.buffers[0].uri -ne [string]$binArtifact[0].relative_path -or
        [int]$gltf.buffers[0].byteLength -ne [int64]$binArtifact[0].bytes -or
        [int]$positionAccessor.count -ne $entry.Value.vertices -or
        $indexTotal / 3 -ne $entry.Value.triangles -or
        $primitives.Count -ne $entry.Value.sections -or @($gltf.materials).Count -ne $entry.Value.sections -or
        $actualUvCount -ne $entry.Value.uv -or
        [string]$gltf.materials[0].name -ne $entry.Value.first_material -or
        [string]$gltf.materials[-1].name -ne $entry.Value.last_material) {
        Add-Failure -Message "StaticMesh glTF structure changed: $($entry.Key)"
    }
    if ($entry.Key -eq 'minimum-real') {
        $bufferPath = Join-Path $bundleRoot ([string]$binArtifact[0].relative_path)
        $bytes = [System.IO.File]::ReadAllBytes($bufferPath)
        $indexView = $gltf.bufferViews[[int]$gltf.accessors[[int]$primitives[0].indices].bufferView]
        $indexOffset = [int]$indexView.byteOffset + [int]$gltf.accessors[[int]$primitives[0].indices].byteOffset
        $indices = @(0..5 | ForEach-Object { [BitConverter]::ToUInt16($bytes, $indexOffset + ($_ * 2)) })
        if (($indices -join ',') -ne '0,1,2,2,3,0') {
            Add-Failure -Message 'Minimum StaticMesh triangle winding changed.'
        }
    }
    $fixtureEvidence[$entry.Key] = [pscustomobject][ordered]@{
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        gltf_sha256 = (Get-FileHash -LiteralPath $gltfPath -Algorithm SHA256).Hash.ToLowerInvariant()
        bin_sha256 = [string]$binArtifact[0].sha256
        bin_bytes = [int64]$binArtifact[0].bytes
    }
}

$invalidJson = Get-Content -LiteralPath (Join-Path $root $requiredFiles[13]) -Raw -Encoding UTF8
$invalid = $invalidJson | ConvertFrom-Json
$invalidGltf = @($invalid.artifacts | Where-Object id -eq 'render-gltf')
if (-not (Test-Json -Json $invalidJson -SchemaFile $manifestSchema -ErrorAction SilentlyContinue) -or
    $invalidGltf.Count -ne 1 -or [string]$invalidGltf[0].sha256 -ne ('0' * 64)) {
    Add-Failure -Message 'The valid-contract StaticMesh invalid-hash fixture changed.'
}

$decoderSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[6]) -Raw -Encoding UTF8
$manifestSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[4]) -Raw -Encoding UTF8
$importerSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[2]) -Raw -Encoding UTF8
$testSource = Get-Content -LiteralPath (Join-Path $root $requiredFiles[7]) -Raw -Encoding UTF8
foreach ($marker in @('MaxVertices', 'UnsignedShortComponent', 'gltf-shared-attribute-contract-invalid',
        'GetSafeNormal', 'decoded.Bounds')) {
    if (-not $decoderSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "glTF decoder marker is missing: $marker"
    }
}
foreach ($marker in @('artifact-integrity-mismatch', 'expected_render_bounds_cm',
        'expected_effective_legacy_bounds_cm', 'authoritative-interchange')) {
    if (-not $manifestSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "StaticMesh Manifest reader marker is missing: $marker"
    }
}
foreach ($marker in @('FStaticMeshAttributes', 'bRecomputeTangents = true',
        'BuildFromMeshDescriptions', 'TMXY.ManifestSha256', 'UPackage::SavePackage')) {
    if (-not $importerSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "StaticMesh Handler marker is missing: $marker"
    }
}
foreach ($marker in @('TMXY.Importer.StaticMesh', 'Triangle winding is preserved',
        'Multi-section source vertex count', 'Static mesh reimport preserves package bytes')) {
    if (-not $testSource.Contains($marker, [StringComparison]::Ordinal)) {
        Add-Failure -Message "StaticMesh Automation marker is missing: $marker"
    }
}
if (($decoderSource + $manifestSource + $importerSource) -match
    '(?i)ClientCode|ServerCode|ToolCode|天命西游') {
    Add-Failure -Message 'StaticMesh runtime Handler contains a legacy runtime/source dependency.'
}

$contentRoot = Join-Path $root 'Apps/UEClient/Content'
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
    Add-Failure -Message 'P1-23 Content does not match the fixed Golden allowlist.'
}
$assetEvidence = @($contentAssets | Where-Object {
        $_.Extension -eq '.uasset' -and $_.FullName -match '[\\/]StaticMeshes[\\/]'
    } | Sort-Object Name |
    ForEach-Object {
        [pscustomobject][ordered]@{
            path = $_.FullName.Substring($contentRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })

$dependencyHashes = [ordered]@{}
foreach ($relativePath in $requiredFiles[17..21]) {
    $dependency = Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ([string]$dependency.result -ne 'PASS' -or
        -not [bool]$dependency.completion_criteria_satisfied) {
        Add-Failure -Message "P1-23 dependency is not complete: $relativePath"
    }
    $dependencyHashes[$relativePath] = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) `
            -Algorithm SHA256).Hash.ToLowerInvariant()
}

$automationReportRoot = Join-Path $root 'Apps/UEClient/Saved/Automation/TMXYImporter'
$generatedReportPath = Join-Path $automationReportRoot 'p1-23-static-mesh-report.json'
$ueReportPath = Join-Path $root 'Data/BuildBaseline/p0-10a-ue-validation.json'
$automationPassed = $null
$generatedReportPassed = $null
$generatedReportSha = $null
$ueReportSha = $null
if ($RequireAutomationEvidence) {
    if (-not (Test-Path -LiteralPath $generatedReportPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ueReportPath -PathType Leaf)) {
        Add-Failure -Message 'P1-23 Automation evidence is missing.'
        $automationPassed = $false
        $generatedReportPassed = $false
    }
    else {
        $ueReport = Get-Content -LiteralPath $ueReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $automationPassed = [string]$ueReport.result -eq 'PASS' -and
            [bool]$ueReport.automation.requested -and [bool]$ueReport.automation.passed -and
            [bool]$ueReport.automation.importer_static_mesh_passed -and
            [int]$ueReport.automation.test_count -eq 8
        $generatedJson = Get-Content -LiteralPath $generatedReportPath -Raw -Encoding UTF8
        $generated = $generatedJson | ConvertFrom-Json
        $reportSchema = Join-Path $root $requiredFiles[8]
        $generatedReportPassed = [bool](Test-Json -Json $generatedJson -SchemaFile $reportSchema `
                -ErrorAction SilentlyContinue) -and [bool]$generated.invalid_hash_rejected -and
            -not [bool]$generated.invalid_hash_asset_created -and [bool]$generated.reimport_passed -and
            [bool]$generated.reimport_package_bytes_unchanged -and
            @($generated.static_meshes).Count -eq 2
        foreach ($expectation in $fixtureExpectations.GetEnumerator()) {
            $observed = @($generated.static_meshes | Where-Object fixture_id -eq $expectation.Key)
            $generatedReportPassed = $generatedReportPassed -and $observed.Count -eq 1 -and
                [int]$observed[0].source_vertex_count -eq $expectation.Value.vertices -and
                [int]$observed[0].render_vertex_count -eq $expectation.Value.render_vertices -and
                [int]$observed[0].triangle_count -eq $expectation.Value.triangles -and
                [int]$observed[0].section_count -eq $expectation.Value.sections -and
                [int]$observed[0].uv_channel_count -eq $expectation.Value.uv -and
                [string]$observed[0].package_name -eq $expectation.Value.package -and
                [bool]$observed[0].coordinate_mapping_verified -and
                [bool]$observed[0].normal_mapping_verified -and [bool]$observed[0].winding_preserved
        }
        if (-not $automationPassed) { Add-Failure -Message 'UE baseline does not prove StaticMesh Automation.' }
        if (-not $generatedReportPassed) { Add-Failure -Message 'Generated StaticMesh report violates P1-23.' }
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
    task = 'P1-23'
    completion_criteria_satisfied = $passed
    source_sha256 = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")
    handler = [pscustomobject][ordered]@{
        format_id = 'khronos.gltf-json'
        gltf_version = '2.0'
        mode = 'single-fixture-only'
        verifies_all_artifact_hashes_before_write = $true
        preserves_source_topology = $true
        content_addressed_reimport_noop = $true
        production_handler_count = 3
    }
    fixtures = $fixtureEvidence
    content = [pscustomobject][ordered]@{
        asset_count = $relativeAssets.Count
        approved_assets = $relativeAssets
        imported_assets = $assetEvidence
    }
    automation_evidence = [pscustomobject][ordered]@{
        required = [bool]$RequireAutomationEvidence
        passed = $automationPassed
        test = 'TMXY.Importer.StaticMesh'
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
if (-not $passed) { throw 'P1-23 UE static mesh import contract failed.' }
