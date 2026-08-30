[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\conversion-routing-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\conversion-routing-v1.schema.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-15-conversion-routing.json'
$reportPath = Join-Path $root 'Data\Exports\P2-15\p2-15-conversion-routing.jsonl'
$generatorPath = Join-Path $root 'Tools\TMXY.ConversionRouting\New-ConversionRouting.ps1'
$pythonPath = Join-Path $root 'Tools\TMXY.ConversionRouting\conversion_routing.py'
$queryPath = Join-Path $root 'Tools\TMXY.ConversionRouting\Find-ConversionRoute.ps1'
$fixturePath = Join-Path $root 'Tests\Fixtures\ConversionRouting\smoke-routing.jsonl'
$healthEvidencePath = Join-Path $root 'Data\Inventory\p2-14-asset-health.json'
$assertions = [Collections.Generic.List[object]]::new()

function Add-Assertion([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
            detail = $Detail
        })
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

foreach ($path in @($policyPath, $schemaPath, $evidencePath, $generatorPath,
        $pythonPath, $queryPath, $fixturePath, $healthEvidencePath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject][ordered]@{
        schema_version = 1; task_id = 'P2-15'; result = 'FAIL'
        completion_criteria_satisfied = $false; assertions = $assertions
    } | ConvertTo-Json -Depth 10
    exit 1
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$healthEvidence = Get-Content -LiteralPath $healthEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
$python = Get-Content -LiteralPath $pythonPath -Raw -Encoding UTF8

Add-Assertion 'Evidence completes P2-15' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-Assertion 'Schema is closed draft 2020-12 evidence' (
    $schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and
    $schema.properties.task_id.const -eq 'P2-15')
Add-Assertion 'Policy freezes complete routes tiers priorities and planning authority' (
    $policy.source_build -eq 'qy-3.0.0.413' -and @($policy.routes).Count -eq 5 -and
    @($policy.routes.tier | Sort-Object -Unique).Count -eq 3 -and
    @($policy.priority_mapping.PSObject.Properties).Count -eq 4 -and
    $policy.estimate_basis -eq 'planning coefficient, not benchmark or schedule commitment' -and
    $policy.completion_policy.requires_every_asset_one_route_tier_priority_and_estimate -and
    $policy.completion_policy.requires_estimates_labeled_as_planning_coefficients)
Add-Assertion 'Descriptor-bound reuse is forbidden and every alias is preserved' (
    @($policy.exact_duplicate_reuse.descriptor_bound_families_forbidden) -contains 'qtx' -and
    @($policy.exact_duplicate_reuse.descriptor_bound_families_forbidden) -contains 'anim' -and
    $policy.exact_duplicate_reuse.preserves_every_source_path_alias -and
    $policy.completion_policy.forbids_descriptor_bound_conversion_reuse_without_descriptor_digest -and
    $policy.completion_policy.forbids_automatic_deletion_or_source_repair)
Add-Assertion 'Evidence binds the exact P2-14 health report' (
    $evidence.input.asset_health_report_sha256 -eq $healthEvidence.report.sha256 -and
    $evidence.input.asset_catalog_sha256 -eq $healthEvidence.input.asset_catalog_sha256 -and
    $evidence.input.reference_closure_sha256 -eq $healthEvidence.input.reference_closure_sha256)
Add-Assertion 'Ignored routing report is deterministic and complete' (
    $evidence.report.path -eq 'Data/Exports/P2-15/p2-15-conversion-routing.jsonl' -and
    -not $evidence.report.tracked -and $evidence.report.lines -eq 40090 -and
    $evidence.report.bytes -eq 21021383 -and
    $evidence.report.sha256 -eq '77620c2db505d98a94f64e1bd9f7c5244fbb48fbad80900cb83d699add832559')
if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    Add-Assertion 'Local routing report hash size and line count match evidence' (
        (Get-Sha256 $reportPath) -eq $evidence.report.sha256 -and
        (Get-Item -LiteralPath $reportPath).Length -eq $evidence.report.bytes -and
        (Get-LineCount $reportPath) -eq $evidence.report.lines)
}
Add-Assertion 'All assets have one job or preserved reuse alias' (
    $evidence.summary.assets.files -eq 40090 -and
    $evidence.summary.assets.bytes -eq 8882019027 -and
    $evidence.summary.assets.conversion_jobs -eq 34601 -and
    $evidence.summary.assets.alias_reuse -eq 5489)

$expectedRoutes = [ordered]@{
    'automatic-qualified-interchange' = @(37935, 32515, 5420, 8534384165, 40, 352.25, 392.25, 97545)
    'automatic-standard-audio' = @(514, 480, 34, 178952251, 24, 9.77, 33.77, 2400)
    'manual-descriptor-recovery' = @(786, 786, 0, 144791420, 80, 393, 473, 0)
    'manual-repair-or-replace' = @(14, 14, 0, 19325289, 32, 112, 144, 0)
    'semi-automatic-navigation-adaptation' = @(841, 806, 35, 4565902, 160, 201.675, 361.675, 8060)
}
$routesPassed = $true
foreach ($item in $expectedRoutes.GetEnumerator()) {
    $actual = $evidence.summary.routes.($item.Key)
    $expected = $item.Value
    $routesPassed = $routesPassed -and $actual.files -eq $expected[0] -and
        $actual.conversion_jobs -eq $expected[1] -and $actual.alias_reuse -eq $expected[2] -and
        $actual.bytes -eq $expected[3] -and $actual.fixed_engineering_hours -eq $expected[4] -and
        $actual.item_human_hours -eq $expected[5] -and
        $actual.planning_human_hours -eq $expected[6] -and
        $actual.machine_seconds -eq $expected[7]
}
Add-Assertion 'Five conversion routes have frozen counts and coefficients' $routesPassed

$expectedTiers = [ordered]@{
    automatic = @(38449, 32995, 5454, 8713336416, 362.02, 99945)
    manual = @(800, 800, 0, 164116709, 505, 0)
    'semi-automatic' = @(841, 806, 35, 4565902, 201.675, 8060)
}
$tiersPassed = $true
foreach ($item in $expectedTiers.GetEnumerator()) {
    $actual = $evidence.summary.tiers.($item.Key)
    $expected = $item.Value
    $tiersPassed = $tiersPassed -and $actual.files -eq $expected[0] -and
        $actual.conversion_jobs -eq $expected[1] -and $actual.alias_reuse -eq $expected[2] -and
        $actual.bytes -eq $expected[3] -and $actual.item_human_hours -eq $expected[4] -and
        $actual.machine_seconds -eq $expected[5]
}
Add-Assertion 'Three execution tiers have frozen aggregate counts' $tiersPassed

$expectedPriorities = [ordered]@{
    'P0-first-playable-slice' = @(14058, 8842, 5216, 2958384062, 122.95, 27004)
    'P1-linked-content' = @(24119, 24025, 94, 5594899826, 288.36, 72124)
    'P2-unlinked-review' = @(1008, 867, 141, 200166716, 454.475, 512)
    'P3-identity-rule-gap' = @(905, 867, 38, 128568423, 202.91, 8365)
}
$prioritiesPassed = $true
foreach ($item in $expectedPriorities.GetEnumerator()) {
    $actual = $evidence.summary.priorities.($item.Key)
    $expected = $item.Value
    $prioritiesPassed = $prioritiesPassed -and $actual.files -eq $expected[0] -and
        $actual.conversion_jobs -eq $expected[1] -and $actual.alias_reuse -eq $expected[2] -and
        $actual.bytes -eq $expected[3] -and $actual.item_human_hours -eq $expected[4] -and
        $actual.machine_seconds -eq $expected[5]
}
Add-Assertion 'Four delivery priorities preserve reference-state semantics' $prioritiesPassed
Add-Assertion 'Duplicate handling and estimate totals are exact' (
    $evidence.summary.duplicate_handling.'exact-duplicate-review-only' -eq 3351 -and
    $evidence.summary.duplicate_handling.'safe-reuse-alias' -eq 5489 -and
    $evidence.summary.duplicate_handling.'safe-reuse-representative' -eq 262 -and
    $evidence.summary.duplicate_handling.unique -eq 30988 -and
    $evidence.summary.estimates.fixed_engineering_hours -eq 336 -and
    $evidence.summary.estimates.item_human_hours -eq 1068.695 -and
    $evidence.summary.estimates.planning_human_hours -eq 1404.695 -and
    $evidence.summary.estimates.machine_seconds -eq 108005)
Add-Assertion 'No classification gap unsafe reuse deletion or payload copy exists' (
    $evidence.summary.unclassified_assets -eq 0 -and
    $evidence.summary.descriptor_bound_alias_reuse -eq 0 -and
    $evidence.summary.deletion_recommendations -eq 0 -and
    $evidence.disclosure.source_aliases_removed -eq 0 -and
    $evidence.disclosure.automatic_deletions_performed -eq 0 -and
    -not $evidence.disclosure.payload_bytes_copied)
Add-Assertion 'Tracked evidence preserves the public repository boundary' (
    -not $evidence.disclosure.tracked_evidence_contains_asset_paths -and
    -not $evidence.disclosure.tracked_evidence_contains_per_asset_hashes -and
    -not $evidence.disclosure.full_report_committed_to_git)
Add-Assertion 'Policy schema implementation and isolation are bound' (
    $evidence.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath) -and
    $python -match 'safe-reuse-alias' -and $python -match 'descriptor_bound' -and
    $generator -match "'--network', 'none'" -and $generator -match "'--read-only'" -and
    $generator -match "'--cap-drop', 'ALL'" -and $evidence.reproduction.builder_user -eq 'tmxy')

$routeQueries = @($policy.routes.id | ForEach-Object {
        & $queryPath -ReportPath $fixturePath -Route $_ -MaximumExamples 10 |
            ConvertFrom-Json
    })
$tierQueries = @('automatic', 'semi-automatic', 'manual' | ForEach-Object {
        & $queryPath -ReportPath $fixturePath -Tier $_ -MaximumExamples 10 |
            ConvertFrom-Json
    })
$priorityQueries = @($policy.priority_mapping.PSObject.Properties.Value | ForEach-Object {
        & $queryPath -ReportPath $fixturePath -Priority $_ -MaximumExamples 10 |
            ConvertFrom-Json
    })
$aliasQuery = & $queryPath -ReportPath $fixturePath -DuplicateHandling safe-reuse-alias `
    -MaximumExamples 10 | ConvertFrom-Json
$queries = @($routeQueries) + @($tierQueries) + @($priorityQueries) + @($aliasQuery)
Add-Assertion 'All routes tiers priorities and safe aliases are queryable without payloads' (
    $routeQueries.Count -eq 5 -and $tierQueries.Count -eq 3 -and
    $priorityQueries.Count -eq 4 -and $aliasQuery.matches -eq 1 -and
    @($queries | Where-Object { $_.result -ne 'PASS' -or $_.matches -lt 1 -or
            $_.query.raw_payloads_emitted -or $_.query.source_hashes_emitted }).Count -eq 0 -and
    @($queries.examples | Where-Object delete_eligible).Count -eq 0)

$localCheck = $null
if ($VerifyDerivedSources) {
    $localCheck = & $generatorPath -RebuildRoot $root -Check | ConvertFrom-Json
    Add-Assertion 'Full deterministic conversion routing regeneration passes' (
        $localCheck.result -eq 'PASS' -and $localCheck.completion_criteria_satisfied -and
        $localCheck.report.sha256 -eq $evidence.report.sha256 -and
        $localCheck.summary.unclassified_assets -eq 0 -and
        $localCheck.summary.deletion_recommendations -eq 0)
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-15'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    verify_derived_sources = [bool]$VerifyDerivedSources
    report = $evidence.report
    summary = $evidence.summary
    local_check = $localCheck
    assertions = $assertions
} | ConvertTo-Json -Depth 20
if ($failed.Count -gt 0) { exit 1 }
