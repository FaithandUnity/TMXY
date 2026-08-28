[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$assertions = [Collections.Generic.List[object]]::new()

function Add-Assertion([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
            detail = $Detail
        })
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Get-TextSha256([string[]]$Lines) {
    $text = (($Lines | Sort-Object -CaseSensitive) -join "`n") + "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Copy-Document($Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-Candidate($Candidate, $Facts) {
    if ($Candidate.result -ne 'BLOCKED' -or $Candidate.task_status -ne 'BLOCKED' -or
        $Candidate.completion_criteria_satisfied -ne $false -or
        $Candidate.decision.required_status -ne 'SATISFIED' -or
        $Candidate.decision.observed_status -ne 'BLOCKED' -or
        $Candidate.decision.satisfied -ne $false -or $Candidate.decision.g2_approved -ne $false -or
        $Candidate.decision.p3_authorized -ne $false) { return $false }
    $scope = $Candidate.scope_definition
    if ($scope.mode -ne 'monotonic-union' -or $scope.outcome_based_exclusion -ne $false -or
        $scope.declared_roots.selection -ne 'all-declared-roots' -or
        @($scope.declared_roots.root_kinds).Count -ne 3 -or
        @(Compare-Object -ReferenceObject @($scope.declared_roots.root_kinds | Sort-Object) `
            -DifferenceObject @('character', 'scene', 'skill')).Count -ne 0 -or
        [int]$scope.core_table_resource_rules.selected_rules -ne 16 -or
        $scope.core_table_resource_rules.owner_filtering -ne 'forbidden' -or
        [int]$scope.core_table_resource_rules.client_presentation_rules -le 0 -or
        [int]$scope.core_table_resource_rules.server_authoritative_rules -le 0) { return $false }
    $closure = $Candidate.closure
    if (-not ($closure.PSObject.Properties.Name -contains 'conditional_required') -or
        -not ($Candidate.decision.thresholds.PSObject.Properties.Name -contains
            'conditional_required_missing')) { return $false }
    if ($closure.scope_complete -ne $false -or
        $closure.auxiliary_config_reference_scope_complete -ne $false -or
        $closure.asset_binding_resolution_explicit -ne $false -or
        [int]$closure.start_nodes -ne [int]$Facts.start_nodes -or
        [int]$closure.reachable_nodes -ne [int]$Facts.reachable_nodes -or
        [string]$closure.start_set_sha256 -cne [string]$Facts.start_sha256 -or
        [string]$closure.reachable_set_sha256 -cne [string]$Facts.reachable_sha256 -or
        [int]$closure.logical_gap_count -ne [int]$Facts.logical_gaps -or
        [string]$closure.gap_set_sha256 -cne [string]$Facts.gap_sha256) { return $false }
    $conditional = $closure.conditional_required
    if (-not (@($conditional.PSObject.Properties.Name) -contains 'conditional_required_missing') -or
        [int]$conditional.runtime_assert_rows -ne [int]$Facts.conditional_rows -or
        [int]$conditional.conditional_required_missing -ne [int]$Facts.conditional_missing -or
        [int]$conditional.conditional_required_unresolved -ne [int]$Facts.conditional_unresolved -or
        $conditional.source_inventory_id -ne 'P2-13' -or
        [string]$conditional.source_inventory_sha256 -cne [string]$Facts.p213_sha256 -or
        $conditional.member_set_exported -ne $false -or $null -ne $conditional.member_set_sha256 -or
        $conditional.zero_threshold_satisfied -ne $false -or
        [int]$Candidate.decision.thresholds.conditional_required_missing -ne 0) { return $false }
    $resolution = $closure.resolution
    if ([int]$resolution.table_unresolved -ne [int]$Facts.table_unresolved -or
        [int]$resolution.table_ambiguous -ne [int]$Facts.table_ambiguous -or
        [int]$resolution.package_unresolved -ne [int]$Facts.package_unresolved -or
        [int]$resolution.package_ambiguous -ne [int]$Facts.package_ambiguous -or
        [int]$resolution.package_scoped_terminal -ne [int]$Facts.scoped_terminal -or
        [int]$resolution.heuristic_target_selections -ne 0) { return $false }
    if ([int]$closure.asset_structure.unresolved -ne [int]$Facts.asset_unresolved -or
        [int]$closure.asset_structure.fail -ne [int]$Facts.asset_fail -or
        [int]$closure.integrity.unknown_record_count -ne 0 -or
        [int]$closure.integrity.unknown_resolution_count -ne 0) { return $false }
    # FK zero is required context but can never override any failed resource condition.
    if ([int]$closure.integrity.core_foreign_key_dangling -ne 0 -or
        [int]$Facts.logical_gaps -le 0) { return $false }
    return $true
}

$required = @(
    'Contracts/data-schema/g2-core-resource-closure-policy-v1.json',
    'Contracts/data-schema/g2-core-resource-closure-v1.schema.json',
    'Tools/TMXY.G2CoreClosure/g2_core_closure.py',
    'Tools/TMXY.G2CoreClosure/core_common.py',
    'Tools/TMXY.G2CoreClosure/core_closure.py',
    'Tools/TMXY.G2CoreClosure/core_report.py',
    'Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1',
    'Data/Governance/p2-g2-core-resource-closure.json',
    'Data/Inventory/p2-20a-core-resource-closure.json',
    'Data/Reports/p2-20a-core-resource-closure-report.json',
    'Data/Reports/p2-20a-core-resource-closure-report.md',
    'Docs/Formats/G2-CORE-RESOURCE-CLOSURE.md'
)
if ($VerifyDerivedSources) {
    $required += 'Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl'
}
foreach ($relative in $required) {
    Add-Assertion "Required file $relative" (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)
}

$policyPath = Join-Path $root 'Contracts/data-schema/g2-core-resource-closure-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts/data-schema/g2-core-resource-closure-v1.schema.json'
$reportPath = Join-Path $root 'Data/Reports/p2-20a-core-resource-closure-report.json'
$markdownPath = Join-Path $root 'Data/Reports/p2-20a-core-resource-closure-report.md'
$governancePath = Join-Path $root 'Data/Governance/p2-g2-core-resource-closure.json'
$evidencePath = Join-Path $root 'Data/Inventory/p2-20a-core-resource-closure.json'
$detailPath = Join-Path $root 'Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl'
$p213Path = Join-Path $root 'Data/Inventory/p2-13-reference-closure.json'
$policy = Get-Content $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$report = Get-Content $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$governance = Get-Content $governancePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$evidence = Get-Content $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$p212 = Get-Content (Join-Path $root 'Data/Inventory/p2-12-full-asset-inventory.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$p213 = Get-Content $p213Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String

$schemaValid = Get-Content $reportPath -Raw -Encoding UTF8 | Test-Json -SchemaFile $schemaPath
Add-Assertion 'Report validates against the closed JSON Schema' $schemaValid
$schemaNegative = Copy-Document $report
$schemaNegative | Add-Member -NotePropertyName unexpected -NotePropertyValue $true
Add-Assertion 'Closed Schema rejects an unknown top-level field' (-not (
        ($schemaNegative | ConvertTo-Json -Depth 100 -Compress) |
        Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))

$rootKinds = @($policy.declared_root_scope.root_kinds)
$traversed = @($policy.traversal.edge_records)
Add-Assertion 'Policy freezes all three prior root authorities without outcome exclusions' (
    $policy.scope_authority -like 'monotonic union*' -and
    @(Compare-Object -ReferenceObject @($rootKinds | Sort-Object) `
        -DifferenceObject @('character', 'scene', 'skill')).Count -eq 0 -and
    $policy.declared_root_scope.allows_outcome_based_exclusion -eq $false)
Add-Assertion 'Policy includes all sixteen core resource rules and both runtime authorities' (
    [int]$policy.core_table_resource_scope.required_rule_count -eq 16 -and
    @(Compare-Object `
        -ReferenceObject @($policy.core_table_resource_scope.include_runtime_authorities | Sort-Object) `
        -DifferenceObject @('client-presentation', 'server-authoritative')).Count -eq 0 -and
    $policy.core_table_resource_scope.owner_filtering -eq 'forbidden')
Add-Assertion 'Policy traverses the exact five evidence-backed edge records' (
    @(Compare-Object -ReferenceObject @($traversed | Sort-Object) -DifferenceObject @(
            'package_asset_edge', 'package_edge', 'table_domain_edge',
            'table_fk_edge', 'table_package_edge')).Count -eq 0)
Add-Assertion 'Policy requires config and asset-binding scope to fail closed' (
    $policy.auxiliary_config_scope.missing_adapters_fail_closed -and
    $policy.auxiliary_config_scope.new_roots_are_union_only -and
    $policy.traversal.first_candidate_selection -eq 'forbidden' -and
    $policy.fail_closed_rules.core_foreign_key_zero_is_not_resource_closure)
Add-Assertion 'Policy independently preserves conditional-required missing values' (
    $policy.conditional_required_scope.missing_values_remain_in_scope_without_table_package_edges -and
    $policy.conditional_required_scope.member_set_exported -eq $false -and
    $policy.conditional_required_scope.member_set_absence_blocks_zero_proof -and
    $policy.conditional_required_scope.core_foreign_key_substitution -eq 'forbidden' -and
    [int]$policy.completion.conditional_required_missing -eq 0 -and
    $policy.fail_closed_rules.conditional_required_metric_must_be_present_and_source_bound -and
    $policy.fail_closed_rules.conditional_required_missing_cannot_be_inferred_from_edge_absence)

$facts = [pscustomobject]@{
    start_nodes = [int]$report.closure.start_nodes
    start_sha256 = [string]$report.closure.start_set_sha256
    reachable_nodes = [int]$report.closure.reachable_nodes
    reachable_sha256 = [string]$report.closure.reachable_set_sha256
    logical_gaps = [int]$report.closure.logical_gap_count
    gap_sha256 = [string]$report.closure.gap_set_sha256
    table_unresolved = [int]$report.closure.resolution.table_unresolved
    table_ambiguous = [int]$report.closure.resolution.table_ambiguous
    package_unresolved = [int]$report.closure.resolution.package_unresolved
    package_ambiguous = [int]$report.closure.resolution.package_ambiguous
    scoped_terminal = [int]$report.closure.resolution.package_scoped_terminal
    asset_unresolved = [int]$report.closure.asset_structure.unresolved
    asset_fail = [int]$report.closure.asset_structure.fail
    conditional_rows = [int]$p213.table_closure.object_references.runtime_assert_rows
    conditional_missing = [int]$p213.table_closure.object_references.runtime_assert_missing_values
    conditional_unresolved = [int]$p213.table_closure.object_references.runtime_assert_unresolved_values
    p213_sha256 = Get-Sha256 $p213Path
}
Add-Assertion 'Tracked closure summary preserves the measured current blocker set' (
    $facts.start_nodes -eq 62256 -and $facts.reachable_nodes -eq 127015 -and
    $facts.logical_gaps -eq 21024 -and $facts.table_unresolved -eq 5161 -and
    $facts.table_ambiguous -eq 6945 -and $facts.package_unresolved -eq 407 -and
    $facts.package_ambiguous -eq 8511 -and $facts.asset_unresolved -eq 18 -and
    $facts.asset_fail -eq 0 -and $facts.start_sha256 -match '^[0-9a-f]{64}$' -and
    $facts.reachable_sha256 -match '^[0-9a-f]{64}$' -and $facts.gap_sha256 -match '^[0-9a-f]{64}$')
Add-Assertion 'P2-13 conditional-required aggregate is preserved independently of graph edges' (
    $facts.conditional_rows -eq 5993 -and $facts.conditional_missing -eq 29 -and
    $facts.conditional_unresolved -eq 0 -and
    [int]$p213.health.legacy_runtime_assert_missing_values -eq $facts.conditional_missing -and
    $report.closure.conditional_required.member_set_exported -eq $false -and
    $null -eq $report.closure.conditional_required.member_set_sha256 -and
    $report.closure.conditional_required.zero_threshold_satisfied -eq $false)
Add-Assertion 'Report matches frozen closure semantics and tracked facts' (Test-Candidate $report $facts)
Add-Assertion 'Scoped terminal edges are reported but never counted as missing or guessed' (
    $facts.scoped_terminal -eq 22040 -and
    [int]$report.closure.resolution.heuristic_target_selections -eq 0)
Add-Assertion 'Ignored detail metadata stays hash-bound without requiring it in a clean checkout' (
    $report.closure.detail_export.path -eq 'Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl' -and
    $report.closure.detail_export.sha256 -match '^[0-9a-f]{64}$' -and
    [int64]$report.closure.detail_export.bytes -eq 33232029 -and
    [int]$report.closure.detail_export.lines -eq 210313 -and
    $report.closure.detail_export.tracked -eq $false)

if ($VerifyDerivedSources) {
    $startIds = [Collections.Generic.List[string]]::new()
    $reachableIds = [Collections.Generic.List[string]]::new()
    $gapLines = [Collections.Generic.List[string]]::new()
    $resolution = @{}
    $assetStructures = @{}
    foreach ($line in [IO.File]::ReadLines($detailPath)) {
        $entry = $line | ConvertFrom-Json -Depth 20
        $record = [string]$entry.record
        if ($record -eq 'scope_start') { $startIds.Add([string]$entry.id) }
        elseif ($record -eq 'reachable_node') { $reachableIds.Add([string]$entry.id) }
        elseif ($record -eq 'logical_gap') {
            $gapLines.Add($line)
            $key = "$($entry.edge_record):$($entry.resolution)"
            $resolution[$key] = 1 + [int]($resolution[$key] ?? 0)
        }
        elseif ($record -eq 'asset_structure_gap') {
            $assetStructures[[string]$entry.structure] =
                1 + [int]($assetStructures[[string]$entry.structure] ?? 0)
        }
    }
    Add-Assertion 'Detailed export independently closes start reachable and gap sets' (
        $startIds.Count -eq $facts.start_nodes -and
        (Get-TextSha256 @($startIds)) -ceq $facts.start_sha256 -and
        $reachableIds.Count -eq $facts.reachable_nodes -and
        (Get-TextSha256 @($reachableIds)) -ceq $facts.reachable_sha256 -and
        $gapLines.Count -eq $facts.logical_gaps -and
        (Get-TextSha256 @($gapLines)) -ceq $facts.gap_sha256 -and
        [int]($resolution['table_package_edge:unresolved'] ?? 0) -eq $facts.table_unresolved -and
        [int]($resolution['table_package_edge:ambiguous'] ?? 0) -eq $facts.table_ambiguous -and
        [int]($resolution['package_edge:unresolved'] ?? 0) -eq $facts.package_unresolved -and
        [int]($resolution['package_edge:ambiguous'] ?? 0) -eq $facts.package_ambiguous -and
        [int]($assetStructures['UNRESOLVED'] ?? 0) -eq $facts.asset_unresolved -and
        [int]($assetStructures['FAIL'] ?? 0) -eq $facts.asset_fail)
    Add-Assertion 'Ignored detailed export bytes and line count are exact when deep verification is requested' (
        $report.closure.detail_export.sha256 -eq (Get-Sha256 $detailPath) -and
        [int64]$report.closure.detail_export.bytes -eq (Get-Item $detailPath).Length -and
        [int]$report.closure.detail_export.lines -eq (Get-LineCount $detailPath))
}

$negativeScope = Copy-Document $report
$negativeScope.scope_definition.declared_roots.root_kinds = @('character', 'scene')
$negativeRules = Copy-Document $report
$negativeRules.scope_definition.core_table_resource_rules.selected_rules = 15
$negativeFirst = Copy-Document $report
$negativeFirst.closure.resolution.heuristic_target_selections = 1
$negativeFk = Copy-Document $report
$negativeFk.closure.resolution.table_unresolved = 0
$negativeFk.closure.resolution.table_ambiguous = 0
$negativeFk.closure.resolution.package_unresolved = 0
$negativeFk.closure.resolution.package_ambiguous = 0
$negativeFk.closure.logical_gap_count = 0
$negativeFk.closure.conditional_required.conditional_required_missing = 0
$negativeFk.closure.conditional_required.zero_threshold_satisfied = $true
$negativeSummary = Copy-Document $report
$negativeSummary.closure.resolution.table_unresolved = 0
$negativeComplete = Copy-Document $report
$negativeComplete.closure.scope_complete = $true
$negativeConditionalZero = Copy-Document $report
$negativeConditionalZero.closure.conditional_required.conditional_required_missing = 0
$negativeConditionalZero.closure.conditional_required.zero_threshold_satisfied = $true
$negativeConditionalDeleted = Copy-Document $report
$negativeConditionalDeleted.closure.conditional_required.PSObject.Properties.Remove(
    'conditional_required_missing')
Add-Assertion 'Negative case rejects outcome-based root narrowing' (-not (Test-Candidate $negativeScope $facts))
Add-Assertion 'Negative case rejects owner or rule narrowing' (-not (Test-Candidate $negativeRules $facts))
Add-Assertion 'Negative case rejects first-candidate or heuristic selection' (-not (Test-Candidate $negativeFirst $facts))
Add-Assertion 'Negative case rejects core-FK-zero substitution' (-not (Test-Candidate $negativeFk $facts))
Add-Assertion 'Negative case rejects summary-only tampering against detailed sets' (-not (Test-Candidate $negativeSummary $facts))
Add-Assertion 'Negative case rejects scope complete while config and binding coverage are false' (-not (Test-Candidate $negativeComplete $facts))
Add-Assertion 'Negative case rejects changing conditional-required missing from twenty-nine to zero' (-not (Test-Candidate $negativeConditionalZero $facts))
Add-Assertion 'Negative case rejects deleting the conditional-required metric' (-not (Test-Candidate $negativeConditionalDeleted $facts))

$bindingsPass = $true
$ignoredBindings = @{
    'asset-catalog' = $p212.catalog
    'reference-graph' = $p213.graph
}
foreach ($binding in $report.input_bindings.artifacts) {
    $path = Join-Path $root ([string]$binding.path)
    if (Test-Path $path -PathType Leaf) {
        if ([string]$binding.sha256 -cne (Get-Sha256 $path) -or
            [int64]$binding.bytes -ne (Get-Item $path).Length) { $bindingsPass = $false }
    }
    elseif ($ignoredBindings.ContainsKey([string]$binding.id)) {
        $metadata = $ignoredBindings[[string]$binding.id]
        if ([string]$binding.path -cne [string]$metadata.path -or
            [string]$binding.sha256 -cne [string]$metadata.sha256 -or
            [int64]$binding.bytes -ne [int64]$metadata.bytes -or
            [int]$binding.lines -ne [int]$metadata.lines) { $bindingsPass = $false }
    }
    else { $bindingsPass = $false }
}
Add-Assertion 'P2-05 P2-08 P2-12 P2-13 P2-18 G2 and ignored inputs are exact-hash bound' $bindingsPass
Add-Assertion 'Governance remains blocked and binds the machine report' (
    $governance.status -eq 'BLOCKED' -and $governance.scope_complete -eq $false -and
    [int]$governance.conditional_required_missing -eq $facts.conditional_missing -and
    $governance.conditional_required_member_set_exported -eq $false -and
    $governance.report.sha256 -eq (Get-Sha256 $reportPath) -and
    $governance.decisions.g2_approved -eq $false -and
    $governance.decisions.p3_authorized -eq $false)
Add-Assertion 'Evidence binds tracked reports governance and ignored-detail metadata' (
    $evidence.result -eq 'BLOCKED' -and $evidence.task_status -eq 'BLOCKED' -and
    $evidence.completion_criteria_satisfied -eq $false -and
    $evidence.outputs.report_json.sha256 -eq (Get-Sha256 $reportPath) -and
    $evidence.outputs.report_markdown.sha256 -eq (Get-Sha256 $markdownPath) -and
    $evidence.outputs.governance.sha256 -eq (Get-Sha256 $governancePath) -and
    $evidence.outputs.detail_export.sha256 -eq $report.closure.detail_export.sha256 -and
    [int64]$evidence.outputs.detail_export.bytes -eq [int64]$report.closure.detail_export.bytes -and
    [int]$evidence.outputs.detail_export.lines -eq [int]$report.closure.detail_export.lines -and
    (-not $VerifyDerivedSources -or
        $evidence.outputs.detail_export.sha256 -eq (Get-Sha256 $detailPath)))
Add-Assertion 'No G2 P3 playable release repair or delete authority is claimed' (
    $report.authority_boundaries.g2_approved -eq $false -and
    $report.authority_boundaries.p3_authorized -eq $false -and
    $report.authority_boundaries.playable_experience_proven -eq $false -and
    $report.authority_boundaries.release_authority -eq $false -and
    $report.authority_boundaries.automatic_repair_or_delete_authority -eq $false)
Add-Assertion 'Tracked disclosure contains no sensitive payload classes' (
    $report.disclosure.private_source_paths -eq $false -and
    $report.disclosure.exact_primary_keys -eq $false -and
    $report.disclosure.raw_table_rows -eq $false -and
    $report.disclosure.decoded_confidential_payloads -eq $false -and
    $report.disclosure.legacy_source_lines -eq $false)

$derivedCheck = 'NOT_REQUESTED'
if ($VerifyDerivedSources) {
    & (Join-Path $root 'Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1') `
        -RebuildRoot $root -Check | Out-Null
    $derivedCheck = 'PASS'
    Add-Assertion 'Byte-identical isolated regeneration passes wrapper check mode' $true
}

$failures = @($assertions | Where-Object result -eq 'FAIL')
$result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$output = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [string]$report.captured_utc
    task_id = 'P2-20A'
    criterion_id = 'G2-06'
    result = $result
    review_result = 'BLOCKED'
    task_status = 'BLOCKED'
    completion_criteria_satisfied = $false
    assertions_passed = @($assertions | Where-Object result -eq 'PASS').Count
    assertions_failed = $failures.Count
    negative_cases = [pscustomobject][ordered]@{
        root_narrowing_rejected = -not (Test-Candidate $negativeScope $facts)
        rule_narrowing_rejected = -not (Test-Candidate $negativeRules $facts)
        first_candidate_rejected = -not (Test-Candidate $negativeFirst $facts)
        foreign_key_substitution_rejected = -not (Test-Candidate $negativeFk $facts)
        summary_tamper_rejected = -not (Test-Candidate $negativeSummary $facts)
        false_scope_completion_rejected = -not (Test-Candidate $negativeComplete $facts)
        conditional_required_zero_tamper_rejected = -not (Test-Candidate $negativeConditionalZero $facts)
        conditional_required_metric_deletion_rejected = -not (Test-Candidate $negativeConditionalDeleted $facts)
    }
    closure = [pscustomobject][ordered]@{
        start_nodes = $facts.start_nodes
        reachable_nodes = $facts.reachable_nodes
        logical_gaps = $facts.logical_gaps
        asset_structure_unresolved = $facts.asset_unresolved
        conditional_required_missing = $facts.conditional_missing
        scope_complete = $false
    }
    derived_check = $derivedCheck
    assertions = @($assertions)
}
$output | ConvertTo-Json -Depth 100
if ($result -ne 'PASS') { throw "P2-20A contract failed with $($failures.Count) assertion(s)." }
