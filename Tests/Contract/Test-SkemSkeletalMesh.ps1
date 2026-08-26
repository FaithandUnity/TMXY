[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-15-skem-skeletal-mesh.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$workspaceRoot = [System.IO.Path]::GetDirectoryName($root)
$moduleRoot = Join-Path $root 'Tools\TMXY.SkeletalMesh'
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
    'Tools/TMXY.SkeletalMesh/CMakeLists.txt',
    'Tools/TMXY.SkeletalMesh/README.md',
    'Tools/TMXY.SkeletalMesh/apps/skem_export_main.cpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/skem_reader.hpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/skeletal_mesh_error.hpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/skeletal_mesh_export.hpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/skeletal_mesh_gltf.hpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/skeletal_mesh_result.hpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/skeletal_mesh_types.hpp',
    'Tools/TMXY.SkeletalMesh/src/package_skeletal_mesh_reader.cpp',
    'Tools/TMXY.SkeletalMesh/src/skem_reader.cpp',
    'Tools/TMXY.SkeletalMesh/src/skeletal_mesh_binding.cpp',
    'Tools/TMXY.SkeletalMesh/src/skeletal_mesh_error.cpp',
    'Tools/TMXY.SkeletalMesh/src/skeletal_mesh_export.cpp',
    'Tools/TMXY.SkeletalMesh/src/skeletal_mesh_gltf.cpp',
    'Tools/TMXY.SkeletalMesh/src/skeletal_mesh_gltf_internal.hpp',
    'Tools/TMXY.SkeletalMesh/src/skeletal_mesh_gltf_json.cpp',
    'Tools/TMXY.SkeletalMesh/tests/CMakeLists.txt',
    'Tools/TMXY.SkeletalMesh/tests/skem_real_samples_test.cpp',
    'Tools/TMXY.SkeletalMesh/tests/skeletal_mesh_parser_test.cpp',
    'Docs/Formats/SKEM-FORMAT.md',
    'Docs/ADR/ADR-006-skem-skeletal-mesh-intermediate.md',
    'Tests/Contract/Test-SkemSkeletalMesh.ps1'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-15 required file is missing: $relativePath"
    }
}

$evidence = @(
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QSkelMesh.cpp'; size = 80302; sha256 = 'd4d00eb79f7c30123df02e9105f7335fac4533c146957a429ba9ad84c108e5f7' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QSkelMesh.h'; size = 18771; sha256 = 'd7b44a3e7160f37a297f7c428d483300d9900f0cb0f0c8140d97aa3af3a8c7ae' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QGeom.h'; size = 6649; sha256 = '91500167970a758df9c22e242477c5db62c4feb99a538dbe1599e49de718b965' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QVector.h'; size = 9985; sha256 = '66658ec9df40c3bef90e509001dfb100b413c5e9b7d332f6a7f56f0872bf7925' },
    [pscustomobject]@{ path = 'ClientCode\Base\Hdr\QArray.h'; size = 12657; sha256 = '831485b5d3392f57c6cb9a832362eb4566111e03b3b9de8225e6f0a09788617a' },
    [pscustomobject]@{ path = 'ClientCode\Base\Hdr\QPString.h'; size = 1837; sha256 = '6374e1a01b82af150d5f94e9974f5d6f8d169cf309c683f980a101776d678b8d' },
    [pscustomobject]@{ path = 'ClientCode\Base\Src\QArchive.cpp'; size = 2242; sha256 = '8fe0cccd38d4876dbf261c30277e8b954ebe9a85ff69f217581397987ad498e8' },
    [pscustomobject]@{ path = 'ClientCode\Base\Src\QProperty.cpp'; size = 17859; sha256 = 'b92a93ba136e1de845b5c5f6d385fad3904db202b7396f213a3749a2e4584a57' },
    [pscustomobject]@{ path = 'ClientCode\Utility\Src\UtSkinMeshFactories.cpp'; size = 44007; sha256 = '5fc2cdb7a481366a8fac04bbbc1a2d56b306ccfc86198c2004124c469165a741' },
    [pscustomobject]@{ path = '天命西游\Packages\SkelMesh\skchar'; size = 281615; sha256 = '0867a016dd0b2a75a35d453ffe2242ffeb5329d003de61ba9b121dcebdba10e7' },
    [pscustomobject]@{ path = '天命西游\Resource\SkelMesh\particle\FXH_O_S_shizuo.skem'; size = 477; sha256 = 'a755d7c0a706895725b53d9ea0289fe42600841dd8ba725fae86f8c5034912d5' },
    [pscustomobject]@{ path = '天命西游\Resource\SkelMesh\skchar\Boy01.skem'; size = 95700140; sha256 = '409fedf015ae3949222241cd8d7cc1aea22bb6ef689b2cc0190a796fe7cf93b6' },
    [pscustomobject]@{ path = '天命西游\Resource\SkelMesh\skchar\Girl01.skem'; size = 115909244; sha256 = '6ada6140d6a615ba1e18b2e236548ed67972d81ab948d4884e20af77913606d9' }
)
$evidenceReport = foreach ($item in $evidence) {
    $path = Join-Path $workspaceRoot $item.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P1-15 evidence is missing: $($item.path)"
    }
    $file = Get-Item -LiteralPath $path
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $item.size -or $actual -ne $item.sha256) {
        throw "P1-15 evidence changed: $($item.path)"
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
        throw "P1-15 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}

$hashRoots = @(
    'Tools/TMXY.FormatCore',
    'Tools/TMXY.Package',
    'Tools/TMXY.Transform',
    'Tools/TMXY.SkeletalMesh'
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
        'Tools/CMakePresets.json', 'Docs/Formats/SKEM-FORMAT.md',
        'Docs/ADR/ADR-006-skem-skeletal-mesh-intermediate.md',
        'Tests/Contract/Test-SkemSkeletalMesh.ps1')) {
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
    throw 'P1-15 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/skem-export
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
find TMXY.SkeletalMesh -type f -print0 | grep -zE '[.](cpp|hpp)$' | xargs -0 clang-format-21 --dry-run --Werror
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang --target tmxy_skeletal_mesh_parser_test tmxy_skem_real_samples_test tmxy_skem_export
find TMXY.SkeletalMesh -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --test-dir out/build/ci-linux-clang -R '^skeletal_mesh[.]' --output-on-failure
REAL_TEST=out/build/ci-linux-clang/TMXY.SkeletalMesh/tests/tmxy_skem_real_samples_test
"$REAL_TEST" '/evidence/天命西游/Packages' '/evidence/天命西游/Resource/SkelMesh'
EXPORTER=out/build/ci-linux-clang/TMXY.SkeletalMesh/tmxy_skem_export
"$EXPORTER" '/evidence/天命西游/Packages/SkelMesh/skchar' 'skchar.Boy01' \
  '/evidence/天命西游/Resource/SkelMesh/skchar/Boy01.skem' \
  '/tmp/skem-export/boy' > /tmp/skem-export/stdout.json
cmp /tmp/skem-export/boy.json /tmp/skem-export/stdout.json
test "$(grep -c '^v ' /tmp/skem-export/boy.obj)" -gt 0
test "$(grep -c '^f ' /tmp/skem-export/boy.obj)" -gt 0
test -s /tmp/skem-export/boy.gltf
test -s /tmp/skem-export/boy.bin
grep -F '# coordinates: Unreal X-forward/Y-right/Z-up centimeters' /tmp/skem-export/boy.obj >/dev/null
grep -F '"bone_count": 80' /tmp/skem-export/boy.json >/dev/null
grep -F '"legacy_unweighted_sentinel_vertex_count": 0' /tmp/skem-export/boy.json >/dev/null
grep -F 'legacy runtime resolves attachments by bone name' /tmp/skem-export/boy.json >/dev/null
grep -F '"JOINTS_0": 3, "WEIGHTS_0": 4' /tmp/skem-export/boy.gltf >/dev/null
grep -F '"inverseBindMatrices": 5' /tmp/skem-export/boy.gltf >/dev/null
grep -F '"tmxyAssetKind": "skeletal_mesh"' /tmp/skem-export/boy.gltf >/dev/null
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
    'PAYLOAD name=minimum groups=1 submeshes=1 vertices=4 indices=6 triangles=2 shadow_indices=0',
    'BOUND result=PASS object=skchar.Boy01 groups=12 submeshes=1620 vertices=842929 indices=2944338 bones=80 roots=1 anim_refs=272 defaults=12 json_fnv=15247003949501018541 obj_fnv=5471625972164385819',
    'BOUND result=PASS object=skchar.Girl01 groups=12 submeshes=1806 vertices=1014104 indices=3668820 bones=80 roots=1 anim_refs=270 defaults=12 json_fnv=1574790148036450785 obj_fnv=7828294081594915180'
)
$passed = $execution.exit_code -eq 0 -and $execution.output -match '100% tests passed'
foreach ($line in $expectedOutput) { $passed = $passed -and $execution.output.Contains($line) }

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-15'
    completion_criteria_satisfied = $passed
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    contract = [pscustomobject][ordered]@{
        descriptor_source = 'Package QSkelMesh QObject property body'
        skem_payload = 'headerless grouped selectable submesh arrays'
        bone_index_encoding = 'integral float32; zero means unused; positive values are one-based'
        bind_pose = 'validated local quaternion and translation per bone'
        attachment_points = 'validated bone-name candidates; no distinct legacy socket record'
        outputs = @('gltf-2.0-json-external-bin-default-selection-authority',
            'obj-default-selection-ue-centimeter-preview', 'json-skeleton-weight-metadata')
        legacy_weight_exception = 'exact all-minus-one weights plus all-zero bone indices only'
    }
    samples = @(
        [pscustomobject]@{ object = 'particle.FXH_O_S_shizuo'; groups = 1; submeshes = 1; vertices = 4; indices = 6; role = 'global-minimum-payload-only' },
        [pscustomobject]@{ object = 'skchar.Boy01'; groups = 12; submeshes = 1620; vertices = 842929; indices = 2944338; bones = 80; sentinel_vertices = 0; role = 'canonical-player' },
        [pscustomobject]@{ object = 'skchar.Girl01'; groups = 12; submeshes = 1806; vertices = 1014104; indices = 3668820; bones = 80; sentinel_vertices = 2; role = 'global-maximum-and-sentinel-boundary' }
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
        'ctest-corrupt-boundary-determinism', 'minimum-plus-two-real-package-skem-pairs',
        'cli-default-obj-json-signature')
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
if (-not $passed) { throw "P1-15 locked-builder validation failed: $($execution.output)" }
