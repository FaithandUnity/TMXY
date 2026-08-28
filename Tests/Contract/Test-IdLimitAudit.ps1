[CmdletBinding()]
param([string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild', [switch]$VerifyDerivedSources)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\id-limit-audit-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\id-limit-audit-v1.schema.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-11-id-limit-audit.json'
$reportPath = Join-Path $root 'Data\Exports\P2-11\p2-11-id-limit-audit.jsonl'
$generatorPath = Join-Path $root 'Tools\TMXY.IdLimitAudit\New-IdLimitAudit.ps1'
$pythonPath = Join-Path $root 'Tools\TMXY.IdLimitAudit\id_limit_audit.py'
$queryPath = Join-Path $root 'Tools\TMXY.IdLimitAudit\Find-IdLimitRisk.ps1'
$fixturePath = Join-Path $root 'Tests\Fixtures\IdLimitAudit\smoke-audit.jsonl'
$p210Path = Join-Path $root 'Data\Inventory\p2-10-canonical-id-map.json'
$p204Path = Join-Path $root 'Data\Inventory\p2-04-current-table-inventory.json'
$assertions = [Collections.Generic.List[object]]::new()
function Add-A([string]$Name, [bool]$Passed) { $assertions.Add([pscustomobject]@{ name = $Name; result = if ($Passed) { 'PASS' } else { 'FAIL' }; detail = '' }) }
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-Lines([string]$Path) { $count = 0; foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }; $count }
foreach ($path in @($policyPath, $schemaPath, $evidencePath, $generatorPath, $pythonPath, $queryPath, $fixturePath, $p210Path, $p204Path)) {
    Add-A "Required file $([IO.Path]::GetFileName($path))" (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count) {
    [pscustomobject]@{ schema_version = 1; task_id = 'P2-11'; result = 'FAIL'; completion_criteria_satisfied = $false; assertions = $assertions } | ConvertTo-Json -Depth 8
    exit 1
}
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
$e = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
$p210 = Get-Content -LiteralPath $p210Path -Raw | ConvertFrom-Json
$python = Get-Content -LiteralPath $pythonPath -Raw
$generator = Get-Content -LiteralPath $generatorPath -Raw
Add-A 'Evidence completes P2-11' ($e.result -eq 'PASS' -and $e.task_status -eq 'COMPLETE' -and $e.completion_criteria_satisfied)
Add-A 'Schema is closed draft 2020-12 evidence' ($schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and $schema.properties.task_id.const -eq 'P2-11')
Add-A 'Policy freezes u8 u16 level and slot audit rules' ($policy.fixed_limits.u8_exclusive_upper -eq 256 -and $policy.fixed_limits.u16_exclusive_upper -eq 65536 -and $policy.fixed_limits.level_inclusive_upper -eq 100 -and @($policy.legacy_source_signals.psobject.Properties).Count -eq 4)
Add-A 'Policy forbids unsafe narrowing and coercion' (-not $policy.risk_policy.automatic_type_narrowing -and $policy.risk_policy.overflow_fails_closed -and $policy.risk_policy.legacy_opaque_never_becomes_numeric_implicitly)
Add-A 'Evidence binds P2-10 and P2-04' ($e.input.p2_10_evidence_sha256 -eq (Get-Sha $p210Path) -and $e.input.p2_10_map_sha256 -eq $p210.report.sha256 -and $e.input.p2_04_evidence_sha256 -eq (Get-Sha $p204Path))
Add-A 'Ignored audit is deterministic and complete' ($e.report.path -eq 'Data/Exports/P2-11/p2-11-id-limit-audit.jsonl' -and -not $e.report.tracked -and $e.report.lines -eq 1283 -and $e.report.bytes -eq 323496 -and $e.report.sha256 -eq '9839296bc39b0a40d65c78b93f76c4ee703a9a3ab939e5ddc5d19f32b48ced9e')
if (Test-Path -LiteralPath $reportPath) {
    Add-A 'Local audit hash size and lines match evidence' ((Get-Sha $reportPath) -eq $e.report.sha256 -and (Get-Item -LiteralPath $reportPath).Length -eq $e.report.bytes -and (Get-Lines $reportPath) -eq $e.report.lines)
}
Add-A 'All Canonical ID components have width classes' ($e.summary.domain_count -eq 12 -and $e.summary.component_count -eq 16 -and $e.summary.numeric_components -eq 13 -and $e.summary.string_components -eq 3 -and $e.summary.bit_width_buckets.lte_8 -eq 6 -and $e.summary.bit_width_buckets.lte_16 -eq 7 -and $e.summary.bit_width_buckets.non_numeric -eq 3)
Add-A 'u16 capacity risks are explicit without overflow' ($e.summary.risk_counts.u16_overflow -eq 0 -and $e.summary.risk_counts.u16_saturated -eq 3 -and $e.summary.risk_counts.u16_near_limit -eq 2 -and $e.summary.risk_counts.u8_overflow -eq 7)
Add-A 'Level sparsity string and Tombstone risks are explicit' ($e.summary.risk_counts.level_cap_saturated -eq 3 -and $e.summary.risk_counts.sparse_lt_10pct -eq 4 -and $e.summary.risk_counts.string_identifier -eq 3 -and $e.summary.risk_counts.tombstone_reserved -eq 7 -and $e.summary.risk_counts.legacy_type_exception -eq 6)
Add-A 'Tracked components contain no exact extrema' (@($e.components).Count -eq 16 -and @($e.components | Where-Object { 'active_minimum' -in $_.psobject.Properties.Name -or 'active_maximum' -in $_.psobject.Properties.Name -or 'reserved_minimum' -in $_.psobject.Properties.Name -or 'reserved_maximum' -in $_.psobject.Properties.Name }).Count -eq 0)
Add-A 'Legacy source roots are completely scanned' ($e.source_signals.total_source_files -eq 8090 -and $e.source_signals.source_files.'legacy-client' -eq 1086 -and $e.source_signals.source_files.'legacy-server' -eq 1956 -and $e.source_signals.source_files.'legacy-tool' -eq 5048 -and $e.source_signals.total_signal_records -eq 1267 -and $e.source_signals.total_signal_hits -eq 5295)
Add-A 'All fixed-limit signal families have exact counts' ($e.source_signals.rules.u16_boundary.files -eq 299 -and $e.source_signals.rules.u16_boundary.hits -eq 892 -and $e.source_signals.rules.u8_boundary.files -eq 956 -and $e.source_signals.rules.u8_boundary.hits -eq 4370 -and $e.source_signals.rules.level_limit_symbol.files -eq 9 -and $e.source_signals.rules.level_limit_symbol.hits -eq 26 -and $e.source_signals.rules.slot_limit_symbol.files -eq 3 -and $e.source_signals.rules.slot_limit_symbol.hits -eq 7)
Add-A 'Implementation and isolation are bound' ($e.contracts.policy_sha256 -eq (Get-Sha $policyPath) -and $e.contracts.schema_sha256 -eq (Get-Sha $schemaPath) -and $python -match 'required_bits' -and $python -match 'slot_limit_symbol' -and $generator -match "'--network', 'none'" -and $generator -match 'target=/legacy-client,readonly' -and $generator -match 'target=/legacy-server,readonly' -and $generator -match 'target=/legacy-tool,readonly' -and $e.reproduction.builder_user -eq 'tmxy')
Add-A 'Tracked evidence preserves disclosure boundary' (-not $e.disclosure.tracked_evidence_contains_primary_keys -and -not $e.disclosure.tracked_evidence_contains_minimum_or_maximum_values -and -not $e.disclosure.tracked_evidence_contains_legacy_source_paths -and -not $e.disclosure.tracked_evidence_contains_legacy_source_lines -and -not $e.disclosure.full_audit_committed_to_git -and -not $e.disclosure.legacy_sources_copied)
$query = & $queryPath -ReportPath $fixturePath -Rule u16_boundary | ConvertFrom-Json
Add-A 'Query emits hashes and counts without restricted values' ($query.result -eq 'PASS' -and $query.matches -eq 1 -and $query.examples[0].rule -eq 'u16_boundary' -and -not $query.query.primary_keys_emitted -and -not $query.query.min_max_values_emitted -and -not $query.query.source_paths_emitted -and -not $query.query.source_lines_emitted -and 'relative_path' -notin @($query.examples[0].psobject.Properties.Name))
$local = $null
if ($VerifyDerivedSources) {
    $local = & $generatorPath -RebuildRoot $root -Check | ConvertFrom-Json
    Add-A 'Full deterministic ID limit regeneration passes' ($local.result -eq 'PASS' -and $local.completion_criteria_satisfied -and $local.report.sha256 -eq $e.report.sha256 -and $local.input.legacy_source_manifest_sha256 -eq $e.input.legacy_source_manifest_sha256)
}
$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{ schema_version = 1; task_id = 'P2-11'; result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }; completion_criteria_satisfied = $failed.Count -eq 0; verify_derived_sources = [bool]$VerifyDerivedSources; report = $e.report; summary = $e.summary; source_signals = $e.source_signals; local_check = $local; assertions = $assertions } | ConvertTo-Json -Depth 24
if ($failed.Count) { exit 1 }
