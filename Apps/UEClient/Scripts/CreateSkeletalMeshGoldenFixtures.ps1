[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$rebuild = Join-Path $workspace 'Rebuild'
$output = Join-Path $rebuild 'Tests\Fixtures\UE\SkeletalMesh\boy01-default-real'
$lock = Get-Content -LiteralPath (Join-Path $rebuild 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$p115 = Get-Content -LiteralPath (Join-Path $rebuild 'Data\BuildBaseline\p1-15-skem-skeletal-mesh.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json

$packageRelative = '天命西游\Packages\SkelMesh\skchar'
$skemRelative = '天命西游\Resource\SkelMesh\skchar\Boy01.skem'
$packageSha256 = '0867a016dd0b2a75a35d453ffe2242ffeb5329d003de61ba9b121dcebdba10e7'
$skemSha256 = '409fedf015ae3949222241cd8d7cc1aea22bb6ef689b2cc0190a796fe7cf93b6'

function Write-JsonLf {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    $json = ($Value | ConvertTo-Json -Depth 15).Replace("`r`n", "`n").Replace("`r", "`n")
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
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$FormatId,
        [Parameter(Mandatory = $true)][string]$FormatVersion,
        [Parameter(Mandatory = $true)][string]$MediaType,
        [Parameter(Mandatory = $true)][string]$Authority,
        [Parameter(Mandatory = $true)][string]$ByteOrder,
        [Parameter(Mandatory = $true)][string]$Coordinate,
        [Parameter(Mandatory = $true)][string]$Unit,
        [string[]]$DependsOn = @(),
        [string[]]$Features = @()
    )
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

if ([string]$p115.result -ne 'PASS' -or -not [bool]$p115.completion_criteria_satisfied) {
    throw 'P1-15 evidence must pass before generating SkeletalMesh fixtures.'
}
foreach ($source in @(
        [pscustomobject]@{ path = $packageRelative; sha256 = $packageSha256 },
        [pscustomobject]@{ path = $skemRelative; sha256 = $skemSha256 })) {
    $path = Join-Path $workspace $source.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $source.sha256) {
        throw "SkeletalMesh golden evidence changed or is missing: $($source.path)"
    }
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
cp -a /workspace/Tools/TMXY.FormatCore /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.Package /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.Transform /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.SkeletalMesh /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TEXTURE=OFF \
  -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang --target tmxy_skem_export
EXPORTER=out/build/ci-linux-clang/TMXY.SkeletalMesh/tmxy_skem_export
"$EXPORTER" '/evidence/天命西游/Packages/SkelMesh/skchar' 'skchar.Boy01' \
  '/evidence/天命西游/Resource/SkelMesh/skchar/Boy01.skem' '/output/mesh' >/tmp/mesh.json
cmp /tmp/mesh.json /output/mesh.json
test -s /output/mesh.gltf
test -s /output/mesh.bin
'@

$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=2g',
    '--mount', "type=bind,source=$rebuild,target=/workspace,readonly",
    '--mount', "type=bind,source=$workspace,target=/evidence,readonly",
    '--mount', "type=bind,source=$output,target=/output",
    $builder, 'bash', '-c', $containerScript
)
& docker @arguments
if ($LASTEXITCODE -ne 0) {
    throw "SkeletalMesh golden generation failed with exit code $LASTEXITCODE."
}

$metadata = Get-Content -LiteralPath (Join-Path $output 'mesh.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$gltf = Get-Content -LiteralPath (Join-Path $output 'mesh.gltf') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$positionAccessor = $gltf.accessors[[int]$gltf.meshes[0].primitives[0].attributes.POSITION]
$indexCount = 0
foreach ($primitive in @($gltf.meshes[0].primitives)) {
    $indexCount += [int]$gltf.accessors[[int]$primitive.indices].count
}
$renderBoundsCm = [pscustomobject][ordered]@{
    minimum = @(
        ([double]$positionAccessor.min[2] * 100.0),
        ([double]$positionAccessor.min[0] * 100.0),
        ([double]$positionAccessor.min[1] * 100.0))
    maximum = @(
        ([double]$positionAccessor.max[2] * 100.0),
        ([double]$positionAccessor.max[0] * 100.0),
        ([double]$positionAccessor.max[1] * 100.0))
}
$packageEvidence = Get-FileEvidence -Path (Join-Path $workspace $packageRelative)
$skemEvidence = Get-FileEvidence -Path (Join-Path $workspace $skemRelative)
$sourceEvidence = [pscustomobject][ordered]@{
    schema_version = 1
    fixture_id = 'boy01-default-real'
    derivation = 'locked TMXY.SkeletalMesh glTF 2.0 export from exact read-only Package/SKEM pair'
    copy_policy = 'reference-only-inputs; deterministic-default-selection-derived-fixture'
    producer_source_sha256 = [string]$p115.source_sha256
    sources = @(
        [pscustomobject][ordered]@{
            role = 'package-metadata'
            path = $packageRelative.Replace('\', '/')
            bytes = $packageEvidence.bytes
            sha256 = $packageEvidence.sha256
        },
        [pscustomobject][ordered]@{
            role = 'legacy-skem-payload'
            path = $skemRelative.Replace('\', '/')
            bytes = $skemEvidence.bytes
            sha256 = $skemEvidence.sha256
        })
}
$sourceEvidencePath = Join-Path $output 'source-evidence.json'
Write-JsonLf -Path $sourceEvidencePath -Value $sourceEvidence
$sourceFile = Get-FileEvidence -Path $sourceEvidencePath

$artifacts = [System.Collections.Generic.List[object]]::new()
$artifacts.Add((New-Artifact -Id 'metadata' -Role 'legacy-metadata' -RelativePath 'mesh.json' `
        -FormatId 'tmxy.asset.metadata-json' -FormatVersion '1.0.0' -MediaType 'application/json' `
        -Authority 'authoritative-interchange' -ByteOrder 'not-applicable' `
        -Coordinate 'legacy-runtime-x-forward-y-right-z-up-meters' -Unit 'meters'))
$artifacts.Add((New-Artifact -Id 'buffer' -Role 'gltf-buffer' -RelativePath 'mesh.bin' `
        -FormatId 'khronos.gltf-bin' -FormatVersion '2.0.0' `
        -MediaType 'application/octet-stream' -Authority 'authoritative-interchange' `
        -ByteOrder 'little-endian' -Coordinate 'gltf-2.0-standard' -Unit 'meters'))
$artifacts.Add((New-Artifact -Id 'render-gltf' -Role 'render-skinning' -RelativePath 'mesh.gltf' `
        -FormatId 'khronos.gltf-json' -FormatVersion '2.0.0' -MediaType 'model/gltf+json' `
        -Authority 'authoritative-interchange' -ByteOrder 'not-applicable' `
        -Coordinate 'gltf-2.0-standard' -Unit 'meters' -DependsOn @('buffer', 'metadata') `
        -Features @('mesh-sections', 'skin', 'joints-0', 'weights-0', 'inverse-bind-matrices')))
$artifacts.Add((New-Artifact -Id 'preview' -Role 'visual-review' -RelativePath 'mesh.obj' `
        -FormatId 'wavefront.obj' -FormatVersion '1.0.0' -MediaType 'model/obj' `
        -Authority 'review' -ByteOrder 'not-applicable' `
        -Coordinate 'ue-x-forward-y-right-z-up-centimeters' -Unit 'centimeters' `
        -DependsOn @('render-gltf')))

$manifest = [pscustomobject][ordered]@{
    schema = 'tmxy.asset.interchange'
    schema_version = 1
    format_version = '1.0.0'
    bundle_id = 'golden.skeletal-mesh.boy01-default-real'
    asset_kind = 'skeletal_mesh'
    producer = [pscustomobject][ordered]@{
        name = 'tmxy-skeletal-mesh'
        version = '0.2.0'
        source_sha256 = [string]$p115.source_sha256
    }
    source_inputs = @([pscustomobject][ordered]@{
            id = 'legacy-source-evidence'
            role = 'provenance-manifest'
            relative_path = 'source-evidence.json'
            bytes = $sourceFile.bytes
            sha256 = $sourceFile.sha256
            copy_policy = 'reference-only'
        })
    artifacts = $artifacts
    unknown_fields = @([pscustomobject][ordered]@{
            path = 'skeletal_mesh.non_default_variants_and_legacy_auxiliary'
            state = 'unmapped'
            preservation = 'namespaced-extension'
            extension_key = 'org.tmxy.legacy-skeletal-mesh'
            reason = 'Golden import intentionally selects the Package default avatar parts; full variants remain read-only evidence.'
            extensions = [pscustomobject]@{}
        })
    extensions = [pscustomobject][ordered]@{
        'org.tmxy.legacy-skeletal-mesh' = [pscustomobject][ordered]@{
            metadata_artifact_id = 'metadata'
            attachment_policy = 'bone-name-candidates-only-no-invented-sockets'
            unweighted_sentinel_policy = 'reject-authoritative-skinning-fixture'
        }
        'org.tmxy.ue-import' = [pscustomobject][ordered]@{
            skeletal_mesh_package_name = '/Game/TMXY/Golden/SkeletalMeshes/SK_Golden_Boy01_Default'
            skeleton_package_name = '/Game/TMXY/Golden/Skeletons/SKEL_Golden_Boy01'
            expected_source_vertex_count = [int]$positionAccessor.count
            expected_triangle_count = [int]($indexCount / 3)
            expected_material_slot_count = @($gltf.meshes[0].primitives).Count
            expected_bone_count = @($gltf.skins[0].joints).Count
            expected_root_bone_count = @($gltf.scenes[0].nodes).Count - 1
            expected_root_bone_name = [string]$gltf.nodes[[int]$gltf.skins[0].skeleton].name
            expected_max_active_influences = 4
            expected_unweighted_sentinel_vertex_count = 0
            expected_render_bounds_cm = $renderBoundsCm
            coordinate_mapping = 'gltf(y,z,x)-to-ue(x,y,z)-centimeters'
            bone_index_mapping = 'legacy-one-based-to-gltf-zero-based'
            preserve_winding = $true
            recompute_tangents = $true
        }
    }
}
Write-JsonLf -Path (Join-Path $output 'manifest.json') -Value $manifest
$invalid = Get-Content -LiteralPath (Join-Path $output 'manifest.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$invalid.extensions.'org.tmxy.ue-import'.skeletal_mesh_package_name =
    '/Game/TMXY/Golden/SkeletalMeshes/SK_Golden_Invalid_Hash'
$invalid.extensions.'org.tmxy.ue-import'.skeleton_package_name =
    '/Game/TMXY/Golden/Skeletons/SKEL_Golden_Invalid_Hash'
($invalid.artifacts | Where-Object id -eq 'render-gltf').sha256 = '0' * 64
Write-JsonLf -Path (Join-Path $output 'manifest-invalid-hash.json') -Value $invalid

$files = Get-ChildItem -LiteralPath $output -File | Sort-Object Name
[pscustomobject][ordered]@{
    result = 'PASS'
    output_root = $output
    generated_file_count = $files.Count
    generated_files = @($files | ForEach-Object {
            [pscustomobject][ordered]@{
                path = $_.Name
                bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
} | ConvertTo-Json -Depth 5
