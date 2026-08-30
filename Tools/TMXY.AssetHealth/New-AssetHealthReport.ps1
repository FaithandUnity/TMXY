[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-14\p2-14-asset-health.jsonl',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-14-asset-health.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$report = [IO.Path]::GetFullPath($ReportPath)
$output = [IO.Path]::GetFullPath($OutputPath)
$exportRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Exports\P2-14')).TrimEnd([char[]]'\/')
$inventoryRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Inventory')).TrimEnd([char[]]'\/')
if (-not $report.StartsWith($exportRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith($inventoryRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-14 outputs escaped their scoped Rebuild directories.'
}

$moduleRoot = Join-Path $root 'Tools\TMXY.AssetHealth'
$pythonPath = Join-Path $moduleRoot 'asset_health.py'
$queryPath = Join-Path $moduleRoot 'Find-AssetHealth.ps1'
$policyPath = Join-Path $root 'Contracts\data-schema\asset-health-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\asset-health-v1.schema.json'
$referencePolicyPath = Join-Path $root 'Contracts\data-schema\reference-closure-policy-v1.json'
$catalogPath = Join-Path $root 'Data\Exports\P2-12\p2-12-full-asset-inventory.jsonl'
$assetEvidencePath = Join-Path $root 'Data\Inventory\p2-12-full-asset-inventory.json'
$closurePath = Join-Path $root 'Data\Exports\P2-13\p2-13-reference-closure.jsonl'
$closureEvidencePath = Join-Path $root 'Data\Inventory\p2-13-reference-closure.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
foreach ($path in @($moduleRoot, $pythonPath, $queryPath, $policyPath, $schemaPath,
        $referencePolicyPath, $catalogPath, $assetEvidencePath, $closurePath,
        $closureEvidencePath, $lockPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-14 input is missing: $path" }
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

$assetEvidence = Get-Content -LiteralPath $assetEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$closureEvidence = Get-Content -LiteralPath $closureEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($assetEvidence.result -ne 'PASS' -or -not $assetEvidence.completion_criteria_satisfied -or
    $closureEvidence.result -ne 'PASS' -or -not $closureEvidence.completion_criteria_satisfied) {
    throw 'P2-14 requires completed P2-12 and P2-13 evidence.'
}
if ((Get-FileSha256 $catalogPath) -ne [string]$assetEvidence.catalog.sha256 -or
    (Get-FileSha256 $closurePath) -ne [string]$closureEvidence.graph.sha256) {
    throw 'P2-14 derived input hash binding failed.'
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
    throw 'P2-14 requires the qualified non-root Clang 21 builder image.'
}

$temporaryName = '.p2-14-' + [Guid]::NewGuid().ToString('N') + '.jsonl'
$temporaryReport = Join-Path $exportRoot $temporaryName
$containerOutput = "/output/$temporaryName"
$containerScript = @'
set -euo pipefail
self_test=$(python3 /workspace/Tools/TMXY.AssetHealth/asset_health.py --self-test)
printf 'SELFTEST\t%s\n' "$self_test"
summary=$(python3 /workspace/Tools/TMXY.AssetHealth/asset_health.py \
  --catalog /workspace/Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl \
  --closure /workspace/Data/Exports/P2-13/p2-13-reference-closure.jsonl \
  --reference-policy /workspace/Contracts/data-schema/reference-closure-policy-v1.json \
  --health-policy /workspace/Contracts/data-schema/asset-health-policy-v1.json \
  --output "$TMXY_ASSET_HEALTH_OUTPUT")
printf 'SUMMARY\t%s\n' "$summary"
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--env', "TMXY_ASSET_HEALTH_OUTPUT=$containerOutput",
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$exportRoot,target=/output",
    $builderReference, 'bash', '-c', $containerScript
)
try {
    $execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
    if ($execution.exit_code -ne 0) {
        throw "P2-14 asset health generation failed: $($execution.stderr.Trim())"
    }
    $selfTestLines = @($execution.stdout -split "`n" |
        Where-Object { $_.StartsWith("SELFTEST`t", [StringComparison]::Ordinal) })
    $summaryLines = @($execution.stdout -split "`n" |
        Where-Object { $_.StartsWith("SUMMARY`t", [StringComparison]::Ordinal) })
    if ($selfTestLines.Count -ne 1 -or $summaryLines.Count -ne 1) {
        throw 'P2-14 generator did not emit one self-test and one summary.'
    }
    $selfTest = $selfTestLines[0].Substring(9) | ConvertFrom-Json
    $summary = $summaryLines[0].Substring(8) | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $temporaryReport -PathType Leaf) -or
        (Get-FileSha256 $temporaryReport) -ne [string]$summary.report.sha256 -or
        (Get-Item -LiteralPath $temporaryReport).Length -ne [int64]$summary.report.bytes) {
        throw 'P2-14 report does not match the isolated generator summary.'
    }

    $referenceTotal = 0
    foreach ($property in $summary.assets.reference_states.PSObject.Properties) {
        $referenceTotal += [int]$property.Value
    }
    $expectedRoots = [int]$closureEvidence.roots.character +
        [int]$closureEvidence.roots.scene + [int]$closureEvidence.roots.skill
    $completed = $selfTest.result -eq 'PASS' -and [int]$selfTest.assertions -eq 8 -and
        $summary.result -eq 'PASS' -and
        [int]$summary.assets.files -eq [int]$assetEvidence.summary.files -and
        [int64]$summary.assets.bytes -eq [int64]$assetEvidence.input.bytes -and
        [int]$summary.report.records.asset_health -eq [int]$assetEvidence.summary.files -and
        $referenceTotal -eq [int]$assetEvidence.summary.files -and
        @($summary.assets.reference_states.PSObject.Properties).Count -eq 4 -and
        [int]$summary.assets.root_count -eq $expectedRoots -and
        @($summary.identity_rule_families).Count -eq 6 -and
        [int]$summary.deletion_recommendations -eq 0 -and
        [int]$summary.semantic_equivalence_claims_without_digest -eq 0 -and
        [int]$summary.duplicates.semantic_equivalence_proven_groups -eq 0

    if ($Check) {
        if (-not (Test-Path -LiteralPath $report -PathType Leaf) -or
            (Get-FileSha256 $report) -ne [string]$summary.report.sha256) {
            throw 'P2-14 report differs from the frozen generated report.'
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
        task_id = 'P2-14'
        result = if ($completed) { 'PASS' } else { 'FAIL' }
        task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
        completion_criteria_satisfied = $completed
        input = [pscustomobject][ordered]@{
            source_build = 'qy-3.0.0.413'
            asset_catalog_sha256 = [string]$assetEvidence.catalog.sha256
            reference_closure_sha256 = [string]$closureEvidence.graph.sha256
            source_copy_policy = 'reference_only'
        }
        report = [pscustomobject][ordered]@{
            path = 'Data/Exports/P2-14/p2-14-asset-health.jsonl'
            tracked = $false
            lines = [int]$summary.report.lines
            bytes = [int64]$summary.report.bytes
            sha256 = [string]$summary.report.sha256
            records = $summary.report.records
        }
        summary = [pscustomobject][ordered]@{
            assets = $summary.assets
            duplicates = $summary.duplicates
            identity_rule_families = $summary.identity_rule_families
            deletion_recommendations = [int]$summary.deletion_recommendations
            semantic_equivalence_claims_without_digest =
                [int]$summary.semantic_equivalence_claims_without_digest
        }
        contracts = [pscustomobject][ordered]@{
            policy = 'Contracts/data-schema/asset-health-policy-v1.json'
            policy_sha256 = Get-FileSha256 $policyPath
            schema = 'Contracts/data-schema/asset-health-v1.schema.json'
            schema_sha256 = Get-FileSha256 $schemaPath
            orphan_definition = 'root reachability review state; never automatic deletion proof'
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceHash
            self_test_assertions = [int]$selfTest.assertions
            generator = 'Tools/TMXY.AssetHealth/New-AssetHealthReport.ps1'
            query = 'Tools/TMXY.AssetHealth/Find-AssetHealth.ps1'
        }
        disclosure = [pscustomobject][ordered]@{
            tracked_evidence_contains_asset_paths = $false
            tracked_evidence_contains_per_asset_hashes = $false
            full_report_committed_to_git = $false
            payload_bytes_copied = $false
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
            tasks = @('P2-15', 'P2-16', 'P2-18')
            detail = 'Route exact duplicates and unreachable candidates for review; never delete from P2-14 evidence alone.'
        }
    }
    $json = ($reportObject | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($Check) {
        $expected = Get-Content -LiteralPath $output -Raw -Encoding UTF8
        if ($expected.Replace("`r`n", "`n").Replace("`r", "`n") -ne $json + "`n") {
            throw 'P2-14 tracked evidence differs from deterministic regeneration.'
        }
    }
    else {
        [IO.File]::WriteAllText($output, $json + "`n", [Text.UTF8Encoding]::new($false))
    }
    $json
    if (-not $completed) { throw 'P2-14 completion criteria were not satisfied.' }
}
finally {
    if (Test-Path -LiteralPath $temporaryReport) {
        Remove-Item -LiteralPath $temporaryReport -Force
    }
}
