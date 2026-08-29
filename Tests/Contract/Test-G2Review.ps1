[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\g2-review-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\g2-review-v1.schema.json'
$reportPath = Join-Path $root 'Data\Reports\p2-20-g2-review-report.json'
$markdownPath = Join-Path $root 'Data\Reports\p2-20-g2-review-report.md'
$evidencePath = Join-Path $root 'Data\Inventory\p2-20-g2-review.json'
$qualityPath = Join-Path $root 'Data\BuildBaseline\p0-12-local-quality-gates.json'
$supplementalPath = Join-Path $root 'Data\Reports\p2-20a-core-resource-closure-report.json'
$descriptorDiagnosticPath = Join-Path $root 'Data\Reports\p2-20a-asset-descriptor-diagnostics-report.json'
$auxiliaryReportPath = Join-Path $root 'Data\Reports\p2-20a-aux-config-reference-report.json'
$remediationPath = Join-Path $root 'Data\Governance\p2-g2-migration-decisions.json'
$reviewPacketsPath = Join-Path $root 'Data\Governance\p2-g2-migration-review-packets.json'
$authorityLedgerPath = Join-Path $root 'Data\Governance\p2-g2-migration-decision-authority-v2.json'
$migrationPolicyPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-policy-v2.json'
$migrationSchemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-registry-v2.schema.json'
$authoritySchemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-authority-v2.schema.json'
$reviewPacketSchemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-review-packets-v2.schema.json'
$generatorPath = Join-Path $root 'Tools\TMXY.G2Review\g2_review.py'
$helperPath = Join-Path $root 'Tools\TMXY.G2Review\g2_evidence.py'
$wrapperPath = Join-Path $root 'Tools\TMXY.G2Review\New-G2Review.ps1'
$assertions = [Collections.Generic.List[object]]::new()

function Add-A([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
            detail = $Detail
        })
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length + 1)).Replace('\', '/')
}

function Copy-JsonObject([object]$Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-AgainstSchema([object]$Value) {
    return [bool](Test-Json -Json ($Value | ConvertTo-Json -Depth 100 -Compress) `
            -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
}

function Test-JsonEqual([object]$Left, [object]$Right) {
    return ($Left | ConvertTo-Json -Depth 100 -Compress) -ceq
        ($Right | ConvertTo-Json -Depth 100 -Compress)
}

function Test-AuxiliaryCoreBinding([object]$Core, [object]$Auxiliary) {
    $bindings = @($Core.input_bindings.artifacts | Where-Object id -eq 'P2-20A.3-AUX')
    if ($bindings.Count -ne 1 -or
        [string]$bindings[0].path -cne
            'Data/Reports/p2-20a-aux-config-reference-report.json' -or
        [string]$bindings[0].sha256 -cne (Get-Sha256 $auxiliaryReportPath) -or
        [int64]$bindings[0].bytes -ne (Get-Item $auxiliaryReportPath).Length -or
        $Auxiliary.evidence_revision -ne 'P2-20A.3' -or
        $Auxiliary.result -ne 'BLOCKED' -or $Auxiliary.review_execution_result -ne 'PASS' -or
        $Auxiliary.task_status -ne 'BLOCKED' -or
        $Auxiliary.completion_criteria_satisfied -ne $false -or
        $Auxiliary.scope_complete -ne $false -or $Auxiliary.g2_06_satisfied -ne $false -or
        $Auxiliary.p3_authorized -ne $false -or @($Auxiliary.file_instances).Count -ne 212) {
        return $false
    }
    $scope = $Core.scope_definition.auxiliary_config
    $measured = $Auxiliary.measured_lexical_candidates
    $states = $Auxiliary.adapter_state_summary
    return $scope.evidence_hash_bound -eq $true -and
        [int]$scope.inventory_files -eq [int]$measured.file_instances -and
        [int]$scope.unique_content_bodies -eq [int]$measured.unique_content_bodies -and
        [int]$scope.parsed_file_instances -eq [int]$measured.parsed_file_instances -and
        [int]$scope.malformed_isolated -eq [int]$measured.malformed_file_instances -and
        [int]$scope.asset_exact_occurrences -eq [int]$measured.asset_exact_occurrences -and
        [int]$scope.package_exact_occurrences -eq [int]$measured.package_exact_occurrences -and
        [int]$scope.config_exact_edges -eq [int]$measured.config_exact_edges -and
        [int]$scope.terminal_file_instances -eq [int]$states.terminal_file_instances -and
        [int]$scope.candidate_only -eq [int]$states.candidate_only -and
        [int]$scope.editor_undecided -eq [int]$states.editor_undecided -and
        [int]$scope.malformed_blocked -eq [int]$states.malformed_blocked -and
        [int]$scope.semantic_approved -eq 0 -and [int]$scope.no_ref_approved -eq 0 -and
        [int]$scope.approved_roots -eq 0 -and $scope.scope_complete -eq $false -and
        $Auxiliary.semantic_resolution.status -eq 'UNASSESSED' -and
        $Auxiliary.config_closure.closure_complete -eq $false -and
        $Auxiliary.config_closure.cycle_detection_complete -eq $false
}

function Get-Criterion([object]$Candidate, [string]$Id) {
    $matches = @($Candidate.criteria | Where-Object { [string]$_.id -eq $Id })
    if ($matches.Count -ne 1) { return $null }
    return $matches[0]
}

function Get-Metric([object]$Criterion, [string]$Name) {
    $matches = @($Criterion.metrics | Where-Object { [string]$_.name -eq $Name })
    if ($matches.Count -ne 1) { return $null }
    return $matches[0].value
}

function Set-Metric([object]$Criterion, [string]$Name, [object]$Value) {
    $matches = @($Criterion.metrics | Where-Object { [string]$_.name -eq $Name })
    if ($matches.Count -ne 1) { throw "Metric is not unique: $Name" }
    $matches[0].value = $Value
}

function Set-CriterionSatisfied([object]$Candidate, [string]$Id) {
    $item = Get-Criterion $Candidate $Id
    $item.satisfied = $true
    $item.observed_status = 'SATISFIED'
    $item.blocker_ids = @()
    $Candidate.blockers = @($Candidate.blockers | Where-Object criterion_id -ne $Id)
    $satisfied = @($Candidate.criteria | Where-Object satisfied | ForEach-Object id)
    $blocked = @($Candidate.criteria | Where-Object { -not $_.satisfied } | ForEach-Object id)
    $Candidate.summary.satisfied = $satisfied.Count
    $Candidate.summary.blocked = $blocked.Count
    $Candidate.summary.satisfied_ids = $satisfied
    $Candidate.summary.blocked_ids = $blocked
    if ($blocked.Count -eq 0) {
        $Candidate.result = 'PASS'
        $Candidate.task_status = 'COMPLETE'
        $Candidate.completion_criteria_satisfied = $true
        $Candidate.gate_decision = 'APPROVED'
        $Candidate.g2_approved = $true
        $Candidate.p3_authorized = $true
    }
}

function Test-PolicySemantics([object]$Candidate) {
    $expectedIds = @(1..9 | ForEach-Object { 'G2-{0:D2}' -f $_ })
    $actualIds = @($Candidate.criteria.id)
    return $Candidate.schema_version -eq 1 -and $Candidate.task_id -eq 'P2-20' -and
        $Candidate.gate -eq 'G2' -and $Candidate.source_build -eq 'qy-3.0.0.413' -and
        @($Candidate.required_inputs).Count -eq 19 -and
        $Candidate.supplemental.task_id -eq 'P2-20A' -and
        $Candidate.supplemental.criterion_id -eq 'G2-06' -and
        $Candidate.supplemental.path -eq 'Data/Reports/p2-20a-core-resource-closure-report.json' -and
        $Candidate.descriptor_diagnostics.task_id -eq 'P2-20A' -and
        $Candidate.descriptor_diagnostics.criterion_id -eq 'G2-06' -and
        $Candidate.descriptor_diagnostics.evidence_revision -eq 'P2-20A.4' -and
        $Candidate.descriptor_diagnostics.path -eq
            'Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json' -and
        $Candidate.remediation.task_id -eq 'P2-20B' -and
        $Candidate.remediation.criterion_id -eq 'G2-07' -and
        $Candidate.remediation.path -eq 'Data/Governance/p2-g2-migration-decisions.json' -and
        @($Candidate.criteria).Count -eq 9 -and
        @(Compare-Object $actualIds $expectedIds).Count -eq 0 -and
        @($Candidate.criteria | Where-Object required_status -ne 'SATISFIED').Count -eq 0 -and
        $Candidate.thresholds.required_criteria -eq 9 -and
        $Candidate.fail_closed_rules.core_foreign_key_zero_does_not_prove_core_resource_reference_zero -and
        $Candidate.fail_closed_rules.first_candidate_or_heuristic_selection_never_proves_resource_closure -and
        $Candidate.fail_closed_rules.explicit_asset_binding_state_does_not_substitute_for_zero_ambiguity_and_unresolved -and
        $Candidate.thresholds.core_asset_binding_resolution_explicit -eq $true -and
        $Candidate.thresholds.core_asset_binding_ambiguous -eq 0 -and
        $Candidate.thresholds.core_asset_binding_unresolved -eq 0 -and
        $Candidate.thresholds.core_asset_binding_unknown -eq 0 -and
        $Candidate.fail_closed_rules.audit_codegen_or_uint64_policy_is_not_a_complete_migration_decision_registry -and
        $Candidate.fail_closed_rules.machine_suggestions_never_count_as_migration_decisions_or_approvals -and
        $Candidate.fail_closed_rules.one_blocked_criterion_blocks_g2 -and
        $Candidate.fail_closed_rules.blocked_g2_never_authorizes_p3_or_release
}

function Test-G2Semantics([object]$Candidate, [object]$Policy) {
    if ($Candidate.result -ne 'BLOCKED' -or $Candidate.review_execution_result -ne 'PASS' -or
        $Candidate.task_status -ne 'BLOCKED' -or $Candidate.completion_criteria_satisfied -or
        $Candidate.gate -ne 'G2' -or $Candidate.gate_decision -ne 'BLOCKED' -or
        $Candidate.g2_approved -or $Candidate.p3_authorized) { return $false }
    $derivedSatisfied = @($Candidate.criteria | Where-Object satisfied | ForEach-Object id)
    $derivedBlocked = @($Candidate.criteria | Where-Object { -not $_.satisfied } | ForEach-Object id)
    if ($Candidate.summary.criteria_total -ne @($Candidate.criteria).Count -or
        $Candidate.summary.satisfied -ne $derivedSatisfied.Count -or
        $Candidate.summary.blocked -ne $derivedBlocked.Count -or
        @(Compare-Object @($Candidate.summary.satisfied_ids) $derivedSatisfied).Count -ne 0 -or
        @(Compare-Object @($Candidate.summary.blocked_ids) $derivedBlocked).Count -ne 0 -or
        $Candidate.summary.satisfied -ne 7 -or $Candidate.summary.blocked -ne 2 -or
        @(Compare-Object $derivedBlocked @('G2-06', 'G2-07')).Count -ne 0) {
        return $false
    }
    if (@($Candidate.criteria).Count -ne 9) { return $false }
    foreach ($policyItem in @($Policy.criteria)) {
        $item = Get-Criterion $Candidate ([string]$policyItem.id)
        if ($null -eq $item -or $policyItem.required_status -ne 'SATISFIED' -or
            $item.required_status -ne 'SATISFIED' -or
            $item.statement -ne $policyItem.statement -or
            @(Compare-Object @($item.evidence_task_ids) @($policyItem.evidence_task_ids)).Count -ne 0) {
            return $false
        }
        $shouldBlock = $item.id -in @('G2-06', 'G2-07')
        if ($shouldBlock -ne (-not [bool]$item.satisfied) -or
            $item.observed_status -ne $(if ($shouldBlock) { 'BLOCKED' } else { 'SATISFIED' })) {
            return $false
        }
    }
    $g206 = Get-Criterion $Candidate 'G2-06'
    if ((Get-Metric $g206 'supplemental_report_present') -ne $true -or
        (Get-Metric $g206 'declared_scope_hash_bound') -ne $true -or
        (Get-Metric $g206 'scope_complete') -ne $false -or
        (Get-Metric $g206 'auxiliary_config_scope_complete') -ne $false -or
        (Get-Metric $g206 'auxiliary_reference_evidence_hash_bound') -ne $true -or
        (Get-Metric $g206 'auxiliary_file_instances') -ne 212 -or
        (Get-Metric $g206 'auxiliary_terminal_file_instances') -ne 0 -or
        (Get-Metric $g206 'auxiliary_nonterminal_file_instances') -ne 212 -or
        (Get-Metric $g206 'auxiliary_candidate_only') -ne 171 -or
        (Get-Metric $g206 'auxiliary_editor_undecided') -ne 35 -or
        (Get-Metric $g206 'auxiliary_malformed_blocked') -ne 6 -or
        (Get-Metric $g206 'auxiliary_semantic_approved') -ne 0 -or
        (Get-Metric $g206 'auxiliary_no_ref_approved') -ne 0 -or
        (Get-Metric $g206 'auxiliary_approved_roots') -ne 0 -or
        (Get-Metric $g206 'auxiliary_asset_exact_occurrences') -ne 3043 -or
        (Get-Metric $g206 'auxiliary_package_exact_occurrences') -ne 638 -or
        (Get-Metric $g206 'auxiliary_package_unique_occurrences') -ne 218 -or
        (Get-Metric $g206 'auxiliary_package_ambiguous_occurrences') -ne 420 -or
        (Get-Metric $g206 'auxiliary_package_ambiguous_candidate_edges') -ne 1136 -or
        (Get-Metric $g206 'auxiliary_config_exact_edges') -ne 8 -or
        (Get-Metric $g206 'auxiliary_semantic_status') -ne 'UNASSESSED' -or
        (Get-Metric $g206 'auxiliary_config_closure_complete') -ne $false -or
        (Get-Metric $g206 'auxiliary_cycle_detection_complete') -ne $false -or
        (Get-Metric $g206 'descriptor_diagnostic_hash_bound') -ne $true -or
        (Get-Metric $g206 'descriptor_diagnostic_targets') -ne 3651 -or
        (Get-Metric $g206 'descriptor_diagnostic_candidate_edges') -ne 12764 -or
        (Get-Metric $g206 'descriptor_diagnostic_resolved_targets') -ne 3617 -or
        (Get-Metric $g206 'descriptor_diagnostic_ambiguous_targets') -ne 15 -or
        (Get-Metric $g206 'descriptor_diagnostic_unresolved_targets') -ne 19 -or
        (Get-Metric $g206 'asset_binding_resolution_explicit') -ne $true -or
        (Get-Metric $g206 'asset_binding_resolved_targets') -ne 21460 -or
        (Get-Metric $g206 'asset_binding_ambiguous_targets') -ne 15 -or
        (Get-Metric $g206 'asset_binding_unresolved_targets') -ne 19 -or
        (Get-Metric $g206 'asset_binding_unknown_targets') -ne 0 -or
        (Get-Metric $g206 'asset_binding_workset_hash_bound') -ne $true -or
        (Get-Metric $g206 'table_resource_unresolved') -ne 5161 -or
        (Get-Metric $g206 'table_resource_ambiguous') -ne 6945 -or
        (Get-Metric $g206 'package_resource_unresolved') -ne 407 -or
        (Get-Metric $g206 'package_resource_ambiguous') -ne 8511 -or
        (Get-Metric $g206 'conditional_required_missing') -ne 29 -or
        (Get-Metric $g206 'conditional_member_set_exported') -ne $true -or
        (Get-Metric $g206 'conditional_member_set_count') -ne 29 -or
        (Get-Metric $g206 'conditional_member_set_hash_bound') -ne $true -or
        (Get-Metric $g206 'conditional_source_hash_bound') -ne $true -or
        (Get-Metric $g206 'heuristic_target_selections') -ne 0 -or
        (Get-Metric $g206 'first_candidate_selection_used') -ne $false -or
        (Get-Metric $g206 'asset_structure_unresolved') -ne 18 -or
        (Get-Metric $g206 'asset_structure_fail') -ne 0 -or
        (Get-Metric $g206 'unknown_record_count') -ne 0 -or
        (Get-Metric $g206 'unknown_resolution_count') -ne 0 -or
        (Get-Metric $g206 'integrity_mismatches') -ne 0 -or
        (Get-Metric $g206 'logical_gap_count') -ne 21024 -or
        (Get-Metric $g206 'logical_gap_set_hash_bound') -ne $true -or
        (Get-Metric $g206 'core_foreign_key_dangling_context') -ne 0 -or
        @($g206.blocker_ids).Count -ne 1 -or $g206.blocker_ids[0] -ne 'G2-BLK-06') {
        return $false
    }
    $g207 = Get-Criterion $Candidate 'G2-07'
    if ((Get-Metric $g207 'migration_decision_registry_present') -ne $true -or
        (Get-Metric $g207 'migration_workflow_version') -ne 2 -or
        (Get-Metric $g207 'migration_workflow_ready') -ne $true -or
        (Get-Metric $g207 'review_packet_count') -ne 39 -or
        (Get-Metric $g207 'review_packet_members') -ne 1359 -or
        (Get-Metric $g207 'authority_ledger_records') -ne 0 -or
        (Get-Metric $g207 'coverage_complete') -ne $true -or
        (Get-Metric $g207 'expected_units') -ne 1359 -or
        (Get-Metric $g207 'enumerated_units') -ne 1359 -or
        (Get-Metric $g207 'missing_units') -ne 0 -or
        (Get-Metric $g207 'duplicate_units') -ne 0 -or
        (Get-Metric $g207 'orphan_units') -ne 0 -or
        (Get-Metric $g207 'pending_decisions') -ne 1359 -or
        (Get-Metric $g207 'decided_units') -ne 0 -or
        (Get-Metric $g207 'approved_units') -ne 0 -or
        (Get-Metric $g207 'verified_units') -ne 0 -or
        (Get-Metric $g207 'approval_count') -ne 0 -or
        (Get-Metric $g207 'machine_suggestions') -ne 1359 -or
        (Get-Metric $g207 'machine_suggestions_count_as_decisions') -ne $false -or
        (Get-Metric $g207 'pending_entries_have_no_chosen_decision') -ne $true -or
        (Get-Metric $g207 'g2_07_registry_satisfied') -ne $false -or
        @($g207.blocker_ids).Count -ne 1 -or $g207.blocker_ids[0] -ne 'G2-BLK-07') {
        return $false
    }
    if (@($Candidate.blockers).Count -ne 2 -or
        @(Compare-Object @($Candidate.blockers.id) @('G2-BLK-06', 'G2-BLK-07')).Count -ne 0 -or
        @(Compare-Object @($Candidate.blockers.criterion_id) @('G2-06', 'G2-07')).Count -ne 0) {
        return $false
    }
    return $true
}

$required = @($policyPath, $schemaPath, $reportPath, $markdownPath, $evidencePath,
    $qualityPath, $supplementalPath, $descriptorDiagnosticPath, $auxiliaryReportPath,
    $remediationPath, $reviewPacketsPath,
    $authorityLedgerPath, $migrationPolicyPath, $migrationSchemaPath,
    $authoritySchemaPath, $reviewPacketSchemaPath, $generatorPath, $helperPath, $wrapperPath)
foreach ($path in $required) {
    Add-A "Required file $(Get-Relative $path)" (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject][ordered]@{
        schema_version = 1; task_id = 'P2-20'; result = 'FAIL'
        completion_criteria_satisfied = $false; assertions = $assertions
    } | ConvertTo-Json -Depth 100
    exit 1
}

$policyText = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8
$schemaText = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
$reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
$policy = $policyText | ConvertFrom-Json -Depth 100 -DateKind String
$schema = $schemaText | ConvertFrom-Json -Depth 100 -DateKind String
$report = $reportText | ConvertFrom-Json -Depth 100 -DateKind String
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$quality = Get-Content -LiteralPath $qualityPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$supplemental = Get-Content -LiteralPath $supplementalPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$descriptorDiagnostic = Get-Content -LiteralPath $descriptorDiagnosticPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$auxiliaryReport = Get-Content -LiteralPath $auxiliaryReportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$remediation = Get-Content -LiteralPath $remediationPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$reviewPackets = Get-Content -LiteralPath $reviewPacketsPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$authorityLedger = Get-Content -LiteralPath $authorityLedgerPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String

function Test-EvidenceSemantics([object]$Candidate) {
    $expectedTop = @('schema_version', 'captured_utc', 'task_id', 'result',
        'review_execution_result', 'task_status', 'completion_criteria_satisfied', 'gate',
        'gate_decision', 'g2_approved', 'p3_authorized', 'input', 'report', 'summary',
        'blockers', 'budget_interpretation', 'authority_boundaries', 'security', 'contracts',
        'implementation', 'disclosure', 'reproduction', 'next_scope')
    $actualTop = @($Candidate.PSObject.Properties.Name)
    if ($actualTop.Count -ne 23 -or @(Compare-Object $actualTop $expectedTop).Count -ne 0 -or
        $Candidate.schema_version -ne 1 -or $Candidate.task_id -ne 'P2-20' -or
        $Candidate.result -ne 'BLOCKED' -or $Candidate.review_execution_result -ne 'PASS' -or
        $Candidate.task_status -ne 'BLOCKED' -or $Candidate.completion_criteria_satisfied -or
        $Candidate.gate -ne 'G2' -or $Candidate.gate_decision -ne 'BLOCKED' -or
        $Candidate.g2_approved -or $Candidate.p3_authorized) { return $false }
    try { [void][DateTimeOffset]::Parse([string]$Candidate.captured_utc) }
    catch { return $false }
    if ($Candidate.input.source_build -ne $report.source_build -or
        -not (Test-JsonEqual $Candidate.input.bindings $report.input_bindings) -or
        $Candidate.report.json.path -ne 'Data/Reports/p2-20-g2-review-report.json' -or
        $Candidate.report.markdown.path -ne 'Data/Reports/p2-20-g2-review-report.md' -or
        -not $Candidate.report.json.tracked -or -not $Candidate.report.markdown.tracked -or
        $Candidate.report.json.sha256 -ne (Get-Sha256 $reportPath) -or
        $Candidate.report.markdown.sha256 -ne (Get-Sha256 $markdownPath) -or
        $Candidate.report.json.bytes -ne (Get-Item -LiteralPath $reportPath).Length -or
        $Candidate.report.markdown.bytes -ne (Get-Item -LiteralPath $markdownPath).Length -or
        $Candidate.report.json.lines -ne (Get-LineCount $reportPath) -or
        $Candidate.report.markdown.lines -ne (Get-LineCount $markdownPath)) { return $false }
    if (-not (Test-JsonEqual $Candidate.summary $report.summary) -or
        -not (Test-JsonEqual $Candidate.blockers $report.blockers) -or
        -not (Test-JsonEqual $Candidate.budget_interpretation $report.budget_interpretation) -or
        -not (Test-JsonEqual $Candidate.authority_boundaries $report.authority_boundaries) -or
        -not (Test-JsonEqual $Candidate.security $report.security) -or
        -not (Test-JsonEqual $Candidate.disclosure $report.disclosure)) { return $false }
    $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'Tools\TMXY.G2Review') -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    if ($Candidate.contracts.policy -ne 'Contracts/data-schema/g2-review-policy-v1.json' -or
        $Candidate.contracts.schema -ne 'Contracts/data-schema/g2-review-v1.schema.json' -or
        $Candidate.contracts.policy_sha256 -ne (Get-Sha256 $policyPath) -or
        $Candidate.contracts.schema_sha256 -ne (Get-Sha256 $schemaPath) -or
        $Candidate.implementation.generator -ne 'Tools/TMXY.G2Review/g2_review.py' -or
        $Candidate.implementation.wrapper -ne 'Tools/TMXY.G2Review/New-G2Review.ps1' -or
        $Candidate.implementation.generator_sha256 -ne (Get-Sha256 $generatorPath) -or
        $Candidate.implementation.wrapper_sha256 -ne (Get-Sha256 $wrapperPath) -or
        $Candidate.implementation.source_files -ne $sourceFiles.Count -or
        $Candidate.implementation.source_sha256 -ne $sourceSha -or
        $Candidate.implementation.self_test_assertions -lt 10) { return $false }
    if ($Candidate.disclosure.private_source_paths -or $Candidate.disclosure.exact_primary_keys -or
        $Candidate.disclosure.exact_observed_extrema -or $Candidate.disclosure.raw_table_rows -or
        $Candidate.disclosure.decoded_confidential_payloads -or
        $Candidate.disclosure.legacy_source_lines -or $Candidate.reproduction.check_mode -or
        $Candidate.reproduction.repository_mount -ne 'read-only' -or
        $Candidate.reproduction.network -ne 'none' -or $Candidate.reproduction.capabilities -ne 'none' -or
        -not $Candidate.reproduction.no_new_privileges -or
        $Candidate.reproduction.builder_user -ne 'tmxy' -or
        @(Compare-Object @($Candidate.next_scope.tasks) @(
                    'P2-20A-remediation', 'P2-20B-owner-decisions', 'P2-20-g2-rerun')).Count -ne 0) {
        return $false
    }
    return $true
}

Add-A 'Policy schema and report are valid JSON' (
    [bool](Test-Json -Json $policyText -ErrorAction SilentlyContinue) -and
    [bool](Test-Json -Json $schemaText -ErrorAction SilentlyContinue) -and
    [bool](Test-Json -Json $reportText -ErrorAction SilentlyContinue))
Add-A 'Report validates against the closed G2 JSON Schema' (
    [bool](Test-Json -Json $reportText -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$actualTop = @($report.PSObject.Properties.Name | Sort-Object)
$requiredTop = @($schema.required | Sort-Object)
Add-A 'Closed report has exactly the 21 required top-level fields' (
    $schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and
    $actualTop.Count -eq 21 -and $requiredTop.Count -eq 21 -and
    @(Compare-Object $actualTop $requiredTop).Count -eq 0)
Add-A 'Policy preserves nine SATISFIED exit requirements and fail-closed rules' (
    Test-PolicySemantics $policy)
Add-A 'Review execution passes while task gate and authorization remain blocked' (
    $report.review_execution_result -eq 'PASS' -and $report.result -eq 'BLOCKED' -and
    $report.task_status -eq 'BLOCKED' -and -not $report.completion_criteria_satisfied -and
    $report.gate_decision -eq 'BLOCKED' -and -not $report.g2_approved -and
    -not $report.p3_authorized)
Add-A 'Observed outcome is exactly seven satisfied and G2-06 G2-07 blocked' (
    Test-G2Semantics $report $policy)

$bindingsPassed = @($report.input_bindings.prerequisites).Count -eq 19
$aggregateLines = [Collections.Generic.List[string]]::new()
foreach ($index in 0..18) {
    $specification = $policy.required_inputs[$index]
    $binding = $report.input_bindings.prerequisites[$index]
    $path = Join-Path $root ([string]$specification.path)
    $upstream = Get-Content -LiteralPath $path -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $observedTask = if ($null -ne $upstream.PSObject.Properties['task_id']) {
        [string]$upstream.task_id
    }
    else { [string]$upstream.task }
    $bindingsPassed = $bindingsPassed -and $binding.task_id -eq $specification.task_id -and
        $binding.path -eq $specification.path -and $binding.sha256 -eq (Get-Sha256 $path) -and
        $observedTask -eq $specification.task_id -and $upstream.result -eq 'PASS' -and
        $upstream.task_status -eq 'COMPLETE' -and $upstream.completion_criteria_satisfied
    $aggregateLines.Add("$($binding.task_id)|$($binding.path)|$($binding.sha256)")
}
$qualityBinding = $report.input_bindings.quality
$supplementalBinding = $report.input_bindings.supplemental
$descriptorBinding = $report.input_bindings.descriptor_diagnostics
$remediationBinding = $report.input_bindings.remediation
$bindingsPassed = $bindingsPassed -and
    $supplementalBinding.task_id -eq $policy.supplemental.task_id -and
    $supplementalBinding.criterion_id -eq $policy.supplemental.criterion_id -and
    $supplementalBinding.path -eq $policy.supplemental.path -and
    $supplementalBinding.sha256 -eq (Get-Sha256 $supplementalPath) -and
    $supplemental.task_id -eq 'P2-20A' -and $supplemental.criterion_id -eq 'G2-06' -and
    $supplemental.review_execution_result -eq 'PASS' -and
    $supplementalBinding.result -eq $supplemental.result -and
    $supplementalBinding.task_status -eq $supplemental.task_status -and
    $supplementalBinding.completion_criteria_satisfied -eq
        $supplemental.completion_criteria_satisfied -and
    (Test-AuxiliaryCoreBinding $supplemental $auxiliaryReport)
$aggregateLines.Add("SUPPLEMENTAL|$($supplementalBinding.task_id)|$($supplementalBinding.criterion_id)|$($supplementalBinding.path)|$($supplementalBinding.sha256)")
$bindingsPassed = $bindingsPassed -and
    $descriptorBinding.task_id -eq $policy.descriptor_diagnostics.task_id -and
    $descriptorBinding.criterion_id -eq $policy.descriptor_diagnostics.criterion_id -and
    $descriptorBinding.evidence_revision -eq $policy.descriptor_diagnostics.evidence_revision -and
    $descriptorBinding.path -eq $policy.descriptor_diagnostics.path -and
    $descriptorBinding.sha256 -eq (Get-Sha256 $descriptorDiagnosticPath) -and
    $descriptorDiagnostic.evidence_revision -eq 'P2-20A.4' -and
    $descriptorDiagnostic.review_execution_result -eq 'PASS' -and
    $descriptorDiagnostic.diagnostic_scope_complete -eq $true -and
    $descriptorDiagnostic.result -eq 'BLOCKED' -and
    $descriptorDiagnostic.g2_06_satisfied -eq $false
$aggregateLines.Add("DESCRIPTOR|$($descriptorBinding.task_id)|$($descriptorBinding.criterion_id)|$($descriptorBinding.evidence_revision)|$($descriptorBinding.path)|$($descriptorBinding.sha256)")
$bindingsPassed = $bindingsPassed -and
    $remediationBinding.task_id -eq $policy.remediation.task_id -and
    $remediationBinding.criterion_id -eq $policy.remediation.criterion_id -and
    $remediationBinding.path -eq $policy.remediation.path -and
    $remediationBinding.sha256 -eq (Get-Sha256 $remediationPath) -and
    $remediation.task_id -eq 'P2-20B' -and $remediation.gate_criterion -eq 'G2-07' -and
    $remediation.generation_result -eq 'PASS' -and
    $remediationBinding.result -eq $remediation.result -and
    $remediationBinding.task_status -eq $remediation.task_status -and
    $remediationBinding.completion_criteria_satisfied -eq
        $remediation.completion_criteria_satisfied -and
    $remediationBinding.g2_07_satisfied -eq $remediation.g2_07_satisfied
$aggregateLines.Add("REMEDIATION|$($remediationBinding.task_id)|$($remediationBinding.criterion_id)|$($remediationBinding.path)|$($remediationBinding.sha256)")
$bindingsPassed = $bindingsPassed -and $qualityBinding.path -eq $policy.quality_evidence -and
    $qualityBinding.sha256 -eq (Get-Sha256 $qualityPath) -and
    $quality.result -eq 'PASS_DIAGNOSTIC' -and $quality.repository.result -eq 'PASS' -and
    $quality.repository.failure_count -eq 0 -and $quality.secret.result -eq 'PASS' -and
    $quality.secret.failure_count -eq 0 -and $quality.secret.finding_count -eq 0
$aggregateLines.Add("QUALITY|$($qualityBinding.path)|$($qualityBinding.sha256)")
$bindingsPassed = $bindingsPassed -and $report.input_bindings.aggregate_sha256 -eq
    (Get-TextSha256 (($aggregateLines -join "`n") + "`n"))
Add-A 'All prerequisites supplemental descriptor remediation and quality evidence are exactly SHA-256 bound' $bindingsPassed

$g206 = Get-Criterion $report 'G2-06'
Add-A 'P2-20A full-scope evidence exposes quantified nonzero G2-06 gaps without FK substitution' (
    $supplemental.closure.scope_complete -eq $false -and
    $supplemental.closure.auxiliary_config_reference_scope_complete -eq $false -and
    (Test-AuxiliaryCoreBinding $supplemental $auxiliaryReport) -and
    (Get-Metric $g206 'auxiliary_reference_evidence_hash_bound') -eq $true -and
    (Get-Metric $g206 'auxiliary_file_instances') -eq 212 -and
    (Get-Metric $g206 'auxiliary_candidate_only') -eq 171 -and
    (Get-Metric $g206 'auxiliary_editor_undecided') -eq 35 -and
    (Get-Metric $g206 'auxiliary_malformed_blocked') -eq 6 -and
    (Get-Metric $g206 'auxiliary_semantic_approved') -eq 0 -and
    (Get-Metric $g206 'auxiliary_no_ref_approved') -eq 0 -and
    (Get-Metric $g206 'auxiliary_approved_roots') -eq 0 -and
    (Get-Metric $g206 'descriptor_diagnostic_hash_bound') -eq $true -and
    (Get-Metric $g206 'descriptor_diagnostic_targets') -eq 3651 -and
    (Get-Metric $g206 'descriptor_diagnostic_candidate_edges') -eq 12764 -and
    (Get-Metric $g206 'descriptor_diagnostic_resolved_targets') -eq 3617 -and
    (Get-Metric $g206 'descriptor_diagnostic_ambiguous_targets') -eq 15 -and
    (Get-Metric $g206 'descriptor_diagnostic_unresolved_targets') -eq 19 -and
    $supplemental.closure.asset_binding_resolution_explicit -eq $true -and
    $supplemental.closure.asset_binding.resolution_explicit -eq $true -and
    $supplemental.closure.asset_binding.resolved_targets -eq 21292 -and
    $supplemental.closure.asset_binding.ambiguous_targets -eq 183 -and
    $supplemental.closure.asset_binding.unresolved_targets -eq 19 -and
    $supplemental.closure.asset_binding.unknown_targets -eq 0 -and
    $supplemental.closure.asset_binding.workset_count -eq 21494 -and
    [string]$supplemental.closure.asset_binding.workset_sha256 -match '^[0-9a-f]{64}$' -and
    $supplemental.closure.conditional_required.conditional_required_missing -eq 29 -and
    $supplemental.closure.conditional_required.member_set_exported -eq $true -and
    $supplemental.closure.conditional_required.member_set_count -eq 29 -and
    [string]$supplemental.closure.conditional_required.member_set_sha256 -match
        '^[0-9a-f]{64}$' -and
    $supplemental.closure.resolution.heuristic_target_selections -eq 0 -and
    $supplemental.closure.integrity.core_foreign_key_dangling -eq 0 -and
    (Get-Metric $g206 'table_resource_unresolved') -eq
        $supplemental.closure.resolution.table_unresolved -and
    (Get-Metric $g206 'table_resource_ambiguous') -eq
        $supplemental.closure.resolution.table_ambiguous -and
    (Get-Metric $g206 'package_resource_unresolved') -eq
        $supplemental.closure.resolution.package_unresolved -and
    (Get-Metric $g206 'package_resource_ambiguous') -eq
        $supplemental.closure.resolution.package_ambiguous -and
    (Get-Metric $g206 'conditional_required_missing') -eq 29 -and
    (Get-Metric $g206 'conditional_member_set_exported') -eq $true -and
    (Get-Metric $g206 'conditional_member_set_count') -eq 29 -and
    (Get-Metric $g206 'conditional_member_set_hash_bound') -eq $true -and
    (Get-Metric $g206 'asset_binding_resolution_explicit') -eq $true -and
    (Get-Metric $g206 'asset_binding_resolved_targets') -eq 21460 -and
    (Get-Metric $g206 'asset_binding_ambiguous_targets') -eq 15 -and
    (Get-Metric $g206 'asset_binding_unresolved_targets') -eq 19 -and
    (Get-Metric $g206 'asset_binding_unknown_targets') -eq 0 -and
    (Get-Metric $g206 'asset_binding_workset_hash_bound') -eq $true -and
    (Get-Metric $g206 'first_candidate_selection_used') -eq $false -and
    (Get-Metric $g206 'asset_structure_unresolved') -eq 18 -and
    (Get-Metric $g206 'unknown_record_count') -eq 0 -and
    (Get-Metric $g206 'unknown_resolution_count') -eq 0 -and
    (Get-Metric $g206 'core_foreign_key_dangling_context') -eq 0 -and
    $g206.interpretation -match 'hash-bound monotonic core-scope closure report' -and
    $g206.interpretation -match 'A.4 independently binds exact' -and
    -not $g206.satisfied -and $g206.observed_status -eq 'BLOCKED')
$g207 = Get-Criterion $report 'G2-07'
Add-A 'P2-20B has complete coverage while all 1359 decisions and approvals remain pending' (
    (Get-Metric $g207 'migration_decision_registry_present') -eq $true -and
    (Get-Metric $g207 'migration_workflow_version') -eq 2 -and
    (Get-Metric $g207 'migration_workflow_ready') -eq $true -and
    (Get-Metric $g207 'review_packet_count') -eq 39 -and
    (Get-Metric $g207 'review_packet_members') -eq 1359 -and
    (Get-Metric $g207 'authority_ledger_records') -eq 0 -and
    (Get-Metric $g207 'coverage_complete') -eq $true -and
    $remediation.workflow_version -eq 2 -and
    $remediation.review_packets.packet_count -eq 39 -and
    $remediation.review_packets.member_count -eq 1359 -and
    $remediation.review_packets.sha256 -eq (Get-Sha256 $reviewPacketsPath) -and
    @($reviewPackets.packets).Count -eq 39 -and
    @($reviewPackets.packets.members).Count -eq 1359 -and
    @($authorityLedger.records).Count -eq 0 -and
    $remediation.summary.expected_units -eq 1359 -and
    $remediation.summary.enumerated_units -eq 1359 -and
    $remediation.completeness.missing -eq 0 -and
    $remediation.completeness.duplicates -eq 0 -and
    $remediation.completeness.orphans -eq 0 -and
    $remediation.summary.pending -eq 1359 -and $remediation.summary.decided -eq 0 -and
    $remediation.summary.approved -eq 0 -and $remediation.summary.approval_count -eq 0 -and
    $remediation.summary.verified -eq 0 -and
    (Get-Metric $g207 'machine_suggestions') -eq 1359 -and
    (Get-Metric $g207 'machine_suggestions_count_as_decisions') -eq $false -and
    -not $remediation.authority_boundaries.machine_can_approve -and
    -not $remediation.g2_07_satisfied -and
    -not $g207.satisfied -and $g207.observed_status -eq 'BLOCKED')
Add-A 'Both blocker records remain non-empty and mapped to their criteria' (
    @($report.blockers).Count -eq 2 -and
    @($report.blockers | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.title) -or
            [string]::IsNullOrWhiteSpace([string]$_.reason) -or
            [string]::IsNullOrWhiteSpace([string]$_.required_action)
        }).Count -eq 0 -and
    @(Compare-Object @($report.blockers.id) @('G2-BLK-06', 'G2-BLK-07')).Count -eq 0 -and
    @($report.blockers | Where-Object { $_.reason -match '\babsent\b|\bmissing evidence\b' }).Count -eq 0 -and
    $report.blockers[0].reason -match 'measured core queues contain' -and
    $report.blockers[1].reason -match 'remain pending')

$p215 = Get-Content -LiteralPath (Join-Path $root 'Data\Inventory\p2-15-conversion-routing.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$p218 = Get-Content -LiteralPath (Join-Path $root 'Data\Inventory\p2-18-content-health.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$p219 = Get-Content -LiteralPath (Join-Path $root 'Data\Inventory\p2-19-resource-budget.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$budget = $report.budget_interpretation
Add-A 'Planning budget is quantified without becoming measured schedule money or commitment' (
    $budget.planning_cost_quantified -and $budget.manual_content_assets -eq 800 -and
    $budget.total_content_assets -eq 40090 -and $budget.manual_content_rate_ppm -eq 19955 -and
    $budget.base_planning_hours -eq $p219.summary.human_budget.base_planning_hours -and
    $budget.risk_adjusted_planning_hours -eq $p219.summary.human_budget.total_planning_hours -and
    $budget.machine_projection_seconds -eq $p219.summary.machine_budget.total_sequential_seconds -and
    $budget.storage_budget_bytes -eq $p219.summary.storage_budget.total_budget_bytes -and
    $budget.incremental_storage_required_bytes -eq $p219.summary.storage_budget.incremental_required_bytes -and
    $budget.storage_capacity_gap_bytes -eq $p219.summary.storage_budget.capacity_gap_bytes -and
    $p218.summary.effort.manual_assets -eq 800 -and $p215.summary.assets.files -eq 40090 -and
    -not $budget.measured_schedule -and -not $budget.monetary_amount_available -and
    -not $budget.financial_total_cost_available -and -not $budget.delivery_commitment)
Add-A 'No playable release production repair delete or official-server authority is claimed' (
    -not $report.authority_boundaries.playable_experience_proven -and
    -not $report.authority_boundaries.release_authority -and
    -not $report.authority_boundaries.production_authority -and
    -not $report.authority_boundaries.automatic_repair_or_delete_authority -and
    -not $report.authority_boundaries.official_server_implementation_recovered)
Add-A 'Security review passes without converting diagnostic evidence into G2 approval' (
    $report.security.quality_result -eq 'PASS_DIAGNOSTIC' -and
    $report.security.repository_result -eq 'PASS' -and $report.security.repository_failures -eq 0 -and
    $report.security.secret_result -eq 'PASS' -and $report.security.secret_findings -eq 0 -and
    $report.security.security_review_result -eq 'PASS' -and -not $report.g2_approved)
Add-A 'Policy and schema hashes plus tracked disclosure boundary are exact' (
    $report.contracts.policy -eq 'Contracts/data-schema/g2-review-policy-v1.json' -and
    $report.contracts.schema -eq 'Contracts/data-schema/g2-review-v1.schema.json' -and
    $report.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $report.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath) -and
    -not $report.disclosure.private_source_paths -and -not $report.disclosure.exact_primary_keys -and
    -not $report.disclosure.exact_observed_extrema -and -not $report.disclosure.raw_table_rows -and
    -not $report.disclosure.decoded_confidential_payloads -and
    -not $report.disclosure.legacy_source_lines)
Add-A 'Complete blocked-task evidence matches report implementation and isolation' (
    Test-EvidenceSemantics $evidence)

$negativeCases = [ordered]@{}
$unknown = Copy-JsonObject $report
$unknown | Add-Member -NotePropertyName optimistic_gate_claim -NotePropertyValue $true
$negativeCases.unknown_field_rejected = -not (Test-AgainstSchema $unknown)
$wrongPolicy = Copy-JsonObject $policy
$wrongPolicy.criteria[5].required_status = 'BLOCKED'
$negativeCases.blocked_exit_requirement_rejected = -not (Test-PolicySemantics $wrongPolicy)
$falseFk = Copy-JsonObject $report
Set-CriterionSatisfied $falseFk 'G2-06'
$negativeCases.core_fk_zero_substitution_rejected =
    (Test-AgainstSchema $falseFk) -and -not (Test-G2Semantics $falseFk $policy)
$explicitBindingOnly = Copy-JsonObject $report
Set-CriterionSatisfied $explicitBindingOnly 'G2-06'
$negativeCases.explicit_asset_binding_with_open_states_rejected =
    (Get-Metric (Get-Criterion $explicitBindingOnly 'G2-06') `
        'asset_binding_resolution_explicit') -eq $true -and
    (Get-Metric (Get-Criterion $explicitBindingOnly 'G2-06') `
        'asset_binding_ambiguous_targets') -eq 15 -and
    (Test-AgainstSchema $explicitBindingOnly) -and
    -not (Test-G2Semantics $explicitBindingOnly $policy)
$scopeForgery = Copy-JsonObject $report
$scopeCriterion = Get-Criterion $scopeForgery 'G2-06'
foreach ($name in @('scope_complete', 'auxiliary_config_scope_complete',
        'asset_binding_resolution_explicit', 'conditional_member_set_exported',
        'conditional_member_set_hash_bound')) {
    Set-Metric $scopeCriterion $name $true
}
foreach ($name in @('table_resource_unresolved', 'table_resource_ambiguous',
        'package_resource_unresolved', 'package_resource_ambiguous',
        'conditional_required_missing', 'asset_binding_ambiguous_targets',
        'asset_binding_unresolved_targets', 'asset_binding_unknown_targets',
        'asset_structure_unresolved')) {
    Set-Metric $scopeCriterion $name 0
}
Set-CriterionSatisfied $scopeForgery 'G2-06'
$negativeCases.scope_and_conditional_29_forgery_rejected =
    (Test-AgainstSchema $scopeForgery) -and -not (Test-G2Semantics $scopeForgery $policy)
$firstCandidate = Copy-JsonObject $scopeForgery
Set-Metric (Get-Criterion $firstCandidate 'G2-06') 'first_candidate_selection_used' $true
$negativeCases.first_candidate_selection_rejected =
    (Test-AgainstSchema $firstCandidate) -and -not (Test-G2Semantics $firstCandidate $policy)
$falseMigration = Copy-JsonObject $report
$falseMigration.criteria[6].evidence_task_ids = @('P2-09', 'P2-11', 'P2-17')
$negativeCases.audit_codegen_migration_substitution_rejected =
    (Test-AgainstSchema $falseMigration) -and -not (Test-G2Semantics $falseMigration $policy)
$pendingApproval = Copy-JsonObject $report
$migrationCriterion = Get-Criterion $pendingApproval 'G2-07'
Set-Metric $migrationCriterion 'pending_decisions' 0
Set-Metric $migrationCriterion 'decided_units' 1359
Set-Metric $migrationCriterion 'approved_units' 1359
Set-Metric $migrationCriterion 'approval_count' 1359
Set-Metric $migrationCriterion 'g2_07_registry_satisfied' $true
Set-CriterionSatisfied $pendingApproval 'G2-07'
$negativeCases.pending_1359_false_approval_rejected =
    (Test-AgainstSchema $pendingApproval) -and -not (Test-G2Semantics $pendingApproval $policy)
$machineDecision = Copy-JsonObject $pendingApproval
Set-Metric (Get-Criterion $machineDecision 'G2-07') `
    'machine_suggestions_count_as_decisions' $true
$negativeCases.machine_suggestion_decision_substitution_rejected =
    (Test-AgainstSchema $machineDecision) -and -not (Test-G2Semantics $machineDecision $policy)
$approved = Copy-JsonObject $scopeForgery
$approvedMigration = Get-Criterion $approved 'G2-07'
Set-Metric $approvedMigration 'pending_decisions' 0
Set-Metric $approvedMigration 'decided_units' 1359
Set-Metric $approvedMigration 'approved_units' 1359
Set-Metric $approvedMigration 'approval_count' 1359
Set-Metric $approvedMigration 'g2_07_registry_satisfied' $true
Set-CriterionSatisfied $approved 'G2-07'
$negativeCases.approved_gate_rejected =
    (Test-AgainstSchema $approved) -and -not (Test-G2Semantics $approved $policy)
$noBlockers = Copy-JsonObject $report
$noBlockers.blockers = @()
$negativeCases.empty_blockers_rejected =
    -not (Test-AgainstSchema $noBlockers) -and -not (Test-G2Semantics $noBlockers $policy)
$missingSupplementalSha = Copy-JsonObject $report
[void]$missingSupplementalSha.input_bindings.supplemental.PSObject.Properties.Remove('sha256')
$negativeCases.missing_supplemental_sha_rejected = -not (Test-AgainstSchema $missingSupplementalSha)
$badSupplementalSha = Copy-JsonObject $report
$badSupplementalSha.input_bindings.supplemental.sha256 = '0' * 64
$negativeCases.supplemental_sha_tamper_rejected =
    (Test-AgainstSchema $badSupplementalSha) -and
    $badSupplementalSha.input_bindings.supplemental.sha256 -ne (Get-Sha256 $supplementalPath)
$missingDescriptorSha = Copy-JsonObject $report
[void]$missingDescriptorSha.input_bindings.descriptor_diagnostics.PSObject.Properties.Remove('sha256')
$negativeCases.missing_descriptor_sha_rejected = -not (Test-AgainstSchema $missingDescriptorSha)
$badDescriptorSha = Copy-JsonObject $report
$badDescriptorSha.input_bindings.descriptor_diagnostics.sha256 = '0' * 64
$negativeCases.descriptor_sha_tamper_rejected =
    (Test-AgainstSchema $badDescriptorSha) -and
    $badDescriptorSha.input_bindings.descriptor_diagnostics.sha256 -ne
        (Get-Sha256 $descriptorDiagnosticPath)
$badAuxMetric = Copy-JsonObject $report
Set-Metric (Get-Criterion $badAuxMetric 'G2-06') `
    'auxiliary_reference_evidence_hash_bound' $false
$negativeCases.auxiliary_metric_tamper_rejected =
    (Test-AgainstSchema $badAuxMetric) -and -not (Test-G2Semantics $badAuxMetric $policy)
$badAuxBinding = Copy-JsonObject $supplemental
@($badAuxBinding.input_bindings.artifacts |
    Where-Object id -eq 'P2-20A.3-AUX')[0].sha256 = '0' * 64
$negativeCases.auxiliary_nested_sha_tamper_rejected = -not (
    Test-AuxiliaryCoreBinding $badAuxBinding $auxiliaryReport)
$badAuxScope = Copy-JsonObject $supplemental
$badAuxScope.scope_definition.auxiliary_config.scope_complete = $true
$negativeCases.auxiliary_false_scope_rejected = -not (
    Test-AuxiliaryCoreBinding $badAuxScope $auxiliaryReport)
$badAuxRoot = Copy-JsonObject $supplemental
$badAuxRoot.scope_definition.auxiliary_config.approved_roots = 1
$negativeCases.auxiliary_fabricated_root_rejected = -not (
    Test-AuxiliaryCoreBinding $badAuxRoot $auxiliaryReport)
$badAuxCount = Copy-JsonObject $supplemental
$badAuxCount.scope_definition.auxiliary_config.inventory_files = 211
$negativeCases.auxiliary_file_count_tamper_rejected = -not (
    Test-AuxiliaryCoreBinding $badAuxCount $auxiliaryReport)
$badAuxPass = Copy-JsonObject $auxiliaryReport
$badAuxPass.result = 'PASS'
$negativeCases.auxiliary_false_pass_rejected = -not (
    Test-AuxiliaryCoreBinding $supplemental $badAuxPass)
$badAuxComplete = Copy-JsonObject $auxiliaryReport
$badAuxComplete.task_status = 'COMPLETE'
$badAuxComplete.completion_criteria_satisfied = $true
$negativeCases.auxiliary_false_complete_rejected = -not (
    Test-AuxiliaryCoreBinding $supplemental $badAuxComplete)
$badRemediationSha = Copy-JsonObject $report
$badRemediationSha.input_bindings.remediation.sha256 = '0' * 64
$negativeCases.remediation_sha_tamper_rejected =
    (Test-AgainstSchema $badRemediationSha) -and
    $badRemediationSha.input_bindings.remediation.sha256 -ne (Get-Sha256 $remediationPath)
$badSha = Copy-JsonObject $report
$badSha.input_bindings.prerequisites[0].sha256 = '0' * 64
$negativeCases.sha_tamper_rejected = (Test-AgainstSchema $badSha)
if ($negativeCases.sha_tamper_rejected) {
    $path = Join-Path $root ([string]$badSha.input_bindings.prerequisites[0].path)
    $negativeCases.sha_tamper_rejected =
        $badSha.input_bindings.prerequisites[0].sha256 -ne (Get-Sha256 $path)
}
$aggregateDrift = Copy-JsonObject $report
$aggregateDrift.input_bindings.aggregate_sha256 = '0' * 64
$negativeCases.aggregate_input_drift_rejected =
    (Test-AgainstSchema $aggregateDrift) -and
    $aggregateDrift.input_bindings.aggregate_sha256 -ne $report.input_bindings.aggregate_sha256
$badEvidence = Copy-JsonObject $evidence
$badEvidence.implementation.source_sha256 = '0' * 64
$negativeCases.full_evidence_tamper_rejected = -not (Test-EvidenceSemantics $badEvidence)
Add-A 'Policy supplemental scope FK migration approval drift and unknown-field negatives fail closed' (
    @($negativeCases.Values | Where-Object { -not $_ }).Count -eq 0)

$localCheck = $null
if ($VerifyDerivedSources) {
    $localCheck = & $wrapperPath -RebuildRoot $root -Check |
        ConvertFrom-Json -Depth 100 -DateKind String
    Add-A 'Byte-identical isolated G2 report regeneration passes wrapper check mode' (
        $localCheck.result -eq 'BLOCKED' -and $localCheck.review_execution_result -eq 'PASS' -and
        $localCheck.task_id -eq 'P2-20' -and $localCheck.gate_decision -eq 'BLOCKED' -and
        $localCheck.report.json.sha256 -eq (Get-Sha256 $reportPath) -and
        $localCheck.report.markdown.sha256 -eq (Get-Sha256 $markdownPath) -and
        (Test-JsonEqual $localCheck $evidence))
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-20'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    contract_assertions_satisfied = $failed.Count -eq 0
    completion_criteria_satisfied = $false
    review_completion_criteria_satisfied = $false
    gate_decision = 'BLOCKED'
    verify_derived_sources = [bool]$VerifyDerivedSources
    negative_cases = $negativeCases
    review = $evidence.report
    local_check = $localCheck
    assertions = $assertions
} | ConvertTo-Json -Depth 100
if ($failed.Count -gt 0) { exit 1 }
