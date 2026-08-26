[CmdletBinding()]
param([string]$WorkspaceRoot = 'E:\QQXYCodeDev')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$rebuild = Join-Path $workspace 'Rebuild'
$output = Join-Path $rebuild 'Tests\Fixtures\UE\Animation\boy01-core-real'
$lock = Get-Content -LiteralPath (Join-Path $rebuild 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$p116 = Get-Content -LiteralPath (Join-Path $rebuild 'Data\BuildBaseline\p1-16-anim-animation.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$p124 = Get-Content -LiteralPath (Join-Path $rebuild 'Data\BuildBaseline\p1-24-ue-skeletal-mesh-import.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json

$packageRelative = '天命西游\Packages\SkelMesh\skchar'
$animRelative = '天命西游\Resource\SkelMesh\skchar\Boy01.anim'
$packageSha256 = '0867a016dd0b2a75a35d453ffe2242ffeb5329d003de61ba9b121dcebdba10e7'
$animSha256 = '912c7e13632082fdc457b148ebb8bd7ca4757a619da2bb6ad17b57acbc3afe3e'
$skeletonManifestRelative = 'Tests/Fixtures/UE/SkeletalMesh/boy01-default-real/manifest.json'
$selectedClips = @(
    [pscustomobject][ordered]@{
        source_name = 'O_RoamIdle'
        package_name = '/Game/TMXY/Golden/Animations/A_Golden_Boy01_RoamIdle'
    },
    [pscustomobject][ordered]@{
        source_name = 'O_Run_Forward'
        package_name = '/Game/TMXY/Golden/Animations/A_Golden_Boy01_RunForward'
    },
    [pscustomobject][ordered]@{
        source_name = 'SelectIdle'
        package_name = '/Game/TMXY/Golden/Animations/A_Golden_Boy01_SelectIdle'
    })

function Write-JsonLf {
    param([Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value)
    $json = ($Value | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Get-FileEvidence {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        bytes = [int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function New-Artifact {
    param([string]$Id, [string]$Role, [string]$RelativePath, [string]$FormatId,
        [string]$FormatVersion, [string]$MediaType, [string]$Authority,
        [string]$ByteOrder, [string]$Coordinate, [string]$Unit,
        [string[]]$DependsOn = @(), [string[]]$Features = @())
    $evidence = Get-FileEvidence -Path (Join-Path $output $RelativePath)
    return [pscustomobject][ordered]@{
        id = $Id
        semantic_role = $Role
        relative_path = $RelativePath
        format_id = $FormatId
        format_version = $FormatVersion
        media_type = $MediaType
        authority = $Authority
        byte_order = $ByteOrder
        coordinate_contract = $Coordinate
        unit_contract = $Unit
        bytes = $evidence.bytes
        sha256 = $evidence.sha256
        depends_on = @($DependsOn)
        required_features = @($Features)
        extensions = [pscustomobject]@{}
    }
}

if ([string]$p116.result -ne 'PASS' -or -not [bool]$p116.completion_criteria_satisfied -or
    [string]$p124.result -ne 'PASS' -or -not [bool]$p124.completion_criteria_satisfied) {
    throw 'P1-16 and P1-24 must pass before generating Animation fixtures.'
}
foreach ($source in @(
        [pscustomobject]@{ path = $packageRelative; sha256 = $packageSha256 },
        [pscustomobject]@{ path = $animRelative; sha256 = $animSha256 })) {
    $path = Join-Path $workspace $source.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $source.sha256) {
        throw "Animation golden evidence changed or is missing: $($source.path)"
    }
}
$skeletonManifestPath = Join-Path $rebuild $skeletonManifestRelative
if (-not (Test-Path -LiteralPath $skeletonManifestPath -PathType Leaf)) {
    throw 'P1-24 skeleton fixture manifest is missing.'
}
New-Item -ItemType Directory -Path $output -Force | Out-Null

$builder = [string]$lock.backend_toolchain.container_image_reference
$expectedId = [string]$lock.backend_toolchain.container_image_digest
$image = @(docker image inspect $builder 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or [string]$image[0].Id -ne $expectedId -or
    [string]$image[0].Config.User -ne 'tmxy') {
    throw 'The qualified non-root Clang 21 builder is required.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools
cp /workspace/.clang-format /tmp/tmxy-rebuild/
cp /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /tmp/tmxy-rebuild/Tools/
cp /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /tmp/tmxy-rebuild/Tools/
for module in TMXY.FormatCore TMXY.Package TMXY.Transform TMXY.SkeletalMesh TMXY.Animation; do
  cp -a "/workspace/Tools/$module" /tmp/tmxy-rebuild/Tools/
done
cd /tmp/tmxy-rebuild/Tools
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TEXTURE=OFF \
  -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_TERRAIN=OFF >/dev/null
cmake --build --preset ci-linux-clang --target tmxy_anim_gltf_export >/dev/null
EXPORTER=out/build/ci-linux-clang/TMXY.Animation/tmxy_anim_gltf_export
"$EXPORTER" '/evidence/天命西游/Packages/SkelMesh/skchar' 'skchar.Boy01' \
  '/evidence/天命西游/Resource/SkelMesh/skchar/Boy01.anim' '/output/animation' \
  'O_RoamIdle' 'O_Run_Forward' 'SelectIdle' >/tmp/animation.json
cmp /tmp/animation.json /output/animation.json
test -s /output/animation.gltf
test -s /output/animation.bin
'@
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=2g',
    '--mount', "type=bind,source=$rebuild,target=/workspace,readonly",
    '--mount', "type=bind,source=$workspace,target=/evidence,readonly",
    '--mount', "type=bind,source=$output,target=/output",
    $builder, 'bash', '-c', $containerScript)
& docker @arguments
if ($LASTEXITCODE -ne 0) { throw "Animation golden generation failed: $LASTEXITCODE" }

$metadata = Get-Content -LiteralPath (Join-Path $output 'animation.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$gltf = Get-Content -LiteralPath (Join-Path $output 'animation.gltf') -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ([int]$metadata.selected_clip_count -ne 3 -or @($gltf.animations).Count -ne 3 -or
    @($gltf.nodes).Count -ne 80) {
    throw 'Generated Animation golden fixture does not match the selected contract.'
}
$packageEvidence = Get-FileEvidence -Path (Join-Path $workspace $packageRelative)
$animEvidence = Get-FileEvidence -Path (Join-Path $workspace $animRelative)
$skeletonManifest = Get-FileEvidence -Path $skeletonManifestPath
$sourceEvidence = [pscustomobject][ordered]@{
    schema_version = 1
    fixture_id = 'boy01-core-real'
    derivation = 'locked TMXY.Animation glTF 2.0 export from exact read-only Package/ANIM pair'
    copy_policy = 'reference-only-inputs; deterministic-selected-clips-derived-fixture'
    producer_source_sha256 = [string]$p116.source_sha256
    sources = @(
        [pscustomobject][ordered]@{ role = 'package-metadata'; path = $packageRelative.Replace('\', '/'); bytes = $packageEvidence.bytes; sha256 = $packageEvidence.sha256 },
        [pscustomobject][ordered]@{ role = 'legacy-anim-payload'; path = $animRelative.Replace('\', '/'); bytes = $animEvidence.bytes; sha256 = $animEvidence.sha256 })
    skeleton_dependency = [pscustomobject][ordered]@{
        path = $skeletonManifestRelative
        bytes = $skeletonManifest.bytes
        sha256 = $skeletonManifest.sha256
    }
}
$sourceEvidencePath = Join-Path $output 'source-evidence.json'
Write-JsonLf -Path $sourceEvidencePath -Value $sourceEvidence
$sourceFile = Get-FileEvidence -Path $sourceEvidencePath

$artifacts = @(
    (New-Artifact -Id 'metadata' -Role 'legacy-metadata' -RelativePath 'animation.json' `
        -FormatId 'tmxy.asset.metadata-json' -FormatVersion '1.0.0' -MediaType 'application/json' `
        -Authority 'authoritative-interchange' -ByteOrder 'not-applicable' `
        -Coordinate 'legacy-runtime-x-forward-y-right-z-up-meters' -Unit 'seconds'),
    (New-Artifact -Id 'buffer' -Role 'gltf-buffer' -RelativePath 'animation.bin' `
        -FormatId 'khronos.gltf-bin' -FormatVersion '2.0.0' -MediaType 'application/octet-stream' `
        -Authority 'authoritative-interchange' -ByteOrder 'little-endian' `
        -Coordinate 'gltf-2.0-standard' -Unit 'seconds'),
    (New-Artifact -Id 'animation-gltf' -Role 'animation' -RelativePath 'animation.gltf' `
        -FormatId 'khronos.gltf-json' -FormatVersion '2.0.0' -MediaType 'model/gltf+json' `
        -Authority 'authoritative-interchange' -ByteOrder 'not-applicable' `
        -Coordinate 'gltf-2.0-standard' -Unit 'seconds' -DependsOn @('buffer', 'metadata') `
        -Features @('skeletal-animation', 'linear-sampling', 'root-track-preserved', 'quaternion-hemisphere-continuity')))

$clipPackages = @()
for ($index = 0; $index -lt $selectedClips.Count; ++$index) {
    $expected = $selectedClips[$index]
    $observed = @($metadata.clips)[$index]
    if ([string]$observed.name -ne [string]$expected.source_name) {
        throw "Selected Animation order changed at index $index."
    }
    $clipPackages += [pscustomobject][ordered]@{
        source_name = [string]$observed.name
        package_name = [string]$expected.package_name
        source_index = [int]$observed.source_index
        expected_frame_count = [int]$observed.frame_count
        expected_track_count = [int]$observed.track_count
        expected_sampled_duration_seconds = [double]$observed.sampled_duration_seconds
        expected_legacy_loop_period_seconds = [double]$observed.legacy_loop_period_seconds
        legacy_self_loop = [bool]$observed.self_loop
        expected_root_classified_moving = [bool]$observed.root_classified_moving
        expected_root_translation_distance_meters = [double]$observed.root_translation_distance_meters
        expected_maximum_endpoint_translation_delta_meters = [double]$observed.maximum_endpoint_translation_delta_meters
        expected_maximum_endpoint_rotation_delta_degrees = [double]$observed.maximum_endpoint_rotation_delta_degrees
    }
}

$manifest = [pscustomobject][ordered]@{
    schema = 'tmxy.asset.interchange'
    schema_version = 1
    format_version = '1.0.0'
    bundle_id = 'golden.animation.boy01-core-real'
    asset_kind = 'animation_set'
    producer = [pscustomobject][ordered]@{
        name = 'tmxy-animation'
        version = '0.2.0'
        source_sha256 = [string]$p116.source_sha256
    }
    source_inputs = @([pscustomobject][ordered]@{
            id = 'legacy-source-evidence'; role = 'provenance-manifest'
            relative_path = 'source-evidence.json'; bytes = $sourceFile.bytes
            sha256 = $sourceFile.sha256; copy_policy = 'reference-only'
        })
    artifacts = $artifacts
    unknown_fields = @([pscustomobject][ordered]@{
            path = 'animation_set.unselected_clips_and_notify_execution'
            state = 'unmapped'; preservation = 'namespaced-extension'
            extension_key = 'org.tmxy.legacy-animation'
            reason = 'Golden import selects three behavior-boundary clips; remaining clips and notify execution remain read-only evidence.'
            extensions = [pscustomobject]@{}
        })
    extensions = [pscustomobject][ordered]@{
        'org.tmxy.legacy-animation' = [pscustomobject][ordered]@{
            metadata_artifact_id = 'metadata'
            source_animation_count = [int]$metadata.source_animation_count
            selected_clip_count = [int]$metadata.selected_clip_count
            root_motion_policy = 'preserved-root-track-not-extracted'
            legacy_loop_policy = 'preserve-metadata-no-forced-loop-flag'
        }
        'org.tmxy.ue-import' = [pscustomobject][ordered]@{
            skeleton_package_name = '/Game/TMXY/Golden/Skeletons/SKEL_Golden_Boy01'
            skeletal_mesh_package_name = '/Game/TMXY/Golden/SkeletalMeshes/SK_Golden_Boy01_Default'
            skeleton_manifest_path = $skeletonManifestRelative
            skeleton_manifest_sha256 = $skeletonManifest.sha256
            expected_bone_count = 80
            sample_rate_numerator = 30
            sample_rate_denominator = 1
            coordinate_mapping = 'gltf(y,z,x)-to-ue(x,y,z)-centimeters'
            quaternion_policy = 'normalized-adjacent-hemisphere-continuity'
            root_motion_policy = 'preserved-root-track-not-extracted'
            clips = $clipPackages
        }
    }
}
Write-JsonLf -Path (Join-Path $output 'manifest.json') -Value $manifest
$invalid = Get-Content -LiteralPath (Join-Path $output 'manifest.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$invalid.extensions.'org.tmxy.ue-import'.clips[0].package_name =
    '/Game/TMXY/Golden/Animations/A_Golden_Invalid_Hash'
($invalid.artifacts | Where-Object id -eq 'animation-gltf').sha256 = '0' * 64
Write-JsonLf -Path (Join-Path $output 'manifest-invalid-hash.json') -Value $invalid

$files = Get-ChildItem -LiteralPath $output -File | Sort-Object Name
[pscustomobject][ordered]@{
    result = 'PASS'
    output_root = $output
    generated_file_count = $files.Count
    generated_files = @($files | ForEach-Object {
            [pscustomobject][ordered]@{
                path = $_.Name; bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
} | ConvertTo-Json -Depth 5
