[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$rebuild = Join-Path $workspace 'Rebuild'
$output = Join-Path $rebuild 'Tests\Fixtures\UE\Texture'
$lock = Get-Content -LiteralPath (Join-Path $rebuild 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json

$evidence = @(
    [pscustomobject]@{
        path = '天命西游\Packages\Texture\texstone'
        sha256 = '350c7d5da525f8ea4490345ad4948da4c2d6d4551ee5136f9aa0ce540d147d23'
    },
    [pscustomobject]@{
        path = '天命西游\Resource\Texture\texstone\WHZ_S_Dimian20_D.qtx'
        sha256 = '686418d443a9d067f90ec640d9d92a8ad7efd1ce6b1c1f05587a256027c003f2'
    },
    [pscustomobject]@{
        path = '天命西游\Packages\Texture\texparticle'
        sha256 = '607a4f926ce977a67f5168928f54a111b0f88711c88c997eb5e067bea4da9a58'
    },
    [pscustomobject]@{
        path = '天命西游\Resource\Texture\texparticle\FXH_T_toumingtu.qtx'
        sha256 = '44126814ab834eb714baffb42461fd53083118232afed00ad0efc5a6603d0804'
    }
)

foreach ($item in $evidence) {
    $path = Join-Path $workspace $item.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Texture golden evidence is missing: $($item.path)"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $item.sha256) {
        throw "Texture golden evidence changed: $($item.path)"
    }
}

$builder = [string]$lock.backend_toolchain.container_image_reference
$expectedId = [string]$lock.backend_toolchain.container_image_digest
$image = @(docker image inspect $builder 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or [string]$image[0].Id -ne $expectedId -or
    [string]$image[0].Config.User -ne 'tmxy') {
    throw 'The qualified non-root Clang 21 builder is required.'
}

New-Item -ItemType Directory -Path (Join-Path $output 'opaque-dxt1') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $output 'transparent-dxt5') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $output 'multi-mip-dxt1') -Force | Out-Null

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/build
cp /workspace/.clang-format /tmp/tmxy-rebuild/
cp /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /tmp/tmxy-rebuild/Tools/
cp /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.FormatCore /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.Package /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.Texture /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TRANSFORM=OFF \
  -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF \
  -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang --target tmxy_qtx_export
EXPORTER=out/build/ci-linux-clang/TMXY.Texture/tmxy_qtx_export
"$EXPORTER" '/evidence/天命西游/Packages/Texture/texstone' \
  'texstone.WHZ_S_Dimian20_D' \
  '/evidence/天命西游/Resource/Texture/texstone/WHZ_S_Dimian20_D.qtx' \
  '/output/opaque-dxt1/texture' >/tmp/opaque.json
"$EXPORTER" '/evidence/天命西游/Packages/Texture/texparticle' \
  'texparticle.FXH_T_toumingtu' \
  '/evidence/天命西游/Resource/Texture/texparticle/FXH_T_toumingtu.qtx' \
  '/output/transparent-dxt5/texture' >/tmp/transparent.json
cmp /tmp/opaque.json /output/opaque-dxt1/texture.json
cmp /tmp/transparent.json /output/transparent-dxt5/texture.json
test "$(stat -c %s /output/opaque-dxt1/texture.dds)" = '160'
test "$(stat -c %s /output/transparent-dxt5/texture.dds)" = '384'
'@

$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--mount', "type=bind,source=$rebuild,target=/workspace,readonly",
    '--mount', "type=bind,source=$workspace,target=/evidence,readonly",
    '--mount', "type=bind,source=$output,target=/output",
    $builder, 'bash', '-c', $containerScript
)
& docker @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Texture golden generation failed with exit code $LASTEXITCODE."
}

function Set-U32LittleEndian {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][uint32]$Value
    )
    $Bytes[$Offset] = [byte]($Value -band 0xff)
    $Bytes[$Offset + 1] = [byte](($Value -shr 8) -band 0xff)
    $Bytes[$Offset + 2] = [byte](($Value -shr 16) -band 0xff)
    $Bytes[$Offset + 3] = [byte](($Value -shr 24) -band 0xff)
}

$syntheticDds = [byte[]]::new(184)
Set-U32LittleEndian -Bytes $syntheticDds -Offset 0 -Value 0x20534444
Set-U32LittleEndian -Bytes $syntheticDds -Offset 4 -Value 124
Set-U32LittleEndian -Bytes $syntheticDds -Offset 8 -Value 0x000A1007
Set-U32LittleEndian -Bytes $syntheticDds -Offset 12 -Value 8
Set-U32LittleEndian -Bytes $syntheticDds -Offset 16 -Value 8
Set-U32LittleEndian -Bytes $syntheticDds -Offset 20 -Value 32
Set-U32LittleEndian -Bytes $syntheticDds -Offset 28 -Value 4
Set-U32LittleEndian -Bytes $syntheticDds -Offset 76 -Value 32
Set-U32LittleEndian -Bytes $syntheticDds -Offset 80 -Value 4
Set-U32LittleEndian -Bytes $syntheticDds -Offset 84 -Value 0x31545844
Set-U32LittleEndian -Bytes $syntheticDds -Offset 108 -Value 0x00401008
[System.IO.File]::WriteAllBytes(
    (Join-Path $output 'multi-mip-dxt1\texture.dds'),
    $syntheticDds)

$files = Get-ChildItem -LiteralPath $output -Recurse -File | Sort-Object FullName
[pscustomobject]@{
    result = 'PASS'
    output_root = $output
    generated_file_count = $files.Count
    generated_files = @($files | ForEach-Object {
        [pscustomobject]@{
            path = $_.FullName.Substring($output.Length + 1).Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
} | ConvertTo-Json -Depth 5
