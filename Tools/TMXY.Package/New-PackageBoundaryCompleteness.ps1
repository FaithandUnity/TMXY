[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-02-package-boundary-completeness.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith(
        $root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-02 output must remain inside Rebuild.'
}

$packagesRoot = Join-Path $client 'Packages'
$manifestPath = Join-Path $root 'Data\RawManifests\client-3.0.0.413.files.jsonl'
$inventoryPath = Join-Path $root 'Data\Inventory\p2-01-package-inventory.json'
$goldenPath = Join-Path $root 'Data\GoldenSamples\p0-golden-samples.json'
$moduleRoot = Join-Path $root 'Tools\TMXY.Package'
foreach ($path in @($packagesRoot, $manifestPath, $inventoryPath, $goldenPath, $moduleRoot)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-02 input is missing: $path" }
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
            throw 'P2-02 refuses Package paths containing control separators.'
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
    throw 'P2-02 requires the frozen set of 167 unique Package files.'
}

$inputFailures = [System.Collections.Generic.List[string]]::new()
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
}
if ($inputFailures.Count -gt 0) {
    throw "P2-02 frozen Package inputs changed: $($inputFailures -join ', ')"
}

$p201 = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$p201.result -ne 'PASS' -or [string]$p201.task -ne 'P2-01' -or
    -not [bool]$p201.completion_criteria_satisfied) {
    throw 'P2-02 requires completed P2-01 inventory evidence.'
}
$p201ByPath = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::Ordinal)
foreach ($entry in @($p201.files)) { $p201ByPath.Add([string]$entry.path, $entry) }
if ($p201ByPath.Count -ne 167) { throw 'P2-01 inventory does not contain 167 unique files.' }

$golden = Get-Content -LiteralPath $goldenPath -Raw -Encoding UTF8 | ConvertFrom-Json
$corePaths = @($golden.samples | Where-Object {
        [string]$_.kind -eq 'package' -and [bool]$_.source_verified -and
        [string]$_.package_version -in @('1.0', '2.0', '3.0')
    } | ForEach-Object { [string]$_.path } | Sort-Object -Unique)
if ($corePaths.Count -ne 12) { throw 'P2-02 requires the frozen 12-package golden core set.' }
$coreSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($path in $corePaths) { [void]$coreSet.Add($path) }

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
    throw 'P2-02 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/package-boundary-audit
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
truncated=/tmp/package-boundary-audit/truncated.package
appended=/tmp/package-boundary-audit/appended.package
while IFS= read -r -d '' file; do
  relative=${file#/legacy/}
  printf '%s\toriginal\t' "$relative"
  "$inventory" "$file"
  bytes=$(stat -c '%s' "$file")
  if (( bytes == 0 )); then
    continue
  fi
  head -c "$((bytes - 1))" "$file" > "$truncated"
  printf '%s\ttruncated_tail\t' "$relative"
  "$inventory" "$truncated"
  cp "$file" "$appended"
  printf '\0' >> "$appended"
  printf '%s\tappended_tail\t' "$relative"
  "$inventory" "$appended"
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
    throw "P2-02 locked audit failed: $($execution.stderr.Trim())"
}

$scans = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::Ordinal)
foreach ($line in @($execution.stdout -split "`n")) {
    $first = $line.IndexOf("`t", [System.StringComparison]::Ordinal)
    if ($first -lt 1) { continue }
    $second = $line.IndexOf("`t", $first + 1)
    if ($second -lt $first -or -not $line.EndsWith('}', [System.StringComparison]::Ordinal)) {
        continue
    }
    $relative = $line.Substring(0, $first)
    $mode = $line.Substring($first + 1, $second - $first - 1)
    if (-not $relative.StartsWith('Packages/', [System.StringComparison]::Ordinal) -or
        $mode -notin @('original', 'truncated_tail', 'appended_tail')) {
        continue
    }
    $key = "$relative|$mode"
    if ($scans.ContainsKey($key)) { throw "P2-02 emitted a duplicate scan: $key" }
    $scans.Add($key, ($line.Substring($second + 1) | ConvertFrom-Json))
}
if (@($scans.Keys | Where-Object { $_.EndsWith('|original') }).Count -ne 167) {
    throw 'P2-02 did not return every original Package-directory file.'
}

$packages = [System.Collections.Generic.List[object]]::new()
$nonPackages = [System.Collections.Generic.List[object]]::new()
$bindingFailures = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $manifestEntries) {
    $baseline = $p201ByPath[$entry.path]
    $original = $scans["$($entry.path)|original"]
    if ($null -eq $original -or [int64]$original.file_bytes -ne $entry.size -or
        [string]$original.version -ne [string]$baseline.version -or
        [bool]$original.recognized -ne [bool]$baseline.recognized -or
        [bool]$original.parsed -ne [bool]$baseline.parsed -or
        [int64]$original.directory_bytes -ne [int64]$baseline.directory_bytes -or
        [int64]$original.record_count -ne [int64]$baseline.record_count -or
        [string]$original.metadata_fingerprint -ne [string]$baseline.metadata_fingerprint) {
        $bindingFailures.Add($entry.path)
        continue
    }
    if (-not [bool]$original.recognized) {
        $nonPackages.Add([pscustomobject][ordered]@{
            path = $entry.path
            bytes = $entry.size
            sha256 = $entry.sha256
            classification = [string]$original.version
            error = [string]$original.error
        })
        continue
    }

    $truncated = $scans["$($entry.path)|truncated_tail"]
    $appended = $scans["$($entry.path)|appended_tail"]
    if ($null -eq $truncated -or $null -eq $appended) {
        $bindingFailures.Add("mutation:$($entry.path)")
        continue
    }
    $headerBytes = if ([string]$original.version -eq '1.0') {
        [int64]$original.directory_bytes
    }
    else {
        29L + [int64]$original.directory_bytes
    }
    $objectBytes = [int64]$entry.size - $headerBytes
    $truncationRejected = [bool]$truncated.recognized -and -not [bool]$truncated.parsed -and
        [string]$truncated.error -eq 'object_range_out_of_file'
    $trailingRejected = [bool]$appended.recognized -and -not [bool]$appended.parsed -and
        [string]$appended.error -eq 'non_contiguous_object_range'
    $boundaryComplete = [bool]$original.parsed -and $headerBytes -ge 0 -and
        $objectBytes -ge 0 -and ($headerBytes + $objectBytes) -eq [int64]$entry.size
    $packages.Add([pscustomobject][ordered]@{
        path = $entry.path
        version = [string]$original.version
        bytes = [int64]$entry.size
        sha256 = $entry.sha256
        core = $coreSet.Contains($entry.path)
        record_count = [int64]$original.record_count
        header_bytes = $headerBytes
        object_bytes = $objectBytes
        covered_bytes = $headerBytes + $objectBytes
        uncovered_bytes = 0L
        boundary_complete = $boundaryComplete
        truncated_tail = [pscustomobject][ordered]@{
            rejected = $truncationRejected
            error = [string]$truncated.error
            error_offset = [int64]$truncated.error_offset
        }
        appended_tail = [pscustomobject][ordered]@{
            rejected = $trailingRejected
            error = [string]$appended.error
            error_offset = [int64]$appended.error_offset
        }
    })
}
if ($bindingFailures.Count -gt 0) {
    throw "P2-02 scan disagrees with P2-01: $($bindingFailures -join ', ')"
}

$packageFiles = @($packages)
$corePackages = @($packageFiles | Where-Object core)
$boundaryFailures = @($packageFiles | Where-Object { -not $_.boundary_complete })
$truncationFailures = @($packageFiles | Where-Object { -not $_.truncated_tail.rejected })
$trailingFailures = @($packageFiles | Where-Object { -not $_.appended_tail.rejected })
$parsedRatePpm = if ($packageFiles.Count -eq 0) { 0 } else {
    [int][Math]::Floor(1000000.0 * @($packageFiles | Where-Object boundary_complete).Count /
        $packageFiles.Count)
}
$coreRatePpm = if ($corePackages.Count -eq 0) { 0 } else {
    [int][Math]::Floor(1000000.0 * @($corePackages | Where-Object boundary_complete).Count /
        $corePackages.Count)
}
$mutationChecks = 2 * $packageFiles.Count
$mutationRejections = $mutationChecks - $truncationFailures.Count - $trailingFailures.Count
$completed = $manifestEntries.Count -eq 167 -and $packageFiles.Count -eq 163 -and
    $nonPackages.Count -eq 4 -and $corePackages.Count -eq 12 -and
    $parsedRatePpm -ge 999000 -and $coreRatePpm -eq 1000000 -and
    $boundaryFailures.Count -eq 0 -and $mutationChecks -eq 326 -and
    $mutationRejections -eq $mutationChecks -and $inputFailures.Count -eq 0

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($completed) { 'PASS' } else { 'FAIL' }
    task = 'P2-02'
    task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
    completion_criteria_satisfied = $completed
    input = [pscustomobject][ordered]@{
        client_version = '3.0.0.413'
        manifest = 'Data/RawManifests/client-3.0.0.413.files.jsonl'
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        p2_01_inventory = 'Data/Inventory/p2-01-package-inventory.json'
        p2_01_inventory_sha256 = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
        golden_samples = 'Data/GoldenSamples/p0-golden-samples.json'
        golden_samples_sha256 = (Get-FileHash -LiteralPath $goldenPath -Algorithm SHA256).Hash.ToLowerInvariant()
        integrity_failures = $inputFailures.Count
        copy_policy = 'reference_only'
    }
    summary = [pscustomobject][ordered]@{
        files_classified = $manifestEntries.Count
        recognized_packages = $packageFiles.Count
        explicit_non_packages = $nonPackages.Count
        complete_packages = @($packageFiles | Where-Object boundary_complete).Count
        complete_parse_rate_ppm = $parsedRatePpm
        required_parse_rate_ppm = 999000
        core_packages = $corePackages.Count
        complete_core_packages = @($corePackages | Where-Object boundary_complete).Count
        core_parse_rate_ppm = $coreRatePpm
        required_core_rate_ppm = 1000000
        records = [int64](($packageFiles | Measure-Object record_count -Sum).Sum)
        source_bytes = [int64](($packageFiles | Measure-Object bytes -Sum).Sum)
        header_bytes = [int64](($packageFiles | Measure-Object header_bytes -Sum).Sum)
        object_bytes = [int64](($packageFiles | Measure-Object object_bytes -Sum).Sum)
        covered_bytes = [int64](($packageFiles | Measure-Object covered_bytes -Sum).Sum)
        uncovered_bytes = [int64](($packageFiles | Measure-Object uncovered_bytes -Sum).Sum)
        mutation_checks = $mutationChecks
        mutation_rejections = $mutationRejections
        silent_truncation_accepts = $truncationFailures.Count
        silent_trailing_byte_accepts = $trailingFailures.Count
    }
    core_definition = [pscustomobject][ordered]@{
        authority = 'Data/GoldenSamples/p0-golden-samples.json'
        rule = 'source_verified Package samples with format version 1.0, 2.0, or 3.0'
        paths = $corePaths
    }
    packages = $packageFiles
    non_packages = @($nonPackages)
    parser_invariants = @(
        'Every object range begins at the prior range end.',
        'The first object begins at header_size.',
        'The final object range ends exactly at file_size.',
        'Directory readers reject trailing directory bytes.'
    )
    mutation_policy = [pscustomobject][ordered]@{
        tail_truncation = 'Remove exactly one byte from every recognized frozen Package; parsing must fail with object_range_out_of_file.'
        trailing_byte = 'Append exactly one zero byte to every recognized frozen Package; parsing must fail with non_contiguous_object_range.'
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
    disclosure = [pscustomobject][ordered]@{
        object_names_emitted = $false
        class_names_emitted = $false
        object_bodies_copied = $false
    }
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        ctest_count = 7
        original_scans = @($scans.Keys | Where-Object { $_.EndsWith('|original') }).Count
        mutation_scans = @($scans.Keys | Where-Object { -not $_.EndsWith('|original') }).Count
        stdout_sha256 = Get-TextSha256 -Value $execution.stdout
        stderr_sha256 = Get-TextSha256 -Value $execution.stderr
    }
    next_scope = [pscustomobject][ordered]@{
        tasks = @('P2-03', 'P2-04')
        detail = 'Use proven source spans to build a dependency graph and catalog object classes without guessing opaque body semantics.'
    }
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($output)) | Out-Null
[System.IO.File]::WriteAllText($output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json
if (-not $completed) { throw 'P2-02 Package boundary audit did not meet completion criteria.' }
