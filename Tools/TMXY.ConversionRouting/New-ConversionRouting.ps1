[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-15\p2-15-conversion-routing.jsonl',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-15-conversion-routing.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$report = [IO.Path]::GetFullPath($ReportPath)
$output = [IO.Path]::GetFullPath($OutputPath)
$exportRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Exports\P2-15')).TrimEnd([char[]]'\/')
$inventoryRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Inventory')).TrimEnd([char[]]'\/')
if (-not $report.StartsWith($exportRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith($inventoryRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-15 outputs escaped their scoped Rebuild directories.'
}

$moduleRoot = Join-Path $root 'Tools\TMXY.ConversionRouting'
$pythonPath = Join-Path $moduleRoot 'conversion_routing.py'
$queryPath = Join-Path $moduleRoot 'Find-ConversionRoute.ps1'
$policyPath = Join-Path $root 'Contracts\data-schema\conversion-routing-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\conversion-routing-v1.schema.json'
$healthReportPath = Join-Path $root 'Data\Exports\P2-14\p2-14-asset-health.jsonl'
$healthEvidencePath = Join-Path $root 'Data\Inventory\p2-14-asset-health.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
foreach ($path in @($moduleRoot, $pythonPath, $queryPath, $policyPath, $schemaPath,
        $healthReportPath, $healthEvidencePath, $lockPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-15 input is missing: $path" }
}
[IO.Directory]::CreateDirectory($exportRoot) | Out-Null

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdout.GetAwaiter().GetResult()
        stderr = $stderr.GetAwaiter().GetResult()
    }
}

$healthEvidence = Get-Content -LiteralPath $healthEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($healthEvidence.result -ne 'PASS' -or -not $healthEvidence.completion_criteria_satisfied) {
    throw 'P2-15 requires completed P2-14 evidence.'
}
if ((Get-FileSha256 $healthReportPath) -ne [string]$healthEvidence.report.sha256) {
    throw 'P2-15 health report hash binding failed.'
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
$sourceLines = @($sourceFiles | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
        "$relative|$(Get-FileSha256 $_.FullName)"
    })
$sourceHash = Get-TextSha256 -Value (($sourceLines -join "`n") + "`n")

$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
    [string]$image[0].Id -ne $expectedBuilderId -or [string]$image[0].Config.User -ne 'tmxy') {
    throw 'P2-15 requires the qualified non-root Clang 21 builder image.'
}

$temporaryName = '.p2-15-' + [Guid]::NewGuid().ToString('N') + '.jsonl'
$temporaryReport = Join-Path $exportRoot $temporaryName
$containerOutput = "/output/$temporaryName"
$containerScript = @'
set -euo pipefail
self_test=$(python3 /workspace/Tools/TMXY.ConversionRouting/conversion_routing.py --self-test)
printf 'SELFTEST\t%s\n' "$self_test"
summary=$(python3 /workspace/Tools/TMXY.ConversionRouting/conversion_routing.py \
  --health-report /workspace/Data/Exports/P2-14/p2-14-asset-health.jsonl \
  --policy /workspace/Contracts/data-schema/conversion-routing-policy-v1.json \
  --output "$TMXY_CONVERSION_ROUTING_OUTPUT")
printf 'SUMMARY\t%s\n' "$summary"
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--env', "TMXY_CONVERSION_ROUTING_OUTPUT=$containerOutput",
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$exportRoot,target=/output",
    $builderReference, 'bash', '-c', $containerScript
)
try {
    $execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
    if ($execution.exit_code -ne 0) {
        throw "P2-15 conversion routing failed: $($execution.stderr.Trim()) $($execution.stdout.Trim())"
    }
    $selfTestLines = @($execution.stdout -split "`n" |
        Where-Object { $_.StartsWith("SELFTEST`t", [StringComparison]::Ordinal) })
    $summaryLines = @($execution.stdout -split "`n" |
        Where-Object { $_.StartsWith("SUMMARY`t", [StringComparison]::Ordinal) })
    if ($selfTestLines.Count -ne 1 -or $summaryLines.Count -ne 1) {
        throw 'P2-15 generator did not emit one self-test and one summary.'
    }
    $selfTest = $selfTestLines[0].Substring(9) | ConvertFrom-Json
    $summary = $summaryLines[0].Substring(8) | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $temporaryReport -PathType Leaf) -or
        (Get-FileSha256 $temporaryReport) -ne [string]$summary.report.sha256 -or
        (Get-Item -LiteralPath $temporaryReport).Length -ne [int64]$summary.report.bytes) {
        throw 'P2-15 report does not match the isolated generator summary.'
    }

    $routeFiles = 0
    foreach ($property in $summary.routes.PSObject.Properties) {
        $routeFiles += [int]$property.Value.files
    }
    $priorityFiles = 0
    foreach ($property in $summary.priorities.PSObject.Properties) {
        $priorityFiles += [int]$property.Value.files
    }
    $duplicateFiles = 0
    foreach ($property in $summary.duplicate_handling.PSObject.Properties) {
        $duplicateFiles += [int]$property.Value
    }
    $completed = $selfTest.result -eq 'PASS' -and [int]$selfTest.assertions -eq 5 -and
        $summary.result -eq 'PASS' -and
        [int]$summary.assets.files -eq [int]$healthEvidence.summary.assets.files -and
        [int64]$summary.assets.bytes -eq [int64]$healthEvidence.summary.assets.bytes -and
        [int]$summary.report.lines -eq [int]$healthEvidence.summary.assets.files -and
        [int]$summary.assets.conversion_jobs + [int]$summary.assets.alias_reuse -eq
            [int]$summary.assets.files -and
        $routeFiles -eq [int]$summary.assets.files -and
        $priorityFiles -eq [int]$summary.assets.files -and
        $duplicateFiles -eq [int]$summary.assets.files -and
        @($summary.routes.PSObject.Properties).Count -eq 5 -and
        @($summary.priorities.PSObject.Properties).Count -eq 4 -and
        @($summary.tiers.PSObject.Properties).Count -eq 3 -and
        [int]$summary.unclassified_assets -eq 0 -and
        [int]$summary.descriptor_bound_alias_reuse -eq 0 -and
        [int]$summary.deletion_recommendations -eq 0 -and
        [string]$summary.estimates.basis -eq 'planning coefficient, not benchmark or schedule commitment'

    if ($Check) {
        if (-not (Test-Path -LiteralPath $report -PathType Leaf) -or
            (Get-FileSha256 $report) -ne [string]$summary.report.sha256) {
            throw 'P2-15 report differs from the frozen generated report.'
        }
    }
    else { Move-Item -LiteralPath $temporaryReport -Destination $report -Force }

    $captured = [DateTimeOffset]::UtcNow.ToString('o')
    if ($Check -and (Test-Path -LiteralPath $output -PathType Leaf)) {
        $captured = [string](Get-Content -LiteralPath $output -Raw -Encoding UTF8 |
            ConvertFrom-Json -DateKind String).captured_utc
    }
    $reportObject = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = $captured
        task_id = 'P2-15'
        result = if ($completed) { 'PASS' } else { 'FAIL' }
        task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
        completion_criteria_satisfied = $completed
        input = [pscustomobject][ordered]@{
            source_build = 'qy-3.0.0.413'
            asset_health_report_sha256 = [string]$healthEvidence.report.sha256
            asset_catalog_sha256 = [string]$healthEvidence.input.asset_catalog_sha256
            reference_closure_sha256 = [string]$healthEvidence.input.reference_closure_sha256
            source_copy_policy = 'reference_only'
        }
        report = [pscustomobject][ordered]@{
            path = 'Data/Exports/P2-15/p2-15-conversion-routing.jsonl'
            tracked = $false
            lines = [int]$summary.report.lines
            bytes = [int64]$summary.report.bytes
            sha256 = [string]$summary.report.sha256
        }
        summary = [pscustomobject][ordered]@{
            assets = $summary.assets
            routes = $summary.routes
            priorities = $summary.priorities
            tiers = $summary.tiers
            duplicate_handling = $summary.duplicate_handling
            estimates = $summary.estimates
            unclassified_assets = [int]$summary.unclassified_assets
            descriptor_bound_alias_reuse = [int]$summary.descriptor_bound_alias_reuse
            deletion_recommendations = [int]$summary.deletion_recommendations
        }
        contracts = [pscustomobject][ordered]@{
            policy = 'Contracts/data-schema/conversion-routing-policy-v1.json'
            policy_sha256 = Get-FileSha256 $policyPath
            schema = 'Contracts/data-schema/conversion-routing-v1.schema.json'
            schema_sha256 = Get-FileSha256 $schemaPath
            estimate_authority = 'planning coefficient only; P2-19 re-estimation required'
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceHash
            self_test_assertions = [int]$selfTest.assertions
            generator = 'Tools/TMXY.ConversionRouting/New-ConversionRouting.ps1'
            query = 'Tools/TMXY.ConversionRouting/Find-ConversionRoute.ps1'
        }
        disclosure = [pscustomobject][ordered]@{
            tracked_evidence_contains_asset_paths = $false
            tracked_evidence_contains_per_asset_hashes = $false
            full_report_committed_to_git = $false
            payload_bytes_copied = $false
            source_aliases_removed = 0
            automatic_deletions_performed = 0
        }
        reproduction = [pscustomobject][ordered]@{
            check_mode = '-Check'
            source_mount = 'read-only'
            network = 'none'
            builder_id = $expectedBuilderId
            builder_user = 'tmxy'
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-16', 'P2-18', 'P2-19')
            detail = 'Build content-addressed invalidation and then replace planning coefficients with measured pilot throughput.'
        }
    }
    $json = ($reportObject | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($Check) {
        $expected = Get-Content -LiteralPath $output -Raw -Encoding UTF8
        if ($expected.Replace("`r`n", "`n").Replace("`r", "`n") -ne $json + "`n") {
            throw 'P2-15 tracked evidence differs from deterministic regeneration.'
        }
    }
    else {
        [IO.File]::WriteAllText($output, $json + "`n", [Text.UTF8Encoding]::new($false))
    }
    $json
    if (-not $completed) { throw 'P2-15 completion criteria were not satisfied.' }
}
finally {
    if (Test-Path -LiteralPath $temporaryReport) {
        Remove-Item -LiteralPath $temporaryReport -Force
    }
}
