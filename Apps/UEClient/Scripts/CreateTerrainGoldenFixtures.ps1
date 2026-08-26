[CmdletBinding()]
param([string]$WorkspaceRoot = 'E:\QQXYCodeDev')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$rebuild = Join-Path $workspace 'Rebuild'
$output = Join-Path $rebuild 'Tests\Fixtures\UE\Terrain\world-adjacency-real'
$lock = Get-Content -LiteralPath (Join-Path $rebuild 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$p117 = Get-Content -LiteralPath (Join-Path $rebuild 'Data\BuildBaseline\p1-17-ter-terrain.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json

$level = [pscustomobject][ordered]@{
    path = '天命西游\Level\world'
    sha256 = '997627584cf4dfb55016be32b64e7d33763a17b980a05e0b580137193fb352f4'
}
$tiles = @(
    [pscustomobject][ordered]@{
        id = 'base'; source = '天命西游\Resource\Terrain\world_001_001.ter'
        sha256 = '233f5be2358d1fdc88ca872373d074eb67b48ca33c3c78708bc74290d0e061e7'
        x = 1; y = 1; package = '/Game/TMXY/Golden/Terrain/SMT_Golden_World_001_001'
    },
    [pscustomobject][ordered]@{
        id = 'right'; source = '天命西游\Resource\Terrain\world_002_001.ter'
        sha256 = '3f343db7478cdafb1828469acd74680a45a6fb2fab60f6e909ae4a80be8867b4'
        x = 2; y = 1; package = '/Game/TMXY/Golden/Terrain/SMT_Golden_World_002_001'
    },
    [pscustomobject][ordered]@{
        id = 'bottom'; source = '天命西游\Resource\Terrain\world_001_002.ter'
        sha256 = 'f14874bbb0a4a1ddcc709ae48f4913d6ba3bce8bc5c3bd5b0d06292a84893389'
        x = 1; y = 2; package = '/Game/TMXY/Golden/Terrain/SMT_Golden_World_001_002'
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

function Read-FloatPlane {
    param([Parameter(Mandatory = $true)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ne 4096 * 4) { throw "Unexpected height plane size: $Path" }
    return @(0..4095 | ForEach-Object { [BitConverter]::ToSingle($bytes, $_ * 4) })
}

function Get-Adjacency {
    param([float[]]$First, [float[]]$Second, [ValidateSet('right', 'bottom')][string]$Direction)
    $deltas = for ($sample = 0; $sample -lt 64; $sample++) {
        $firstIndex = if ($Direction -eq 'right') { $sample * 64 + 63 } else { 63 * 64 + $sample }
        $secondIndex = if ($Direction -eq 'right') { $sample * 64 } else { $sample }
        [Math]::Abs([double]$First[$firstIndex] - [double]$Second[$secondIndex])
    }
    return [pscustomobject][ordered]@{
        sample_count = 64
        differing_sample_count = @($deltas | Where-Object { $_ -ne 0.0 }).Count
        maximum_absolute_delta_source_units = [double](($deltas | Measure-Object -Maximum).Maximum)
        maximum_absolute_delta_cm = [double](($deltas | Measure-Object -Maximum).Maximum) * 400.0
    }
}

if ([string]$p117.result -ne 'PASS' -or -not [bool]$p117.completion_criteria_satisfied) {
    throw 'P1-17 must pass before generating Terrain fixtures.'
}
foreach ($source in @($level) + $tiles) {
    $relative = if ($source.PSObject.Properties.Name -contains 'source') { $source.source } else { $source.path }
    $path = Join-Path $workspace $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $source.sha256) {
        throw "Terrain golden evidence changed or is missing: $relative"
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
cp -a /workspace/Tools/TMXY.Terrain /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
cmake --preset ci-linux-clang -DTMXY_BUILD_PACKAGE=OFF -DTMXY_BUILD_TABLE=OFF \
  -DTMXY_BUILD_TRANSFORM=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF \
  -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF >/dev/null
cmake --build --preset ci-linux-clang --target tmxy_ter_export >/dev/null
EXPORTER=out/build/ci-linux-clang/TMXY.Terrain/tmxy_ter_export
"$EXPORTER" '/evidence/天命西游/Resource/Terrain/world_001_001.ter' '/output/base' >/tmp/base.json
"$EXPORTER" '/evidence/天命西游/Resource/Terrain/world_002_001.ter' '/output/right' >/tmp/right.json
"$EXPORTER" '/evidence/天命西游/Resource/Terrain/world_001_002.ter' '/output/bottom' >/tmp/bottom.json
cmp /tmp/base.json /output/base.json
cmp /tmp/right.json /output/right.json
cmp /tmp/bottom.json /output/bottom.json
'@
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--mount', "type=bind,source=$rebuild,target=/workspace,readonly",
    '--mount', "type=bind,source=$workspace,target=/evidence,readonly",
    '--mount', "type=bind,source=$output,target=/output",
    $builder, 'bash', '-c', $containerScript)
& docker @arguments
if ($LASTEXITCODE -ne 0) { throw "Terrain golden generation failed with exit code $LASTEXITCODE." }

$sourceItems = @($level) + $tiles
$sourceEvidence = [pscustomobject][ordered]@{
    schema_version = 1
    fixture_id = 'world-adjacency-real'
    derivation = 'locked TMXY.Terrain typed-plane export plus matching QLevel scale evidence'
    copy_policy = 'reference-only-inputs; deterministic-small-derived-fixture'
    producer_source_sha256 = [string]$p117.source_sha256
    level_contract = [pscustomobject][ordered]@{
        package_object = 'world.QLEVEL'; terrain_info_object = 'world.terrainInfo'
        width_zones = 52; length_zones = 52; zone_size_source_units = 252.0
        cells_per_zone_axis = 63; source_units_per_cell = 4.0; centimeters_per_source_unit = 100.0
    }
    sources = @($sourceItems | ForEach-Object {
            $relative = if ($_.PSObject.Properties.Name -contains 'source') { $_.source } else { $_.path }
            $evidence = Get-FileEvidence -Path (Join-Path $workspace $relative)
            [pscustomobject][ordered]@{
                role = if ($relative -match '\\Level\\') { 'matching-level-package' } else { 'legacy-ter-payload' }
                path = $relative.Replace('\', '/')
                bytes = $evidence.bytes
                sha256 = $evidence.sha256
            }
        })
}
Write-JsonLf -Path (Join-Path $output 'source-evidence.json') -Value $sourceEvidence
$sourceFile = Get-FileEvidence -Path (Join-Path $output 'source-evidence.json')

$artifacts = [System.Collections.Generic.List[object]]::new()
foreach ($tile in $tiles) {
    $artifacts.Add((New-Artifact -Id "$($tile.id)-metadata" -Role 'legacy-metadata' `
            -RelativePath "$($tile.id).json" -FormatId 'tmxy.asset.metadata-json' `
            -FormatVersion '1.0.0' -MediaType 'application/json' `
            -Authority 'authoritative-interchange' -ByteOrder 'not-applicable' `
            -Coordinate 'legacy-runtime-x-forward-y-right-z-up-meters' -Unit 'source-units'))
    $artifacts.Add((New-Artifact -Id "$($tile.id)-height" -Role 'height-plane' `
            -RelativePath "$($tile.id).height.f32le" -FormatId 'tmxy.terrain.height-f32le' `
            -FormatVersion '1.0.0' -MediaType 'application/octet-stream' `
            -Authority 'authoritative-interchange' -ByteOrder 'little-endian' `
            -Coordinate 'legacy-runtime-x-forward-y-right-z-up-meters' -Unit 'source-units' `
            -DependsOn @("$($tile.id)-metadata") -Features @('physical-scale-from-level-metadata')))
    $artifacts.Add((New-Artifact -Id "$($tile.id)-layers" -Role 'layer-alpha-plane' `
            -RelativePath "$($tile.id).layers.rgba8" -FormatId 'tmxy.terrain.layers-rgba8' `
            -FormatVersion '1.0.0' -MediaType 'application/octet-stream' `
            -Authority 'authoritative-interchange' -ByteOrder 'not-applicable' `
            -Coordinate 'legacy-runtime-x-forward-y-right-z-up-meters' -Unit 'not-applicable' `
            -DependsOn @("$($tile.id)-metadata")))
    $artifacts.Add((New-Artifact -Id "$($tile.id)-edges" -Role 'terrain-edge-review' `
            -RelativePath "$($tile.id).edges.csv" -FormatId 'text.csv-rfc4180' `
            -FormatVersion '1.0.0' -MediaType 'text/csv' -Authority 'review' `
            -ByteOrder 'not-applicable' -Coordinate 'legacy-runtime-x-forward-y-right-z-up-meters' `
            -Unit 'source-units' -DependsOn @("$($tile.id)-height")))
}
$planes = [ordered]@{}
foreach ($tile in $tiles) {
    $planes[$tile.id] = Read-FloatPlane -Path (Join-Path $output "$($tile.id).height.f32le")
}
$rightAdjacency = Get-Adjacency -First $planes.base -Second $planes.right -Direction right
$bottomAdjacency = Get-Adjacency -First $planes.base -Second $planes.bottom -Direction bottom

$tileSettings = @($tiles | ForEach-Object {
        $metadata = Get-Content -LiteralPath (Join-Path $output "$($_.id).json") -Raw -Encoding UTF8 |
            ConvertFrom-Json
        [pscustomobject][ordered]@{
            fixture_id = $_.id; package_name = $_.package; tile_x = $_.x; tile_y = $_.y
            metadata_artifact_id = "$($_.id)-metadata"; height_artifact_id = "$($_.id)-height"
            layer_artifact_id = "$($_.id)-layers"; expected_vertex_count = 4096
            expected_triangle_count = 7938
            expected_min_height_source_units = [double]$metadata.height_source_units.minimum
            expected_max_height_source_units = [double]$metadata.height_source_units.maximum
        }
    })
$manifest = [pscustomobject][ordered]@{
    schema = 'tmxy.asset.interchange'; schema_version = 1; format_version = '1.0.0'
    bundle_id = 'golden.terrain.world-adjacency-real'; asset_kind = 'terrain_tile'
    producer = [pscustomobject][ordered]@{
        name = 'tmxy-terrain'; version = '0.1.0'; source_sha256 = [string]$p117.source_sha256
    }
    source_inputs = @([pscustomobject][ordered]@{
            id = 'legacy-source-evidence'; role = 'provenance-manifest'
            relative_path = 'source-evidence.json'; bytes = $sourceFile.bytes
            sha256 = $sourceFile.sha256; copy_policy = 'reference-only'
        })
    artifacts = $artifacts
    unknown_fields = @([pscustomobject][ordered]@{
            path = 'terrain.runtime-rendering-policy'; state = 'unsupported'
            preservation = 'namespaced-extension'; extension_key = 'org.tmxy.legacy-terrain'
            reason = 'P1-26 proves interchange and UE geometry; Landscape versus custom runtime rendering remains P3-11.'
            extensions = [pscustomobject]@{}
        })
    extensions = [pscustomobject][ordered]@{
        'org.tmxy.legacy-terrain' = [pscustomobject][ordered]@{
            level_package_source = $level.path.Replace('\', '/')
            level_package_sha256 = $level.sha256; qlevel_property_count = 1163
            qlevel_body_offset = 1617462; terrain_info_body_offset = 593124
            width_zones = 52; length_zones = 52; zone_size_source_units = 252.0
            terrain_tile_num = 63; existing_edge_differences_preserved = $true
        }
        'org.tmxy.ue-import' = [pscustomobject][ordered]@{
            coordinate_mapping = 'legacy-x-forward-y-right-z-up-to-ue-x-forward-y-right-z-up'
            edge_vertex_count = 64; cells_per_axis = 63; source_units_per_cell = 4.0
            centimeters_per_source_unit = 100.0; cell_spacing_cm = 400.0
            zone_size_cm = 25200.0; preserve_existing_edge_differences = $true
            tile_meshes = $tileSettings
            adjacency = @(
                [pscustomobject][ordered]@{
                    first = 'base'; first_edge = 'right'; second = 'right'; second_edge = 'left'
                    sample_count = $rightAdjacency.sample_count
                    differing_sample_count = $rightAdjacency.differing_sample_count
                    maximum_absolute_delta_source_units = $rightAdjacency.maximum_absolute_delta_source_units
                    maximum_absolute_delta_cm = $rightAdjacency.maximum_absolute_delta_cm
                },
                [pscustomobject][ordered]@{
                    first = 'base'; first_edge = 'bottom'; second = 'bottom'; second_edge = 'top'
                    sample_count = $bottomAdjacency.sample_count
                    differing_sample_count = $bottomAdjacency.differing_sample_count
                    maximum_absolute_delta_source_units = $bottomAdjacency.maximum_absolute_delta_source_units
                    maximum_absolute_delta_cm = $bottomAdjacency.maximum_absolute_delta_cm
                })
        }
    }
}
Write-JsonLf -Path (Join-Path $output 'manifest.json') -Value $manifest
$invalid = Get-Content -LiteralPath (Join-Path $output 'manifest.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
foreach ($tile in @($invalid.extensions.'org.tmxy.ue-import'.tile_meshes)) {
    $tile.package_name = $tile.package_name.Replace('SMT_Golden_', 'SMT_Golden_Invalid_')
}
($invalid.artifacts | Where-Object id -eq 'base-height').sha256 = '0' * 64
Write-JsonLf -Path (Join-Path $output 'manifest-invalid-hash.json') -Value $invalid

$files = Get-ChildItem -LiteralPath $output -File | Sort-Object Name
[pscustomobject][ordered]@{
    result = 'PASS'; output_root = $output; generated_file_count = $files.Count
    right_adjacency = $rightAdjacency; bottom_adjacency = $bottomAdjacency
    generated_files = @($files | ForEach-Object {
            [pscustomobject][ordered]@{
                path = $_.Name; bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
} | ConvertTo-Json -Depth 8
