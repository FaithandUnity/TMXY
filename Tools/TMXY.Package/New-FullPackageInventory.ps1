[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-01-package-inventory.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith(
        $root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-01 inventory output must remain inside Rebuild.'
}
$packagesRoot = Join-Path $client 'Packages'
$manifestPath = Join-Path $root 'Data\RawManifests\client-3.0.0.413.files.jsonl'
$moduleRoot = Join-Path $root 'Tools\TMXY.Package'
foreach ($path in @($packagesRoot, $manifestPath, $moduleRoot)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-01 input is missing: $path" }
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [System.Array]::Clear($bytes, 0, $bytes.Length) }
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
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdoutTask.GetAwaiter().GetResult()
        stderr = $stderrTask.GetAwaiter().GetResult()
    }
}

$manifestEntries = [System.Collections.Generic.List[object]]::new()
foreach ($line in [System.IO.File]::ReadLines($manifestPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $entry = $line | ConvertFrom-Json
    $relative = [string]$entry.path
    if ($relative.StartsWith('Packages/', [System.StringComparison]::Ordinal)) {
        if ($relative.Contains("`t") -or $relative.Contains("`r") -or $relative.Contains("`n")) {
            throw 'P2-01 refuses Package paths containing control separators.'
        }
        $manifestEntries.Add([pscustomobject][ordered]@{
            path = $relative
            size = [int64]$entry.size
            sha256 = [string]$entry.sha256
        })
    }
}
$manifestEntries = @($manifestEntries | Sort-Object path)
if ($manifestEntries.Count -ne 167 -or
    @($manifestEntries.path | Sort-Object -Unique).Count -ne 167) {
    throw 'P2-01 requires the frozen set of 167 unique Package files.'
}

$inputFailures = [System.Collections.Generic.List[string]]::new()
$inputBindingLines = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $manifestEntries) {
    $path = Join-Path $client $entry.path.Replace(
        '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $inputFailures.Add("missing:$($entry.path)")
        continue
    }
    $item = Get-Item -LiteralPath $path
    $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne $entry.size -or $sha -ne $entry.sha256) {
        $inputFailures.Add("integrity:$($entry.path)")
    }
    $inputBindingLines.Add("$($entry.path)|$($entry.size)|$($entry.sha256)")
}
if ($inputFailures.Count -gt 0) {
    throw "P2-01 frozen Package inputs changed: $($inputFailures -join ', ')"
}
$inputSetSha = Get-TextSha256 -Value (($inputBindingLines -join "`n") + "`n")

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') -or $_.Name -eq 'CMakeLists.txt' } |
    Sort-Object FullName)
$sourceBindingLines = foreach ($file in $sourceFiles) {
    $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$relative|$sha"
}
$sourceSha = Get-TextSha256 -Value (($sourceBindingLines -join "`n") + "`n")

$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$imageRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$imagePresent = $LASTEXITCODE -eq 0 -and $imageRecords.Count -gt 0
$actualBuilderId = if ($imagePresent) { [string]$imageRecords[0].Id } else { '' }
$builderUser = if ($imagePresent) { [string]$imageRecords[0].Config.User } else { '' }
if (-not $imagePresent -or $actualBuilderId -ne $expectedBuilderId -or
    $builderUser -ne 'tmxy') {
    throw 'P2-01 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools
cp /workspace/.clang-format /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /workspace/Tools/TMXY.FormatCore /workspace/Tools/TMXY.Package /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
find TMXY.FormatCore TMXY.Package -type f \( -name '*.cpp' -o -name '*.hpp' \) -print0 | xargs -0 clang-format-21 --dry-run --Werror --style=file
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TRANSFORM=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang
find TMXY.FormatCore TMXY.Package -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --preset ci-linux-clang
inventory=./out/build/ci-linux-clang/TMXY.Package/tmxy_package_inventory
while IFS= read -r -d '' file; do
  relative=${file#/legacy/}
  printf '%s\t' "$relative"
  "$inventory" "$file"
done < <(find /legacy/Packages -type f -print0 | sort -z)
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$packagesRoot,target=/legacy/Packages,readonly",
    $builderReference, 'bash', '-c', $containerScript
)
$execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments `
    -WorkingDirectory $root
if ($execution.exit_code -ne 0) {
    throw "P2-01 locked scan failed: $($execution.stderr.Trim())"
}

$scannedByPath = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::Ordinal)
foreach ($line in @($execution.stdout -split "`n")) {
    $tab = $line.IndexOf("`t", [System.StringComparison]::Ordinal)
    if ($tab -lt 1 -or -not $line.EndsWith('}', [System.StringComparison]::Ordinal)) {
        continue
    }
    $relative = $line.Substring(0, $tab)
    if (-not $relative.StartsWith('Packages/', [System.StringComparison]::Ordinal)) {
        continue
    }
    if ($scannedByPath.ContainsKey($relative)) {
        throw "P2-01 inventory emitted a duplicate path: $relative"
    }
    $scannedByPath.Add($relative, ($line.Substring($tab + 1) | ConvertFrom-Json))
}
if ($scannedByPath.Count -ne $manifestEntries.Count) {
    throw "P2-01 inventory returned $($scannedByPath.Count) of $($manifestEntries.Count) files."
}

$files = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $manifestEntries) {
    if (-not $scannedByPath.ContainsKey($entry.path)) {
        throw "P2-01 inventory omitted a frozen file: $($entry.path)"
    }
    $metrics = $scannedByPath[$entry.path]
    if ([int64]$metrics.file_bytes -ne $entry.size) {
        throw "P2-01 inventory size disagrees with Manifest: $($entry.path)"
    }
    $files.Add([pscustomobject][ordered]@{
        path = $entry.path
        bytes = $entry.size
        sha256 = $entry.sha256
        version = [string]$metrics.version
        recognized = [bool]$metrics.recognized
        parsed = [bool]$metrics.parsed
        directory_bytes = [int64]$metrics.directory_bytes
        record_count = [int64]$metrics.record_count
        distinct_class_count = [int64]$metrics.distinct_class_count
        unknown_object_count = [int64]$metrics.unknown_object_count
        metadata_fingerprint = [string]$metrics.metadata_fingerprint
        error = [string]$metrics.error
        error_offset = [int64]$metrics.error_offset
    })
}

$recognized = @($files | Where-Object recognized)
$recognizedFailures = @($recognized | Where-Object { -not $_.parsed })
$versionCounts = @($files | Group-Object version | Sort-Object Name | ForEach-Object {
        [pscustomobject][ordered]@{ version = $_.Name; files = $_.Count }
    })
$recordCount = [int64](($files | Measure-Object record_count -Sum).Sum)
$directoryBytes = [int64](($files | Measure-Object directory_bytes -Sum).Sum)
$unknownObjectCount = [int64](($files | Measure-Object unknown_object_count -Sum).Sum)
$completed = $files.Count -eq 167 -and $recognized.Count -eq 163 -and
    $recognizedFailures.Count -eq 0 -and
    @($files | Where-Object version -eq '1.0').Count -eq 1 -and
    @($files | Where-Object version -eq '2.0').Count -eq 22 -and
    @($files | Where-Object version -eq '3.0').Count -eq 140 -and
    @($files | Where-Object version -eq 'empty').Count -eq 1 -and
    @($files | Where-Object version -eq 'unknown').Count -eq 3 -and
    $recordCount -eq 121715 -and $directoryBytes -eq 5510040 -and
    $unknownObjectCount -eq 121715

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($completed) { 'PASS' } else { 'FAIL' }
    task = 'P2-01'
    task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
    completion_criteria_satisfied = $completed
    input = [pscustomobject][ordered]@{
        client_version = '3.0.0.413'
        manifest = 'Data/RawManifests/client-3.0.0.413.files.jsonl'
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        package_set_sha256 = $inputSetSha
        copy_policy = 'reference_only'
        integrity_failures = $inputFailures.Count
    }
    summary = [pscustomobject][ordered]@{
        files = $files.Count
        bytes = [int64](($files | Measure-Object bytes -Sum).Sum)
        recognized = $recognized.Count
        parsed = @($files | Where-Object parsed).Count
        recognized_parse_failures = $recognizedFailures.Count
        versions = $versionCounts
        records = $recordCount
        directory_bytes = $directoryBytes
        unknown_objects = $unknownObjectCount
        unknown_object_interpretation = 'Every object body remains an explicit unparsed source span at P2-01.'
    }
    files = @($files)
    implementation = [pscustomobject][ordered]@{
        source_file_count = $sourceFiles.Count
        source_sha256 = $sourceSha
        inventory_cli = 'Tools/TMXY.Package/apps/package_inventory_main.cpp'
        error_schema_version = 1
        object_names_emitted = $false
        class_names_emitted = $false
        object_bodies_copied = $false
    }
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        client_mount = 'read-only'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_storage = 'ephemeral_tmpfs'
    }
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        ctest_count = 7
        inventory_line_count = $scannedByPath.Count
        stdout_sha256 = Get-TextSha256 -Value $execution.stdout
        stderr_sha256 = Get-TextSha256 -Value $execution.stderr
    }
    next_scope = [pscustomobject][ordered]@{
        tasks = @('P2-02', 'P2-03')
        detail = 'Validate full boundaries and derive the resource dependency graph without interpreting unknown bodies.'
    }
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($output)) | Out-Null
[System.IO.File]::WriteAllText($output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json
if (-not $completed) { throw 'P2-01 full Package inventory did not meet completion criteria.' }
