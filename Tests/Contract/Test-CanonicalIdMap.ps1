[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\canonical-id-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\canonical-id-map-v1.schema.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-10-canonical-id-map.json'
$reportPath = Join-Path $root 'Data\Exports\P2-10\p2-10-canonical-id-map.jsonl'
$generatorPath = Join-Path $root 'Tools\TMXY.CanonicalId\New-CanonicalIdMap.ps1'
$pythonPath = Join-Path $root 'Tools\TMXY.CanonicalId\canonical_id.py'
$queryPath = Join-Path $root 'Tools\TMXY.CanonicalId\Find-CanonicalIdMapping.ps1'
$fixturePath = Join-Path $root 'Tests\Fixtures\CanonicalId\smoke-map.jsonl'
$p209Path = Join-Path $root 'Data\Inventory\p2-09-legacy-current-diff.json'
$p207Path = Join-Path $root 'Data\Inventory\p2-07-core-table-schema.json'
$registryPath = Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
$assertions = [Collections.Generic.List[object]]::new()

function Add-Assertion([string]$Name, [bool]$Passed) {
    $assertions.Add([pscustomobject]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
            detail = ''
        })
}

function Get-Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Lines([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    $count
}

foreach ($path in @(
        $policyPath, $schemaPath, $evidencePath, $generatorPath, $pythonPath,
        $queryPath, $fixturePath, $p209Path, $p207Path, $registryPath
    )) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" (
        Test-Path -LiteralPath $path -PathType Leaf
    )
}
if (@($assertions | Where-Object result -eq 'FAIL').Count) {
    [pscustomobject]@{
        schema_version = 1
        task_id = 'P2-10'
        result = 'FAIL'
        completion_criteria_satisfied = $false
        assertions = $assertions
    } | ConvertTo-Json -Depth 8
    exit 1
}

$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
$evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
$p209 = Get-Content -LiteralPath $p209Path -Raw | ConvertFrom-Json
$p207 = Get-Content -LiteralPath $p207Path -Raw | ConvertFrom-Json
$python = Get-Content -LiteralPath $pythonPath -Raw
$generator = Get-Content -LiteralPath $generatorPath -Raw

Add-Assertion 'Evidence completes P2-10' (
    $evidence.result -eq 'PASS' -and $evidence.task_status -eq 'COMPLETE' -and
    $evidence.completion_criteria_satisfied
)
Add-Assertion 'Schema is closed draft 2020-12 evidence' (
    $schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and
    $schema.properties.task_id.const -eq 'P2-10'
)
Add-Assertion 'Policy preserves IDs and fails conflicts closed' (
    $policy.preservation.shared_legacy_current -match 'preserve' -and
    $policy.preservation.current_only -match 'adopt' -and
    $policy.preservation.legacy_only -match 'Tombstone' -and
    -not $policy.conflict_policy.automatic_renumbering -and
    -not $policy.conflict_policy.implicit_key_reuse -and
    $policy.conflict_policy.requires_explicit_reviewed_remap -and
    $policy.conflict_policy.unresolved_conflicts_fail_closed -and
    $policy.evolution_policy.tombstones_are_permanent
)
Add-Assertion 'Legacy type exceptions cannot be coerced or activated' (
    -not $policy.legacy_type_exception_policy.coerce_to_current_type -and
    $policy.legacy_type_exception_policy.preserve_as_legacy_opaque_tombstone -and
    -not $policy.legacy_type_exception_policy.may_become_active_without_explicit_review
)
Add-Assertion 'Evidence binds P2-09 P2-07 and registry' (
    $evidence.input.p2_09_evidence_sha256 -eq (Get-Sha $p209Path) -and
    $evidence.input.p2_09_report_sha256 -eq $p209.report.sha256 -and
    $evidence.input.p2_07_evidence_sha256 -eq (Get-Sha $p207Path) -and
    $evidence.input.core_registry_sha256 -eq (Get-Sha $registryPath) -and
    $evidence.input.legacy_manifest_sha256 -eq $p209.input.legacy_manifest_sha256
)
Add-Assertion 'Ignored map is deterministic and complete' (
    $evidence.report.path -eq 'Data/Exports/P2-10/p2-10-canonical-id-map.jsonl' -and
    -not $evidence.report.tracked -and $evidence.report.lines -eq 87328 -and
    $evidence.report.bytes -eq 26610829 -and
    $evidence.report.sha256 -eq 'af21fefcfdc4e6819236d53d84d7de2af59fb4b00882093598c4f51667e5d2af'
)
if (Test-Path -LiteralPath $reportPath) {
    Add-Assertion 'Local map hash size and lines match evidence' (
        (Get-Sha $reportPath) -eq $evidence.report.sha256 -and
        (Get-Item -LiteralPath $reportPath).Length -eq $evidence.report.bytes -and
        (Get-Lines $reportPath) -eq $evidence.report.lines
    )
}
Add-Assertion 'All P2-07 domains have typed Canonical IDs' (
    $evidence.summary.domain_count -eq 12 -and
    $evidence.summary.comparable_legacy_domains -eq 10 -and
    @($evidence.domains).Count -eq 12 -and
    @($evidence.domains | Select-Object -ExpandProperty domain -Unique).Count -eq 12 -and
    ($evidence.domains | Measure-Object -Property key_arity -Sum).Sum -eq 16 -and
    @($evidence.domains | Where-Object key_arity -eq 1).Count -eq 8 -and
    @($evidence.domains | Where-Object key_arity -eq 2).Count -eq 4
)
$allTypes = @($evidence.domains | ForEach-Object { @($_.key_types) })
Add-Assertion 'Key component types stay bound to P2-07' (
    @($allTypes | Where-Object { $_ -eq 'int64' }).Count -eq 13 -and
    @($allTypes | Where-Object { $_ -eq 'string' }).Count -eq 3 -and
    @($allTypes | Where-Object { $_ -notin @('int64', 'string') }).Count -eq 0
)
Add-Assertion 'Active and Tombstone sets close exactly' (
    $evidence.summary.mapping_records -eq 87328 -and
    $evidence.summary.active_ids -eq 87044 -and
    $evidence.summary.tombstones -eq 284 -and
    $evidence.summary.active_ids + $evidence.summary.tombstones -eq
        $evidence.summary.mapping_records -and
    $evidence.summary.shared_ids -eq 26968 -and
    $evidence.summary.current_only_ids -eq 60076 -and
    $evidence.summary.shared_ids + $evidence.summary.current_only_ids -eq
        $evidence.summary.active_ids
)
Add-Assertion 'Every legacy and current ID is preserved' (
    $evidence.summary.legacy_unique_ids -eq 27252 -and
    $evidence.summary.legacy_preserved_ids -eq 27252 -and
    $evidence.summary.shared_ids + $evidence.summary.tombstones -eq
        $evidence.summary.legacy_preserved_ids -and
    $evidence.summary.current_unique_ids -eq 87044 -and
    $evidence.summary.current_physical_rows -eq 87844
)
Add-Assertion 'Approved identical duplicates collapse without conflict' (
    $evidence.summary.collapsed_duplicate_groups -eq 700 -and
    $evidence.summary.collapsed_duplicate_occurrences -eq 800 -and
    $evidence.summary.current_physical_rows - $evidence.summary.current_unique_ids -eq 800
)
Add-Assertion 'Legacy type exceptions remain explicit' (
    $evidence.summary.legacy_type_exception_components -eq 6 -and
    ($evidence.domains | Measure-Object -Property legacy_type_exception_components -Sum).Sum -eq 6
)
Add-Assertion 'No implicit remap or unresolved conflict exists' (
    $evidence.summary.conflicts -eq 0 -and
    $evidence.summary.unresolved_conflicts -eq 0 -and
    $evidence.summary.explicit_remaps -eq 0 -and
    $evidence.summary.automatic_renumberings -eq 0
)
Add-Assertion 'Contracts implementation and isolation are bound' (
    $evidence.contracts.policy_sha256 -eq (Get-Sha $policyPath) -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha $schemaPath) -and
    $python -match 'preserve_legacy_tombstone' -and
    $python -match 'legacy-opaque' -and
    $generator -match "'--network', 'none'" -and
    $generator -match 'target=/legacy,readonly' -and
    $evidence.reproduction.builder_user -eq 'tmxy'
)
Add-Assertion 'Tracked evidence preserves disclosure boundary' (
    -not $evidence.disclosure.tracked_evidence_contains_primary_keys -and
    -not $evidence.disclosure.tracked_evidence_contains_row_values -and
    $evidence.disclosure.full_map_contains_primary_keys -and
    -not $evidence.disclosure.full_map_committed_to_git -and
    -not $evidence.disclosure.query_emits_primary_keys -and
    -not $evidence.disclosure.legacy_payloads_copied
)
$query = & $queryPath -ReportPath $fixturePath -Status tombstone | ConvertFrom-Json
Add-Assertion 'Query returns digest metadata without primary keys' (
    $query.result -eq 'PASS' -and $query.matches -eq 1 -and
    $query.examples[0].status -eq 'tombstone' -and
    -not $query.query.primary_keys_emitted -and -not $query.query.row_values_emitted -and
    $query.query.digest_only -and
    'canonical_id' -notin @($query.examples[0].psobject.Properties.Name)
)
$local = $null
if ($VerifyDerivedSources) {
    $local = & $generatorPath -RebuildRoot $root -Check | ConvertFrom-Json
    Add-Assertion 'Full deterministic Canonical ID regeneration passes' (
        $local.result -eq 'PASS' -and $local.completion_criteria_satisfied -and
        $local.report.sha256 -eq $evidence.report.sha256 -and
        $local.summary.mapping_records -eq $evidence.summary.mapping_records
    )
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-10'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    verify_derived_sources = [bool]$VerifyDerivedSources
    report = $evidence.report
    summary = $evidence.summary
    local_check = $local
    assertions = $assertions
} | ConvertTo-Json -Depth 24
if ($failed.Count) { exit 1 }
