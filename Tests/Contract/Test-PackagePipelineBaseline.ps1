[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-07-package-pipeline.json'
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

$requiredFiles = @(
    'Tools/CMakeLists.txt',
    'Tools/CMakePresets.json',
    'Tools/cmake/TMXYToolOptions.cmake',
    'Tools/TMXY.Package/CMakeLists.txt',
    'Tools/TMXY.Package/include/tmxy/package/package_directory_codec.hpp',
    'Tools/TMXY.Package/src/package_directory_codec.cpp',
    'Tools/TMXY.Package/src/package_v2_reader.cpp',
    'Tools/TMXY.Package/src/package_v3_reader.cpp',
    'Tools/TMXY.Package/tests/CMakeLists.txt',
    'Tools/TMXY.Package/tests/package_directory_codec_test.cpp'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-07 required file is missing: $relativePath"
    }
}
$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -match $forbiddenPattern) {
        throw "P1-07 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}
$hashLines = foreach ($relativePath in $requiredFiles | Sort-Object) {
    $fileHash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($fileHash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")

$v2ReportPath = Join-Path $root 'Data\BuildBaseline\p1-05-package-v2.json'
$v3ReportPath = Join-Path $root 'Data\BuildBaseline\p1-06-package-v3.json'
$v2 = Get-Content -LiteralPath $v2ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$v3 = Get-Content -LiteralPath $v3ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$v2.result -ne 'PASS' -or [int]$v2.frozen_sample_set.sample_count -ne 22 -or
    [string]$v2.frozen_sample_set.sample_set_sha256 -ne
        '2371a43ac6a46403e68e0d31e884bb6b27b54ac5babc3db6b3c448695c3179e6') {
    throw 'P1-07 requires the passing frozen Package 2.0 baseline.'
}
if ([string]$v3.result -ne 'PASS' -or [int]$v3.frozen_sample_set.sample_count -ne 140 -or
    [string]$v3.frozen_sample_set.sample_set_sha256 -ne
        '9e6872a12464bcbe7c98de2cd96a9ad3d831156a14a7b50b1a2dd07ec75260dd') {
    throw 'P1-07 requires the passing frozen Package 3.0 baseline.'
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
    throw 'P1-07 requires the qualified non-root Clang 21 builder image.'
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
./out/build/ci-linux-clang/TMXY.Package/tests/tmxy_package_directory_codec_test /legacy/Packages
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
    $null -ne $sampleResult -and [int]$sampleResult.v2_sample_count -eq 22 -and
    [int]$sampleResult.v3_sample_count -eq 140 -and
    [int]$sampleResult.record_count -eq 118711 -and
    [int64]$sampleResult.directory_bytes -eq 5364459 -and
    [int64]$sampleResult.file_bytes -eq 42117271 -and
    [string]$sampleResult.decoded_fnv1a64 -eq '7c86de5289714cc8'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-07'
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    input_reports = [pscustomobject][ordered]@{
        package_v2_sha256 = (Get-FileHash $v2ReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        package_v3_sha256 = (Get-FileHash $v3ReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    pipeline = @(
        'read-and-validate-outer-header',
        'select-versioned-directory-codec',
        'decode-reversible-obfuscation',
        'parse-and-validate-directory-records',
        'expose-bounded-raw-object-body-spans'
    )
    classification = [pscustomobject][ordered]@{
        directory_operation = 'fixed-reversible-obfuscation'
        directory_compression = 'none-observed'
        directory_encryption = $false
        key_or_secret_required = $false
        object_body_transform = 'none-at-container-layer'
        object_body_semantics = 'deferred-to-versioned-object-codecs'
    }
    frozen_roundtrip = [pscustomobject][ordered]@{
        v2_sample_count = if ($null -ne $sampleResult) { [int]$sampleResult.v2_sample_count } else { 0 }
        v3_sample_count = if ($null -ne $sampleResult) { [int]$sampleResult.v3_sample_count } else { 0 }
        encoded_roundtrip_exact = $passed
        record_count = if ($null -ne $sampleResult) { [int]$sampleResult.record_count } else { 0 }
        directory_bytes = if ($null -ne $sampleResult) {
            [int64]$sampleResult.directory_bytes
        }
        else { 0 }
        decoded_fnv1a64 = if ($null -ne $sampleResult) {
            [string]$sampleResult.decoded_fnv1a64
        }
        else { '' }
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
    stages = @('dependency-baseline-check', 'clang-format-21', 'cmake-clang-21',
        'clang-tidy-21', 'ctest', 'all-directory-byte-roundtrip')
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        output_line_count = @($execution.output -split "`n").Count
        output_sha256 = Get-TextSha256 -Value $execution.output
    }
}
$json = ($report | ConvertTo-Json -Depth 7).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw "P1-07 locked-builder validation failed: $($execution.output)" }
