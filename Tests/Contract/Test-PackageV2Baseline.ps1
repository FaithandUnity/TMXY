[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-05-package-v2.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$packagesRoot = Join-Path $client 'Packages'
$moduleRoot = Join-Path $root 'Tools\TMXY.Package'

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
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

function Test-PackageV2Header {
    param([Parameter(Mandatory = $true)][string]$Path)
    $version = [System.Text.Encoding]::ASCII.GetBytes('QRENDER PACKAGE VER 2.0')
    $expected = [byte[]](23, 0) + $version
    $actual = [byte[]]::new($expected.Length)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $read = $stream.Read($actual, 0, $actual.Length)
    }
    finally {
        $stream.Dispose()
    }
    return $read -eq $actual.Length -and
        [System.Convert]::ToHexString($actual) -ceq [System.Convert]::ToHexString($expected)
}

$requiredFiles = @(
    'Tools/CMakeLists.txt',
    'Tools/CMakePresets.json',
    'Tools/cmake/TMXYToolOptions.cmake',
    'Tools/TMXY.Package/CMakeLists.txt',
    'Tools/TMXY.Package/include/tmxy/package/package_v2.hpp',
    'Tools/TMXY.Package/include/tmxy/package/package_v2_reader.hpp',
    'Tools/TMXY.Package/src/package_v2.cpp',
    'Tools/TMXY.Package/src/package_v2_reader.cpp',
    'Tools/TMXY.Package/tests/CMakeLists.txt',
    'Tools/TMXY.Package/tests/package_v2_reader_test.cpp'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-05 required file is missing: $relativePath"
    }
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -match $forbiddenPattern) {
        throw "P1-05 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}
$hashLines = foreach ($relativePath in $requiredFiles | Sort-Object) {
    $fileHash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($fileHash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")

$manifestPath = Join-Path $root 'Data\RawManifests\client-3.0.0.413.files.jsonl'
$expectedManifestSha = 'b80cde6fbb736c9a6b85fd5e4528554f4e6e9bf950b1ac12a036b4c54d5d60c3'
$manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($manifestSha -ne $expectedManifestSha) {
    throw 'P1-05 requires the frozen client 3.0.0.413 raw manifest.'
}
$manifestByPath = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::Ordinal)
foreach ($line in [System.IO.File]::ReadLines($manifestPath)) {
    $record = $line | ConvertFrom-Json
    $manifestByPath.Add([string]$record.path, $record)
}

$sampleRecords = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $packagesRoot -Recurse -File | Sort-Object FullName) {
    if (-not (Test-PackageV2Header -Path $file.FullName)) { continue }
    $relative = 'Packages/' + [System.IO.Path]::GetRelativePath(
        $packagesRoot, $file.FullName).Replace('\', '/')
    if (-not $manifestByPath.ContainsKey($relative)) {
        throw "P1-05 Package 2.0 sample is absent from the frozen manifest: $relative"
    }
    $manifestRecord = $manifestByPath[$relative]
    $actualSha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne [int64]$manifestRecord.size -or
        $actualSha -ne [string]$manifestRecord.sha256) {
        throw "P1-05 Package 2.0 sample differs from the frozen manifest: $relative"
    }
    $sampleRecords.Add([pscustomobject][ordered]@{
        path = $relative
        size = [int64]$file.Length
        sha256 = $actualSha
    })
}
$sampleLines = foreach ($sample in $sampleRecords | Sort-Object path) {
    "$($sample.path)|$($sample.size)|$($sample.sha256)"
}
$sampleSetSha = Get-TextSha256 -Value (($sampleLines -join "`n") + "`n")
$expectedSampleSetSha = '2371a43ac6a46403e68e0d31e884bb6b27b54ac5babc3db6b3c448695c3179e6'
$sampleBytes = ($sampleRecords | Measure-Object -Property size -Sum).Sum
if ($sampleRecords.Count -ne 22 -or $sampleBytes -ne 5783942 -or
    $sampleSetSha -ne $expectedSampleSetSha) {
    throw 'P1-05 Package 2.0 sample set differs from the frozen 22-file baseline.'
}

$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$imageRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$imagePresent = $LASTEXITCODE -eq 0 -and $imageRecords.Count -gt 0
$actualBuilderId = if ($imagePresent) { [string]$imageRecords[0].Id } else { '' }
$builderUser = if ($imagePresent) { [string]$imageRecords[0].Config.User } else { '' }
if (-not $imagePresent -or $actualBuilderId -ne $expectedBuilderId -or $builderUser -ne 'tmxy') {
    throw 'P1-05 requires the qualified non-root Clang 21 builder image.'
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
cd /tmp/tmxy-rebuild/Tools
find TMXY.FormatCore TMXY.Package -type f \( -name '*.cpp' -o -name '*.hpp' \) -print0 | xargs -0 clang-format-21 --dry-run --Werror --style=file
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TRANSFORM=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang
find TMXY.FormatCore TMXY.Package -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --preset ci-linux-clang
./out/build/ci-linux-clang/TMXY.Package/tests/tmxy_package_v2_reader_test /legacy/Packages
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$packagesRoot,target=/legacy/Packages,readonly",
    $builderReference, 'bash', '-c', $containerScript
)
$execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
$sampleOutputLine = @($execution.output -split "`n" |
    Where-Object { $_ -match '^\{"sample_result":"PASS"' } | Select-Object -Last 1)
$sampleResult = if ($sampleOutputLine.Count -eq 1) {
    $sampleOutputLine[0] | ConvertFrom-Json
}
else {
    $null
}
$passed = $execution.exit_code -eq 0 -and $execution.output -match '100% tests passed' -and
    $null -ne $sampleResult -and [int]$sampleResult.sample_count -eq 22 -and
    [int]$sampleResult.record_count -eq 27637 -and
    [int64]$sampleResult.directory_bytes -eq 1220531 -and
    [int64]$sampleResult.file_bytes -eq 5783942 -and
    [string]$sampleResult.aggregate_fnv1a64 -eq '2d2d359bc9f5da7f'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-05'
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    error_schema_version = 1
    transform = 'four-byte half-swap plus bitwise-not; remainder bitwise-not'
    raw_manifest = [pscustomobject][ordered]@{
        path = 'Data/RawManifests/client-3.0.0.413.files.jsonl'
        sha256 = $manifestSha
    }
    frozen_sample_set = [pscustomobject][ordered]@{
        root = 'Packages'
        copy_policy = 'reference_only'
        sample_count = $sampleRecords.Count
        file_bytes = [int64]$sampleBytes
        sample_set_sha256 = $sampleSetSha
        record_count = if ($null -ne $sampleResult) { [int]$sampleResult.record_count } else { 0 }
        directory_bytes = if ($null -ne $sampleResult) {
            [int64]$sampleResult.directory_bytes
        }
        else { 0 }
        metadata_fnv1a64 = if ($null -ne $sampleResult) {
            [string]$sampleResult.aggregate_fnv1a64
        }
        else { '' }
        samples = @($sampleRecords | Sort-Object path)
    }
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        legacy_sample_mount = 'read-only-directory'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_storage = 'ephemeral_tmpfs'
    }
    stages = @('raw-manifest-sha256', 'sample-set-sha256', 'sample-file-sha256',
        'clang-format-21', 'cmake-clang-21', 'clang-tidy-21', 'ctest',
        'frozen-sample-set-parse')
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
if (-not $passed) { throw "P1-05 locked-builder validation failed: $($execution.output)" }
