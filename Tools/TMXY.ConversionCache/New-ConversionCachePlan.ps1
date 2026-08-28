[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-16\p2-16-conversion-cache-plan.jsonl',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-16-conversion-cache.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$report = [IO.Path]::GetFullPath($ReportPath)
$output = [IO.Path]::GetFullPath($OutputPath)
$exportRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Exports\P2-16')).TrimEnd([char[]]'\/')
$inventoryRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Inventory')).TrimEnd([char[]]'\/')
if (-not $report.StartsWith($exportRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith($inventoryRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-16 outputs escaped their scoped Rebuild directories.'
}

$moduleRoot = Join-Path $root 'Tools\TMXY.ConversionCache'
$pythonPath = Join-Path $moduleRoot 'conversion_cache.py'
$policyPath = Join-Path $root 'Contracts\data-schema\conversion-cache-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\conversion-cache-v1.schema.json'
$assetCatalogPath = Join-Path $root 'Data\Exports\P2-12\p2-12-full-asset-inventory.jsonl'
$assetEvidencePath = Join-Path $root 'Data\Inventory\p2-12-full-asset-inventory.json'
$routingReportPath = Join-Path $root 'Data\Exports\P2-15\p2-15-conversion-routing.jsonl'
$routingEvidencePath = Join-Path $root 'Data\Inventory\p2-15-conversion-routing.json'
$routingPolicyPath = Join-Path $root 'Contracts\data-schema\conversion-routing-policy-v1.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
foreach ($path in @($moduleRoot, $pythonPath, $policyPath, $schemaPath, $assetCatalogPath,
        $assetEvidencePath, $routingReportPath, $routingEvidencePath, $routingPolicyPath, $lockPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-16 input is missing: $path" }
}
[IO.Directory]::CreateDirectory($exportRoot) | Out-Null

function Get-FileSha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-TextSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}
function Invoke-NativeProcess([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    [pscustomobject]@{exit_code=$process.ExitCode; stdout=$stdout.Result; stderr=$stderr.Result}
}

$assetEvidence = Get-Content $assetEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$routingEvidence = Get-Content $routingEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($assetEvidence.result -ne 'PASS' -or $routingEvidence.result -ne 'PASS' -or
    (Get-FileSha256 $assetCatalogPath) -ne [string]$assetEvidence.catalog.sha256 -or
    (Get-FileSha256 $routingReportPath) -ne [string]$routingEvidence.report.sha256) {
    throw 'P2-16 upstream evidence binding failed.'
}

$sourceFiles = @(Get-ChildItem $moduleRoot -Recurse -File |
    Where-Object Extension -in @('.ps1', '.py') | Sort-Object FullName)
$sourceLines = @($sourceFiles | ForEach-Object {
        "$([IO.Path]::GetRelativePath($root, $_.FullName).Replace('\','/'))|$(Get-FileSha256 $_.FullName)"
    })
$sourceHash = Get-TextSha256 (($sourceLines -join "`n") + "`n")
$lock = Get-Content $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or [string]$image[0].Id -ne $expectedBuilderId -or
    [string]$image[0].Config.User -ne 'tmxy') {
    throw 'P2-16 requires the qualified non-root Clang 21 builder image.'
}

$temporaryName = '.p2-16-' + [Guid]::NewGuid().ToString('N') + '.jsonl'
$temporaryReport = Join-Path $exportRoot $temporaryName
$containerOutput = "/output/$temporaryName"
$containerScript = @'
set -euo pipefail
self_test=$(python3 /workspace/Tools/TMXY.ConversionCache/conversion_cache.py --self-test)
printf 'SELFTEST\t%s\n' "$self_test"
summary=$(python3 /workspace/Tools/TMXY.ConversionCache/conversion_cache.py \
  --root /workspace \
  --asset-catalog /workspace/Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl \
  --routing-report /workspace/Data/Exports/P2-15/p2-15-conversion-routing.jsonl \
  --routing-policy /workspace/Contracts/data-schema/conversion-routing-policy-v1.json \
  --policy /workspace/Contracts/data-schema/conversion-cache-policy-v1.json \
  --output "$TMXY_CONVERSION_CACHE_OUTPUT")
printf 'SUMMARY\t%s\n' "$summary"
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @('run','--rm','--network','none','--read-only','--cap-drop','ALL',
    '--security-opt','no-new-privileges:true','--tmpfs','/tmp:rw,exec,nosuid,size=1g',
    '--env',"TMXY_CONVERSION_CACHE_OUTPUT=$containerOutput",
    '--mount',"type=bind,source=$root,target=/workspace,readonly",
    '--mount',"type=bind,source=$exportRoot,target=/output",
    $builderReference,'bash','-c',$containerScript)
try {
    $execution = Invoke-NativeProcess $docker $arguments $root
    if ($execution.exit_code -ne 0) { throw "P2-16 generation failed: $($execution.stderr)" }
    $selfLine = @($execution.stdout -split "`n" | Where-Object { $_.StartsWith("SELFTEST`t") })
    $summaryLine = @($execution.stdout -split "`n" | Where-Object { $_.StartsWith("SUMMARY`t") })
    if ($selfLine.Count -ne 1 -or $summaryLine.Count -ne 1) { throw 'P2-16 output framing failed.' }
    $selfTest = $selfLine[0].Substring(9) | ConvertFrom-Json
    $summary = $summaryLine[0].Substring(8) | ConvertFrom-Json
    if ((Get-FileSha256 $temporaryReport) -ne [string]$summary.report.sha256 -or
        (Get-Item $temporaryReport).Length -ne [int64]$summary.report.bytes) {
        throw 'P2-16 report hash or size mismatch.'
    }
    $completed = $selfTest.result -eq 'PASS' -and $selfTest.assertions -eq 5 -and
        $summary.result -eq 'PASS' -and $summary.summary.assets.files -eq 40090 -and
        $summary.summary.assets.conversion_jobs -eq 34601 -and
        $summary.summary.assets.aliases -eq 5489 -and
        $summary.summary.cache_keys.ready_jobs -eq 33801 -and
        $summary.summary.cache_keys.distinct_ready_keys -eq 33801 -and
        $summary.summary.cache_keys.alias_assignments -eq 5489 -and
        $summary.summary.cache_keys.blocked_manual_jobs -eq 800 -and
        $summary.summary.invalidation_proof.source_mutation_changed_keys -eq 1 -and
        $summary.summary.invalidation_proof.routing_policy_mutation_changed_keys -eq 33801 -and
        $summary.summary.invalidation_proof.target_profile_mutation_changed_keys -eq 33801 -and
        $summary.summary.output_hash_verification_required -and
        -not $summary.summary.shared_cache_write_authorized
    if ($Check) {
        if (-not (Test-Path $report) -or (Get-FileSha256 $report) -ne $summary.report.sha256) {
            throw 'P2-16 report differs from frozen output.'
        }
    } else { Move-Item $temporaryReport $report -Force }
    $captured = [DateTimeOffset]::UtcNow.ToString('o')
    if ($Check -and (Test-Path $output)) {
        $captured = [string](Get-Content $output -Raw | ConvertFrom-Json -DateKind String).captured_utc
    }
    $evidence = [pscustomobject][ordered]@{
        schema_version=1; captured_utc=$captured; task_id='P2-16'
        result=if($completed){'PASS'}else{'FAIL'}
        task_status=if($completed){'COMPLETE'}else{'IN_PROGRESS'}
        completion_criteria_satisfied=$completed
        input=[pscustomobject][ordered]@{
            source_build='qy-3.0.0.413'
            asset_catalog_sha256=[string]$assetEvidence.catalog.sha256
            conversion_routing_sha256=[string]$routingEvidence.report.sha256
            routing_policy_sha256=Get-FileSha256 $routingPolicyPath
            source_copy_policy='reference_only'
        }
        report=[pscustomobject][ordered]@{
            path='Data/Exports/P2-16/p2-16-conversion-cache-plan.jsonl'; tracked=$false
            lines=[int]$summary.report.lines; bytes=[int64]$summary.report.bytes
            sha256=[string]$summary.report.sha256
        }
        summary=$summary.summary
        key_inputs=$summary.inputs
        contracts=[pscustomobject][ordered]@{
            policy='Contracts/data-schema/conversion-cache-policy-v1.json'
            policy_sha256=Get-FileSha256 $policyPath
            schema='Contracts/data-schema/conversion-cache-v1.schema.json'
            schema_sha256=Get-FileSha256 $schemaPath
        }
        implementation=[pscustomobject][ordered]@{
            source_files=$sourceFiles.Count; source_sha256=$sourceHash
            self_test_assertions=[int]$selfTest.assertions
            generator='Tools/TMXY.ConversionCache/New-ConversionCachePlan.ps1'
            query='Tools/TMXY.ConversionCache/Find-ConversionCachePlan.ps1'
            verifier='Tools/TMXY.ConversionCache/Test-ConversionCacheEntry.ps1'
        }
        disclosure=[pscustomobject][ordered]@{
            tracked_evidence_contains_asset_paths=$false
            tracked_evidence_contains_source_hashes=$false
            full_plan_committed_to_git=$false
            cache_artifacts_committed_to_git=$false
            payload_bytes_copied=$false
        }
        reproduction=[pscustomobject][ordered]@{
            check_mode='-Check'; source_mount='read-only'; network='none'
            builder_id=$expectedBuilderId; builder_user='tmxy'
        }
        next_scope=[pscustomobject][ordered]@{
            tasks=@('P2-17','P2-18','P2-19')
            detail='Use the cache key contract in conversion pilots and replace planning coefficients with measured throughput.'
        }
    }
    $json=($evidence|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")
    if ($Check) {
        if ((Get-Content $output -Raw).Replace("`r`n","`n").Replace("`r","`n") -ne $json+"`n") {
            throw 'P2-16 evidence differs from deterministic regeneration.'
        }
    } else { [IO.File]::WriteAllText($output,$json+"`n",[Text.UTF8Encoding]::new($false)) }
    $json
    if (-not $completed) { throw 'P2-16 completion criteria failed.' }
}
finally {
    if (Test-Path $temporaryReport) { Remove-Item $temporaryReport -Force }
}
