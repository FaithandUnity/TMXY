[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-17-ter-terrain.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$workspaceRoot = [System.IO.Path]::GetDirectoryName($root)
$moduleRoot = Join-Path $root 'Tools\TMXY.Terrain'
$terrainRoot = Join-Path $workspaceRoot '天命西游\Resource\Terrain'
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
    'Tools/TMXY.Terrain/CMakeLists.txt',
    'Tools/TMXY.Terrain/README.md',
    'Tools/TMXY.Terrain/apps/ter_export_main.cpp',
    'Tools/TMXY.Terrain/include/tmxy/terrain/ter_reader.hpp',
    'Tools/TMXY.Terrain/include/tmxy/terrain/terrain_error.hpp',
    'Tools/TMXY.Terrain/include/tmxy/terrain/terrain_export.hpp',
    'Tools/TMXY.Terrain/include/tmxy/terrain/terrain_result.hpp',
    'Tools/TMXY.Terrain/include/tmxy/terrain/terrain_types.hpp',
    'Tools/TMXY.Terrain/src/ter_reader.cpp',
    'Tools/TMXY.Terrain/src/terrain_error.cpp',
    'Tools/TMXY.Terrain/src/terrain_export.cpp',
    'Tools/TMXY.Terrain/tests/CMakeLists.txt',
    'Tools/TMXY.Terrain/tests/ter_real_samples_test.cpp',
    'Tools/TMXY.Terrain/tests/terrain_parser_test.cpp',
    'Docs/Formats/TER-FORMAT.md',
    'Docs/ADR/ADR-014-ter-terrain-intermediate.md',
    'Tests/Contract/Test-TerTerrain.ps1'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-17 required file is missing: $relativePath"
    }
}

$evidence = @(
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QTerrain.cpp'; size = 69191; sha256 = '3b9a5de0d6c404d2cb5b94b56dbd6ab8a35b18afccc13deaa345a3371e4af8b4' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QTerrain.h'; size = 8188; sha256 = '1feba47e776ce3734d5dec8f3375907e7a41cce7eef279bf8c4c312176755252' },
    [pscustomobject]@{ path = 'ClientCode\Utility\Src\UtTerrainFactories.cpp'; size = 20630; sha256 = 'bdd6118bfab99311f87aae504f041f411d3e03622282ce6e13ee33fc2b00b139' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\EngineMath.h'; size = 18750; sha256 = '1e4fad6e97874c30815820fb8d87521bc1977c0f2a13a241cf92af3b93fa0538' },
    [pscustomobject]@{ path = '天命西游\Resource\Terrain\bqg2\bqg2_000_000.ter'; size = 147485; sha256 = '178fc8ca10974b55a75ac83c68c60e70414506938a964bd9ba0c38b35d93fd37' },
    [pscustomobject]@{ path = '天命西游\Resource\Terrain\zyhsz\zyhsz_015_015.ter'; size = 147501; sha256 = '3c4d9e7dc16845e1c21b9aecdb106cf6fef53f92cd11a41719e89d05262cf947' },
    [pscustomobject]@{ path = '天命西游\Resource\Terrain\world_001_001.ter'; size = 147501; sha256 = '233f5be2358d1fdc88ca872373d074eb67b48ca33c3c78708bc74290d0e061e7' },
    [pscustomobject]@{ path = '天命西游\Resource\Terrain\world_002_001.ter'; size = 147501; sha256 = '3f343db7478cdafb1828469acd74680a45a6fb2fab60f6e909ae4a80be8867b4' },
    [pscustomobject]@{ path = '天命西游\Resource\Terrain\world_001_002.ter'; size = 147501; sha256 = 'f14874bbb0a4a1ddcc709ae48f4913d6ba3bce8bc5c3bd5b0d06292a84893389' }
)
$evidenceReport = foreach ($item in $evidence) {
    $path = Join-Path $workspaceRoot $item.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P1-17 evidence is missing: $($item.path)"
    }
    $file = Get-Item -LiteralPath $path
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $item.size -or $actual -ne $item.sha256) {
        throw "P1-17 evidence changed: $($item.path)"
    }
    [pscustomobject][ordered]@{
        path = $item.path
        size = $file.Length
        sha256 = $actual
        passed = $true
    }
}

$terrainFiles = @(Get-ChildItem -LiteralPath $terrainRoot -Recurse -File -Filter '*.ter')
$sizeGroups = @($terrainFiles | Group-Object Length | Sort-Object { [int64]$_.Name } |
    ForEach-Object { [pscustomobject][ordered]@{ bytes = [int64]$_.Name; count = $_.Count } })
$expectedSizeGroups = @(
    '147485:29', '147489:36', '147493:112', '147497:345', '147501:8354'
)
$actualSizeGroups = @($sizeGroups | ForEach-Object { "$($_.bytes):$($_.count)" })
$terrainBytes = [int64]($terrainFiles | Measure-Object Length -Sum).Sum
if ($terrainFiles.Count -ne 8876 -or $terrainBytes -ne 1309215704 -or
    (Compare-Object $expectedSizeGroups $actualSizeGroups)) {
    throw 'P1-17 installed terrain corpus inventory changed.'
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx|CoreMinimal\.h)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($content -match $forbiddenPattern) {
        throw "P1-17 forbidden legacy/platform dependency found: $($file.FullName)"
    }
    if (@(Get-Content -LiteralPath $file.FullName -Encoding UTF8).Count -gt 1000) {
        throw "P1-17 source file exceeds hard 1000-line limit: $($file.FullName)"
    }
}

$hashFiles = [System.Collections.Generic.List[string]]::new()
foreach ($hashRoot in @('Tools/TMXY.FormatCore', 'Tools/TMXY.Terrain')) {
    Get-ChildItem -LiteralPath (Join-Path $root $hashRoot) -Recurse -File |
        Where-Object { $_.Extension -in @('.cpp', '.hpp') -or $_.Name -eq 'CMakeLists.txt' } |
        ForEach-Object {
            $hashFiles.Add([System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/'))
        }
}
foreach ($path in @('.clang-format', '.clang-tidy', 'Tools/CMakeLists.txt',
        'Tools/CMakePresets.json', 'Docs/Formats/TER-FORMAT.md',
        'Docs/ADR/ADR-014-ter-terrain-intermediate.md', 'Tests/Contract/Test-TerTerrain.ps1')) {
    $hashFiles.Add($path)
}
$hashLines = foreach ($relativePath in $hashFiles | Sort-Object -Unique) {
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
    throw 'P1-17 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/terrain-export
cp /workspace/.clang-format /tmp/tmxy-rebuild/
cp /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /tmp/tmxy-rebuild/Tools/
cp /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /tmp/tmxy-rebuild/Tools/
for module in TMXY.FormatCore TMXY.Terrain; do
  cp -a "/workspace/Tools/$module" /tmp/tmxy-rebuild/Tools/
done
cd /tmp/tmxy-rebuild/Tools
find TMXY.Terrain -type f -print0 | grep -zE '[.](cpp|hpp)$' | xargs -0 clang-format-21 --dry-run --Werror
cmake --preset ci-linux-clang -DTMXY_BUILD_PACKAGE=OFF -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TRANSFORM=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF
cmake --build --preset ci-linux-clang --target tmxy_terrain_parser_test tmxy_ter_real_samples_test tmxy_ter_export
find TMXY.Terrain -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --test-dir out/build/ci-linux-clang -R '^terrain[.]parser$' --output-on-failure
REAL_TEST=out/build/ci-linux-clang/TMXY.Terrain/tests/tmxy_ter_real_samples_test
"$REAL_TEST" '/evidence/天命西游/Resource/Terrain'
EXPORTER=out/build/ci-linux-clang/TMXY.Terrain/tmxy_ter_export
"$EXPORTER" '/evidence/天命西游/Resource/Terrain/world_001_001.ter' \
  '/tmp/terrain-export/world' > /tmp/terrain-export/stdout.json
cmp /tmp/terrain-export/world.json /tmp/terrain-export/stdout.json
grep -F '"edge_vertex_count": 64' /tmp/terrain-export/world.json >/dev/null
grep -F '"tile_count_per_axis": 63' /tmp/terrain-export/world.json >/dev/null
grep -F '"map_name": "world", "x": 1, "y": 1' /tmp/terrain-export/world.json >/dev/null
test "$(wc -c < /tmp/terrain-export/world.height.f32le)" -eq 16384
test "$(wc -c < /tmp/terrain-export/world.layers.rgba8)" -eq 16384
test "$(wc -l < /tmp/terrain-export/world.edges.csv)" -eq 257
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
    'TERRAIN_SAMPLE result=PASS name=bqg2_000_000.ter bytes=147485 vertices=4096 edge=64 tiles=63 layers=4 water=1 color=0 min=50 max=50 json_fnv=17639934814673212859 height_fnv=8514296656032408357 layer_fnv=10596818350380000037 edge_fnv=17560127726405711754',
    'TERRAIN_SAMPLE result=PASS name=zyhsz_015_015.ter bytes=147501 vertices=4096 edge=64 tiles=63 layers=4 water=1 color=1 min=0 max=0 json_fnv=12620290506198056086 height_fnv=11248824735641314085 layer_fnv=10596818350380000037 edge_fnv=16928986208558536282',
    'TERRAIN_SAMPLE result=PASS name=world_001_001.ter bytes=147501 vertices=4096 edge=64 tiles=63 layers=4 water=0 color=1 min=-15.9555 max=26.6885 json_fnv=17591700090707867230 height_fnv=17368412191409383455 layer_fnv=1961755361218945919 edge_fnv=8241279424783832823',
    'TERRAIN_ADJACENCY result=PASS base=world_001_001.ter right_different=16 right_max_delta=0.0320091248 bottom_different=10 bottom_max_delta=0.00478887558'
)
$passed = $execution.exit_code -eq 0 -and $execution.output -match '100% tests passed'
foreach ($line in $expectedOutput) { $passed = $passed -and $execution.output.Contains($line) }

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-17'
    completion_criteria_satisfied = $passed
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    contract = [pscustomobject][ordered]@{
        vertex = 'height f32 + normal xyz f32 + color rgba f32 + four layer-alpha u8'
        grid = 'row-major square grid; installed files are 64x64 vertices and 63x63 cells'
        tail = 'water bool/height + zero-to-four ordered package layer references + optional color'
        edge_order = @('top-x-increasing', 'right-y-increasing', 'bottom-x-increasing', 'left-y-increasing')
        scale = 'source units retained; level zone size is required for physical scale'
        outputs = @('json-summary', 'f32le-height-plane', 'rgba8-layer-alpha', 'csv-complete-edges')
    }
    corpus = [pscustomobject][ordered]@{
        file_count = $terrainFiles.Count
        total_bytes = $terrainBytes
        size_distribution = $sizeGroups
    }
    samples = @(
        [pscustomobject]@{ path = 'bqg2/bqg2_000_000.ter'; bytes = 147485; role = 'global-minimum-no-water-color' },
        [pscustomobject]@{ path = 'zyhsz/zyhsz_015_015.ter'; bytes = 147501; role = 'global-maximum-with-water-color' },
        [pscustomobject]@{ path = 'world_001_001.ter'; bytes = 147501; role = 'non-flat-adjacency-base' },
        [pscustomobject]@{ path = 'world_002_001.ter'; bytes = 147501; role = 'right-neighbor' },
        [pscustomobject]@{ path = 'world_001_002.ter'; bytes = 147501; role = 'bottom-neighbor' }
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
        'ctest-corrupt-boundary-determinism', 'five-real-terrain-samples',
        'non-flat-adjacency-diagnostic', 'cli-four-output-signature')
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
if (-not $passed) { throw "P1-17 locked-builder validation failed: $($execution.output)" }
