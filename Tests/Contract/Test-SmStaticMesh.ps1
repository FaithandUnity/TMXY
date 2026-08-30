[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-14-sm-static-mesh.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$workspaceRoot = [System.IO.Path]::GetDirectoryName($root)
$moduleRoot = Join-Path $root 'Tools\TMXY.StaticMesh'
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
    'Tools/TMXY.StaticMesh/CMakeLists.txt',
    'Tools/TMXY.StaticMesh/README.md',
    'Tools/TMXY.StaticMesh/apps/sm_export_main.cpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/package_static_mesh_reader.hpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/sm_reader.hpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_error.hpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_export.hpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_gltf.hpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_result.hpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_types.hpp',
    'Tools/TMXY.StaticMesh/src/package_static_mesh_reader.cpp',
    'Tools/TMXY.StaticMesh/src/sm_reader.cpp',
    'Tools/TMXY.StaticMesh/src/static_mesh_error.cpp',
    'Tools/TMXY.StaticMesh/src/static_mesh_export.cpp',
    'Tools/TMXY.StaticMesh/src/static_mesh_gltf.cpp',
    'Tools/TMXY.StaticMesh/tests/CMakeLists.txt',
    'Tools/TMXY.StaticMesh/tests/sm_real_samples_test.cpp',
    'Tools/TMXY.StaticMesh/tests/static_mesh_parser_test.cpp',
    'Tools/TMXY.StaticMesh/tests/static_mesh_gltf_test.cpp',
    'Docs/Formats/SM-FORMAT.md',
    'Docs/ADR/ADR-005-sm-static-mesh-intermediate.md',
    'Tests/Contract/Test-SmStaticMesh.ps1'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-14 required file is missing: $relativePath"
    }
}

$evidence = @(
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QStaticMesh.cpp'; size = 51870; sha256 = '5462960f3c022539d00738f0a8c24bc43dcd955e2bf45018e0bba5a8a23648f4' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QGeom.h'; size = 6649; sha256 = '91500167970a758df9c22e242477c5db62c4feb99a538dbe1599e49de718b965' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QVector.h'; size = 9985; sha256 = '66658ec9df40c3bef90e509001dfb100b413c5e9b7d332f6a7f56f0872bf7925' },
    [pscustomobject]@{ path = 'ClientCode\Base\Hdr\QArray.h'; size = 12657; sha256 = '831485b5d3392f57c6cb9a832362eb4566111e03b3b9de8225e6f0a09788617a' },
    [pscustomobject]@{ path = 'ClientCode\Base\Src\QArchive.cpp'; size = 2242; sha256 = '8fe0cccd38d4876dbf261c30277e8b954ebe9a85ff69f217581397987ad498e8' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QRenderTypes.cpp'; size = 16776; sha256 = 'b276b91ba85256a91d38a894c786e9ebd2a4f4035a812b333fb4405f0bebff50' },
    [pscustomobject]@{ path = 'ClientCode\Utility\Src\UtStaticMeshFactories.cpp'; size = 46138; sha256 = 'c3d2ef7d2749c3f2b2a97d3eaab11aa9cf890709855428651c217e25d1e06cdb' },
    [pscustomobject]@{ path = '天命西游\Packages\particle'; size = 3435518; sha256 = '2e74819ee5eb665b5298710c06ea73de5016909535dee0ad388b7c194c6bd3b9' },
    [pscustomobject]@{ path = '天命西游\Packages\newscenc'; size = 43554; sha256 = '79bf6e339149b9a37535d6d5c92e5a4c09b5737072be1ac9fe21681630f8d433' },
    [pscustomobject]@{ path = '天命西游\Packages\StaticMesh\scene09'; size = 215837; sha256 = '481f0d93560eaabed09db7e2c71b35d5b0b757903378cb4c42c9d8f1beb5bd2c' },
    [pscustomobject]@{ path = '天命西游\Resource\StaticMesh\particle\ZFH_O_S_Tianpian100.sm'; size = 309; sha256 = '79669d7fbc5d3ebbfa82c6f3075c39b512d7ea021adf2d749b596d6e82dd81e8' },
    [pscustomobject]@{ path = '天命西游\Resource\StaticMesh\newscenc\dy_bx_stl_005.sm'; size = 13165223; sha256 = 'b0d788088736c00697c3e1b36d0b49044506cf14844a957cbd225f7c4886e242' },
    [pscustomobject]@{ path = '天命西游\Resource\StaticMesh\newscenc\dy_bx_bqg_006.sm'; size = 12185471; sha256 = 'b5189a2daf0daa16fae12ad0fa6c308981ec28d7ba0094cf24dc032a066870c1' },
    [pscustomobject]@{ path = '天命西游\Resource\StaticMesh\scene09\GT_B_S_BangPai05.sm'; size = 966853; sha256 = 'c72bbcde94f51f8b8f8d8c9fc5800fbd2ca0356bdc6efec441cae6ce9a5260a8' }
)
$evidenceReport = foreach ($item in $evidence) {
    $path = Join-Path $workspaceRoot $item.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P1-14 evidence is missing: $($item.path)"
    }
    $file = Get-Item -LiteralPath $path
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $item.size -or $actual -ne $item.sha256) {
        throw "P1-14 evidence changed: $($item.path)"
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
        throw "P1-14 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}

$hashRoots = @(
    'Tools/TMXY.FormatCore',
    'Tools/TMXY.Package',
    'Tools/TMXY.Transform',
    'Tools/TMXY.StaticMesh'
)
$hashFiles = [System.Collections.Generic.List[string]]::new()
foreach ($hashRoot in $hashRoots) {
    Get-ChildItem -LiteralPath (Join-Path $root $hashRoot) -Recurse -File |
        Where-Object { $_.Extension -in @('.cpp', '.hpp') -or $_.Name -eq 'CMakeLists.txt' } |
        ForEach-Object {
            $hashFiles.Add([System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/'))
        }
}
foreach ($path in @('.clang-format', '.clang-tidy', 'Tools/CMakeLists.txt',
        'Tools/CMakePresets.json', 'Docs/Formats/SM-FORMAT.md',
        'Docs/ADR/ADR-005-sm-static-mesh-intermediate.md',
        'Tests/Contract/Test-SmStaticMesh.ps1')) {
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
    throw 'P1-14 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/sm-export
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
find TMXY.StaticMesh -type f -print0 | grep -zE '[.](cpp|hpp)$' | xargs -0 clang-format-21 --dry-run --Werror
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang --target tmxy_static_mesh_parser_test tmxy_static_mesh_gltf_test tmxy_sm_real_samples_test tmxy_sm_export
find TMXY.StaticMesh -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --test-dir out/build/ci-linux-clang -R '^static_mesh[.]' --output-on-failure
REAL_TEST=out/build/ci-linux-clang/TMXY.StaticMesh/tests/tmxy_sm_real_samples_test
"$REAL_TEST" \
  '/evidence/天命西游/Packages/particle' 'particle.ZFH_O_S_Tianpian100' '/evidence/天命西游/Resource/StaticMesh/particle/ZFH_O_S_Tianpian100.sm' \
  '/evidence/天命西游/Packages/newscenc' 'newscenc.dy_bx_stl_005' '/evidence/天命西游/Resource/StaticMesh/newscenc/dy_bx_stl_005.sm' \
  '/evidence/天命西游/Packages/newscenc' 'newscenc.dy_bx_bqg_006' '/evidence/天命西游/Resource/StaticMesh/newscenc/dy_bx_bqg_006.sm' \
  '/evidence/天命西游/Packages/StaticMesh/scene09' 'scene09.GT_B_S_BangPai05' '/evidence/天命西游/Resource/StaticMesh/scene09/GT_B_S_BangPai05.sm'
EXPORTER=out/build/ci-linux-clang/TMXY.StaticMesh/tmxy_sm_export
"$EXPORTER" '/evidence/天命西游/Packages/particle' 'particle.ZFH_O_S_Tianpian100' \
  '/evidence/天命西游/Resource/StaticMesh/particle/ZFH_O_S_Tianpian100.sm' \
  '/tmp/sm-export/sample' > /tmp/sm-export/stdout.json
cmp /tmp/sm-export/sample.json /tmp/sm-export/stdout.json
test "$(grep -c '^v ' /tmp/sm-export/sample.obj)" = '4'
test "$(grep -c '^f ' /tmp/sm-export/sample.obj)" = '2'
grep -F '# coordinates: Unreal X-forward/Y-right/Z-up centimeters' /tmp/sm-export/sample.obj >/dev/null
grep -F '"declared_bounds_relation": "contains"' /tmp/sm-export/sample.json >/dev/null
grep -F '"coordinate_contract": "legacy-runtime-x-forward-y-right-z-up-meters"' /tmp/sm-export/sample.json >/dev/null
test -s /tmp/sm-export/sample.gltf
test -s /tmp/sm-export/sample.bin
grep -F '"version": "2.0"' /tmp/sm-export/sample.gltf >/dev/null
grep -F '"uri": "sample.bin"' /tmp/sm-export/sample.gltf >/dev/null
grep -F '"tmxyCoordinateMapping": "legacy(x,y,z)-to-gltf(y,z,x)"' /tmp/sm-export/sample.gltf >/dev/null
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=2g',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$workspaceRoot,target=/evidence,readonly",
    $builderReference, 'bash', '-c', $containerScript
)
$execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
$expectedOutput = @(
    'particle.ZFH_O_S_Tianpian100 vertices=4 indices=6 sections=1 uv_channels=1 shadow_vertices=0 shadow_indices=0 collision_vertices=0 octree_nodes=0 octree_indices=0 declared_bounds=contains bounds=-17.5672302,-17.2778435,-4.68960619:-14.7323551,14.307416,19.1825714 json_fnv=13026901066817879978 obj_fnv=7919486951111466039',
    'newscenc.dy_bx_stl_005 vertices=157638 indices=157638 sections=1 uv_channels=2 shadow_vertices=74907 shadow_indices=366357 collision_vertices=0 octree_nodes=11 octree_indices=114924 declared_bounds=contains bounds=-100.774826,-3.03948212,2.30944395:10.8779144,317.66629,5.70774889 json_fnv=5344752217521232092 obj_fnv=0',
    'newscenc.dy_bx_bqg_006 vertices=47964 indices=250614 sections=1 uv_channels=2 shadow_vertices=250614 shadow_indices=1002456 collision_vertices=0 octree_nodes=194 octree_indices=291201 declared_bounds=mismatch bounds=-150.552399,-173.027374,-71.6268158:289.874359,217.916229,109.383087 json_fnv=7825768401660102655 obj_fnv=0',
    'scene09.GT_B_S_BangPai05 vertices=11847 indices=19533 sections=43 uv_channels=2 shadow_vertices=0 shadow_indices=0 collision_vertices=6416 octree_nodes=340 octree_indices=23379 declared_bounds=exact bounds=-37.4604683,-42.9401703,-8.96472454:37.3805618,42.9401779,8.96472931 json_fnv=6463187087661512439 obj_fnv=0'
)
$passed = $execution.exit_code -eq 0 -and $execution.output -match '100% tests passed'
foreach ($line in $expectedOutput) { $passed = $passed -and $execution.output.Contains($line) }

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-14'
    completion_criteria_satisfied = $passed
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    contract = [pscustomobject][ordered]@{
        descriptor_source = 'Package QStaticMesh QObject property body'
        sm_payload = 'headerless ordered runtime arrays'
        coordinate_source = 'legacy-runtime-x-forward-y-right-z-up-meters'
        outputs = @('obj-ue-centimeter-preview', 'json-metadata',
            'gltf-2.0-json-authoritative', 'gltf-2.0-external-bin-authoritative')
        bounds_relations = @('absent', 'exact', 'contains', 'mismatch')
        material_slot_bases = @('package_descriptor', 'payload_section_prefix_contract')
        strict_material_slot_rule = 'non-zero exact Package slots to payload sections'
        explicit_prefix_rule = 'exact or Package slots greater than non-zero payload sections'
        material_synthesis = $false
        octree_rule = 'face ranges are authoritative for leaf nodes only'
    }
    samples = @(
        [pscustomobject]@{ object = 'particle.ZFH_O_S_Tianpian100'; vertices = 4; indices = 6; sections = 1; role = 'minimum' },
        [pscustomobject]@{ object = 'newscenc.dy_bx_stl_005'; vertices = 157638; indices = 157638; sections = 1; role = 'largest-file-and-uv1' },
        [pscustomobject]@{ object = 'newscenc.dy_bx_bqg_006'; vertices = 47964; indices = 250614; sections = 1; role = 'shadow-and-stale-bounds' },
        [pscustomobject]@{ object = 'scene09.GT_B_S_BangPai05'; vertices = 11847; indices = 19533; sections = 43; role = 'multisection-and-collision' }
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
        'ctest-corrupt-boundary-determinism', 'four-real-package-sm-pairs',
        'cli-obj-json-gltf-bin-signature')
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
if (-not $passed) { throw "P1-14 locked-builder validation failed: $($execution.output)" }
