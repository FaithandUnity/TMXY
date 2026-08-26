[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-01-format-core.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$moduleRoot = Join-Path $root 'Tools\TMXY.FormatCore'
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
    'Tools/TMXY.FormatCore/CMakeLists.txt',
    'Tools/TMXY.FormatCore/README.md',
    'Tools/TMXY.FormatCore/include/tmxy/format/binary_reader.hpp',
    'Tools/TMXY.FormatCore/include/tmxy/format/read_error.hpp',
    'Tools/TMXY.FormatCore/include/tmxy/format/read_result.hpp',
    'Tools/TMXY.FormatCore/src/binary_reader.cpp',
    'Tools/TMXY.FormatCore/src/read_error.cpp',
    'Tools/TMXY.FormatCore/tests/binary_reader_test.cpp'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-01 required file is missing: $relativePath"
    }
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -match $forbiddenPattern) {
        throw "P1-01 forbidden legacy/platform dependency found: $($file.FullName)"
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
    throw 'P1-01 requires the qualified non-root Clang 21 builder image.'
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
cd /tmp/tmxy-rebuild/Tools
find TMXY.FormatCore -type f \( -name '*.cpp' -o -name '*.hpp' \) -print0 | xargs -0 clang-format-21 --dry-run --Werror
cmake --preset ci-linux-clang -DTMXY_BUILD_PACKAGE=OFF -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TRANSFORM=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang
find TMXY.FormatCore -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --preset ci-linux-clang
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
    task = 'P1-01'
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    error_schema_version = 1
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
    stages = @('clang-format-21', 'cmake-clang-21', 'clang-tidy-21', 'ctest')
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        output_line_count = @($execution.output -split "`n").Count
        output_sha256 = Get-TextSha256 -Value $execution.output
    }
}
$json = ($report | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw "P1-01 locked-builder validation failed: $($execution.output)" }
