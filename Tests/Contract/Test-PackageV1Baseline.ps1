[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$ClientSourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-02-package-v1.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$clientSource = [System.IO.Path]::GetFullPath($ClientSourceRoot).TrimEnd([char[]]'\/')
$moduleRoot = Join-Path $root 'Tools\TMXY.Package'

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Resolve-ContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|/)\.\.(/|$)') {
        throw "Evidence path must be portable and relative: $RelativePath"
    }
    $candidate = [System.IO.Path]::GetFullPath(
        (Join-Path $BasePath $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
    $prefix = $BasePath + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Evidence path escapes its read-only root: $RelativePath"
    }
    return $candidate
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
    'Tools/TMXY.Package/README.md',
    'Tools/TMXY.Package/include/tmxy/package/package_v1.hpp',
    'Tools/TMXY.Package/include/tmxy/package/package_v1_reader.hpp',
    'Tools/TMXY.Package/src/package_v1.cpp',
    'Tools/TMXY.Package/src/package_v1_reader.cpp',
    'Tools/TMXY.Package/tests/CMakeLists.txt',
    'Tools/TMXY.Package/tests/package_v1_reader_test.cpp'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-02 required file is missing: $relativePath"
    }
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -match $forbiddenPattern) {
        throw "P1-02 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}

$hashLines = foreach ($relativePath in $requiredFiles | Sort-Object) {
    $fileHash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($fileHash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")

$goldenPath = Join-Path $root 'Data\GoldenSamples\p0-golden-samples.json'
$golden = Get-Content -LiteralPath $goldenPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sampleMatches = @($golden.samples | Where-Object { [string]$_.id -eq 'package-v1-reference' })
if ($sampleMatches.Count -ne 1 -or [string]$golden.copy_policy -ne 'reference_only') {
    throw 'P1-02 requires exactly one reference-only package-v1-reference sample.'
}
$sample = $sampleMatches[0]
$samplePath = Resolve-ContainedPath -BasePath $client -RelativePath ([string]$sample.path)
if (-not (Test-Path -LiteralPath $samplePath -PathType Leaf)) {
    throw "P1-02 frozen sample is missing: $($sample.path)"
}
$sampleFile = Get-Item -LiteralPath $samplePath
$sampleSha = (Get-FileHash -LiteralPath $samplePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sampleFile.Length -ne [int64]$sample.size -or $sampleSha -ne [string]$sample.sha256) {
    throw 'P1-02 frozen Package 1.0 sample differs from the reviewed golden-sample baseline.'
}

$legacySources = @(
    [pscustomobject]@{ path = 'Base/Hdr/QArchive.h'; size = 1910; sha256 = 'c5363a07e944c34ac4eb395d377aaeef2da80bb5df3805b414d9142b84ab8e84' },
    [pscustomobject]@{ path = 'Base/Hdr/QDict.h'; size = 10894; sha256 = 'c3f2e74d3a5bfd454c3ed34433acd3f2aefc70a611336f142ea4ef0c1bb952a9' },
    [pscustomobject]@{ path = 'Base/Hdr/QPackage.h'; size = 3258; sha256 = 'b6598586f5dee3cc5af2a139317aeacbbe1b8c1e9a09025e8f4ae1a61e2b630a' },
    [pscustomobject]@{ path = 'Base/Src/QArchive.cpp'; size = 2242; sha256 = '8fe0cccd38d4876dbf261c30277e8b954ebe9a85ff69f217581397987ad498e8' },
    [pscustomobject]@{ path = 'Base/Src/QMetaclass.cpp'; size = 11979; sha256 = '3a4ba187ea1099706328c0b49084ad555fa3d2f68f16d8b8e7f0a53fa0b8fc57' },
    [pscustomobject]@{ path = 'Base/Src/QPackage.cpp'; size = 7423; sha256 = 'b4abf66d3f84f583f80f88b70c44e7c90fcac9fd380c34f08f398cf3e8ccd064' }
)
foreach ($evidence in $legacySources) {
    $evidencePath = Resolve-ContainedPath -BasePath $clientSource -RelativePath ([string]$evidence.path)
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        throw "P1-02 legacy format evidence is missing: $($evidence.path)"
    }
    $evidenceFile = Get-Item -LiteralPath $evidencePath
    $evidenceSha = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($evidenceFile.Length -ne [int64]$evidence.size -or $evidenceSha -ne [string]$evidence.sha256) {
        throw "P1-02 legacy format evidence changed: $($evidence.path)"
    }
}

$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$imageRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$imagePresent = $LASTEXITCODE -eq 0 -and $imageRecords.Count -gt 0
$actualBuilderId = if ($imagePresent) { [string]$imageRecords[0].Id } else { '' }
$builderUser = if ($imagePresent) { [string]$imageRecords[0].Config.User } else { '' }
if (-not $imagePresent -or $actualBuilderId -ne $expectedBuilderId -or $builderUser -ne 'tmxy') {
    throw 'P1-02 requires the qualified non-root Clang 21 builder image.'
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
./out/build/ci-linux-clang/TMXY.Package/tests/tmxy_package_v1_reader_test /legacy/package-v1
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=512m',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$samplePath,target=/legacy/package-v1,readonly",
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
    $null -ne $sampleResult -and [int]$sampleResult.record_count -eq 3004 -and
    [int64]$sampleResult.header_size -eq 145581 -and [int64]$sampleResult.file_size -eq 319813 -and
    [string]$sampleResult.metadata_fnv1a64 -eq '1691fafacd3ab5bd'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-02'
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    error_schema_version = 1
    legacy_format_evidence = $legacySources
    frozen_sample = [pscustomobject][ordered]@{
        id = [string]$sample.id
        path = [string]$sample.path
        evidence_level = [string]$sample.evidence_level
        copy_policy = [string]$golden.copy_policy
        size = [int64]$sample.size
        sha256 = [string]$sample.sha256
        record_count = if ($null -ne $sampleResult) { [int]$sampleResult.record_count } else { 0 }
        header_size = if ($null -ne $sampleResult) { [int64]$sampleResult.header_size } else { 0 }
        class_count = if ($null -ne $sampleResult) { [int]$sampleResult.class_count } else { 0 }
        metadata_fnv1a64 = if ($null -ne $sampleResult) { [string]$sampleResult.metadata_fnv1a64 } else { '' }
    }
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        legacy_sample_mount = 'read-only-single-file'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_storage = 'ephemeral_tmpfs'
    }
    stages = @('legacy-evidence-sha256', 'golden-sample-sha256', 'clang-format-21',
        'cmake-clang-21', 'clang-tidy-21', 'ctest', 'frozen-sample-parse')
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
if (-not $passed) { throw "P1-02 locked-builder validation failed: $($execution.output)" }
