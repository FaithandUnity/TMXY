[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-24-ue-skeletal-mesh-import.json',
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
    [System.Convert]::ToHexString(
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
    'Apps/UEClient/Scripts/CreateSkeletalMeshGoldenFixtures.ps1',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYGltfImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYSkeletalMeshImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYGltfImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalMeshImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalMeshManifest.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalMeshManifest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalGltfDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalGltfDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYSkeletalMeshImporterTest.cpp',
    'Contracts/data-schema/asset-interchange-v1.schema.json',
    'Contracts/data-schema/ue-skeletal-mesh-import-report-v1.schema.json',
    'Docs/Testing/UE-GOLDEN-SKELETAL-MESH-IMPORT.md',
    'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/manifest.json',
    'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/manifest-invalid-hash.json',
    'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/source-evidence.json',
    'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/mesh.json',
    'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/mesh.gltf',
    'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/mesh.bin',
    'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/mesh.obj',
    'Apps/UEClient/Content/TMXY/Golden/SkeletalMeshes/SK_Golden_Boy01_Default.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Skeletons/SKEL_Golden_Boy01.uasset',
    'Tests/Contract/Test-UESkeletalMeshImport.ps1',
    'Data/BuildBaseline/p1-15-skem-skeletal-mesh.json',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-21-ue-importer-plugin.json',
    'Data/BuildBaseline/p1-23-ue-static-mesh-import.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-24 required file is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$manifestPath = Join-Path $root 'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/manifest.json'
$manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
$manifest = $manifestJson | ConvertFrom-Json
$manifestSchema = Join-Path $root 'Contracts/data-schema/asset-interchange-v1.schema.json'
if (-not (Test-Json -Json $manifestJson -SchemaFile $manifestSchema -ErrorAction SilentlyContinue)) {
    Add-Failure -Message 'SkeletalMesh Manifest violates Interchange v1.'
}
$settings = $manifest.extensions.'org.tmxy.ue-import'
$legacyExtension = $manifest.extensions.'org.tmxy.legacy-skeletal-mesh'
$gltfArtifact = @($manifest.artifacts | Where-Object id -eq 'render-gltf')
$binArtifact = @($manifest.artifacts | Where-Object id -eq 'buffer')
$metadataArtifact = @($manifest.artifacts | Where-Object id -eq 'metadata')
if ([string]$manifest.asset_kind -ne 'skeletal_mesh' -or
    [string]$manifest.producer.name -ne 'tmxy-skeletal-mesh' -or
    $gltfArtifact.Count -ne 1 -or $binArtifact.Count -ne 1 -or $metadataArtifact.Count -ne 1 -or
    [string]$gltfArtifact[0].format_id -ne 'khronos.gltf-json' -or
    [string]$gltfArtifact[0].authority -ne 'authoritative-interchange' -or
    @($gltfArtifact[0].required_features).Count -ne 5 -or
    [string]$binArtifact[0].format_id -ne 'khronos.gltf-bin' -or
    [string]$settings.skeletal_mesh_package_name -ne
        '/Game/TMXY/Golden/SkeletalMeshes/SK_Golden_Boy01_Default' -or
    [string]$settings.skeleton_package_name -ne
        '/Game/TMXY/Golden/Skeletons/SKEL_Golden_Boy01' -or
    [int]$settings.expected_source_vertex_count -ne 10338 -or
    [int]$settings.expected_triangle_count -ne 8757 -or
    [int]$settings.expected_material_slot_count -ne 7 -or
    [int]$settings.expected_bone_count -ne 80 -or
    [int]$settings.expected_root_bone_count -ne 1 -or
    [string]$settings.expected_root_bone_name -ne 'Bip01' -or
    [int]$settings.expected_max_active_influences -ne 4 -or
    [int]$settings.expected_unweighted_sentinel_vertex_count -ne 0 -or
    [string]$settings.coordinate_mapping -ne 'gltf(y,z,x)-to-ue(x,y,z)-centimeters' -or
    [string]$settings.bone_index_mapping -ne 'legacy-one-based-to-gltf-zero-based' -or
    -not [bool]$settings.preserve_winding -or -not [bool]$settings.recompute_tangents -or
    [string]$legacyExtension.attachment_policy -ne
        'bone-name-candidates-only-no-invented-sockets') {
    Add-Failure -Message 'SkeletalMesh fixture semantic contract changed.'
}
if (@($settings.expected_render_bounds_cm.minimum).Count -ne 3 -or
    @($settings.expected_render_bounds_cm.maximum).Count -ne 3) {
    Add-Failure -Message 'SkeletalMesh bounds contract changed.'
}

$bundleRoot = Split-Path -Parent $manifestPath
foreach ($source in @($manifest.source_inputs)) {
    Test-BundleFile -BundleRoot $bundleRoot -Entry $source -Label 'SkeletalMesh source evidence'
}
foreach ($artifact in @($manifest.artifacts)) {
    Test-BundleFile -BundleRoot $bundleRoot -Entry $artifact -Label 'SkeletalMesh artifact'
}

$sourceEvidence = Get-Content -LiteralPath (Join-Path $bundleRoot 'source-evidence.json') -Raw |
    ConvertFrom-Json
if ([string]$sourceEvidence.copy_policy -ne
    'reference-only-inputs; deterministic-default-selection-derived-fixture' -or
    @($sourceEvidence.sources).Count -ne 2 -or
    [string]$sourceEvidence.sources[0].sha256 -ne
        '0867a016dd0b2a75a35d453ffe2242ffeb5329d003de61ba9b121dcebdba10e7' -or
    [string]$sourceEvidence.sources[1].sha256 -ne
        '409fedf015ae3949222241cd8d7cc1aea22bb6ef689b2cc0190a796fe7cf93b6') {
    Add-Failure -Message 'SkeletalMesh read-only source provenance changed.'
}

$metadata = Get-Content -LiteralPath (Join-Path $bundleRoot 'mesh.json') -Raw | ConvertFrom-Json
if ([int]$metadata.vertex_count -lt 10338 -or [int]$metadata.triangle_count -lt 8757 -or
    [int]$metadata.bone_count -ne 80 -or @($metadata.root_bone_ids).Count -ne 1 -or
    [int]$metadata.root_bone_ids[0] -ne 0 -or @($metadata.bones).Count -ne 80 -or
    @($metadata.attachment_point_candidates).Count -ne 80 -or
    [int]$metadata.legacy_unweighted_sentinel_vertex_count -ne 0) {
    Add-Failure -Message 'SkeletalMesh metadata contract changed.'
}

$gltfPath = Join-Path $bundleRoot 'mesh.gltf'
$gltf = Get-Content -LiteralPath $gltfPath -Raw -Encoding UTF8 | ConvertFrom-Json
$primitives = @($gltf.meshes[0].primitives)
$attributes = $primitives[0].attributes.PSObject.Properties.Name
$indexCount = 0
foreach ($primitive in $primitives) {
    $indexCount += [int]$gltf.accessors[[int]$primitive.indices].count
}
if ([string]$gltf.asset.version -ne '2.0' -or @($gltf.skins).Count -ne 1 -or
    @($gltf.skins[0].joints).Count -ne 80 -or @($gltf.nodes).Count -ne 81 -or
    [int]$gltf.skins[0].skeleton -ne 0 -or
    -not ($attributes -contains 'POSITION') -or -not ($attributes -contains 'NORMAL') -or
    -not ($attributes -contains 'TEXCOORD_0') -or -not ($attributes -contains 'JOINTS_0') -or
    -not ($attributes -contains 'WEIGHTS_0') -or $primitives.Count -ne 7 -or
    $indexCount / 3 -ne 8757 -or @($gltf.materials).Count -ne 7 -or
    [string]$gltf.buffers[0].uri -ne 'mesh.bin' -or
    [int64]$gltf.buffers[0].byteLength -ne [int64]$binArtifact[0].bytes) {
    Add-Failure -Message 'SkeletalMesh glTF structure changed.'
}

$invalidPath = Join-Path $bundleRoot 'manifest-invalid-hash.json'
$invalidJson = Get-Content -LiteralPath $invalidPath -Raw -Encoding UTF8
$invalid = $invalidJson | ConvertFrom-Json
$invalidGltf = @($invalid.artifacts | Where-Object id -eq 'render-gltf')
if (-not (Test-Json -Json $invalidJson -SchemaFile $manifestSchema -ErrorAction SilentlyContinue) -or
    $invalidGltf.Count -ne 1 -or [string]$invalidGltf[0].sha256 -ne ('0' * 64)) {
    Add-Failure -Message 'The valid-contract SkeletalMesh invalid-hash fixture changed.'
}

$sourceGroups = [ordered]@{
    router = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYGltfImporter.cpp',
        @('assetKind == TEXT("static_mesh")', 'assetKind == TEXT("skeletal_mesh")'))
    decoder = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalGltfDecoder.cpp',
        @('JOINTS_0', 'WEIGHTS_0', 'inverseBindMatrices', 'ValidateInverseBindOrientation',
            'ValidateInfluences'))
    manifest = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalMeshManifest.cpp',
        @('artifact-integrity-mismatch', 'expected_unweighted_sentinel_vertex_count',
            'legacy-one-based-to-gltf-zero-based'))
    importer = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalMeshImporter.cpp',
        @('FStaticToSkeletalMeshConverter', 'FSkeletalMeshAttributes', 'TMXY.ManifestSha256',
            'MergeAllBonesToBoneTree', 'UPackage::SavePackage'))
    test = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYSkeletalMeshImporterTest.cpp',
        @('TMXY.Importer.SkeletalMesh', 'All source vertices have normalized valid skin weights',
            'Bone-name attachment candidates exist without invented sockets',
            'Skeleton reimport preserves package bytes'))
}
foreach ($entry in $sourceGroups.GetEnumerator()) {
    $sourcePath = Join-Path $root ([string]$entry.Value[0])
    $source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
    foreach ($marker in @($entry.Value[1])) {
        if (-not $source.Contains([string]$marker, [StringComparison]::Ordinal)) {
            Add-Failure -Message "SkeletalMesh $($entry.Key) marker is missing: $marker"
        }
    }
    if ($entry.Key -ne 'test' -and $source -match
        '(?i)ClientCode|ServerCode|ToolCode|天命西游') {
        Add-Failure -Message "SkeletalMesh runtime $($entry.Key) has a legacy dependency."
    }
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
    Add-Failure -Message 'P1-24 Content does not match the fixed Golden allowlist.'
}
$assetEvidence = @($contentAssets | Where-Object {
        $_.Extension -eq '.uasset' -and $_.FullName -match '[\\/](SkeletalMeshes|Skeletons)[\\/]'
    } | Sort-Object FullName | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        [pscustomobject][ordered]@{
            path = $_.FullName.Substring($contentRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            unreal_package_tag = if ($bytes.Length -ge 4) { '0x{0:x8}' -f [BitConverter]::ToUInt32($bytes, 0) } else { 'invalid' }
        }
    })
if ($assetEvidence.Count -ne 2 -or @($assetEvidence | Where-Object {
            $_.bytes -le 0 -or $_.unreal_package_tag -ne '0x9e2a83c1'
        }).Count -gt 0) {
    Add-Failure -Message 'P1-24 generated assets are not valid Unreal packages.'
}

$dependencyPaths = @(
    'Data/BuildBaseline/p1-15-skem-skeletal-mesh.json',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-21-ue-importer-plugin.json',
    'Data/BuildBaseline/p1-23-ue-static-mesh-import.json'
)
$dependencyHashes = [ordered]@{}
foreach ($relativePath in $dependencyPaths) {
    $dependencyPath = Join-Path $root $relativePath
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$dependency.result -ne 'PASS' -or
        -not [bool]$dependency.completion_criteria_satisfied) {
        Add-Failure -Message "P1-24 dependency is not complete: $relativePath"
    }
    $dependencyHashes[$relativePath] =
        (Get-FileHash -LiteralPath $dependencyPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

$generatedReportPath = Join-Path $root `
    'Apps/UEClient/Saved/Automation/TMXYImporter/p1-24-skeletal-mesh-report.json'
$ueReportPath = Join-Path $root 'Data/BuildBaseline/p0-10a-ue-validation.json'
$automationPassed = $null
$generatedReportPassed = $null
$generatedReportSha = $null
$ueReportSha = $null
if ($RequireAutomationEvidence) {
    if (-not (Test-Path -LiteralPath $generatedReportPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ueReportPath -PathType Leaf)) {
        Add-Failure -Message 'P1-24 Automation evidence is missing.'
        $automationPassed = $false
        $generatedReportPassed = $false
    }
    else {
        $ueReport = Get-Content -LiteralPath $ueReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $automationPassed = [string]$ueReport.result -eq 'PASS' -and
            [bool]$ueReport.automation.requested -and [bool]$ueReport.automation.passed -and
            [bool]$ueReport.automation.importer_skeletal_mesh_passed -and
            [int]$ueReport.automation.test_count -eq 8
        $generatedJson = Get-Content -LiteralPath $generatedReportPath -Raw -Encoding UTF8
        $generated = $generatedJson | ConvertFrom-Json
        $reportSchema = Join-Path $root `
            'Contracts/data-schema/ue-skeletal-mesh-import-report-v1.schema.json'
        $generatedReportPassed = [bool](Test-Json -Json $generatedJson -SchemaFile $reportSchema `
                -ErrorAction SilentlyContinue) -and [bool]$generated.weights_verified -and
            [bool]$generated.bind_pose_verified -and
            [bool]$generated.inverse_bind_orientation_preserved -and
            [bool]$generated.attachment_policy_verified -and
            [bool]$generated.invalid_hash_rejected -and
            -not [bool]$generated.invalid_hash_asset_created -and
            [bool]$generated.reimport_passed -and
            [bool]$generated.reimport_mesh_bytes_unchanged -and
            [bool]$generated.reimport_skeleton_bytes_unchanged
        if (-not $automationPassed) {
            Add-Failure -Message 'UE baseline does not prove SkeletalMesh Automation.'
        }
        if (-not $generatedReportPassed) {
            Add-Failure -Message 'Generated SkeletalMesh report violates P1-24.'
        }
        $generatedReportSha =
            (Get-FileHash -LiteralPath $generatedReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $ueReportSha =
            (Get-FileHash -LiteralPath $ueReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$hashLines = foreach ($relativePath in $requiredFiles[0..22] | Sort-Object) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($hash.ToLowerInvariant())"
}
$passed = $failures.Count -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-24'
    completion_criteria_satisfied = $passed
    source_sha256 = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")
    handler = [pscustomobject][ordered]@{
        format_id = 'khronos.gltf-json'
        gltf_version = '2.0'
        asset_kind = 'skeletal_mesh'
        verifies_all_artifact_hashes_before_write = $true
        maximum_active_influences = 4
        rejects_unweighted_vertices = $true
        positive_inverse_bind_orientation_required = $true
        attachment_policy = 'bone-name-candidates-only-no-invented-sockets'
        content_addressed_reimport_noop = $true
        production_handler_count = 3
    }
    fixture = [pscustomobject][ordered]@{
        id = 'boy01-default-real'
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        gltf_sha256 = (Get-FileHash -LiteralPath $gltfPath -Algorithm SHA256).Hash.ToLowerInvariant()
        bin_sha256 = [string]$binArtifact[0].sha256
        bin_bytes = [int64]$binArtifact[0].bytes
        source_vertex_count = 10338
        triangle_count = 8757
        material_slot_count = 7
        bone_count = 80
    }
    content = [pscustomobject][ordered]@{
        asset_count = $relativeAssets.Count
        approved_assets = $relativeAssets
        imported_assets = $assetEvidence
    }
    automation_evidence = [pscustomobject][ordered]@{
        required = [bool]$RequireAutomationEvidence
        passed = $automationPassed
        test = 'TMXY.Importer.SkeletalMesh'
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
if (-not $passed) { throw 'P1-24 UE skeletal mesh import contract failed.' }
