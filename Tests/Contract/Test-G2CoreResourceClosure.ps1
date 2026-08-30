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

function Get-OrderedTextSha256([string[]]$Lines) {
    $text = ($Lines -join "`n") + "`n"
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

function Test-AuxiliaryDocument($Candidate) {
    if ($Candidate.evidence_revision -ne 'P2-20A.3' -or
        $Candidate.task_id -ne 'P2-20A' -or $Candidate.criterion_id -ne 'G2-06' -or
        $Candidate.source_build -ne 'qy-3.0.0.413' -or
        $Candidate.result -ne 'BLOCKED' -or $Candidate.review_execution_result -ne 'PASS' -or
        $Candidate.task_status -ne 'BLOCKED' -or
        $Candidate.completion_criteria_satisfied -ne $false -or
        $Candidate.scope_complete -ne $false -or $Candidate.g2_06_satisfied -ne $false -or
        $Candidate.p3_authorized -ne $false -or @($Candidate.file_instances).Count -ne 212) {
        return $false
    }
    $measured = $Candidate.measured_lexical_candidates
    $states = $Candidate.adapter_state_summary
    $semantic = $Candidate.semantic_resolution
    $config = $Candidate.config_closure
    $completion = $Candidate.completion
    $stateCounts = @{}
    $instanceIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in $Candidate.file_instances) {
        $name = [string]$item.adapter_state
        $stateCounts[$name] = 1 + [int]($stateCounts[$name] ?? 0)
        if (-not $instanceIds.Add([string]$item.instance_sha256)) { return $false }
    }
    return $measured.measurement_authority -eq 'LEXICAL_ONLY' -and
        [int]$measured.file_instances -eq 212 -and
        [int]$measured.unique_content_bodies -eq 196 -and
        [int]$measured.parsed_file_instances -eq 206 -and
        [int]$measured.malformed_file_instances -eq 6 -and
        [int]$measured.scalar_positions -eq 39522 -and
        [int]$measured.nonempty_scalar_positions -eq 39498 -and
        [int]$measured.asset_exact_occurrences -eq 3043 -and
        [int]$measured.package_exact_occurrences -eq 638 -and
        [int]$measured.package_unique_occurrences -eq 218 -and
        [int]$measured.package_ambiguous_occurrences -eq 420 -and
        [int]$measured.package_ambiguous_candidate_edges -eq 1136 -and
        [int]$measured.config_exact_edges -eq 8 -and
        [int]$states.terminal_file_instances -eq 0 -and
        [int]$states.nonterminal_file_instances -eq 212 -and
        [int]$states.semantic_approved -eq 0 -and [int]$states.no_ref_approved -eq 0 -and
        [int]$states.candidate_only -eq 171 -and [int]$states.editor_undecided -eq 35 -and
        [int]$states.malformed_blocked -eq 6 -and [int]$states.approved_roots -eq 0 -and
        [int]($stateCounts['candidate-only'] ?? 0) -eq 171 -and
        [int]($stateCounts['editor-undecided'] ?? 0) -eq 35 -and
        [int]($stateCounts['malformed-blocked'] ?? 0) -eq 6 -and
        $semantic.status -eq 'UNASSESSED' -and
        $null -eq $semantic.resolved_occurrences -and $null -eq $semantic.ambiguous_occurrences -and
        $null -eq $semantic.unresolved_occurrences -and $null -eq $semantic.unknown_occurrences -and
        [int]$semantic.first_candidate_selections -eq 0 -and
        [int]$semantic.heuristic_target_selections -eq 0 -and
        [int]$config.approved_root_count -eq 0 -and $config.closure_complete -eq $false -and
        $config.cycle_detection_complete -eq $false -and $null -eq $config.cycle_count -and
        $null -eq $config.unresolved_cycle_count -and
        $config.reason_code -eq 'APPROVED_ROOTS_AND_SEMANTIC_EDGES_UNAVAILABLE' -and
        $completion.semantic_adapters_terminal -eq $false -and
        $completion.semantic_resolution_complete -eq $false -and
        $completion.config_closure_complete -eq $false -and
        $completion.scope_complete -eq $false -and $completion.satisfied -eq $false -and
        $Candidate.authority_boundaries.g2_06_satisfied -eq $false -and
        $Candidate.authority_boundaries.g2_approved -eq $false -and
        $Candidate.authority_boundaries.p3_authorized -eq $false -and
        $Candidate.disclosure.anonymous_hash_count_reason_only -eq $true -and
        $Candidate.disclosure.raw_scalar_values -eq $false -and
        $Candidate.disclosure.file_names -eq $false -and
        $Candidate.disclosure.private_source_paths -eq $false -and
        $Candidate.disclosure.exact_primary_keys -eq $false -and
        $Candidate.disclosure.raw_table_rows -eq $false -and
        $Candidate.disclosure.decoded_payloads -eq $false
}

function Test-AuxiliaryBinding($Candidate, [string]$AuxiliaryPath, $Auxiliary) {
    $bindings = @($Candidate.input_bindings.artifacts |
        Where-Object { $_.id -eq 'P2-20A.3-AUX' })
    if ($bindings.Count -ne 1) { return $false }
    $binding = $bindings[0]
    return [string]$binding.path -ceq
        'Data/Reports/p2-20a-aux-config-reference-report.json' -and
        [string]$binding.sha256 -ceq (Get-Sha256 $AuxiliaryPath) -and
        [int64]$binding.bytes -eq (Get-Item $AuxiliaryPath).Length -and
        (Test-AuxiliaryDocument $Auxiliary)
}

function Test-CoreInputBindings($Candidate, $Policy, $IgnoredBindings) {
    $expected = [ordered]@{
        'P2-05' = [string]$Policy.inputs.p2_05
        'P2-06' = [string]$Policy.inputs.p2_06
        'P2-08' = [string]$Policy.inputs.p2_08
        'ownership-registry' = [string]$Policy.inputs.ownership_registry
        'core-registry' = [string]$Policy.inputs.core_registry
        'P2-12' = [string]$Policy.inputs.p2_12
        'asset-catalog' = [string]$Policy.inputs.asset_catalog
        'reference-policy' = [string]$Policy.inputs.reference_policy
        'P2-13' = [string]$Policy.inputs.p2_13
        'reference-graph' = [string]$Policy.inputs.reference_graph
        'P2-18' = [string]$Policy.inputs.p2_18
        'auxiliary-reference-policy' = [string]$Policy.inputs.auxiliary_reference_policy
        'auxiliary-reference-schema' = [string]$Policy.inputs.auxiliary_reference_schema
        'P2-20A.3-AUX' = [string]$Policy.inputs.auxiliary_reference_evidence
        'P2-20A.4-REPORT' = [string]$Policy.inputs.asset_descriptor_report
        'P2-20A.4-DETAIL' = [string]$Policy.inputs.asset_descriptor_detail
        'P2-20A.4-EVIDENCE' = [string]$Policy.inputs.asset_descriptor_evidence
        'P2-20A.7-REPORT' = [string]$Policy.inputs.asset_binding_failure_report
        'P2-20A.7-EVIDENCE' = [string]$Policy.inputs.asset_binding_failure_evidence
        'P2-20A.8-REPORT' = [string]$Policy.inputs.asset_binding_recovery_report
        'P2-20A.8-EVIDENCE' = [string]$Policy.inputs.asset_binding_recovery_evidence
        'g2-policy' = [string]$Policy.inputs.g2_policy
    }
    $bindings = @($Candidate.input_bindings.artifacts)
    if ($bindings.Count -ne $expected.Count -or
        @(Compare-Object @($bindings.id) @($expected.Keys) -SyncWindow 0).Count -ne 0 -or
        @($bindings.id | Sort-Object -Unique).Count -ne $expected.Count) { return $false }
    $aggregateLines = [Collections.Generic.List[string]]::new()
    foreach ($binding in $bindings) {
        $id = [string]$binding.id
        if (-not $expected.Contains($id) -or
            [string]$binding.path -cne [string]$expected[$id]) { return $false }
        $path = Join-Path $root ([string]$binding.path)
        if (Test-Path $path -PathType Leaf) {
            if ([string]$binding.sha256 -cne (Get-Sha256 $path) -or
                [int64]$binding.bytes -ne (Get-Item $path).Length) { return $false }
        }
        elseif ($IgnoredBindings.ContainsKey($id)) {
            $metadata = $IgnoredBindings[$id]
            if ([string]$binding.sha256 -cne [string]$metadata.sha256 -or
                [int64]$binding.bytes -ne [int64]$metadata.bytes -or
                [int]$binding.lines -ne [int]$metadata.lines) { return $false }
        }
        else { return $false }
        $aggregateLines.Add("$id|$($binding.path)|$($binding.sha256)")
    }
    return [string]$Candidate.input_bindings.aggregate_sha256 -ceq
        (Get-OrderedTextSha256 @($aggregateLines))
}

function Test-MemberWorkset($Records, [int]$ExpectedCount, [string]$ExpectedSha,
    [string[]]$AllowedRules) {
    if (@($Records).Count -ne $ExpectedCount) { return $false }
    $members = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($record in @($Records)) {
        $names = @($record.PSObject.Properties.Name | Sort-Object)
        if (@(Compare-Object $names @('member_sha256', 'reason', 'rule_id')).Count -ne 0 -or
            [string]$record.member_sha256 -notmatch '^[0-9a-f]{64}$' -or
            [string]$record.reason -cne 'missing-required-value' -or
            [string]$record.rule_id -cnotin $AllowedRules -or
            -not $members.Add([string]$record.member_sha256)) { return $false }
        $lines.Add('{"member_sha256":"' + [string]$record.member_sha256 +
            '","reason":"missing-required-value","rule_id":"' +
            [string]$record.rule_id + '"}')
    }
    return (Get-TextSha256 @($lines)) -ceq $ExpectedSha
}

function Test-AssetWorkset($Records, [object]$Facts) {
    if (@($Records).Count -ne [int]$Facts.binding_assets) { return $false }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $lines = [Collections.Generic.List[string]]::new()
    $targets = @{ RESOLVED = 0; AMBIGUOUS = 0; UNRESOLVED = 0 }
    $edges = @{ RESOLVED = 0; AMBIGUOUS = 0; UNRESOLVED = 0 }
    $fields = @('asset_id', 'candidate_count', 'candidate_set_sha256',
        'descriptor_variants', 'family', 'heuristic_selection', 'resolution',
        'resolution_basis', 'structure', 'valid_variants')
    foreach ($record in @($Records)) {
        $names = @($record.PSObject.Properties.Name | Sort-Object)
        $resolution = [string]$record.resolution
        $basis = [string]$record.resolution_basis
        $family = [string]$record.family
        $valid = [int]$record.valid_variants
        $candidateCount = [int]$record.candidate_count
        $semantic = switch ($basis) {
            'UNIQUE_VALID_DESCRIPTOR' { $resolution -eq 'RESOLVED' -and $valid -gt 0 }
            'EQUIVALENT_VALID_DESCRIPTOR_SET' { $resolution -eq 'RESOLVED' -and $valid -gt 0 }
            'SELF_DESCRIBING_RULE' { $resolution -eq 'RESOLVED' -and $family -in @('ter', 'wav') }
            'DIVERGENT_DESCRIPTOR_SET' { $resolution -eq 'AMBIGUOUS' }
            'DESCRIPTOR_VALIDATION_FAILED' { $resolution -eq 'UNRESOLVED' -and $valid -eq 0 }
            'MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES' { $resolution -eq 'AMBIGUOUS' }
            'OPEN_REJECTED_CANDIDATE' { $resolution -eq 'AMBIGUOUS' }
            'NO_PRODUCTION_COMPATIBLE_CANDIDATE' { $resolution -eq 'UNRESOLVED' }
            'SINGLE_COMPATIBLE_SEMANTIC_CLASS' { $resolution -eq 'RESOLVED' }
            default { $false }
        }
        if (@(Compare-Object $names $fields).Count -ne 0 -or
            [string]$record.asset_id -notmatch '^[0-9a-f]{64}$' -or
            [string]$record.candidate_set_sha256 -notmatch '^[0-9a-f]{64}$' -or
            $family -notin @('anim', 'qtx', 'skem', 'sm', 'ter', 'wav') -or
            $resolution -notin @('RESOLVED', 'AMBIGUOUS', 'UNRESOLVED') -or
            [string]$record.structure -notin @('PASS', 'UNRESOLVED', 'FAIL') -or
            $candidateCount -le 0 -or [int]$record.descriptor_variants -lt 0 -or $valid -lt 0 -or
            $record.heuristic_selection -ne $false -or -not $semantic -or
            -not $ids.Add([string]$record.asset_id)) { return $false }
        ++$targets[$resolution]
        $edges[$resolution] += $candidateCount
        $ordered = [pscustomobject][ordered]@{
            asset_id = [string]$record.asset_id
            candidate_count = $candidateCount
            candidate_set_sha256 = [string]$record.candidate_set_sha256
            descriptor_variants = [int]$record.descriptor_variants
            family = $family
            heuristic_selection = $false
            resolution = $resolution
            resolution_basis = $basis
            structure = [string]$record.structure
            valid_variants = $valid
        }
        $lines.Add(($ordered | ConvertTo-Json -Compress))
    }
    return $targets.RESOLVED -eq [int]$Facts.binding_resolved -and
        $targets.AMBIGUOUS -eq [int]$Facts.binding_ambiguous -and
        $targets.UNRESOLVED -eq [int]$Facts.binding_unresolved -and
        $edges.RESOLVED -eq [int]$Facts.binding_resolved_edges -and
        $edges.AMBIGUOUS -eq [int]$Facts.binding_ambiguous_edges -and
        $edges.UNRESOLVED -eq [int]$Facts.binding_unresolved_edges -and
        (Get-TextSha256 @($lines)) -ceq [string]$Facts.binding_workset_sha
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
    $auxiliary = $scope.auxiliary_config
    if ($auxiliary.evidence_revision -ne 'P2-20A.3' -or
        $auxiliary.evidence_hash_bound -ne $true -or
        $auxiliary.measurement_authority -ne 'LEXICAL_ONLY' -or
        [int]$auxiliary.inventory_files -ne 212 -or
        [int]$auxiliary.unique_content_bodies -ne 196 -or
        [int]$auxiliary.parsed_file_instances -ne 206 -or
        [int]$auxiliary.malformed_isolated -ne 6 -or
        [int]$auxiliary.nonempty_scalar_positions -ne 39498 -or
        [int]$auxiliary.asset_exact_occurrences -ne 3043 -or
        [int]$auxiliary.package_exact_occurrences -ne 638 -or
        [int]$auxiliary.config_exact_edges -ne 8 -or
        [int]$auxiliary.reference_adapters -ne 0 -or
        $auxiliary.reference_adapter_coverage -ne 'lexical-candidate-inventory-only' -or
        [int]$auxiliary.terminal_file_instances -ne 0 -or
        [int]$auxiliary.candidate_only -ne 171 -or
        [int]$auxiliary.editor_undecided -ne 35 -or
        [int]$auxiliary.malformed_blocked -ne 6 -or
        [int]$auxiliary.semantic_approved -ne 0 -or
        [int]$auxiliary.no_ref_approved -ne 0 -or
        [int]$auxiliary.approved_roots -ne 0 -or
        $auxiliary.exact_complete_scalar_matching -ne $true -or
        $auxiliary.first_candidate_selection_used -ne $false -or
        $auxiliary.scope_complete -ne $false) { return $false }
    $closure = $Candidate.closure
    if (-not ($closure.PSObject.Properties.Name -contains 'conditional_required') -or
        -not ($closure.PSObject.Properties.Name -contains 'asset_binding') -or
        -not ($Candidate.decision.thresholds.PSObject.Properties.Name -contains
            'conditional_required_missing')) { return $false }
    if ($closure.scope_complete -ne $false -or
        $closure.auxiliary_config_reference_scope_complete -ne $false -or
        $closure.asset_binding_resolution_explicit -ne $true -or
        [int]$closure.start_nodes -ne [int]$Facts.start_nodes -or
        [int]$closure.reachable_nodes -ne [int]$Facts.reachable_nodes -or
        [string]$closure.start_set_sha256 -cne [string]$Facts.start_sha256 -or
        [string]$closure.reachable_set_sha256 -cne [string]$Facts.reachable_sha256 -or
        [int]$closure.logical_gap_count -ne [int]$Facts.logical_gaps -or
        [string]$closure.gap_set_sha256 -cne [string]$Facts.gap_sha256) { return $false }
    $binding = $closure.asset_binding
    if ($binding.resolution_explicit -ne $true -or
        [int]$binding.reachable_assets -ne [int]$Facts.binding_assets -or
        [int]$binding.resolved_targets -ne [int]$Facts.binding_resolved -or
        [int]$binding.ambiguous_targets -ne [int]$Facts.binding_ambiguous -or
        [int]$binding.unresolved_targets -ne [int]$Facts.binding_unresolved -or
        [int]$binding.unknown_targets -ne 0 -or
        [int]$binding.candidate_edges -ne [int]$Facts.binding_edges -or
        [int]$binding.resolved_edges -ne [int]$Facts.binding_resolved_edges -or
        [int]$binding.ambiguous_edges -ne [int]$Facts.binding_ambiguous_edges -or
        [int]$binding.unresolved_edges -ne [int]$Facts.binding_unresolved_edges -or
        [int]$binding.unknown_edges -ne 0 -or
        [int]$binding.workset_count -ne [int]$Facts.binding_assets -or
        [string]$binding.workset_sha256 -cne [string]$Facts.binding_workset_sha -or
        $binding.workset_exported -ne $true -or
        $binding.first_candidate_selection_used -ne $false -or
        [int]$Candidate.decision.thresholds.asset_binding_ambiguous -ne 0 -or
        [int]$Candidate.decision.thresholds.asset_binding_unresolved -ne 0 -or
        [int]$Candidate.decision.thresholds.asset_binding_unknown -ne 0) { return $false }
    $conditional = $closure.conditional_required
    if (-not (@($conditional.PSObject.Properties.Name) -contains 'conditional_required_missing') -or
        [int]$conditional.runtime_assert_rows -ne [int]$Facts.conditional_rows -or
        [int]$conditional.conditional_required_missing -ne [int]$Facts.conditional_missing -or
        [int]$conditional.conditional_required_unresolved -ne [int]$Facts.conditional_unresolved -or
        $conditional.source_inventory_id -ne 'P2-13' -or
        [string]$conditional.source_inventory_sha256 -cne [string]$Facts.p213_sha256 -or
        $conditional.member_source_inventory_id -ne 'P2-06' -or
        [string]$conditional.member_source_inventory_sha256 -cne [string]$Facts.p206_sha256 -or
        [int]$conditional.member_source_file_count -ne 1 -or
        [string]$conditional.member_source_file_set_sha256 -cne [string]$Facts.member_source_sha -or
        $conditional.member_set_exported -ne $true -or
        [int]$conditional.member_set_count -ne [int]$Facts.conditional_missing -or
        [string]$conditional.member_set_sha256 -cne [string]$Facts.member_set_sha -or
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
    'Tools/TMXY.G2CoreClosure/asset_binding_workset.py',
    'Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1',
    'Data/Governance/p2-g2-core-resource-closure.json',
    'Data/Inventory/p2-20a-core-resource-closure.json',
    'Data/Reports/p2-20a-core-resource-closure-report.json',
    'Data/Reports/p2-20a-core-resource-closure-report.md',
    'Docs/Formats/G2-CORE-RESOURCE-CLOSURE.md'
)
if ($VerifyDerivedSources) {
    $required += @(
        'Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl',
        'Data/Exports/P2-20/p2-20a-conditional-required-workset.jsonl',
        'Data/Exports/P2-20/p2-20a-asset-binding-workset.jsonl',
        'Data/Exports/P2-20/p2-20a-effective-asset-binding-workset.jsonl'
    )
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
$worksetPath = Join-Path $root 'Data/Exports/P2-20/p2-20a-conditional-required-workset.jsonl'
$assetWorksetPath = Join-Path $root 'Data/Exports/P2-20/p2-20a-effective-asset-binding-workset.jsonl'
$auxiliaryReportPath = Join-Path $root 'Data/Reports/p2-20a-aux-config-reference-report.json'
$auxiliaryPolicyPath = Join-Path $root 'Contracts/data-schema/g2-auxiliary-config-reference-policy-v1.json'
$auxiliarySchemaPath = Join-Path $root 'Contracts/data-schema/g2-auxiliary-config-reference-v1.schema.json'
$p206Path = Join-Path $root 'Data/Inventory/p2-06-three-layer-data.json'
$p213Path = Join-Path $root 'Data/Inventory/p2-13-reference-closure.json'
$policy = Get-Content $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$report = Get-Content $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$governance = Get-Content $governancePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$evidence = Get-Content $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$auxiliaryReport = Get-Content $auxiliaryReportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$assetDescriptorReport = Get-Content (Join-Path $root ([string]$policy.inputs.asset_descriptor_report)) `
    -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$p212 = Get-Content (Join-Path $root 'Data/Inventory/p2-12-full-asset-inventory.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$p213 = Get-Content $p213Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$p206 = Get-Content $p206Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$referencePolicy = Get-Content (Join-Path $root ([string]$policy.inputs.reference_policy)) `
    -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String

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
    $policy.auxiliary_config_scope.lexical_evidence_must_be_hash_bound -and
    $policy.auxiliary_config_scope.lexical_evidence_revision -eq 'P2-20A.3' -and
    $policy.auxiliary_config_scope.measurement_authority -eq 'LEXICAL_ONLY' -and
    $policy.auxiliary_config_scope.current_coverage -eq 'lexical-candidate-inventory-only' -and
    $policy.auxiliary_config_scope.semantic_approval_required -and
    $policy.auxiliary_config_scope.zero_lexical_match_is_not_no_reference_approval -and
    $policy.auxiliary_config_scope.malformed_inputs_remain_blocking -and
    $policy.auxiliary_config_scope.machine_candidates_are_not_approvals -and
    $policy.auxiliary_config_scope.new_roots_are_union_only -and
    $policy.traversal.first_candidate_selection -eq 'forbidden' -and
    $policy.fail_closed_rules.core_foreign_key_zero_is_not_resource_closure -and
    $policy.asset_binding_scope.explicit_state_does_not_imply_resolved -and
    $policy.asset_binding_scope.ambiguous_and_unresolved_remain_blocking -and
    $policy.asset_binding_scope.first_candidate_selection -eq 'forbidden' -and
    [int]$policy.completion.asset_binding_ambiguous -eq 0 -and
    [int]$policy.completion.asset_binding_unresolved -eq 0 -and
    [int]$policy.completion.asset_binding_unknown -eq 0)
Add-Assertion 'Policy independently preserves conditional-required missing values' (
    $policy.conditional_required_scope.missing_values_remain_in_scope_without_table_package_edges -and
    $policy.evidence_revision -eq 'P2-20A.3' -and
    $policy.conditional_required_scope.member_set_exported -eq $true -and
    $policy.conditional_required_scope.member_set_must_be_complete_unique_and_hash_bound -and
    $policy.conditional_required_scope.member_values_forbidden -and
    @(Compare-Object @($policy.conditional_required_scope.member_record_fields | Sort-Object) `
        @('member_sha256', 'reason', 'rule_id')).Count -eq 0 -and
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
    p206_sha256 = Get-Sha256 $p206Path
    p213_sha256 = Get-Sha256 $p213Path
    member_source_sha = [string]$report.closure.conditional_required.member_source_file_set_sha256
    member_set_sha = [string]$report.closure.conditional_required.member_set_sha256
    binding_assets = [int]$report.closure.asset_binding.reachable_assets
    binding_resolved = [int]$report.closure.asset_binding.resolved_targets
    binding_ambiguous = [int]$report.closure.asset_binding.ambiguous_targets
    binding_unresolved = [int]$report.closure.asset_binding.unresolved_targets
    binding_edges = [int]$report.closure.asset_binding.candidate_edges
    binding_resolved_edges = [int]$report.closure.asset_binding.resolved_edges
    binding_ambiguous_edges = [int]$report.closure.asset_binding.ambiguous_edges
    binding_unresolved_edges = [int]$report.closure.asset_binding.unresolved_edges
    binding_workset_sha = [string]$report.closure.asset_binding.workset_sha256
}
Add-Assertion 'Tracked closure summary preserves the measured current blocker set' (
    $facts.start_nodes -eq 62256 -and $facts.reachable_nodes -eq 127015 -and
    $facts.logical_gaps -eq 21024 -and $facts.table_unresolved -eq 5161 -and
    $facts.table_ambiguous -eq 6945 -and $facts.package_unresolved -eq 407 -and
    $facts.package_ambiguous -eq 8511 -and $facts.asset_unresolved -eq 18 -and
    $facts.asset_fail -eq 0 -and $facts.start_sha256 -match '^[0-9a-f]{64}$' -and
    $facts.binding_assets -eq 21494 -and $facts.binding_resolved -eq 21299 -and
    $facts.binding_ambiguous -eq 189 -and $facts.binding_unresolved -eq 6 -and
    $facts.binding_edges -eq 39351 -and $facts.binding_resolved_edges -eq 38796 -and
    $facts.binding_ambiguous_edges -eq 546 -and $facts.binding_unresolved_edges -eq 9 -and
    $facts.binding_workset_sha -match '^[0-9a-f]{64}$' -and
    $facts.reachable_sha256 -match '^[0-9a-f]{64}$' -and $facts.gap_sha256 -match '^[0-9a-f]{64}$')
Add-Assertion 'P2-13 conditional-required aggregate is preserved independently of graph edges' (
    $facts.conditional_rows -eq 5993 -and $facts.conditional_missing -eq 29 -and
    $facts.conditional_unresolved -eq 0 -and
    [int]$p213.health.legacy_runtime_assert_missing_values -eq $facts.conditional_missing -and
    $report.closure.conditional_required.member_set_exported -eq $true -and
    [int]$report.closure.conditional_required.member_set_count -eq 29 -and
    $report.closure.conditional_required.member_set_sha256 -match '^[0-9a-f]{64}$' -and
    $report.closure.conditional_required.member_source_file_set_sha256 -match '^[0-9a-f]{64}$' -and
    $report.closure.conditional_required.zero_threshold_satisfied -eq $false)
Add-Assertion 'Report matches frozen closure semantics and tracked facts' (Test-Candidate $report $facts)
Add-Assertion 'A.3 auxiliary report remains blocked and is exactly SHA-256 bound by core closure' (
    (Test-AuxiliaryBinding $report $auxiliaryReportPath $auxiliaryReport) -and
    [string]$auxiliaryReport.contracts.policy_sha256 -ceq (Get-Sha256 $auxiliaryPolicyPath) -and
    [string]$auxiliaryReport.contracts.schema_sha256 -ceq (Get-Sha256 $auxiliarySchemaPath))
Add-Assertion 'Scoped terminal edges are reported but never counted as missing or guessed' (
    $facts.scoped_terminal -eq 22040 -and
    [int]$report.closure.resolution.heuristic_target_selections -eq 0)
Add-Assertion 'Ignored detail metadata stays hash-bound without requiring it in a clean checkout' (
    $report.closure.detail_export.path -eq 'Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl' -and
    $report.closure.detail_export.sha256 -match '^[0-9a-f]{64}$' -and
    [int64]$report.closure.detail_export.bytes -eq 33232029 -and
    [int]$report.closure.detail_export.lines -eq 210313 -and
    $report.closure.detail_export.tracked -eq $false)
Add-Assertion 'Tracked evidence exposes only anonymous workset counts and hashes' (
    $report.evidence_revision -eq 'P2-20A.3' -and
    [int]$report.closure.conditional_required.member_set_count -eq 29 -and
    $report.closure.conditional_required.member_set_sha256 -match '^[0-9a-f]{64}$' -and
    @($evidence.outputs.conditional_required_workset.PSObject.Properties.Name).Count -eq 3 -and
    $evidence.outputs.conditional_required_workset.tracked -eq $false -and
    [int]$evidence.outputs.conditional_required_workset.count -eq 29 -and
    [string]$evidence.outputs.conditional_required_workset.sha256 -ceq $facts.member_set_sha -and
    @($evidence.outputs.asset_binding_workset.PSObject.Properties.Name).Count -eq 3 -and
    $evidence.outputs.asset_binding_workset.tracked -eq $false -and
    [int]$evidence.outputs.asset_binding_workset.count -eq $facts.binding_assets -and
    [string]$evidence.outputs.asset_binding_workset.sha256 -ceq $facts.binding_workset_sha)

$memberOmissionRejected = $false
$memberDuplicateRejected = $false
$memberValueRejected = $false
$assetOmissionRejected = $false
$assetDuplicateRejected = $false
$assetResolutionRejected = $false
$assetHeuristicRejected = $false
if ($VerifyDerivedSources) {
    $memberRecords = [Collections.Generic.List[object]]::new()
    foreach ($line in [IO.File]::ReadLines($worksetPath)) {
        $memberRecords.Add(($line | ConvertFrom-Json -Depth 10))
    }
    $allowedRules = @($referencePolicy.table_object_references |
        Where-Object { $_.PSObject.Properties.Name -contains 'runtime_assert_when' -and
            $null -ne $_.runtime_assert_when } | ForEach-Object { [string]$_.id })
    Add-Assertion 'Conditional member workset is complete unique closed and SHA-bound' (
        (Test-MemberWorkset @($memberRecords) 29 $facts.member_set_sha $allowedRules) -and
        (Get-Sha256 $worksetPath) -ceq $facts.member_set_sha)
    $omitted = @($memberRecords | Select-Object -SkipLast 1)
    $duplicated = @($memberRecords | ForEach-Object { Copy-Document $_ })
    $duplicated[-1] = Copy-Document $duplicated[0]
    $fabricated = @($memberRecords | ForEach-Object { Copy-Document $_ })
    $fabricated[0] | Add-Member -NotePropertyName value -NotePropertyValue 'forbidden'
    $memberOmissionRejected = -not (Test-MemberWorkset $omitted 29 $facts.member_set_sha $allowedRules)
    $memberDuplicateRejected = -not (Test-MemberWorkset $duplicated 29 $facts.member_set_sha $allowedRules)
    $memberValueRejected = -not (Test-MemberWorkset $fabricated 29 $facts.member_set_sha $allowedRules)
    Add-Assertion 'Negative case rejects an omitted conditional member' $memberOmissionRejected
    Add-Assertion 'Negative case rejects a duplicated conditional member' $memberDuplicateRejected
    Add-Assertion 'Negative case rejects a fabricated member value field' $memberValueRejected
    $assetRecords = [Collections.Generic.List[object]]::new()
    foreach ($line in [IO.File]::ReadLines($assetWorksetPath)) {
        $assetRecords.Add(($line | ConvertFrom-Json -Depth 10))
    }
    Add-Assertion 'Asset binding workset is complete unique closed nonheuristic and SHA-bound' (
        (Test-AssetWorkset @($assetRecords) $facts) -and
        (Get-Sha256 $assetWorksetPath) -ceq $facts.binding_workset_sha)
    $assetOmitted = @($assetRecords | Select-Object -SkipLast 1)
    $assetDuplicated = @($assetRecords)
    $assetDuplicated[-1] = $assetDuplicated[0]
    $assetResolution = @($assetRecords)
    $assetResolution[0] = Copy-Document $assetResolution[0]
    $assetResolution[0].resolution = 'RESOLVED'
    $assetResolution[0].resolution_basis = 'DESCRIPTOR_VALIDATION_FAILED'
    $assetHeuristic = @($assetRecords)
    $assetHeuristic[0] = Copy-Document $assetHeuristic[0]
    $assetHeuristic[0].heuristic_selection = $true
    $assetOmissionRejected = -not (Test-AssetWorkset $assetOmitted $facts)
    $assetDuplicateRejected = -not (Test-AssetWorkset $assetDuplicated $facts)
    $assetResolutionRejected = -not (Test-AssetWorkset $assetResolution $facts)
    $assetHeuristicRejected = -not (Test-AssetWorkset $assetHeuristic $facts)
    Add-Assertion 'Negative case rejects an omitted asset binding member' $assetOmissionRejected
    Add-Assertion 'Negative case rejects a duplicated asset binding member' $assetDuplicateRejected
    Add-Assertion 'Negative case rejects a contradictory asset binding state' $assetResolutionRejected
    Add-Assertion 'Negative case rejects heuristic asset candidate selection' $assetHeuristicRejected
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
$negativeMemberCount = Copy-Document $report
$negativeMemberCount.closure.conditional_required.member_set_count = 28
$negativeMemberSha = Copy-Document $report
$negativeMemberSha.closure.conditional_required.member_set_sha256 = '0' * 64
$negativeBindingImplicit = Copy-Document $report
$negativeBindingImplicit.closure.asset_binding_resolution_explicit = $false
$negativeBindingImplicit.closure.asset_binding.resolution_explicit = $false
$negativeBindingZero = Copy-Document $report
$negativeBindingZero.closure.asset_binding.resolved_targets = 21494
$negativeBindingZero.closure.asset_binding.ambiguous_targets = 0
$negativeBindingZero.closure.asset_binding.unresolved_targets = 0
$negativeBindingFirst = Copy-Document $report
$negativeBindingFirst.closure.asset_binding.first_candidate_selection_used = $true
$negativeBindingCount = Copy-Document $report
$negativeBindingCount.closure.asset_binding.workset_count = 21493
$negativeBindingSha = Copy-Document $report
$negativeBindingSha.closure.asset_binding.workset_sha256 = '0' * 64
$negativeAuxScope = Copy-Document $report
$negativeAuxScope.scope_definition.auxiliary_config.scope_complete = $true
$negativeAuxRoots = Copy-Document $report
$negativeAuxRoots.scope_definition.auxiliary_config.approved_roots = 1
$negativeAuxFiles = Copy-Document $report
$negativeAuxFiles.scope_definition.auxiliary_config.inventory_files = 211
$negativeAuxBindingSha = Copy-Document $report
@($negativeAuxBindingSha.input_bindings.artifacts |
    Where-Object id -eq 'P2-20A.3-AUX')[0].sha256 = '0' * 64
$negativeAuxAggregate = Copy-Document $report
$negativeAuxAggregate.input_bindings.aggregate_sha256 = '0' * 64
$negativeAuxMissing = Copy-Document $report
$negativeAuxMissing.input_bindings.artifacts = @(
    $negativeAuxMissing.input_bindings.artifacts | Where-Object id -ne 'P2-20A.3-AUX')
$negativeAuxDuplicate = Copy-Document $report
$negativeAuxDuplicate.input_bindings.artifacts[-1] = Copy-Document `
    @($negativeAuxDuplicate.input_bindings.artifacts |
        Where-Object id -eq 'P2-20A.3-AUX')[0]
$negativeAuxPass = Copy-Document $auxiliaryReport
$negativeAuxPass.result = 'PASS'
$negativeAuxComplete = Copy-Document $auxiliaryReport
$negativeAuxComplete.task_status = 'COMPLETE'
$negativeAuxComplete.completion_criteria_satisfied = $true
$negativeAuxDisclosure = Copy-Document $auxiliaryReport
$negativeAuxDisclosure.disclosure.private_source_paths = $true
Add-Assertion 'Negative case rejects outcome-based root narrowing' (-not (Test-Candidate $negativeScope $facts))
Add-Assertion 'Negative case rejects owner or rule narrowing' (-not (Test-Candidate $negativeRules $facts))
Add-Assertion 'Negative case rejects first-candidate or heuristic selection' (-not (Test-Candidate $negativeFirst $facts))
Add-Assertion 'Negative case rejects core-FK-zero substitution' (-not (Test-Candidate $negativeFk $facts))
Add-Assertion 'Negative case rejects summary-only tampering against detailed sets' (-not (Test-Candidate $negativeSummary $facts))
Add-Assertion 'Negative case rejects scope complete while config and binding coverage are false' (-not (Test-Candidate $negativeComplete $facts))
Add-Assertion 'Negative case rejects changing conditional-required missing from twenty-nine to zero' (-not (Test-Candidate $negativeConditionalZero $facts))
Add-Assertion 'Negative case rejects deleting the conditional-required metric' (-not (Test-Candidate $negativeConditionalDeleted $facts))
Add-Assertion 'Negative case rejects conditional member count tampering' (-not (Test-Candidate $negativeMemberCount $facts))
Add-Assertion 'Negative case rejects conditional member SHA tampering' (-not (Test-Candidate $negativeMemberSha $facts))
Add-Assertion 'Negative case rejects reverting asset binding to implicit state' (-not (Test-Candidate $negativeBindingImplicit $facts))
Add-Assertion 'Negative case rejects explicit binding falsely reported as fully resolved' (-not (Test-Candidate $negativeBindingZero $facts))
Add-Assertion 'Negative case rejects first-candidate asset binding selection' (-not (Test-Candidate $negativeBindingFirst $facts))
Add-Assertion 'Negative case rejects asset binding workset count tampering' (-not (Test-Candidate $negativeBindingCount $facts))
Add-Assertion 'Negative case rejects asset binding workset SHA tampering' (-not (Test-Candidate $negativeBindingSha $facts))
Add-Assertion 'Negative case rejects falsely completed auxiliary scope' (-not (Test-Candidate $negativeAuxScope $facts))
Add-Assertion 'Negative case rejects a fabricated approved auxiliary root' (-not (Test-Candidate $negativeAuxRoots $facts))
Add-Assertion 'Negative case rejects auxiliary file-instance count tampering' (-not (Test-Candidate $negativeAuxFiles $facts))
Add-Assertion 'Negative case rejects auxiliary BLOCKED evidence promoted to PASS' (-not (Test-AuxiliaryDocument $negativeAuxPass))
Add-Assertion 'Negative case rejects auxiliary evidence promoted to COMPLETE' (-not (Test-AuxiliaryDocument $negativeAuxComplete))
Add-Assertion 'Negative case rejects weakened auxiliary disclosure' (-not (Test-AuxiliaryDocument $negativeAuxDisclosure))

$ignoredBindings = @{
    'asset-catalog' = $p212.catalog
    'reference-graph' = $p213.graph
    'P2-20A.4-DETAIL' = $assetDescriptorReport.detail_export
}
$bindingsPass = Test-CoreInputBindings $report $policy $ignoredBindings
Add-Assertion 'All twenty-two ordered prerequisite and supplemental inputs are uniquely exact-hash bound' $bindingsPass
Add-Assertion 'Negative case rejects auxiliary binding SHA tampering' (-not (
        Test-CoreInputBindings $negativeAuxBindingSha $policy $ignoredBindings))
Add-Assertion 'Negative case rejects input aggregate SHA tampering' (-not (
        Test-CoreInputBindings $negativeAuxAggregate $policy $ignoredBindings))
Add-Assertion 'Negative case rejects a missing auxiliary binding' (-not (
        Test-CoreInputBindings $negativeAuxMissing $policy $ignoredBindings))
Add-Assertion 'Negative case rejects a duplicated auxiliary binding' (-not (
        Test-CoreInputBindings $negativeAuxDuplicate $policy $ignoredBindings))
Add-Assertion 'Governance remains blocked and binds the machine report' (
    $governance.status -eq 'BLOCKED' -and $governance.scope_complete -eq $false -and
    $governance.auxiliary_reference_evidence_hash_bound -eq $true -and
    [int]$governance.auxiliary_file_instances -eq 212 -and
    [int]$governance.auxiliary_candidate_only -eq 171 -and
    [int]$governance.auxiliary_editor_undecided -eq 35 -and
    [int]$governance.auxiliary_malformed_blocked -eq 6 -and
    [int]$governance.auxiliary_approved_roots -eq 0 -and
    $governance.asset_binding_resolution_explicit -eq $true -and
    [int]$governance.asset_binding_resolved_targets -eq $facts.binding_resolved -and
    [int]$governance.asset_binding_ambiguous_targets -eq $facts.binding_ambiguous -and
    [int]$governance.asset_binding_unresolved_targets -eq $facts.binding_unresolved -and
    [int]$governance.asset_binding_unknown_targets -eq 0 -and
    [string]$governance.asset_binding_workset_sha256 -ceq $facts.binding_workset_sha -and
    [int]$governance.conditional_required_missing -eq $facts.conditional_missing -and
    $governance.conditional_required_member_set_exported -eq $true -and
    [int]$governance.conditional_required_member_set_count -eq 29 -and
    [string]$governance.conditional_required_member_set_sha256 -ceq $facts.member_set_sha -and
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
    [int]$evidence.outputs.conditional_required_workset.count -eq 29 -and
    [string]$evidence.outputs.conditional_required_workset.sha256 -ceq $facts.member_set_sha -and
    [int]$evidence.outputs.asset_binding_workset.count -eq $facts.binding_assets -and
    [string]$evidence.outputs.asset_binding_workset.sha256 -ceq $facts.binding_workset_sha -and
    (-not $VerifyDerivedSources -or
        ($evidence.outputs.detail_export.sha256 -eq (Get-Sha256 $detailPath) -and
         $evidence.outputs.conditional_required_workset.sha256 -eq (Get-Sha256 $worksetPath) -and
         $evidence.outputs.asset_binding_workset.sha256 -eq (Get-Sha256 $assetWorksetPath))))
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
        conditional_member_omission_rejected = $memberOmissionRejected
        conditional_member_duplicate_rejected = $memberDuplicateRejected
        conditional_member_count_tamper_rejected = -not (Test-Candidate $negativeMemberCount $facts)
        conditional_member_sha_tamper_rejected = -not (Test-Candidate $negativeMemberSha $facts)
        conditional_member_value_rejected = $memberValueRejected
        asset_member_omission_rejected = $assetOmissionRejected
        asset_member_duplicate_rejected = $assetDuplicateRejected
        asset_member_resolution_rejected = $assetResolutionRejected
        asset_member_heuristic_rejected = $assetHeuristicRejected
        asset_binding_implicit_rejected = -not (Test-Candidate $negativeBindingImplicit $facts)
        asset_binding_false_zero_rejected = -not (Test-Candidate $negativeBindingZero $facts)
        asset_binding_first_candidate_rejected = -not (Test-Candidate $negativeBindingFirst $facts)
        asset_binding_count_tamper_rejected = -not (Test-Candidate $negativeBindingCount $facts)
        asset_binding_sha_tamper_rejected = -not (Test-Candidate $negativeBindingSha $facts)
        auxiliary_false_scope_rejected = -not (Test-Candidate $negativeAuxScope $facts)
        auxiliary_fabricated_root_rejected = -not (Test-Candidate $negativeAuxRoots $facts)
        auxiliary_file_count_tamper_rejected = -not (Test-Candidate $negativeAuxFiles $facts)
        auxiliary_binding_sha_tamper_rejected = -not (
            Test-CoreInputBindings $negativeAuxBindingSha $policy $ignoredBindings)
        auxiliary_aggregate_sha_tamper_rejected = -not (
            Test-CoreInputBindings $negativeAuxAggregate $policy $ignoredBindings)
        auxiliary_missing_binding_rejected = -not (
            Test-CoreInputBindings $negativeAuxMissing $policy $ignoredBindings)
        auxiliary_duplicate_binding_rejected = -not (
            Test-CoreInputBindings $negativeAuxDuplicate $policy $ignoredBindings)
        auxiliary_false_pass_rejected = -not (Test-AuxiliaryDocument $negativeAuxPass)
        auxiliary_false_complete_rejected = -not (Test-AuxiliaryDocument $negativeAuxComplete)
        auxiliary_disclosure_weakening_rejected = -not (
            Test-AuxiliaryDocument $negativeAuxDisclosure)
    }
    closure = [pscustomobject][ordered]@{
        start_nodes = $facts.start_nodes
        reachable_nodes = $facts.reachable_nodes
        logical_gaps = $facts.logical_gaps
        asset_structure_unresolved = $facts.asset_unresolved
        conditional_required_missing = $facts.conditional_missing
        asset_binding_resolved = $facts.binding_resolved
        asset_binding_ambiguous = $facts.binding_ambiguous
        asset_binding_unresolved = $facts.binding_unresolved
        scope_complete = $false
    }
    derived_check = $derivedCheck
    assertions = @($assertions)
}
$output | ConvertTo-Json -Depth 100
if ($result -ne 'PASS') { throw "P2-20A contract failed with $($failures.Count) assertion(s)." }
