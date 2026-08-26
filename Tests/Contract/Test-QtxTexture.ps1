[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-13-qtx-texture.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$workspaceRoot = [System.IO.Path]::GetDirectoryName($root)
$moduleRoot = Join-Path $root 'Tools\TMXY.Texture'
$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        output = ($stdout + $stderr).Trim()
    }
}

$requiredFiles = @(
    'Tools/CMakeLists.txt',
    'Tools/CMakePresets.json',
    'Tools/TMXY.Texture/CMakeLists.txt',
    'Tools/TMXY.Texture/README.md',
    'Tools/TMXY.Texture/apps/qtx_export_main.cpp',
    'Tools/TMXY.Texture/include/tmxy/texture/legacy_texture_descriptor_reader.hpp',
    'Tools/TMXY.Texture/include/tmxy/texture/package_texture_reader.hpp',
    'Tools/TMXY.Texture/include/tmxy/texture/qtx_reader.hpp',
    'Tools/TMXY.Texture/include/tmxy/texture/texture_error.hpp',
    'Tools/TMXY.Texture/include/tmxy/texture/texture_export.hpp',
    'Tools/TMXY.Texture/include/tmxy/texture/texture_result.hpp',
    'Tools/TMXY.Texture/include/tmxy/texture/texture_types.hpp',
    'Tools/TMXY.Texture/src/block_compression.cpp',
    'Tools/TMXY.Texture/src/dds_writer.cpp',
    'Tools/TMXY.Texture/src/legacy_texture_descriptor_reader.cpp',
    'Tools/TMXY.Texture/src/package_texture_reader.cpp',
    'Tools/TMXY.Texture/src/png_writer.cpp',
    'Tools/TMXY.Texture/src/qtx_reader.cpp',
    'Tools/TMXY.Texture/src/texture_decode.cpp',
    'Tools/TMXY.Texture/src/texture_error.cpp',
    'Tools/TMXY.Texture/src/texture_export.cpp',
    'Tools/TMXY.Texture/src/tga_writer.cpp',
    'Tools/TMXY.Texture/src/texture_decode_internal.hpp',
    'Tools/TMXY.Texture/tests/CMakeLists.txt',
    'Tools/TMXY.Texture/tests/texture_parser_test.cpp',
    'Tools/TMXY.Texture/tests/qtx_real_samples_test.cpp',
    'Docs/Formats/QTX-FORMAT.md',
    'Docs/ADR/ADR-004-qtx-texture-intermediate.md',
    'Tests/Contract/Test-QtxTexture.ps1'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-13 required file is missing: $relativePath"
    }
}

$evidence = @(
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QTexture.h'; size = 1719; sha256 = 'bd381809fcd2cfff93227482ef52b53551de9c5fd69123153b324fe53be52bb9' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QTexture.cpp'; size = 799; sha256 = '299ef9ff707a912d06d0b8010e3ffcd502de2eba8e31effbd5af59bf1a88738f' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QRenderTypes.cpp'; size = 16776; sha256 = 'b276b91ba85256a91d38a894c786e9ebd2a4f4035a812b333fb4405f0bebff50' },
    [pscustomobject]@{ path = 'ClientCode\D3D9RDev\Src\D3DRendInterface.cpp'; size = 42954; sha256 = '134444b822c3bd271bcb91db4a0ac59a2b540bacbe460e35c54077f78589be87' },
    [pscustomobject]@{ path = 'ClientCode\Base\Src\QObject.cpp'; size = 28782; sha256 = '1f10ae3b06062564ac283a9396b1d232c261c669bcd6c22271b414aa6d6323e5' },
    [pscustomobject]@{ path = '天命西游\Packages\Texture\texstone'; size = 695794; sha256 = '350c7d5da525f8ea4490345ad4948da4c2d6d4551ee5136f9aa0ce540d147d23' },
    [pscustomobject]@{ path = '天命西游\Packages\newscenc'; size = 43554; sha256 = '79bf6e339149b9a37535d6d5c92e5a4c09b5737072be1ac9fe21681630f8d433' },
    [pscustomobject]@{ path = '天命西游\Packages\Texture\texparticle'; size = 162914; sha256 = '607a4f926ce977a67f5168928f54a111b0f88711c88c997eb5e067bea4da9a58' },
    [pscustomobject]@{ path = '天命西游\Packages\editorui'; size = 222; sha256 = '1f7d7c535a2ff76eb328ddc0ad0b9e9126f32efb1c4f0ad075c51242520567a7' },
    [pscustomobject]@{ path = '天命西游\Resource\Texture\texstone\WHZ_S_Dimian20_D.qtx'; size = 32; sha256 = '686418d443a9d067f90ec640d9d92a8ad7efd1ce6b1c1f05587a256027c003f2' },
    [pscustomobject]@{ path = '天命西游\Resource\Texture\newscenc\dy_bx_xlys_01_D.qtx'; size = 22369648; sha256 = 'bfdc514d8ece8424bd0b9b193a651b7656cc37520e89502a03c28dd68160a69a' },
    [pscustomobject]@{ path = '天命西游\Resource\Texture\texparticle\FXH_T_toumingtu.qtx'; size = 256; sha256 = '44126814ab834eb714baffb42461fd53083118232afed00ad0efc5a6603d0804' },
    [pscustomobject]@{ path = '天命西游\Resource\Texture\editorui\ToolBoxHighLight.qtx'; size = 1048576; sha256 = '173259db23fcd44d2a522c1066dc0e851b7690ee384d9880719fab76f2f8368b' }
)
$evidenceReport = foreach ($item in $evidence) {
    $path = Join-Path $workspaceRoot $item.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P1-13 evidence is missing: $($item.path)"
    }
    $file = Get-Item -LiteralPath $path
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $item.size -or $actual -ne $item.sha256) {
        throw "P1-13 evidence changed: $($item.path)"
    }
    [pscustomobject][ordered]@{
        path = $item.path
        size = $file.Length
        sha256 = $actual
        passed = $true
    }
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx|CoreMinimal\.h)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -match $forbiddenPattern) {
        throw "P1-13 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}

$hashLines = foreach ($relativePath in $requiredFiles | Sort-Object) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($hash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")

$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$imageRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$imagePresent = $LASTEXITCODE -eq 0 -and $imageRecords.Count -gt 0
$actualBuilderId = if ($imagePresent) { [string]$imageRecords[0].Id } else { '' }
$builderUser = if ($imagePresent) { [string]$imageRecords[0].Config.User } else { '' }
if (-not $imagePresent -or $actualBuilderId -ne $expectedBuilderId -or $builderUser -ne 'tmxy') {
    throw 'P1-13 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/qtx-export
cp /workspace/.clang-format /tmp/tmxy-rebuild/
cp /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /tmp/tmxy-rebuild/Tools/
cp /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.FormatCore /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.Package /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.Texture /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
find TMXY.Texture -type f -print0 | grep -zE '[.](cpp|hpp)$' | xargs -0 clang-format-21 --dry-run --Werror
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TRANSFORM=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang --target tmxy_texture_parser_test tmxy_qtx_real_samples_test tmxy_qtx_export
find TMXY.Texture -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --test-dir out/build/ci-linux-clang -R '^texture.' --output-on-failure
REAL_TEST=out/build/ci-linux-clang/TMXY.Texture/tests/tmxy_qtx_real_samples_test
"$REAL_TEST" \
  '/evidence/天命西游/Packages/Texture/texstone' 'texstone.WHZ_S_Dimian20_D' '/evidence/天命西游/Resource/Texture/texstone/WHZ_S_Dimian20_D.qtx' \
  '/evidence/天命西游/Packages/newscenc' 'newscenc.dy_bx_xlys_01_D' '/evidence/天命西游/Resource/Texture/newscenc/dy_bx_xlys_01_D.qtx' \
  '/evidence/天命西游/Packages/Texture/texparticle' 'texparticle.FXH_T_toumingtu' '/evidence/天命西游/Resource/Texture/texparticle/FXH_T_toumingtu.qtx' \
  '/evidence/天命西游/Packages/editorui' 'editorui.ToolBoxHighLight' '/evidence/天命西游/Resource/Texture/editorui/ToolBoxHighLight.qtx'
EXPORTER=out/build/ci-linux-clang/TMXY.Texture/tmxy_qtx_export
"$EXPORTER" '/evidence/天命西游/Packages/Texture/texstone' 'texstone.WHZ_S_Dimian20_D' \
  '/evidence/天命西游/Resource/Texture/texstone/WHZ_S_Dimian20_D.qtx' '/tmp/qtx-export/sample' \
  > /tmp/qtx-export/stdout.json
cmp /tmp/qtx-export/sample.json /tmp/qtx-export/stdout.json
test "$(stat -c %s /tmp/qtx-export/sample.dds)" = '160'
test "$(stat -c %s /tmp/qtx-export/sample.tga)" = '274'
test "$(od -An -tx1 -N8 /tmp/qtx-export/sample.png | tr -d ' \n')" = '89504e470d0a1a0a'
grep -F '"format": {"value": 3, "name": "dxt1"}' /tmp/qtx-export/sample.json >/dev/null
grep -F '"alpha_coverage": "opaque"' /tmp/qtx-export/sample.json >/dev/null
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$workspaceRoot,target=/evidence,readonly",
    $builderReference, 'bash', '-c', $containerScript
)
$execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
$expectedOutput = @(
    'texstone.WHZ_S_Dimian20_D format=dxt1 size=8x8 mips=1 alpha=opaque dds_fnv=10879648251367638573 png_fnv=18285426521403921869 tga_fnv=3912029440869627911',
    'newscenc.dy_bx_xlys_01_D format=dxt5 size=4096x4096 mips=13 alpha=opaque dds_fnv=7182726370061829726 png_fnv=0 tga_fnv=0',
    'texparticle.FXH_T_toumingtu format=dxt5 size=16x16 mips=1 alpha=transparent dds_fnv=6768284568393444360 png_fnv=11225435358868736781 tga_fnv=4559013871301248807',
    'editorui.ToolBoxHighLight format=rgba8 size=512x512 mips=1 alpha=translucent dds_fnv=17865601572116883525 png_fnv=3340869983753852703 tga_fnv=9479884574790263331'
)
$passed = $execution.exit_code -eq 0 -and $execution.output -match '100% tests passed'
foreach ($line in $expectedOutput) { $passed = $passed -and $execution.output.Contains($line) }

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-13'
    completion_criteria_satisfied = $passed
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    contract = [pscustomobject][ordered]@{
        descriptor_source = 'Package QTexture QObject property body'
        qtx_payload = 'headerless contiguous mip bytes'
        formats = @('rgba8', 'rgba16f', 'r32f', 'dxt1', 'dxt1a', 'dxt3', 'dxt5')
        outputs = @('dds-lossless-all-mips', 'png-rgba8-mip0', 'tga-bgra8-mip0', 'json-metadata')
        alpha_fields = @('encoding', 'decoded_coverage')
    }
    samples = @(
        [pscustomobject]@{ object = 'texstone.WHZ_S_Dimian20_D'; format = 'dxt1'; width = 8; height = 8; mips = 1; alpha = 'opaque'; payload_size = 32 },
        [pscustomobject]@{ object = 'newscenc.dy_bx_xlys_01_D'; format = 'dxt5'; width = 4096; height = 4096; mips = 13; alpha = 'opaque'; payload_size = 22369648 },
        [pscustomobject]@{ object = 'texparticle.FXH_T_toumingtu'; format = 'dxt5'; width = 16; height = 16; mips = 1; alpha = 'transparent'; payload_size = 256 },
        [pscustomobject]@{ object = 'editorui.ToolBoxHighLight'; format = 'rgba8'; width = 512; height = 512; mips = 1; alpha = 'translucent'; payload_size = 1048576 }
    )
    evidence = $evidenceReport
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        evidence_mount = 'read-only'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_and_output_storage = 'ephemeral_tmpfs'
    }
    stages = @('clang-format-21', 'cmake-ninja-clang-21-werror', 'clang-tidy-21',
        'ctest-corrupt-boundary-determinism', 'four-real-package-qtx-pairs',
        'cli-dds-png-tga-json-signature')
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        output_line_count = @($execution.output -split "`n").Count
        output_sha256 = Get-TextSha256 -Value $execution.output
    }
}
$json = ($report | ConvertTo-Json -Depth 9).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw "P1-13 locked-builder validation failed: $($execution.output)" }
