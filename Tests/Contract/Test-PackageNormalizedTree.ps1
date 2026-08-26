[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-08-package-normalized-tree.json'
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
    'Contracts/data-schema/package-tree-v1.schema.json',
    'Tools/CMakeLists.txt',
    'Tools/CMakePresets.json',
    'Tools/cmake/TMXYToolOptions.cmake',
    'Tools/TMXY.Package/CMakeLists.txt',
    'Tools/TMXY.Package/include/tmxy/package/package_normalized_tree.hpp',
    'Tools/TMXY.Package/src/package_normalized_tree.cpp',
    'Tools/TMXY.Package/apps/package_tree_export_main.cpp',
    'Tools/TMXY.Package/tests/CMakeLists.txt',
    'Tools/TMXY.Package/tests/package_normalized_tree_test.cpp'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-08 required file is missing: $relativePath"
    }
}
$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -match $forbiddenPattern) {
        throw "P1-08 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}
$hashLines = foreach ($relativePath in $requiredFiles | Sort-Object) {
    $fileHash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($fileHash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")

$schemaPath = Join-Path $root 'Contracts\data-schema\package-tree-v1.schema.json'
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$schemaPassed = [string]$schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    [string]$schema.properties.schema.const -eq 'tmxy.package.tree' -and
    [int]$schema.properties.schema_version.const -eq 1 -and
    [string]$schema.'$defs'.opaqueBytes.properties.encoding.const -eq 'opaque-bytes' -and
    [string]$schema.'$defs'.object.properties.unknown_fields.items.properties.preservation.const `
        -eq 'source-span' -and
    [string]$schema.'$defs'.object.properties.transform.properties.state.const -eq 'unparsed'
if (-not $schemaPassed) {
    throw 'P1-08 normalized tree JSON Schema does not preserve the required boundaries.'
}

$dependencyReports = @(
    'p1-02-package-v1.json',
    'p1-05-package-v2.json',
    'p1-06-package-v3.json',
    'p1-07-package-pipeline.json'
)
$dependencyHashes = [ordered]@{}
foreach ($name in $dependencyReports) {
    $path = Join-Path $root "Data\BuildBaseline\$name"
    $report = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$report.result -ne 'PASS') {
        throw "P1-08 dependency baseline is not passing: $name"
    }
    $dependencyHashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
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
    throw 'P1-08 requires the qualified non-root Clang 21 builder image.'
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
exporter=./out/build/ci-linux-clang/TMXY.Package/tmxy_package_tree_export
$exporter /legacy/Packages/Texture/tempfile.tmp Packages/Texture/tempfile.tmp > /tmp/v1.json
$exporter /legacy/Packages/Level/bydfb Packages/Level/bydfb > /tmp/v2.json
$exporter /legacy/Packages/Texture/texeditor Packages/Texture/texeditor > /tmp/v3.json
v1_hash=$(sha256sum /tmp/v1.json | cut -d' ' -f1)
v2_hash=$(sha256sum /tmp/v2.json | cut -d' ' -f1)
v3_hash=$(sha256sum /tmp/v3.json | cut -d' ' -f1)
v1_bytes=$(wc -c < /tmp/v1.json)
v2_bytes=$(wc -c < /tmp/v2.json)
v3_bytes=$(wc -c < /tmp/v3.json)
printf '{"sample_result":"PASS","v1":{"bytes":%s,"sha256":"%s"},"v2":{"bytes":%s,"sha256":"%s"},"v3":{"bytes":%s,"sha256":"%s"}}\n' "$v1_bytes" "$v1_hash" "$v2_bytes" "$v2_hash" "$v3_bytes" "$v3_hash"
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
    $null -ne $sampleResult -and [int64]$sampleResult.v1.bytes -eq 1350653 -and
    [string]$sampleResult.v1.sha256 -eq
        '4ab058aafd9ffd44065e442994591b33415dc5c1ff37307a8ceb6a02bd89c13c' -and
    [int64]$sampleResult.v2.bytes -eq 5223 -and [string]$sampleResult.v2.sha256 -eq
        '9a738c3ab36adb33da85866d252c71e6f48eef92f4000ce5bcc2cdf8a8d370a8' -and
    [int64]$sampleResult.v3.bytes -eq 676 -and [string]$sampleResult.v3.sha256 -eq
        'f75e249ce19f82be23c6b6d3b039a64cf58771cbb033460e3d43fc7869b4bec3'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-08'
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    json_schema = [pscustomobject][ordered]@{
        path = 'Contracts/data-schema/package-tree-v1.schema.json'
        sha256 = (Get-FileHash $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
        draft = [string]$schema.'$schema'
        passed = $schemaPassed
    }
    dependency_report_sha256 = $dependencyHashes
    semantic_states = [pscustomobject][ordered]@{
        names_and_classes = 'opaque-bytes-hex'
        references = 'unparsed'
        transform = 'unparsed'
        materials = 'unparsed'
        unknown_body = 'source-span'
        guessed_fields = 0
    }
    frozen_exports = if ($null -ne $sampleResult) { $sampleResult } else { @{} }
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
    stages = @('json-schema-contract', 'dependency-baseline-check', 'clang-format-21',
        'cmake-clang-21', 'clang-tidy-21', 'ctest', 'v1-v2-v3-deterministic-export')
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
if (-not $passed) { throw "P1-08 locked-builder validation failed: $($execution.output)" }
