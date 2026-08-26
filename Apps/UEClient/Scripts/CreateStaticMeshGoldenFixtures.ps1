[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$rebuild = Join-Path $workspace 'Rebuild'
$output = Join-Path $rebuild 'Tests\Fixtures\UE\StaticMesh'
$lock = Get-Content -LiteralPath (Join-Path $rebuild 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$p114 = Get-Content -LiteralPath (Join-Path $rebuild 'Data\BuildBaseline\p1-14-sm-static-mesh.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json

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

$fixtures = @(
    [pscustomobject][ordered]@{
        id = 'minimum-real'
        bundle_id = 'golden.static-mesh.minimum-real'
        package_path = '天命西游\Packages\particle'
        package_sha256 = '2e74819ee5eb665b5298710c06ea73de5016909535dee0ad388b7c194c6bd3b9'
        object_name = 'particle.ZFH_O_S_Tianpian100'
        sm_path = '天命西游\Resource\StaticMesh\particle\ZFH_O_S_Tianpian100.sm'
        sm_sha256 = '79669d7fbc5d3ebbfa82c6f3075c39b512d7ea021adf2d749b596d6e82dd81e8'
        package_name = '/Game/TMXY/Golden/StaticMeshes/SM_Golden_Minimum_Real'
    },
    [pscustomobject][ordered]@{
        id = 'multisection-real'
        bundle_id = 'golden.static-mesh.multisection-real'
        package_path = '天命西游\Packages\StaticMesh\scene09'
        package_sha256 = '481f0d93560eaabed09db7e2c71b35d5b0b757903378cb4c42c9d8f1beb5bd2c'
        object_name = 'scene09.GT_B_S_BangPai05'
        sm_path = '天命西游\Resource\StaticMesh\scene09\GT_B_S_BangPai05.sm'
        sm_sha256 = 'c72bbcde94f51f8b8f8d8c9fc5800fbd2ca0356bdc6efec441cae6ce9a5260a8'
        package_name = '/Game/TMXY/Golden/StaticMeshes/SM_Golden_MultiSection_Real'
    }
)

if ([string]$p114.result -ne 'PASS' -or -not [bool]$p114.completion_criteria_satisfied) {
    throw 'P1-14 evidence must pass before generating StaticMesh fixtures.'
}
foreach ($fixture in $fixtures) {
    foreach ($source in @(
            [pscustomobject]@{ path = $fixture.package_path; sha256 = $fixture.package_sha256 },
            [pscustomobject]@{ path = $fixture.sm_path; sha256 = $fixture.sm_sha256 })) {
        $path = Join-Path $workspace $source.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $source.sha256) {
            throw "StaticMesh golden evidence changed or is missing: $($source.path)"
        }
    }
    New-Item -ItemType Directory -Path (Join-Path $output $fixture.id) -Force | Out-Null
}

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
cp -a /workspace/Tools/TMXY.StaticMesh /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TEXTURE=OFF \
  -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang --target tmxy_sm_export
EXPORTER=out/build/ci-linux-clang/TMXY.StaticMesh/tmxy_sm_export
"$EXPORTER" '/evidence/天命西游/Packages/particle' 'particle.ZFH_O_S_Tianpian100' \
  '/evidence/天命西游/Resource/StaticMesh/particle/ZFH_O_S_Tianpian100.sm' \
  '/output/minimum-real/mesh' >/tmp/minimum.json
"$EXPORTER" '/evidence/天命西游/Packages/StaticMesh/scene09' 'scene09.GT_B_S_BangPai05' \
  '/evidence/天命西游/Resource/StaticMesh/scene09/GT_B_S_BangPai05.sm' \
  '/output/multisection-real/mesh' >/tmp/multisection.json
cmp /tmp/minimum.json /output/minimum-real/mesh.json
cmp /tmp/multisection.json /output/multisection-real/mesh.json
test -s /output/minimum-real/mesh.gltf
test -s /output/minimum-real/mesh.bin
test -s /output/multisection-real/mesh.gltf
test -s /output/multisection-real/mesh.bin
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
    throw "StaticMesh golden generation failed with exit code $LASTEXITCODE."
}

function New-Artifact {
    param(
        [Parameter(Mandatory = $true)][string]$BundleRoot,
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
    $evidence = Get-FileEvidence -Path (Join-Path $BundleRoot $RelativePath)
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

foreach ($fixture in $fixtures) {
    $bundleRoot = Join-Path $output $fixture.id
    $metadata = Get-Content -LiteralPath (Join-Path $bundleRoot 'mesh.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $gltf = Get-Content -LiteralPath (Join-Path $bundleRoot 'mesh.gltf') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $positionAccessorIndex = [int]$gltf.meshes[0].primitives[0].attributes.POSITION
    $positionAccessor = $gltf.accessors[$positionAccessorIndex]
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
    $packageEvidence = Get-FileEvidence -Path (Join-Path $workspace $fixture.package_path)
    $smEvidence = Get-FileEvidence -Path (Join-Path $workspace $fixture.sm_path)
    $sourceEvidence = [pscustomobject][ordered]@{
        schema_version = 1
        fixture_id = $fixture.id
        derivation = 'locked TMXY.StaticMesh glTF 2.0 export from exact read-only Package/SM pair'
        copy_policy = 'reference-only-inputs; deterministic-small-derived-fixture'
        producer_source_sha256 = [string]$p114.source_sha256
        sources = @(
            [pscustomobject][ordered]@{
                role = 'package-metadata'
                path = $fixture.package_path.Replace('\', '/')
                bytes = $packageEvidence.bytes
                sha256 = $packageEvidence.sha256
            },
            [pscustomobject][ordered]@{
                role = 'legacy-sm-payload'
                path = $fixture.sm_path.Replace('\', '/')
                bytes = $smEvidence.bytes
                sha256 = $smEvidence.sha256
            })
    }
    $sourceEvidencePath = Join-Path $bundleRoot 'source-evidence.json'
    Write-JsonLf -Path $sourceEvidencePath -Value $sourceEvidence
    $sourceFile = Get-FileEvidence -Path $sourceEvidencePath
    $features = @('mesh-sections')
    if ([int]$metadata.uv_channel_count -eq 2) { $features += 'second-uv-channel' }
    $artifacts = [System.Collections.Generic.List[object]]::new()
    $artifacts.Add((New-Artifact -BundleRoot $bundleRoot -Id 'metadata' `
            -Role 'legacy-metadata' -RelativePath 'mesh.json' `
            -FormatId 'tmxy.asset.metadata-json' -FormatVersion '1.0.0' `
            -MediaType 'application/json' -Authority 'authoritative-interchange' `
            -ByteOrder 'not-applicable' -Coordinate 'legacy-runtime-x-forward-y-right-z-up-meters' `
            -Unit 'meters'))
    $artifacts.Add((New-Artifact -BundleRoot $bundleRoot -Id 'buffer' -Role 'gltf-buffer' `
            -RelativePath 'mesh.bin' -FormatId 'khronos.gltf-bin' -FormatVersion '2.0.0' `
            -MediaType 'application/octet-stream' -Authority 'authoritative-interchange' `
            -ByteOrder 'little-endian' -Coordinate 'gltf-2.0-standard' -Unit 'meters'))
    $artifacts.Add((New-Artifact -BundleRoot $bundleRoot -Id 'render-gltf' `
            -Role 'render-geometry' -RelativePath 'mesh.gltf' -FormatId 'khronos.gltf-json' `
            -FormatVersion '2.0.0' -MediaType 'model/gltf+json' `
            -Authority 'authoritative-interchange' -ByteOrder 'not-applicable' `
            -Coordinate 'gltf-2.0-standard' -Unit 'meters' `
            -DependsOn @('buffer', 'metadata') -Features $features))
    $artifacts.Add((New-Artifact -BundleRoot $bundleRoot -Id 'preview' -Role 'visual-review' `
            -RelativePath 'mesh.obj' -FormatId 'wavefront.obj' -FormatVersion '1.0.0' `
            -MediaType 'model/obj' -Authority 'review' -ByteOrder 'not-applicable' `
            -Coordinate 'ue-x-forward-y-right-z-up-centimeters' -Unit 'centimeters' `
            -DependsOn @('render-gltf')))
    $manifest = [pscustomobject][ordered]@{
        schema = 'tmxy.asset.interchange'
        schema_version = 1
        format_version = '1.0.0'
        bundle_id = $fixture.bundle_id
        asset_kind = 'static_mesh'
        producer = [pscustomobject][ordered]@{
            name = 'tmxy-static-mesh'
            version = '0.1.0'
            source_sha256 = [string]$p114.source_sha256
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
                path = 'static_mesh.legacy_runtime_auxiliary'
                state = 'unsupported'
                preservation = 'namespaced-extension'
                extension_key = 'org.tmxy.legacy-static-mesh'
                reason = 'Collision, shadow, octree and emitter semantics remain in authoritative metadata.'
                extensions = [pscustomobject]@{}
            })
        extensions = [pscustomobject][ordered]@{
            'org.tmxy.legacy-static-mesh' = [pscustomobject][ordered]@{
                metadata_artifact_id = 'metadata'
                collision_policy = 'preserved-in-metadata-not-imported-p1-23'
            }
            'org.tmxy.ue-import' = [pscustomobject][ordered]@{
                package_name = $fixture.package_name
                expected_vertex_count = [int]$metadata.vertex_count
                expected_triangle_count = [int]$metadata.triangle_count
                expected_material_slot_count = [int]$metadata.section_count
                expected_uv_channel_count = [int]$metadata.uv_channel_count
                expected_use_light_map = [bool]$metadata.use_light_map
                expected_render_bounds_cm = $renderBoundsCm
                expected_effective_legacy_bounds_cm = $metadata.ue_centimeter_bounds
                coordinate_mapping = 'gltf(y,z,x)-to-ue(x,y,z)-centimeters'
                preserve_winding = $true
                recompute_tangents = $true
            }
        }
    }
    Write-JsonLf -Path (Join-Path $bundleRoot 'manifest.json') -Value $manifest
    if ($fixture.id -eq 'minimum-real') {
        $invalid = (Get-Content -LiteralPath (Join-Path $bundleRoot 'manifest.json') -Raw |
                ConvertFrom-Json)
        $invalid.extensions.'org.tmxy.ue-import'.package_name =
            '/Game/TMXY/Golden/StaticMeshes/SM_Golden_Invalid_Hash'
        ($invalid.artifacts | Where-Object id -eq 'render-gltf').sha256 = '0' * 64
        Write-JsonLf -Path (Join-Path $bundleRoot 'manifest-invalid-hash.json') -Value $invalid
    }
}

$files = Get-ChildItem -LiteralPath $output -Recurse -File | Sort-Object FullName
[pscustomobject][ordered]@{
    result = 'PASS'
    output_root = $output
    generated_file_count = $files.Count
    generated_files = @($files | ForEach-Object {
            [pscustomobject][ordered]@{
                path = $_.FullName.Substring($output.Length + 1).Replace('\', '/')
                bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
} | ConvertTo-Json -Depth 5
