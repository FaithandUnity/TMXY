[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyRoot = 'E:\QQXYCodeDev\DevDoc\游戏资料\ltb\解密后',
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-10\p2-10-canonical-id-map.jsonl',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-10-canonical-id-map.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$legacy = [IO.Path]::GetFullPath($LegacyRoot).TrimEnd([char[]]'\/')
$report = [IO.Path]::GetFullPath($ReportPath)
$output = [IO.Path]::GetFullPath($OutputPath)
$exportRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Exports\P2-10')).TrimEnd([char[]]'\/')
if (-not $report.StartsWith(
        $exportRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'P2-10 report escaped its output root.'
}

$moduleRoot = Join-Path $root 'Tools\TMXY.CanonicalId'
$pythonPath = Join-Path $moduleRoot 'canonical_id.py'
$policyPath = Join-Path $root 'Contracts\data-schema\canonical-id-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\canonical-id-map-v1.schema.json'
$currentRoot = Join-Path $root 'Data\Exports\P2-06\tables'
$p209Path = Join-Path $root 'Data\Inventory\p2-09-legacy-current-diff.json'
$p207Path = Join-Path $root 'Data\Inventory\p2-07-core-table-schema.json'
$registryPath = Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
foreach ($path in @(
        $legacy, $moduleRoot, $pythonPath, $policyPath, $schemaPath, $currentRoot,
        $p209Path, $p207Path, $registryPath, $lockPath
    )) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "P2-10 input missing: $path"
    }
}

function Get-Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    try {
        [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)
        ).ToLowerInvariant()
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Invoke-Native([string]$File, [string[]]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $File
    $start.WorkingDirectory = $root
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    [pscustomobject]@{ code = $process.ExitCode; out = $stdout.Result; err = $stderr.Result }
}

$p209 = Get-Content -LiteralPath $p209Path -Raw | ConvertFrom-Json
$p207 = Get-Content -LiteralPath $p207Path -Raw | ConvertFrom-Json
if ($p209.result -ne 'PASS' -or -not $p209.completion_criteria_satisfied) {
    throw 'P2-10 requires completed P2-09.'
}
if ($p207.result -ne 'PASS' -or -not $p207.completion_criteria_satisfied) {
    throw 'P2-10 requires completed P2-07.'
}

$sourceFiles = @(
    Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object Extension -in @('.ps1', '.py') |
        Sort-Object FullName
)
$sourceLines = @($sourceFiles | ForEach-Object {
        "$([IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/'))|$(Get-Sha $_.FullName)"
    })
$sourceHash = Get-TextSha (($sourceLines -join "`n") + "`n")
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$imageRef = [string]$lock.backend_toolchain.container_image_reference
$imageId = [string]$lock.backend_toolchain.container_image_digest
$image = @(docker image inspect $imageRef 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
    $image[0].Id -ne $imageId -or $image[0].Config.User -ne 'tmxy') {
    throw 'P2-10 requires qualified builder.'
}

[IO.Directory]::CreateDirectory($exportRoot) | Out-Null
$tempName = '.p2-10-' + [Guid]::NewGuid().ToString('N') + '.jsonl'
$temp = Join-Path $exportRoot $tempName
$script = @'
set -euo pipefail
self=$(python3 /workspace/Tools/TMXY.CanonicalId/canonical_id.py --self-test)
printf 'SELFTEST\t%s\n' "$self"
summary=$(python3 /workspace/Tools/TMXY.CanonicalId/canonical_id.py --legacy /legacy --current /workspace/Data/Exports/P2-06/tables --registry /workspace/Data/Schemas/core-table-registry-v1.json --output "$TMXY_CANONICAL_ID_OUTPUT")
printf 'SUMMARY\t%s\n' "$summary"
'@
$docker = (Get-Command docker).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--env', "TMXY_CANONICAL_ID_OUTPUT=/output/$tempName",
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$legacy,target=/legacy,readonly",
    '--mount', "type=bind,source=$exportRoot,target=/output",
    $imageRef, 'bash', '-c', $script
)

try {
    $run = Invoke-Native -File $docker -Arguments $arguments
    if ($run.code -ne 0) {
        throw "P2-10 failed: $($run.err)"
    }
    $selfLine = @($run.out -split "`n" | Where-Object { $_.StartsWith("SELFTEST`t") })
    $summaryLine = @($run.out -split "`n" | Where-Object { $_.StartsWith("SUMMARY`t") })
    if ($selfLine.Count -ne 1 -or $summaryLine.Count -ne 1) {
        throw 'P2-10 framing failed.'
    }
    $self = $selfLine[0].Substring(9) | ConvertFrom-Json
    $summary = $summaryLine[0].Substring(8) | ConvertFrom-Json
    if ((Get-Sha $temp) -ne $summary.report.sha256 -or
        (Get-Item -LiteralPath $temp).Length -ne $summary.report.bytes) {
        throw 'P2-10 report hash mismatch.'
    }
    if ($summary.inputs.legacy_manifest_sha256 -ne $p209.input.legacy_manifest_sha256) {
        throw 'P2-10 legacy snapshot binding differs from P2-09.'
    }
    $complete = $self.result -eq 'PASS' -and $self.assertions -eq 8 -and
        $summary.result -eq 'PASS' -and $summary.summary.domain_count -eq 12 -and
        $summary.summary.comparable_legacy_domains -eq 10 -and
        $summary.summary.mapping_records -eq 87328 -and
        $summary.summary.current_unique_ids -eq 87044 -and
        $summary.summary.legacy_unique_ids -eq 27252 -and
        $summary.summary.shared_ids -eq 26968 -and
        $summary.summary.current_only_ids -eq 60076 -and
        $summary.summary.tombstones -eq 284 -and
        $summary.summary.legacy_preserved_ids -eq 27252 -and
        $summary.summary.collapsed_duplicate_groups -eq 700 -and
        $summary.summary.collapsed_duplicate_occurrences -eq 800 -and
        $summary.summary.legacy_type_exception_components -eq 6 -and
        $summary.summary.conflicts -eq 0 -and
        $summary.summary.explicit_remaps -eq 0 -and
        $summary.summary.automatic_renumberings -eq 0 -and
        $summary.summary.unresolved_conflicts -eq 0
    if ($Check) {
        if (-not (Test-Path -LiteralPath $report) -or (Get-Sha $report) -ne $summary.report.sha256) {
            throw 'P2-10 report changed.'
        }
    }
    else {
        Move-Item -LiteralPath $temp -Destination $report -Force
    }
    $captured = [DateTimeOffset]::UtcNow.ToString('o')
    if ($Check -and (Test-Path -LiteralPath $output)) {
        $captured = [string](
            Get-Content -LiteralPath $output -Raw |
                ConvertFrom-Json -DateKind String
        ).captured_utc
    }
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = $captured
        task_id = 'P2-10'
        result = if ($complete) { 'PASS' } else { 'FAIL' }
        task_status = if ($complete) { 'COMPLETE' } else { 'IN_PROGRESS' }
        completion_criteria_satisfied = $complete
        input = [pscustomobject][ordered]@{
            legacy_snapshot = [string]$p209.input.legacy_snapshot
            legacy_build = 'unknown-not-inferred'
            legacy_manifest_sha256 = [string]$summary.inputs.legacy_manifest_sha256
            current_build = [string]$p209.input.current_build
            current_manifest_sha256 = [string]$summary.inputs.current_manifest_sha256
            p2_09_evidence_sha256 = Get-Sha $p209Path
            p2_09_report_sha256 = [string]$p209.report.sha256
            p2_07_evidence_sha256 = Get-Sha $p207Path
            core_registry_sha256 = [string]$summary.inputs.registry_sha256
            copy_policy = 'reference_only'
        }
        report = [pscustomobject][ordered]@{
            path = 'Data/Exports/P2-10/p2-10-canonical-id-map.jsonl'
            tracked = $false
            lines = [int]$summary.report.lines
            bytes = [int64]$summary.report.bytes
            sha256 = [string]$summary.report.sha256
        }
        summary = $summary.summary
        domains = $summary.domains
        contracts = [pscustomobject][ordered]@{
            policy = 'Contracts/data-schema/canonical-id-policy-v1.json'
            policy_sha256 = Get-Sha $policyPath
            schema = 'Contracts/data-schema/canonical-id-map-v1.schema.json'
            schema_sha256 = Get-Sha $schemaPath
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceHash
            self_test_assertions = [int]$self.assertions
            generator = 'Tools/TMXY.CanonicalId/New-CanonicalIdMap.ps1'
            query = 'Tools/TMXY.CanonicalId/Find-CanonicalIdMapping.ps1'
        }
        disclosure = [pscustomobject][ordered]@{
            tracked_evidence_contains_primary_keys = $false
            tracked_evidence_contains_row_values = $false
            full_map_contains_primary_keys = $true
            full_map_committed_to_git = $false
            query_emits_primary_keys = $false
            legacy_payloads_copied = $false
        }
        reproduction = [pscustomobject][ordered]@{
            check_mode = '-Check'
            legacy_mount = 'read-only'
            workspace_mount = 'read-only'
            network = 'none'
            builder_id = $imageId
            builder_user = 'tmxy'
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-11', 'P2-17')
            detail = 'Audit ID widths and generate shared typed ID declarations from the frozen domains.'
        }
    }
    $json = ($evidence | ConvertTo-Json -Depth 30).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($Check) {
        $existing = (Get-Content -LiteralPath $output -Raw).Replace("`r`n", "`n").Replace("`r", "`n")
        if ($existing -ne $json + "`n") {
            throw 'P2-10 evidence changed.'
        }
    }
    else {
        [IO.File]::WriteAllText($output, $json + "`n", [Text.UTF8Encoding]::new($false))
    }
    $json
    if (-not $complete) {
        throw 'P2-10 incomplete.'
    }
}
finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force
    }
}
