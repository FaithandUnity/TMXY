[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\ClientCode',
    [string]$ServerRoot = 'E:\QQXYCodeDev\ServerCode',
    [string]$ToolRoot = 'E:\QQXYCodeDev\ToolCode',
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-11\p2-11-id-limit-audit.jsonl',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-11-id-limit-audit.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$server = [IO.Path]::GetFullPath($ServerRoot).TrimEnd([char[]]'\/')
$tool = [IO.Path]::GetFullPath($ToolRoot).TrimEnd([char[]]'\/')
$report = [IO.Path]::GetFullPath($ReportPath)
$output = [IO.Path]::GetFullPath($OutputPath)
$exportRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Exports\P2-11')).TrimEnd([char[]]'\/')
if (-not $report.StartsWith($exportRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-11 report escaped its output root.'
}
$moduleRoot = Join-Path $root 'Tools\TMXY.IdLimitAudit'
$pythonPath = Join-Path $moduleRoot 'id_limit_audit.py'
$policyPath = Join-Path $root 'Contracts\data-schema\id-limit-audit-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\id-limit-audit-v1.schema.json'
$p210Path = Join-Path $root 'Data\Inventory\p2-10-canonical-id-map.json'
$p210Report = Join-Path $root 'Data\Exports\P2-10\p2-10-canonical-id-map.jsonl'
$p204Path = Join-Path $root 'Data\Inventory\p2-04-current-table-inventory.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
foreach ($path in @($client, $server, $tool, $moduleRoot, $pythonPath, $policyPath, $schemaPath, $p210Path, $p210Report, $p204Path, $lockPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-11 input missing: $path" }
}

function Get-Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-TextSha([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    try { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}
function Invoke-Native([string]$File, [string[]]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $File; $start.WorkingDirectory = $root
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    [pscustomobject]@{ code = $process.ExitCode; out = $stdout.Result; err = $stderr.Result }
}

$p210 = Get-Content -LiteralPath $p210Path -Raw | ConvertFrom-Json
$p204 = Get-Content -LiteralPath $p204Path -Raw | ConvertFrom-Json
if ($p210.result -ne 'PASS' -or -not $p210.completion_criteria_satisfied) { throw 'P2-11 requires completed P2-10.' }
if ($p204.result -ne 'PASS' -or -not $p204.completion_criteria_satisfied) { throw 'P2-11 requires completed P2-04.' }
$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File | Where-Object Extension -in @('.ps1', '.py') | Sort-Object FullName)
$sourceLines = @($sourceFiles | ForEach-Object { "$([IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/'))|$(Get-Sha $_.FullName)" })
$sourceHash = Get-TextSha (($sourceLines -join "`n") + "`n")
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$imageRef = [string]$lock.backend_toolchain.container_image_reference
$imageId = [string]$lock.backend_toolchain.container_image_digest
$image = @(docker image inspect $imageRef 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or $image[0].Id -ne $imageId -or $image[0].Config.User -ne 'tmxy') {
    throw 'P2-11 requires qualified builder.'
}

[IO.Directory]::CreateDirectory($exportRoot) | Out-Null
$tempName = '.p2-11-' + [Guid]::NewGuid().ToString('N') + '.jsonl'
$temp = Join-Path $exportRoot $tempName
$script = @'
set -euo pipefail
self=$(python3 /workspace/Tools/TMXY.IdLimitAudit/id_limit_audit.py --self-test)
printf 'SELFTEST\t%s\n' "$self"
summary=$(python3 /workspace/Tools/TMXY.IdLimitAudit/id_limit_audit.py --canonical-map /workspace/Data/Exports/P2-10/p2-10-canonical-id-map.jsonl --canonical-evidence /workspace/Data/Inventory/p2-10-canonical-id-map.json --client /legacy-client --server /legacy-server --tool /legacy-tool --output "$TMXY_ID_LIMIT_OUTPUT")
printf 'SUMMARY\t%s\n' "$summary"
'@
$docker = (Get-Command docker).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--env', "TMXY_ID_LIMIT_OUTPUT=/output/$tempName",
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$client,target=/legacy-client,readonly",
    '--mount', "type=bind,source=$server,target=/legacy-server,readonly",
    '--mount', "type=bind,source=$tool,target=/legacy-tool,readonly",
    '--mount', "type=bind,source=$exportRoot,target=/output",
    $imageRef, 'bash', '-c', $script
)
try {
    $run = Invoke-Native -File $docker -Arguments $arguments
    if ($run.code -ne 0) { throw "P2-11 failed: $($run.err)" }
    $selfLine = @($run.out -split "`n" | Where-Object { $_.StartsWith("SELFTEST`t") })
    $summaryLine = @($run.out -split "`n" | Where-Object { $_.StartsWith("SUMMARY`t") })
    if ($selfLine.Count -ne 1 -or $summaryLine.Count -ne 1) { throw 'P2-11 framing failed.' }
    $self = $selfLine[0].Substring(9) | ConvertFrom-Json
    $summary = $summaryLine[0].Substring(8) | ConvertFrom-Json
    if ((Get-Sha $temp) -ne $summary.report.sha256 -or (Get-Item -LiteralPath $temp).Length -ne $summary.report.bytes) {
        throw 'P2-11 report hash mismatch.'
    }
    if ($summary.inputs.canonical_map_sha256 -ne $p210.report.sha256) { throw 'P2-11 Canonical ID map binding differs.' }
    $complete = $self.result -eq 'PASS' -and $self.assertions -eq 7 -and $summary.result -eq 'PASS' -and
        $summary.summary.domain_count -eq 12 -and $summary.summary.component_count -eq 16 -and
        $summary.summary.numeric_components -eq 13 -and $summary.summary.string_components -eq 3 -and
        $summary.summary.risk_counts.u16_overflow -eq 0 -and
        $summary.source_signals.total_source_files -eq 8090 -and
        @($summary.source_signals.rules.psobject.Properties).Count -eq 4
    if ($Check) {
        if (-not (Test-Path -LiteralPath $report) -or (Get-Sha $report) -ne $summary.report.sha256) { throw 'P2-11 report changed.' }
    }
    else { Move-Item -LiteralPath $temp -Destination $report -Force }
    $captured = [DateTimeOffset]::UtcNow.ToString('o')
    if ($Check -and (Test-Path -LiteralPath $output)) {
        $captured = [string](Get-Content -LiteralPath $output -Raw | ConvertFrom-Json -DateKind String).captured_utc
    }
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1; captured_utc = $captured; task_id = 'P2-11'
        result = if ($complete) { 'PASS' } else { 'FAIL' }
        task_status = if ($complete) { 'COMPLETE' } else { 'IN_PROGRESS' }
        completion_criteria_satisfied = $complete
        input = [pscustomobject][ordered]@{
            p2_10_evidence_sha256 = Get-Sha $p210Path; p2_10_map_sha256 = [string]$summary.inputs.canonical_map_sha256
            p2_04_evidence_sha256 = Get-Sha $p204Path; legacy_source_manifest_sha256 = [string]$summary.inputs.legacy_source_manifest_sha256
            copy_policy = 'reference_only'
        }
        report = [pscustomobject][ordered]@{ path = 'Data/Exports/P2-11/p2-11-id-limit-audit.jsonl'; tracked = $false; lines = [int]$summary.report.lines; bytes = [int64]$summary.report.bytes; sha256 = [string]$summary.report.sha256 }
        summary = $summary.summary; components = $summary.components; source_signals = $summary.source_signals
        contracts = [pscustomobject][ordered]@{
            policy = 'Contracts/data-schema/id-limit-audit-policy-v1.json'; policy_sha256 = Get-Sha $policyPath
            schema = 'Contracts/data-schema/id-limit-audit-v1.schema.json'; schema_sha256 = Get-Sha $schemaPath
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count; source_sha256 = $sourceHash; self_test_assertions = [int]$self.assertions
            generator = 'Tools/TMXY.IdLimitAudit/New-IdLimitAudit.ps1'; query = 'Tools/TMXY.IdLimitAudit/Find-IdLimitRisk.ps1'
        }
        disclosure = [pscustomobject][ordered]@{
            tracked_evidence_contains_primary_keys = $false; tracked_evidence_contains_minimum_or_maximum_values = $false
            tracked_evidence_contains_legacy_source_paths = $false; tracked_evidence_contains_legacy_source_lines = $false
            full_audit_committed_to_git = $false; legacy_sources_copied = $false
        }
        reproduction = [pscustomobject][ordered]@{
            check_mode = '-Check'; workspace_mount = 'read-only'; legacy_mounts = 3; network = 'none'
            builder_id = $imageId; builder_user = 'tmxy'
        }
        next_scope = [pscustomobject][ordered]@{ tasks = @('P2-17'); detail = 'Generate shared strongly typed ID declarations without narrowing past the audited limits.' }
    }
    $json = ($evidence | ConvertTo-Json -Depth 30).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($Check) {
        $existing = (Get-Content -LiteralPath $output -Raw).Replace("`r`n", "`n").Replace("`r", "`n")
        if ($existing -ne $json + "`n") { throw 'P2-11 evidence changed.' }
    }
    else { [IO.File]::WriteAllText($output, $json + "`n", [Text.UTF8Encoding]::new($false)) }
    $json
    if (-not $complete) { throw 'P2-11 incomplete.' }
}
finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
