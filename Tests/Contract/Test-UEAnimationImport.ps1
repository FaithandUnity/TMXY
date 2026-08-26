[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-25-ue-animation-import.json',
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
        Add-Failure -Message "$Label path is unsafe: $relative"
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
    'Apps/UEClient/Scripts/CreateAnimationGoldenFixtures.ps1',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYAnimationImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimationImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimationManifest.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimationManifest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimGltfDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimGltfDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYAnimationImporterTest.cpp',
    'Tools/TMXY.Animation/include/tmxy/animation/animation_gltf.hpp',
    'Tools/TMXY.Animation/src/animation_gltf.cpp',
    'Tools/TMXY.Animation/apps/anim_gltf_export_main.cpp',
    'Contracts/data-schema/asset-interchange-v1.schema.json',
    'Contracts/data-schema/ue-animation-import-report-v1.schema.json',
    'Docs/Testing/UE-GOLDEN-ANIMATION-IMPORT.md',
    'Tests/Fixtures/UE/Animation/boy01-core-real/manifest.json',
    'Tests/Fixtures/UE/Animation/boy01-core-real/manifest-invalid-hash.json',
    'Tests/Fixtures/UE/Animation/boy01-core-real/source-evidence.json',
    'Tests/Fixtures/UE/Animation/boy01-core-real/animation.json',
    'Tests/Fixtures/UE/Animation/boy01-core-real/animation.gltf',
    'Tests/Fixtures/UE/Animation/boy01-core-real/animation.bin',
    'Apps/UEClient/Content/TMXY/Golden/Animations/A_Golden_Boy01_RoamIdle.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Animations/A_Golden_Boy01_RunForward.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Animations/A_Golden_Boy01_SelectIdle.uasset',
    'Data/BuildBaseline/p1-16-anim-animation.json',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-21-ue-importer-plugin.json',
    'Data/BuildBaseline/p1-24-ue-skeletal-mesh-import.json',
    'Tests/Contract/Test-UEAnimationImport.ps1'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-25 required file is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$manifestPath = Join-Path $root 'Tests/Fixtures/UE/Animation/boy01-core-real/manifest.json'
$bundleRoot = Split-Path -Parent $manifestPath
$manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
$manifest = $manifestJson | ConvertFrom-Json
$manifestSchema = Join-Path $root 'Contracts/data-schema/asset-interchange-v1.schema.json'
if (-not (Test-Json -Json $manifestJson -SchemaFile $manifestSchema -ErrorAction SilentlyContinue)) {
    Add-Failure -Message 'Animation manifest violates Interchange v1.'
}
$settings = $manifest.extensions.'org.tmxy.ue-import'
$legacy = $manifest.extensions.'org.tmxy.legacy-animation'
$gltfArtifact = @($manifest.artifacts | Where-Object id -eq 'animation-gltf')
$binArtifact = @($manifest.artifacts | Where-Object id -eq 'buffer')
$metadataArtifact = @($manifest.artifacts | Where-Object id -eq 'metadata')
$expectedNames = @('O_RoamIdle', 'O_Run_Forward', 'SelectIdle')
$expectedFrames = @(50, 24, 60)
$clips = @($settings.clips)
if ([string]$manifest.asset_kind -ne 'animation_set' -or
    [string]$manifest.producer.name -ne 'tmxy-animation' -or
    $gltfArtifact.Count -ne 1 -or $binArtifact.Count -ne 1 -or
    $metadataArtifact.Count -ne 1 -or
    [string]$gltfArtifact[0].format_id -ne 'khronos.gltf-json' -or
    [string]$gltfArtifact[0].authority -ne 'authoritative-interchange' -or
    @($gltfArtifact[0].required_features).Count -ne 4 -or
    [string]$binArtifact[0].format_id -ne 'khronos.gltf-bin' -or
    [string]$settings.skeleton_package_name -ne
        '/Game/TMXY/Golden/Skeletons/SKEL_Golden_Boy01' -or
    [string]$settings.skeletal_mesh_package_name -ne
        '/Game/TMXY/Golden/SkeletalMeshes/SK_Golden_Boy01_Default' -or
    [int]$settings.expected_bone_count -ne 80 -or
    [int]$settings.sample_rate_numerator -ne 30 -or
    [int]$settings.sample_rate_denominator -ne 1 -or
    [string]$settings.coordinate_mapping -ne
        'gltf(y,z,x)-to-ue(x,y,z)-centimeters' -or
    [string]$settings.quaternion_policy -ne
        'normalized-adjacent-hemisphere-continuity' -or
    [string]$settings.root_motion_policy -ne
        'preserved-root-track-not-extracted' -or
    [string]$legacy.legacy_loop_policy -ne
        'preserve-metadata-no-forced-loop-flag' -or $clips.Count -ne 3) {
    Add-Failure -Message 'Animation fixture semantic contract changed.'
}
for ($index = 0; $index -lt $clips.Count; $index++) {
    if ([string]$clips[$index].source_name -ne $expectedNames[$index] -or
        [int]$clips[$index].expected_frame_count -ne $expectedFrames[$index] -or
        [int]$clips[$index].expected_track_count -ne 80 -or
        [bool]$clips[$index].legacy_self_loop) {
        Add-Failure -Message "Animation selected clip contract changed at index $index."
    }
}
foreach ($source in @($manifest.source_inputs)) {
    Test-BundleFile -BundleRoot $bundleRoot -Entry $source -Label 'Animation source evidence'
}
foreach ($artifact in @($manifest.artifacts)) {
    Test-BundleFile -BundleRoot $bundleRoot -Entry $artifact -Label 'Animation artifact'
}

$gltf = Get-Content -LiteralPath (Join-Path $bundleRoot 'animation.gltf') -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ([string]$gltf.asset.version -ne '2.0' -or @($gltf.nodes).Count -ne 80 -or
    @($gltf.animations).Count -ne 3 -or [string]$gltf.buffers[0].uri -ne 'animation.bin' -or
    [int64]$gltf.buffers[0].byteLength -ne [int64]$binArtifact[0].bytes) {
    Add-Failure -Message 'Animation glTF structure changed.'
}
for ($index = 0; $index -lt 3; $index++) {
    $animation = $gltf.animations[$index]
    if ([string]$animation.name -ne $expectedNames[$index] -or
        @($animation.samplers).Count -ne 160 -or @($animation.channels).Count -ne 160) {
        Add-Failure -Message "Animation glTF clip structure changed at index $index."
    }
}

$invalidJson = Get-Content -LiteralPath (Join-Path $bundleRoot 'manifest-invalid-hash.json') `
    -Raw -Encoding UTF8
$invalid = $invalidJson | ConvertFrom-Json
$invalidGltf = @($invalid.artifacts | Where-Object id -eq 'animation-gltf')
if (-not (Test-Json -Json $invalidJson -SchemaFile $manifestSchema -ErrorAction SilentlyContinue) -or
    $invalidGltf.Count -ne 1 -or [string]$invalidGltf[0].sha256 -ne ('0' * 64)) {
    Add-Failure -Message 'The valid-contract Animation invalid-hash fixture changed.'
}

$sourceGroups = [ordered]@{
    router = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYGltfImporter.cpp',
        @('assetKind == TEXT("animation_set")', 'AnimationRoot'))
    decoder = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimGltfDecoder.cpp',
        @('translation', 'rotation', 'LINEAR', 'animation-gltf-contract-invalid'))
    manifest = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimationManifest.cpp',
        @('artifact-integrity-mismatch', 'preserved-root-track-not-extracted'))
    importer = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimationImporter.cpp',
        @('SetBoneTrackKeys', 'TMXY.LegacySelfLoop', 'UPackage::SavePackage'))
    test = @('Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYAnimationImporterTest.cpp',
        @('TMXY.Importer.Animation', 'all_keys_match_interchange',
            'Animation reimport preserves every package byte'))
}
foreach ($entry in $sourceGroups.GetEnumerator()) {
    $source = Get-Content -LiteralPath (Join-Path $root ([string]$entry.Value[0])) -Raw -Encoding UTF8
    foreach ($marker in @($entry.Value[1])) {
        if (-not $source.Contains([string]$marker, [StringComparison]::Ordinal)) {
            Add-Failure -Message "Animation $($entry.Key) marker is missing: $marker"
        }
    }
    if ($entry.Key -ne 'test' -and $source -match '(?i)ClientCode|ServerCode|ToolCode|天命西游') {
        Add-Failure -Message "Animation runtime $($entry.Key) has a legacy dependency."
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
    Add-Failure -Message 'P1-25 Content does not match the fixed Golden allowlist.'
}
$animationAssets = @($contentAssets | Where-Object {
        $_.FullName -match '[\\/]Animations[\\/]' -and $_.Extension -eq '.uasset'
    } | Sort-Object FullName | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        [pscustomobject][ordered]@{
            path = $_.FullName.Substring($contentRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            unreal_package_tag = if ($bytes.Length -ge 4) { '0x{0:x8}' -f [BitConverter]::ToUInt32($bytes, 0) } else { 'invalid' }
        }
    })
if ($animationAssets.Count -ne 3 -or @($animationAssets | Where-Object {
            $_.bytes -le 0 -or $_.unreal_package_tag -ne '0x9e2a83c1'
        }).Count -gt 0) {
    Add-Failure -Message 'P1-25 generated animations are not valid Unreal packages.'
}

$dependencyPaths = @(
    'Data/BuildBaseline/p1-16-anim-animation.json',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-21-ue-importer-plugin.json',
    'Data/BuildBaseline/p1-24-ue-skeletal-mesh-import.json'
)
$dependencyHashes = [ordered]@{}
foreach ($relativePath in $dependencyPaths) {
    $path = Join-Path $root $relativePath
    $dependency = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$dependency.result -ne 'PASS' -or
        -not [bool]$dependency.completion_criteria_satisfied) {
        Add-Failure -Message "P1-25 dependency is not complete: $relativePath"
    }
    $dependencyHashes[$relativePath] =
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$generatedReportPath = Join-Path $root `
    'Apps/UEClient/Saved/Automation/TMXYImporter/p1-25-animation-report.json'
$ueReportPath = Join-Path $root 'Data/BuildBaseline/p0-10a-ue-validation.json'
$automationPassed = $null
$generatedReportPassed = $null
$generatedReportSha = $null
$ueReportSha = $null
if ($RequireAutomationEvidence) {
    if (-not (Test-Path -LiteralPath $generatedReportPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ueReportPath -PathType Leaf)) {
        Add-Failure -Message 'P1-25 Automation evidence is missing.'
    }
    else {
        $ueReport = Get-Content -LiteralPath $ueReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $automationPassed = [string]$ueReport.result -eq 'PASS' -and
            [bool]$ueReport.automation.requested -and [bool]$ueReport.automation.passed -and
            [bool]$ueReport.automation.importer_animation_passed -and
            [int]$ueReport.automation.test_count -eq 8
        $generatedJson = Get-Content -LiteralPath $generatedReportPath -Raw -Encoding UTF8
        $generated = $generatedJson | ConvertFrom-Json
        $reportSchema = Join-Path $root `
            'Contracts/data-schema/ue-animation-import-report-v1.schema.json'
        $generatedReportPassed = [bool](Test-Json -Json $generatedJson -SchemaFile $reportSchema `
                -ErrorAction SilentlyContinue) -and
            [bool]$generated.all_clip_contracts_passed -and
            [bool]$generated.invalid_hash_rejected -and
            -not [bool]$generated.invalid_hash_asset_created -and
            [bool]$generated.reimport_passed -and [bool]$generated.reimport_bytes_unchanged
        if (-not $automationPassed) { Add-Failure -Message 'UE baseline does not prove Animation Automation.' }
        if (-not $generatedReportPassed) { Add-Failure -Message 'Generated Animation report violates P1-25.' }
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
    task = 'P1-25'
    completion_criteria_satisfied = $passed
    source_sha256 = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")
    handler = [pscustomobject][ordered]@{
        format_id = 'khronos.gltf-json'
        gltf_version = '2.0'
        asset_kind = 'animation_set'
        verifies_all_artifact_hashes_before_write = $true
        all_keys_verified = $true
        root_motion_policy = 'preserved-root-track-not-extracted'
        legacy_loop_policy = 'preserve-metadata-no-forced-loop-flag'
        content_addressed_reimport_noop = $true
        production_handler_count = 3
    }
    fixture = [pscustomobject][ordered]@{
        id = 'boy01-core-real'
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        gltf_sha256 = [string]$gltfArtifact[0].sha256
        bin_sha256 = [string]$binArtifact[0].sha256
        bin_bytes = [int64]$binArtifact[0].bytes
        selected_clip_count = 3
        bone_count = 80
        total_frame_count = 134
        sample_rate_hz = 30
    }
    content = [pscustomobject][ordered]@{
        asset_count = $relativeAssets.Count
        approved_assets = $relativeAssets
        imported_assets = $animationAssets
    }
    automation_evidence = [pscustomobject][ordered]@{
        required = [bool]$RequireAutomationEvidence
        passed = $automationPassed
        test = 'TMXY.Importer.Animation'
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
if (-not $passed) { throw ($failures -join [Environment]::NewLine) }
