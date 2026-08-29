[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-16-anim-animation.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$workspaceRoot = [System.IO.Path]::GetDirectoryName($root)
$moduleRoot = Join-Path $root 'Tools\TMXY.Animation'
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
    'Tools/TMXY.Animation/CMakeLists.txt',
    'Tools/TMXY.Animation/README.md',
    'Tools/TMXY.Animation/apps/anim_export_main.cpp',
    'Tools/TMXY.Animation/include/tmxy/animation/anim_reader.hpp',
    'Tools/TMXY.Animation/include/tmxy/animation/animation_error.hpp',
    'Tools/TMXY.Animation/include/tmxy/animation/animation_export.hpp',
    'Tools/TMXY.Animation/include/tmxy/animation/animation_result.hpp',
    'Tools/TMXY.Animation/include/tmxy/animation/animation_types.hpp',
    'Tools/TMXY.Animation/include/tmxy/animation/package_animation_reader.hpp',
    'Tools/TMXY.Animation/src/anim_reader.cpp',
    'Tools/TMXY.Animation/src/animation_error.cpp',
    'Tools/TMXY.Animation/src/animation_export.cpp',
    'Tools/TMXY.Animation/src/package_animation_reader.cpp',
    'Tools/TMXY.Animation/src/package_object_index.cpp',
    'Tools/TMXY.Animation/src/package_object_index.hpp',
    'Tools/TMXY.Animation/tests/CMakeLists.txt',
    'Tools/TMXY.Animation/tests/anim_real_samples_test.cpp',
    'Tools/TMXY.Animation/tests/animation_parser_test.cpp',
    'Docs/Formats/ANIM-FORMAT.md',
    'Docs/ADR/ADR-007-anim-animation-intermediate.md',
    'Tests/Contract/Test-AnimAnimation.ps1'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-16 required file is missing: $relativePath"
    }
}

$evidence = @(
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QSkelMesh.cpp'; size = 80302; sha256 = 'd4d00eb79f7c30123df02e9105f7335fac4533c146957a429ba9ad84c108e5f7' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QSkelMesh.h'; size = 18771; sha256 = 'd7b44a3e7160f37a297f7c428d483300d9900f0cb0f0c8140d97aa3af3a8c7ae' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QAnimNotify.cpp'; size = 863; sha256 = 'ee1f2f1f0b4ca8f2b1f15df235d7d5eabbeeb0d1d8dd0cde44fc4d562222f5e4' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QAnimNotify.h'; size = 961; sha256 = 'c2a9d24f3394b9dc21e014e6365268ad4f5c65db15b8b08b2c10f6ae7411c4ca' },
    [pscustomobject]@{ path = 'ClientCode\Base\Src\QArchive.cpp'; size = 2242; sha256 = '8fe0cccd38d4876dbf261c30277e8b954ebe9a85ff69f217581397987ad498e8' },
    [pscustomobject]@{ path = 'ClientCode\Base\Src\QProperty.cpp'; size = 17859; sha256 = 'b92a93ba136e1de845b5c5f6d385fad3904db202b7396f213a3749a2e4584a57' },
    [pscustomobject]@{ path = 'ClientCode\Utility\Src\UtSkinMeshFactories.cpp'; size = 44007; sha256 = '5fc2cdb7a481366a8fac04bbbc1a2d56b306ccfc86198c2004124c469165a741' },
    [pscustomobject]@{ path = '天命西游\Packages\SkelMesh\skchar'; size = 281615; sha256 = '0867a016dd0b2a75a35d453ffe2242ffeb5329d003de61ba9b121dcebdba10e7' },
    [pscustomobject]@{ path = '天命西游\Resource\SkelMesh\particle\ZFH_B_S_XALGF001.anim'; size = 4; sha256 = 'df3f619804a92fdb4057192dc43dd748ea778adc52bc498ce80524c014b81119' },
    [pscustomobject]@{ path = '天命西游\Resource\SkelMesh\skchar\Boy01.anim'; size = 32855816; sha256 = '912c7e13632082fdc457b148ebb8bd7ca4757a619da2bb6ad17b57acbc3afe3e' },
    [pscustomobject]@{ path = '天命西游\Resource\SkelMesh\skchar\Girl01.anim'; size = 33275128; sha256 = '524f612bff80de06ce92ebb558ecf4d783cdb84e097dd708aed64f7f8524c257' }
)
$evidenceReport = foreach ($item in $evidence) {
    $path = Join-Path $workspaceRoot $item.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P1-16 evidence is missing: $($item.path)"
    }
    $file = Get-Item -LiteralPath $path
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $item.size -or $actual -ne $item.sha256) {
        throw "P1-16 evidence changed: $($item.path)"
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
        throw "P1-16 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}

$hashRoots = @(
    'Tools/TMXY.FormatCore',
    'Tools/TMXY.Package',
    'Tools/TMXY.Transform',
    'Tools/TMXY.SkeletalMesh',
    'Tools/TMXY.Animation'
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
        'Tools/CMakePresets.json', 'Docs/Formats/ANIM-FORMAT.md',
        'Docs/ADR/ADR-007-anim-animation-intermediate.md',
        'Tests/Contract/Test-AnimAnimation.ps1')) {
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
    throw 'P1-16 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/anim-export
cp /workspace/.clang-format /tmp/tmxy-rebuild/
cp /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /tmp/tmxy-rebuild/Tools/
cp /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /tmp/tmxy-rebuild/Tools/
for module in TMXY.FormatCore TMXY.Package TMXY.Transform TMXY.SkeletalMesh TMXY.Animation; do
  cp -a "/workspace/Tools/$module" /tmp/tmxy-rebuild/Tools/
done
cd /tmp/tmxy-rebuild/Tools
find TMXY.Animation -type f -print0 | grep -zE '[.](cpp|hpp)$' | xargs -0 clang-format-21 --dry-run --Werror
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang --target tmxy_animation_parser_test tmxy_anim_real_samples_test tmxy_anim_export
find TMXY.Animation -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --test-dir out/build/ci-linux-clang -R '^animation[.]parser$' --output-on-failure
REAL_TEST=out/build/ci-linux-clang/TMXY.Animation/tests/tmxy_anim_real_samples_test
"$REAL_TEST" '/evidence/天命西游/Packages' '/evidence/天命西游/Resource/SkelMesh'
EXPORTER=out/build/ci-linux-clang/TMXY.Animation/tmxy_anim_export
"$EXPORTER" '/evidence/天命西游/Packages/SkelMesh/skchar' 'skchar.Boy01' \
  '/evidence/天命西游/Resource/SkelMesh/skchar/Boy01.anim' \
  '/tmp/anim-export/boy' > /tmp/anim-export/stdout.json
cmp /tmp/anim-export/boy.json /tmp/anim-export/stdout.json
grep -F '"animation_count": 272' /tmp/anim-export/boy.json >/dev/null
grep -F '"total_key_count": 1173344' /tmp/anim-export/boy.json >/dev/null
grep -F '"root_motion_policy": "measured root bone track; not extracted or removed"' /tmp/anim-export/boy.json >/dev/null
test "$(wc -l < /tmp/anim-export/boy.root-motion.csv)" -gt 1
grep -F 'clip_index,animation_name,frame,time_seconds' /tmp/anim-export/boy.root-motion.csv >/dev/null
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
    'MINIMUM_ANIM result=PASS bytes=4 clips=0',
    'BOUND_ANIM result=PASS object=skchar.Boy01 clips=272 tracks=21702 keys=1173344 frames_min=12 frames_max=250 tracks_min=22 tracks_max=80 loops=0 moving=261 notify_refs=80 max_root_excursion_m=2.66504 emitters=0 json_fnv=4099007401523946227 csv_fnv=14896642631070048600',
    'BOUND_ANIM result=PASS object=skchar.Girl01 clips=270 tracks=21600 keys=1188320 frames_min=11 frames_max=341 tracks_min=80 tracks_max=80 loops=0 moving=254 notify_refs=80 max_root_excursion_m=2.27806 emitters=0 json_fnv=12404515761744622130 csv_fnv=12537756524220434413'
)
$passed = $execution.exit_code -eq 0 -and $execution.output -match '100% tests passed'
foreach ($line in $expectedOutput) { $passed = $passed -and $execution.output.Contains($line) }
$verifiedOutput = (@('100% tests passed') + $expectedOutput) -join "`n"
$executionSha = Get-TextSha256 -Value ($verifiedOutput + "`n")
$capturedUtc = [DateTimeOffset]::UtcNow.ToString('o')
if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
    $prior = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -DateKind String
    if ([string]$prior.source_sha256 -ceq $sourceSha -and
        [string]$prior.execution.output_sha256 -ceq $executionSha -and
        [string]$prior.result -ceq $(if ($passed) { 'PASS' } else { 'FAIL' }) -and
        [string]$prior.captured_utc -match '^\d{4}-\d{2}-\d{2}T') {
        $capturedUtc = [string]$prior.captured_utc
    }
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = $capturedUtc
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-16'
    completion_criteria_satisfied = $passed
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    contract = [pscustomobject][ordered]@{
        descriptor_source = 'ordered Package QSkelMesh references and QSkelAnim property bodies'
        payload = 'headerless bone-major then frame-major QAnim key stream'
        track_identity = 'dense zero-based skeleton prefix; partial tails are valid'
        key_encoding = 'float32 quaternion xyzw plus local translation xyz'
        duration = 'sampled=(frames-1)*delta; legacy loop period honors selfLoop duplicate terminal key'
        root_motion = 'measured root track; no extraction or mutation'
        outputs = @('json-animation-summary', 'csv-complete-root-track')
    }
    samples = @(
        [pscustomobject]@{ path = 'particle/ZFH_B_S_XALGF001.anim'; bytes = 4; clips = 0; role = 'global-minimum' },
        [pscustomobject]@{ object = 'skchar.Boy01'; clips = 272; tracks = 21702; keys = 1173344; moving = 261; role = 'partial-track-prefix' },
        [pscustomobject]@{ object = 'skchar.Girl01'; clips = 270; tracks = 21600; keys = 1188320; moving = 254; role = 'canonical-full-track' }
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
        'ctest-corrupt-boundary-determinism', 'minimum-plus-two-real-package-anim-pairs',
        'cli-json-root-csv-signature')
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        output_line_count = @($execution.output -split "`n").Count
        output_sha256 = $executionSha
    }
}
$json = ($report | ConvertTo-Json -Depth 9).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw "P1-16 locked-builder validation failed: $($execution.output)" }
