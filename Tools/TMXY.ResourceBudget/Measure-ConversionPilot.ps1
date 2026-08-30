[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath =
        'E:\QQXYCodeDev\Rebuild\Data\Performance\p2-19-conversion-pilot.json',
    [ValidateRange(5, 20)]
    [int]$MeasurementRuns = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$workspaceRoot = [System.IO.Path]::GetDirectoryName($root)
$output = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith(
        $root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-19 pilot output must remain inside Rebuild.'
}

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally {
        [System.Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON evidence is missing: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-One {
    param(
        [Parameter(Mandatory = $true)][object[]]$Values,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if ($Values.Count -ne 1) {
        throw "Expected exactly one $Description; found $($Values.Count)."
    }
    return $Values[0]
}

function Get-ObjectScope {
    param([Parameter(Mandatory = $true)][string]$ObjectName)
    $separator = $ObjectName.IndexOf('.')
    if ($separator -le 0 -or $separator -eq $ObjectName.Length - 1) {
        throw 'Selected evidence object does not have a scoped identity.'
    }
    return [pscustomobject][ordered]@{
        scope = $ObjectName.Substring(0, $separator)
        local_name = $ObjectName.Substring($separator + 1)
    }
}

function Resolve-ObjectCase {
    param(
        [Parameter(Mandatory = $true)][string]$Family,
        [Parameter(Mandatory = $true)][object]$Evidence,
        [Parameter(Mandatory = $true)][object]$Sample,
        [Parameter(Mandatory = $true)][string]$Extension
    )
    $identity = Get-ObjectScope -ObjectName ([string]$Sample.object)
    $payloadCandidates = @($Evidence.evidence | Where-Object {
            [System.IO.Path]::GetExtension([string]$_.path) -ieq $Extension -and
            [System.IO.Path]::GetFileNameWithoutExtension([string]$_.path) -ceq
                $identity.local_name
        })
    if ($Sample.PSObject.Properties.Name -contains 'payload_size') {
        $payloadCandidates = @($payloadCandidates | Where-Object {
                [int64]$_.size -eq [int64]$Sample.payload_size
            })
    }
    $payload = Assert-One -Values $payloadCandidates -Description "$Family payload evidence"
    $descriptor = Assert-One -Values @($Evidence.evidence | Where-Object {
            [System.IO.Path]::GetExtension([string]$_.path) -eq '' -and
            [System.IO.Path]::GetFileName([string]$_.path) -ceq $identity.scope
        }) -Description "$Family descriptor evidence"
    return [pscustomobject][ordered]@{
        family = $Family
        object_name = [string]$Sample.object
        payload = $payload
        descriptor = $descriptor
    }
}

function Resolve-PathCase {
    param(
        [Parameter(Mandatory = $true)][string]$Family,
        [Parameter(Mandatory = $true)][object]$Evidence,
        [Parameter(Mandatory = $true)][object]$Sample,
        [Parameter(Mandatory = $true)][string]$Extension
    )
    $suffix = ([string]$Sample.path).Replace('\', '/')
    $payload = Assert-One -Values @($Evidence.evidence | Where-Object {
            $candidate = ([string]$_.path).Replace('\', '/')
            [System.IO.Path]::GetExtension($candidate) -ieq $Extension -and
            $candidate.EndsWith('/' + $suffix, [System.StringComparison]::Ordinal)
        }) -Description "$Family payload evidence"
    return [pscustomobject][ordered]@{
        family = $Family
        object_name = $null
        payload = $payload
        descriptor = $null
    }
}

function Select-UpperMedianObjectCase {
    param(
        [Parameter(Mandatory = $true)][string]$Family,
        [Parameter(Mandatory = $true)][object]$Evidence,
        [Parameter(Mandatory = $true)][string]$Extension
    )
    $candidates = @(foreach ($sample in $Evidence.samples) {
            if ($sample.PSObject.Properties.Name -contains 'object') {
                Resolve-ObjectCase -Family $Family -Evidence $Evidence -Sample $sample `
                    -Extension $Extension
            }
        })
    if ($candidates.Count -lt 3) {
        throw "Median pilot selection requires at least three $Family evidence samples."
    }
    $ordered = @($candidates | Sort-Object -Property @(
            @{ Expression = { [int64]$_.payload.size }; Ascending = $true },
            @{ Expression = { [string]$_.payload.sha256 }; Ascending = $true }
        ))
    return $ordered[[math]::Floor($ordered.Count / 2)]
}

function Test-LegacyEvidenceRecord {
    param([Parameter(Mandatory = $true)][object]$Record)
    $relativePath = ([string]$Record.path).Replace('/', '\').TrimStart([char[]]'\')
    if ([System.IO.Path]::IsPathRooted($relativePath)) {
        throw 'Selected legacy evidence must use a workspace-relative path.'
    }
    $segments = @($relativePath.Split(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.StringSplitOptions]::RemoveEmptyEntries))
    if ($segments.Count -lt 2) {
        throw 'Selected legacy evidence is outside the five authorized read-only roots.'
    }
    $allowedRoots = @('ClientCode', 'ServerCode', 'ToolCode', 'DevDoc', '天命西游')
    $allowedRoot = @($allowedRoots | Where-Object {
            [string]::Equals($_, $segments[0], [System.StringComparison]::OrdinalIgnoreCase)
        })
    if ($allowedRoot.Count -ne 1) {
        throw 'Selected legacy evidence is outside the five authorized read-only roots.'
    }
    $authorizedRoot = [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot $allowedRoot[0]))
    $path = [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot $relativePath))
    if (-not $path.StartsWith(
            $authorizedRoot + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Selected legacy evidence is outside its authorized read-only root or is missing.'
    }
    $file = Get-Item -LiteralPath $path
    $actualSha = Get-LowerSha256 -Path $path
    if ([int64]$file.Length -ne [int64]$Record.size -or
        $actualSha -cne ([string]$Record.sha256).ToLowerInvariant() -or
        -not [bool]$Record.passed) {
        throw 'Selected legacy evidence differs from its tracked P1 contract.'
    }
    return [pscustomobject][ordered]@{
        host_path = $path
        container_path = '/evidence/' + ([string]$Record.path).Replace('\', '/')
        bytes = [int64]$file.Length
        sha256 = $actualSha
    }
}

function Get-DirectoryBytes {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return [int64]0 }
    $total = [int64]0
    foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File -Force) {
        $total += [int64]$file.Length
    }
    return $total
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
    [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@(
            $stdoutTask, $stderrTask))
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdout.Trim()
        stderr_sha256 = Get-TextSha256 -Value $stderr
    }
}

$p1Paths = [ordered]@{
    qtx = 'Data/BuildBaseline/p1-13-qtx-texture.json'
    sm = 'Data/BuildBaseline/p1-14-sm-static-mesh.json'
    skem = 'Data/BuildBaseline/p1-15-skem-skeletal-mesh.json'
    anim = 'Data/BuildBaseline/p1-16-anim-animation.json'
    ter = 'Data/BuildBaseline/p1-17-ter-terrain.json'
}
$p1 = [ordered]@{}
$p1Bindings = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $p1Paths.GetEnumerator()) {
    $path = Join-Path $root $entry.Value.Replace('/', '\')
    $value = Read-JsonFile -Path $path
    if ([string]$value.result -ne 'PASS' -or
        -not [bool]$value.completion_criteria_satisfied) {
        throw "P1 evidence is not complete for family $($entry.Key)."
    }
    $p1[$entry.Key] = $value
    $p1Bindings.Add([pscustomobject][ordered]@{
            family = $entry.Key
            task_id = [string]$value.task
            evidence = $entry.Value
            evidence_sha256 = Get-LowerSha256 -Path $path
        })
}

$skemSample = Assert-One -Values @($p1.skem.samples | Where-Object {
        [string]$_.role -eq 'canonical-player'
    }) -Description 'canonical-player skeletal-mesh sample'
$animSample = Assert-One -Values @($p1.anim.samples | Where-Object {
        $_.PSObject.Properties.Name -contains 'object' -and
        [string]$_.object -ceq [string]$skemSample.object
    }) -Description 'animation sample sharing the canonical-player identity'
$terSample = Assert-One -Values @($p1.ter.samples | Where-Object {
        [string]$_.role -like 'non-flat*'
    }) -Description 'non-flat terrain sample'

$selectedCases = @(
    Select-UpperMedianObjectCase -Family 'qtx' -Evidence $p1.qtx -Extension '.qtx'
    Select-UpperMedianObjectCase -Family 'sm' -Evidence $p1.sm -Extension '.sm'
    Resolve-ObjectCase -Family 'skem' -Evidence $p1.skem -Sample $skemSample -Extension '.skem'
    Resolve-ObjectCase -Family 'anim' -Evidence $p1.anim -Sample $animSample -Extension '.anim'
    Resolve-PathCase -Family 'ter' -Evidence $p1.ter -Sample $terSample -Extension '.ter'
)

$manifestCases = [System.Collections.Generic.List[object]]::new()
$selectedSourceRecords = [System.Collections.Generic.List[string]]::new()
foreach ($case in $selectedCases) {
    $payload = Test-LegacyEvidenceRecord -Record $case.payload
    $selectedSourceRecords.Add($payload.container_path)
    $descriptor = if ($null -ne $case.descriptor) {
        Test-LegacyEvidenceRecord -Record $case.descriptor
    }
    else { $null }
    if ($null -ne $descriptor) { $selectedSourceRecords.Add($descriptor.container_path) }
    $caseMaterial = "p2-19-pilot-v1`0$($case.family)`0$($payload.sha256)"
    if ($null -ne $descriptor) { $caseMaterial += "`0$($descriptor.sha256)" }
    $manifestCases.Add([pscustomobject][ordered]@{
            family = [string]$case.family
            case_id = Get-TextSha256 -Value $caseMaterial
            payload_path = $payload.container_path
            descriptor_path = if ($null -ne $descriptor) {
                $descriptor.container_path
            }
            else { $null }
            object_name = if ($null -ne $case.object_name) {
                [string]$case.object_name
            }
            else { $null }
            payload_bytes = $payload.bytes
            descriptor_bytes = if ($null -ne $descriptor) { $descriptor.bytes } else { 0 }
        })
}

$p215Path = Join-Path $root 'Data\Inventory\p2-15-conversion-routing.json'
$p215 = Read-JsonFile -Path $p215Path
if ([string]$p215.task_id -ne 'P2-15' -or [string]$p215.result -ne 'PASS' -or
    -not [bool]$p215.completion_criteria_satisfied) {
    throw 'P2-15 evidence is not complete.'
}
$routingPath = Join-Path $root ([string]$p215.report.path).Replace('/', '\')
if (-not (Test-Path -LiteralPath $routingPath -PathType Leaf)) {
    throw 'The ignored P2-15 full routing report must be regenerated before measuring P2-19.'
}
$routingSha = Get-LowerSha256 -Path $routingPath
$routingFile = Get-Item -LiteralPath $routingPath
if ($routingSha -cne [string]$p215.report.sha256 -or
    [int64]$routingFile.Length -ne [int64]$p215.report.bytes) {
    throw 'The P2-15 full routing report differs from its tracked evidence binding.'
}

$familyAggregates = [ordered]@{}
$routingLines = 0
$aliasJobViolations = 0
$manualNonJobViolations = 0
foreach ($line in Get-Content -LiteralPath $routingPath -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $row = $line | ConvertFrom-Json
    $family = [string]$row.family
    if (-not $familyAggregates.Contains($family)) {
        $familyAggregates[$family] = [ordered]@{
            family = $family
            files = [int64]0
            jobs = [int64]0
            aliases = [int64]0
            bytes = [int64]0
            ready = [int64]0
            manual = [int64]0
            ready_job_bytes = [int64]0
            manual_job_bytes = [int64]0
        }
    }
    $aggregate = $familyAggregates[$family]
    $aggregate.files++
    $aggregate.bytes += [int64]$row.bytes
    if ([bool]$row.conversion_job_required) {
        $aggregate.jobs++
        if ([string]$row.tier -eq 'manual') {
            $aggregate.manual_job_bytes += [int64]$row.bytes
        }
        else {
            $aggregate.ready_job_bytes += [int64]$row.bytes
        }
    }
    if ([string]$row.duplicate_handling -eq 'safe-reuse-alias') { $aggregate.aliases++ }
    if ([string]$row.tier -eq 'manual') { $aggregate.manual++ } else { $aggregate.ready++ }
    if ([string]$row.duplicate_handling -eq 'safe-reuse-alias' -and
        [bool]$row.conversion_job_required) {
        $aliasJobViolations++
    }
    if ([string]$row.tier -eq 'manual' -and -not [bool]$row.conversion_job_required) {
        $manualNonJobViolations++
    }
    $routingLines++
}
if ($routingLines -ne [int]$p215.report.lines) {
    throw 'P2-15 routing line count differs from its evidence binding.'
}
$routingByFamily = @($familyAggregates.Values | ForEach-Object {
        [pscustomobject]$_
    } | Sort-Object family)
$routingTotals = [pscustomobject][ordered]@{
    files = [int64](($routingByFamily | Measure-Object files -Sum).Sum)
    jobs = [int64](($routingByFamily | Measure-Object jobs -Sum).Sum)
    aliases = [int64](($routingByFamily | Measure-Object aliases -Sum).Sum)
    bytes = [int64](($routingByFamily | Measure-Object bytes -Sum).Sum)
    ready = [int64](($routingByFamily | Measure-Object ready -Sum).Sum)
    manual = [int64](($routingByFamily | Measure-Object manual -Sum).Sum)
    ready_job_bytes = [int64](($routingByFamily | Measure-Object ready_job_bytes -Sum).Sum)
    manual_job_bytes = [int64](($routingByFamily | Measure-Object manual_job_bytes -Sum).Sum)
}
if ($routingTotals.files -ne [int64]$p215.summary.assets.files -or
    $routingTotals.jobs -ne [int64]$p215.summary.assets.conversion_jobs -or
    $routingTotals.aliases -ne [int64]$p215.summary.assets.alias_reuse -or
    $routingTotals.bytes -ne [int64]$p215.summary.assets.bytes -or
    $routingTotals.manual -ne [int64]$p215.summary.tiers.manual.files -or
    $routingTotals.jobs -ne $routingTotals.files - $routingTotals.aliases -or
    $aliasJobViolations -ne 0 -or $manualNonJobViolations -ne 0) {
    throw 'P2-15 family aggregation does not close against tracked totals.'
}

$hostMemory = [int64](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$driveRoot = [System.IO.Path]::GetPathRoot($root)
$drive = [System.IO.DriveInfo]::new($driveRoot)
$gitDirectory = (& git -C $root rev-parse --absolute-git-dir).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the repository Git directory.' }
$trackedBytes = [int64]0
foreach ($relativePath in @(& git -C $root -c core.quotepath=false ls-files)) {
    $trackedPath = Join-Path $root $relativePath
    if (Test-Path -LiteralPath $trackedPath -PathType Leaf) {
        $trackedBytes += [int64](Get-Item -LiteralPath $trackedPath).Length
    }
}
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate Git-tracked files.' }

$generatedScopes = [ordered]@{
    data_exports = 'Data\Exports'
    generated_contracts = 'Contracts\generated'
    native_build = 'out'
    ue_binaries = 'Apps\UEClient\Binaries'
    ue_intermediate = 'Apps\UEClient\Intermediate'
    ue_saved = 'Apps\UEClient\Saved'
}
$generatedBreakdown = [System.Collections.Generic.List[object]]::new()
$generatedBytes = [int64]0
foreach ($scope in $generatedScopes.GetEnumerator()) {
    $bytes = Get-DirectoryBytes -Path (Join-Path $root $scope.Value)
    $generatedBytes += $bytes
    $generatedBreakdown.Add([pscustomobject][ordered]@{
            scope = $scope.Key
            bytes = $bytes
        })
}
$hostEnvironment = [pscustomobject][ordered]@{
    logical_processors = [Environment]::ProcessorCount
    physical_memory_bytes = $hostMemory
}
$storage = [pscustomobject][ordered]@{
    workspace_volume = $driveRoot.TrimEnd([char[]]'\/')
    workspace_volume_total_bytes = [int64]$drive.TotalSize
    workspace_volume_available_bytes = [int64]$drive.AvailableFreeSpace
    rebuild_bytes = Get-DirectoryBytes -Path $root
    git_database_bytes = Get-DirectoryBytes -Path $gitDirectory
    tracked_worktree_bytes = $trackedBytes
    generated_directories_bytes = $generatedBytes
    generated_breakdown = @($generatedBreakdown)
}

$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$lock = Read-JsonFile -Path $lockPath
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$docker = (Get-Command docker -ErrorAction Stop).Source
$imageJson = & $docker image inspect $builderReference 2>$null
if ($LASTEXITCODE -ne 0 -or -not $imageJson) {
    throw "Required builder image is unavailable: $builderReference"
}
$imageRecords = @($imageJson | ConvertFrom-Json)
$actualBuilderId = [string]$imageRecords[0].Id
$builderUser = [string]$imageRecords[0].Config.User
if ($actualBuilderId -cne $expectedBuilderId -or $builderUser -cne 'tmxy') {
    throw 'P2-19 requires the locked non-root builder identity.'
}

$localDirectory = Join-Path $root 'Data\Local'
[System.IO.Directory]::CreateDirectory($localDirectory) | Out-Null
$manifestName = '.p2-19-pilot-{0}.json' -f [Guid]::NewGuid().ToString('N')
$manifestPath = Join-Path $localDirectory $manifestName
$manifest = [pscustomobject][ordered]@{
    schema_version = 1
    measurement_runs = $MeasurementRuns
    cases = @($manifestCases)
}
$manifestJson = ($manifest | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    $manifestPath, $manifestJson + "`n", [System.Text.UTF8Encoding]::new($false))

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/pilot
cp /workspace/.clang-format /tmp/tmxy-rebuild/
cp /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /tmp/tmxy-rebuild/Tools/
cp /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /tmp/tmxy-rebuild/Tools/
for module in TMXY.FormatCore TMXY.Package TMXY.Transform TMXY.Texture \
  TMXY.StaticMesh TMXY.SkeletalMesh TMXY.Animation TMXY.Terrain; do
  cp -a "/workspace/Tools/$module" /tmp/tmxy-rebuild/Tools/
done
cd /tmp/tmxy-rebuild/Tools
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_ASSET_INVENTORY=OFF \
  >/tmp/pilot/configure.log 2>&1
cmake --build --preset ci-linux-clang --parallel 8 --target \
  tmxy_qtx_export tmxy_sm_export tmxy_skem_export tmxy_anim_export tmxy_ter_export \
  >/tmp/pilot/build.log 2>&1
python3 - <<'PY'
import hashlib
import json
import math
import os
import shutil
import statistics
import subprocess
import time
from pathlib import Path

manifest = json.loads(Path(os.environ["TMXY_PILOT_MANIFEST"]).read_text(encoding="utf-8"))
executables = {
    "qtx": "out/build/ci-linux-clang/TMXY.Texture/tmxy_qtx_export",
    "sm": "out/build/ci-linux-clang/TMXY.StaticMesh/tmxy_sm_export",
    "skem": "out/build/ci-linux-clang/TMXY.SkeletalMesh/tmxy_skem_export",
    "anim": "out/build/ci-linux-clang/TMXY.Animation/tmxy_anim_export",
    "ter": "out/build/ci-linux-clang/TMXY.Terrain/tmxy_ter_export",
}

def read_first(path, default):
    try:
        return Path(path).read_text(encoding="ascii").strip()
    except OSError:
        return default

def memory_total():
    for line in Path("/proc/meminfo").read_text(encoding="ascii").splitlines():
        if line.startswith("MemTotal:"):
            return int(line.split()[1]) * 1024
    return 0

def output_fingerprint(directory):
    digest = hashlib.sha256()
    total = 0
    files = sorted(path for path in directory.rglob("*") if path.is_file())
    for path in files:
        name = path.relative_to(directory).as_posix().encode("utf-8")
        digest.update(len(name).to_bytes(4, "big"))
        digest.update(name)
        with path.open("rb") as stream:
            while True:
                block = stream.read(1024 * 1024)
                if not block:
                    break
                total += len(block)
                digest.update(block)
    return total, len(files), digest.hexdigest()

def command_for(case, stem):
    command = [executables[case["family"]]]
    if case["family"] == "ter":
        return command + [case["payload_path"], str(stem)]
    return command + [
        case["descriptor_path"], case["object_name"], case["payload_path"], str(stem)
    ]

def execute(case, run_root):
    if run_root.exists():
        shutil.rmtree(run_root)
    run_root.mkdir(parents=True)
    started = time.perf_counter_ns()
    completed = subprocess.run(
        command_for(case, run_root / "sample"),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    elapsed_ns = time.perf_counter_ns() - started
    if completed.returncode != 0:
        raise RuntimeError("anonymous exporter case failed")
    output_bytes, output_files, output_sha256 = output_fingerprint(run_root)
    return round(elapsed_ns / 1_000_000.0, 3), output_bytes, output_files, output_sha256

results = []
for case in manifest["cases"]:
    family_root = Path("/tmp/pilot") / case["family"]
    execute(case, family_root / "warmup")
    elapsed = []
    output_bytes = []
    output_files = []
    output_hashes = []
    for index in range(manifest["measurement_runs"]):
        measurement = execute(case, family_root / f"measurement-{index}")
        elapsed.append(measurement[0])
        output_bytes.append(measurement[1])
        output_files.append(measurement[2])
        output_hashes.append(measurement[3])
    ordered = sorted(elapsed)
    p80 = ordered[math.ceil(0.80 * len(ordered)) - 1]
    results.append({
        "family": case["family"],
        "case_id": case["case_id"],
        "input_bytes": case["payload_bytes"] + case["descriptor_bytes"],
        "payload_bytes": case["payload_bytes"],
        "descriptor_bytes": case["descriptor_bytes"],
        "output_bytes": output_bytes[0],
        "output_file_count": output_files[0],
        "elapsed_ms": elapsed,
        "median_ms": round(statistics.median(elapsed), 3),
        "p80_ms": round(p80, 3),
        "output_hash_stable": len(set(output_hashes)) == 1,
        "output_size_stable": len(set(output_bytes)) == 1 and len(set(output_files)) == 1,
        "output_sha256": output_hashes[0],
    })
    shutil.rmtree(family_root)

container = {
    "visible_logical_processors": os.cpu_count() or 0,
    "visible_memory_bytes": memory_total(),
    "cgroup_cpu_max": read_first("/sys/fs/cgroup/cpu.max", "unavailable"),
    "cgroup_memory_max": read_first("/sys/fs/cgroup/memory.max", "unavailable"),
}
payload = {"container": container, "cases": results}
print("TMXY_PILOT_JSON=" + json.dumps(payload, sort_keys=True, separators=(",", ":")))
PY
'@

$containerManifest = '/workspace/Data/Local/' + $manifestName
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--pids-limit', '1024',
    '--tmpfs', '/tmp:rw,exec,nosuid,size=8g',
    '--env', "TMXY_PILOT_MANIFEST=$containerManifest",
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$workspaceRoot,target=/evidence,readonly",
    $builderReference, 'bash', '-c', $containerScript
)

try {
    $execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments `
        -WorkingDirectory $root
}
finally {
    if (Test-Path -LiteralPath $manifestPath) {
        Remove-Item -LiteralPath $manifestPath -Force
    }
}
if ($execution.exit_code -ne 0) {
    throw "P2-19 pilot container failed; stderr SHA-256: $($execution.stderr_sha256)"
}
$markerLines = @($execution.stdout -split "`n" | Where-Object {
        $_.StartsWith('TMXY_PILOT_JSON=', [System.StringComparison]::Ordinal)
    })
$marker = Assert-One -Values $markerLines -Description 'sanitized pilot result marker'
$pilot = $marker.Substring('TMXY_PILOT_JSON='.Length) | ConvertFrom-Json
$measuredCases = @($pilot.cases)
$stable = $measuredCases.Count -eq 5 -and
    @($measuredCases | Where-Object {
            -not [bool]$_.output_hash_stable -or
            -not [bool]$_.output_size_stable -or
            @($_.elapsed_ms).Count -ne $MeasurementRuns
        }).Count -eq 0

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($stable) { 'PASS' } else { 'FAIL' }
    task_id = 'P2-19-PILOT'
    evidence_kind = 'conversion-pilot'
    task_status = if ($stable) { 'COMPLETE' } else { 'FAILED' }
    completion_criteria_satisfied = $stable
    measurement_complete = $stable
    task_completion_claimed = $false
    protocol = [pscustomobject][ordered]@{
        sample_families = @('qtx', 'sm', 'skem', 'anim', 'ter')
        warmup_runs_per_case = 1
        measurement_runs_per_case = $MeasurementRuns
        timing_scope = 'exporter process only; configure and build are excluded'
        median_method = 'median of measured elapsed milliseconds'
        p80_method = 'nearest-rank ceiling at 80 percent'
        output_stability = 'SHA-256 over sorted generated filenames and bytes'
    }
    selection = [pscustomobject][ordered]@{
        source = 'tracked P1-13 through P1-17 evidence'
        qtx = 'upper-middle payload size after stable size and digest ordering'
        sm = 'upper-middle payload size after stable size and digest ordering'
        skem = 'canonical-player role'
        anim = 'sample sharing the canonical-player skeletal identity'
        ter = 'non-flat role'
        source_paths_emitted = $false
        object_names_emitted = $false
        sample_bytes_are_case_facts_not_population_bounds = $true
    }
    input_bindings = [pscustomobject][ordered]@{
        p1 = @($p1Bindings)
        p2_15 = [pscustomobject][ordered]@{
            evidence = 'Data/Inventory/p2-15-conversion-routing.json'
            evidence_sha256 = Get-LowerSha256 -Path $p215Path
            full_report_sha256 = $routingSha
            full_report_bytes = [int64]$routingFile.Length
            full_report_lines = $routingLines
        }
        selected_source_records_verified = $selectedSourceRecords.Count
        selected_unique_source_files_verified =
            @($selectedSourceRecords | Sort-Object -Unique).Count
    }
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
        exporters_compiled_before_measurement = 5
    }
    isolation = [pscustomobject][ordered]@{
        containers = 1
        network = 'none'
        repository_mount = 'read-only'
        legacy_evidence_mount = 'read-only'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        temporary_storage = 'container tmpfs and cleaned Data/Local manifest'
    }
    environment = [pscustomobject][ordered]@{
        host = $hostEnvironment
        container = $pilot.container
        storage = $storage
    }
    routing_by_family = $routingByFamily
    routing_totals = $routingTotals
    extrapolation_invariants = [pscustomobject][ordered]@{
        throughput_population = 'conversion jobs only'
        ready_job_count = $routingTotals.jobs - $routingTotals.manual
        manual_job_count = $routingTotals.manual
        alias_file_count = $routingTotals.aliases
        aliases_excluded_from_job_counts =
            $routingTotals.jobs -eq $routingTotals.files - $routingTotals.aliases
        aliases_excluded_from_ready_job_bytes = $true
        ready_job_bytes_plus_manual_job_bytes =
            $routingTotals.ready_job_bytes + $routingTotals.manual_job_bytes
        full_asset_bytes_include_aliases = $routingTotals.bytes
    }
    cases = $measuredCases
    disclosure = [pscustomobject][ordered]@{
        legacy_source_paths = $false
        legacy_object_names = $false
        raw_table_rows = $false
        exact_primary_keys = $false
        exact_observed_extrema = $false
        decoded_confidential_payloads = $false
    }
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($output)) | Out-Null
[System.IO.File]::WriteAllText($output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json
if (-not $stable) { throw 'P2-19 conversion pilot did not produce stable measured outputs.' }
