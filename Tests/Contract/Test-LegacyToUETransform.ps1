[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-12-legacy-to-ue-transform.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$workspaceRoot = [System.IO.Path]::GetDirectoryName($root)
$moduleRoot = Join-Path $root 'Tools\TMXY.Transform'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json

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
    'Tools/cmake/TMXYToolOptions.cmake',
    'Tools/TMXY.Transform/CMakeLists.txt',
    'Tools/TMXY.Transform/README.md',
    'Tools/TMXY.Transform/include/tmxy/transform/legacy_to_ue_transform.hpp',
    'Tools/TMXY.Transform/include/tmxy/transform/transform_error.hpp',
    'Tools/TMXY.Transform/include/tmxy/transform/transform_result.hpp',
    'Tools/TMXY.Transform/include/tmxy/transform/transform_types.hpp',
    'Tools/TMXY.Transform/src/legacy_to_ue_transform.cpp',
    'Tools/TMXY.Transform/src/transform_error.cpp',
    'Tools/TMXY.Transform/tests/CMakeLists.txt',
    'Tools/TMXY.Transform/tests/legacy_to_ue_transform_test.cpp',
    'Docs/ADR/ADR-003-legacy-to-ue-transform.md',
    'Docs/Formats/LEGACY-TO-UE-TRANSFORM.md'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-12 required file is missing: $relativePath"
    }
}

$evidence = @(
    [pscustomobject]@{ path = 'ClientCode\Base\Hdr\QMath.h'; sha256 = '62b5f6f18aa1885b70587ca79cd2bad08e7cce62d572808b66288611708d13ac' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QRotator.h'; sha256 = '661c662041667513d2deaa4c6d4bd6a1244a8fa7b09e533b4ed8a4df1ed51a3f' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QMatrix.h'; sha256 = '99defaa9fa607285bb2c553d257d948fbc1028d58e53cdaf6d38dfb25a4ecc58' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QPawnPhy.cpp'; sha256 = 'd82ab57cd8dafc7f1f5a7d811e0c94bc49c3246e2438deded597d3552641028b' },
    [pscustomobject]@{ path = 'ToolCode\XwMaxExp\XwMaxExp.h'; sha256 = '674549952ee6b3eacb0068efb4aa1d50c41ddbb40a819e2cc809715f45071c1d' },
    [pscustomobject]@{ path = 'ToolCode\XwMaxExp\XwMaxMesh.cpp'; sha256 = '8133ea9e6326da55e1d542bfcfb44731a4a48cabf5984bedcbba7dfb97bdcaea' },
    [pscustomobject]@{ path = 'DevDoc\游戏资料\CLSVShare\unit_disp_ids.csv'; sha256 = '05a6a64e66654784eada747f5ff35310c2b48fea881f6a8ff12c356053b54fc0' }
)
$evidenceReport = foreach ($item in $evidence) {
    $path = Join-Path $workspaceRoot $item.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P1-12 evidence is missing: $($item.path)"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $item.sha256) {
        throw "P1-12 evidence hash changed: $($item.path)"
    }
    [pscustomobject][ordered]@{ path = $item.path; sha256 = $actual; passed = $true }
}

$ueEvidencePath = 'C:\Program Files\Epic Games\UE_5.8\Engine\Source\Runtime\Core\Public\Math\RotationTranslationMatrix.h'
$ueEvidenceSha = '8dd14f716b4c8a26b5a1aa270a7da73aa76e09d2d83b6ddba55a289e2e1124c4'
if (-not (Test-Path -LiteralPath $ueEvidencePath -PathType Leaf)) {
    throw 'P1-12 UE 5.8.2 matrix evidence is missing.'
}
$actualUESha = (Get-FileHash -LiteralPath $ueEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualUESha -ne $ueEvidenceSha) { throw 'P1-12 UE matrix evidence hash changed.' }

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx|CoreMinimal\.h)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -match $forbiddenPattern) {
        throw "P1-12 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}

$hashLines = foreach ($relativePath in $requiredFiles | Sort-Object) {
    $fileHash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($fileHash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")

$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$imageRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$imagePresent = $LASTEXITCODE -eq 0 -and $imageRecords.Count -gt 0
$actualBuilderId = if ($imagePresent) { [string]$imageRecords[0].Id } else { '' }
$builderUser = if ($imagePresent) { [string]$imageRecords[0].Config.User } else { '' }
if (-not $imagePresent -or $actualBuilderId -ne $expectedBuilderId -or $builderUser -ne 'tmxy') {
    throw 'P1-12 requires the qualified non-root Clang 21 builder image.'
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
cp -a /workspace/Tools/TMXY.Transform /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
find TMXY.Transform -type f \( -name '*.cpp' -o -name '*.hpp' \) -print0 | xargs -0 clang-format-21 --dry-run --Werror
cmake --preset ci-linux-clang -DTMXY_BUILD_PACKAGE=OFF -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang --target tmxy_legacy_to_ue_transform_test
find TMXY.Transform -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --test-dir out/build/ci-linux-clang -R '^transform\.' --output-on-failure
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=512m',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    $builderReference, 'bash', '-c', $containerScript
)
$execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
$passed = $execution.exit_code -eq 0 -and $execution.output -match '100% tests passed'
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-12'
    completion_criteria_satisfied = $passed
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    convention = [pscustomobject][ordered]@{
        axes = 'identity_x_forward_y_right_z_up'
        centimeters_per_legacy_unit = 100
        legacy_angle_units_per_turn = 65536
        rotator_signs = [pscustomobject]@{ pitch = -1; yaw = 1; roll = -1 }
        matrix = 'row_vector_affine_translation_row_3'
        uv = 'identity_serialized_legacy_to_ue'
        triangle_winding = 'preserve_unless_negative_basis_is_baked'
    }
    evidence = @($evidenceReport) + @([pscustomobject][ordered]@{
        path = 'UE_5.8/Engine/Source/Runtime/Core/Public/Math/RotationTranslationMatrix.h'
        sha256 = $actualUESha
        passed = $true
    })
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_storage = 'ephemeral_tmpfs'
    }
    stages = @('clang-format-21', 'cmake-ninja-clang-21', 'clang-tidy-21', 'ctest-golden-boundary')
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        output_line_count = @($execution.output -split "`n").Count
        output_sha256 = Get-TextSha256 -Value $execution.output
    }
}
$json = ($report | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw "P1-12 locked-builder validation failed: $($execution.output)" }
