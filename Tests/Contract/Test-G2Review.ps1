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
$auxSemanticDiagnosticPath = Join-Path $root 'Data\Reports\p2-20a-aux-semantic-diagnostics-report.json'
$auxPackageContextPath = Join-Path $root 'Data\Reports\p2-20a-aux-package-context-report.json'
$auxEcfParserParityPath = Join-Path $root 'Data\Reports\p2-20a-aux-ecf-parser-parity-report.json'
$auxMalformedXmlPath = Join-Path $root 'Data\Reports\p2-20a-aux-malformed-xml-diagnostics-report.json'
$identityNormalizationPath = Join-Path $root 'Data\Reports\p2-20a-asset-identity-normalization-report.json'
$bindingFailurePath = Join-Path $root 'Data\Reports\p2-20a-asset-binding-failure-diagnostics-report.json'
$bindingRecoveryPath = Join-Path $root 'Data\Reports\p2-20a-asset-binding-recovery-report.json'
$auxiliaryReportPath = Join-Path $root 'Data\Reports\p2-20a-aux-config-reference-report.json'
$remediationPath = Join-Path $root 'Data\Governance\p2-g2-migration-decisions.json'
$reviewPacketsPath = Join-Path $root 'Data\Governance\p2-g2-migration-review-packets.json'
$authorityLedgerPath = Join-Path $root 'Data\Governance\p2-g2-migration-decision-authority-v2.json'
$migrationPolicyPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-policy-v2.json'
$migrationSchemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-registry-v2.schema.json'
$authoritySchemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-authority-v2.schema.json'
$reviewPacketSchemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-review-packets-v2.schema.json'
$generatorPath = Join-Path $root 'Tools\TMXY.G2Review\g2_review.py'
$reportModelHelperPath = Join-Path $root 'Tools\TMXY.G2Review\g2_report_model.py'
$helperPath = Join-Path $root 'Tools\TMXY.G2Review\g2_evidence.py'
$auxSemanticHelperPath = Join-Path $root 'Tools\TMXY.G2Review\g2_aux_semantic.py'
$auxPackageContextHelperPath = Join-Path $root 'Tools\TMXY.G2Review\g2_aux_package_context.py'
$auxMalformedPythonPath = Join-Path $root 'Tools\TMXY.G2Review\g2_aux_malformed_xml.py'
$identityNormalizationHelperPath = Join-Path $root 'Tools\TMXY.G2Review\g2_identity_normalization.py'
$bindingFailureHelperPath = Join-Path $root 'Tools\TMXY.G2Review\g2_binding_failure.py'
$bindingRecoveryHelperPath = Join-Path $root 'Tools\TMXY.G2Review\g2_binding_recovery.py'
$wrapperPath = Join-Path $root 'Tools\TMXY.G2Review\New-G2Review.ps1'
$negativeCasesHelperPath = Join-Path $root 'Tests\Contract\G2Review-NegativeCases.ps1'
$malformedCasesHelperPath = Join-Path $root 'Tests\Contract\G2Review-MalformedXmlCases.ps1'
. $malformedCasesHelperPath
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
        $Candidate.aux_semantic_diagnostics.task_id -eq 'P2-20A' -and
        $Candidate.aux_semantic_diagnostics.criterion_id -eq 'G2-06' -and
        $Candidate.aux_semantic_diagnostics.evidence_revision -eq 'P2-20A.5' -and
        $Candidate.aux_semantic_diagnostics.path -eq
            'Data/Reports/p2-20a-aux-semantic-diagnostics-report.json' -and
        $Candidate.aux_package_context.task_id -eq 'P2-20A' -and
        $Candidate.aux_package_context.criterion_id -eq 'G2-06' -and
        $Candidate.aux_package_context.evidence_revision -eq 'P2-20A.9' -and
        $Candidate.aux_package_context.path -eq
            'Data/Reports/p2-20a-aux-package-context-report.json' -and
        $Candidate.aux_ecf_parser_parity.task_id -eq 'P2-20A' -and
        $Candidate.aux_ecf_parser_parity.criterion_id -eq 'G2-06' -and
        $Candidate.aux_ecf_parser_parity.evidence_revision -eq 'P2-20A.10' -and
        $Candidate.aux_ecf_parser_parity.path -eq
            'Data/Reports/p2-20a-aux-ecf-parser-parity-report.json' -and
        (Test-G2MalformedXmlPolicy $Candidate) -and
        $Candidate.identity_normalization_safety.task_id -eq 'P2-20A' -and
        $Candidate.identity_normalization_safety.criterion_id -eq 'G2-06' -and
        $Candidate.identity_normalization_safety.evidence_revision -eq 'P2-20A.6' -and
        $Candidate.identity_normalization_safety.path -eq
            'Data/Reports/p2-20a-asset-identity-normalization-report.json' -and
        $Candidate.binding_failure_diagnostics.evidence_revision -eq 'P2-20A.7' -and
        $Candidate.binding_failure_diagnostics.path -eq
            'Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json' -and
        $Candidate.binding_recovery.evidence_revision -eq 'P2-20A.8' -and
        $Candidate.binding_recovery.path -eq
            'Data/Reports/p2-20a-asset-binding-recovery-report.json' -and
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
        $Candidate.fail_closed_rules.ascii_lower_identity_collision_does_not_prove_semantic_equivalence_or_candidate_selection -and
        $Candidate.fail_closed_rules.binding_error_diagnosis_does_not_reduce_unresolved_without_verified_remediation -and
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
    if (-not (Test-G2MalformedXmlMetrics $g206)) { return $false }
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
        (Get-Metric $g206 'descriptor_diagnostic_resolved_targets') -ne 3450 -or
        (Get-Metric $g206 'descriptor_diagnostic_ambiguous_targets') -ne 189 -or
        (Get-Metric $g206 'descriptor_diagnostic_unresolved_targets') -ne 12 -or
        (Get-Metric $g206 'identity_normalization_hash_bound') -ne $true -or
        (Get-Metric $g206 'identity_case_fold_collision_targets') -ne 13 -or
        (Get-Metric $g206 'identity_case_fold_collision_edges') -ne 26 -or
        (Get-Metric $g206 'identity_non_case_targets') -ne 2 -or
        (Get-Metric $g206 'identity_non_case_edges') -ne 4 -or
        (Get-Metric $g206 'identity_strict_descriptor_equivalent_targets') -ne 0 -or
        (Get-Metric $g206 'identity_strict_full_semantic_equivalent_targets') -ne 0 -or
        (Get-Metric $g206 'identity_automatic_selected_targets') -ne 0 -or
        (Get-Metric $g206 'identity_retained_ambiguous_targets') -ne 15 -or
        (Get-Metric $g206 'identity_retained_ambiguous_edges') -ne 30 -or
        (Get-Metric $g206 'identity_retained_unresolved_targets') -ne 12 -or
        (Get-Metric $g206 'identity_retained_unresolved_edges') -ne 15 -or
        (Get-Metric $g206 'binding_failure_diagnostic_hash_bound') -ne $true -or
        (Get-Metric $g206 'binding_failure_diagnostic_scope_complete') -ne $true -or
        (Get-Metric $g206 'binding_failure_remediation_scope_complete') -ne $false -or
        (Get-Metric $g206 'binding_failure_diagnosed_targets') -ne 19 -or
        (Get-Metric $g206 'binding_failure_diagnosed_edges') -ne 24 -or
        (Get-Metric $g206 'binding_failure_typed_error_edges') -ne 24 -or
        (Get-Metric $g206 'binding_failure_unclassified_error_edges') -ne 0 -or
        (Get-Metric $g206 'binding_failure_effective_resolved_targets') -ne 7 -or
        (Get-Metric $g206 'binding_failure_effective_resolved_edges') -ne 9 -or
        (Get-Metric $g206 'binding_failure_effective_ambiguous_targets') -ne 0 -or
        (Get-Metric $g206 'binding_failure_effective_ambiguous_edges') -ne 0 -or
        (Get-Metric $g206 'binding_failure_effective_unresolved_targets') -ne 12 -or
        (Get-Metric $g206 'binding_failure_effective_unresolved_edges') -ne 15 -or
        (Get-Metric $g206 'binding_failure_candidate_selections') -ne 0 -or
        (Get-Metric $g206 'binding_failure_automatic_resolutions') -ne 0 -or
        (Get-Metric $g206 'binding_failure_owner_dispositions') -ne 0 -or
        (Get-Metric $g206 'binding_recovery_cross_proof_hash_bound') -ne $true -or
        (Get-Metric $g206 'binding_recovery_attempted_targets') -ne 17 -or
        (Get-Metric $g206 'binding_recovery_attempted_edges') -ne 21 -or
        (Get-Metric $g206 'binding_recovery_successful_targets') -ne 7 -or
        (Get-Metric $g206 'binding_recovery_successful_edges') -ne 9 -or
        (Get-Metric $g206 'aux_semantic_diagnostic_hash_bound') -ne $true -or
        (Get-Metric $g206 'aux_semantic_scope_complete') -ne $false -or
        (Get-Metric $g206 'aux_semantic_g2_06_satisfied') -ne $false -or
        (Get-Metric $g206 'aux_semantic_unique_references') -ne 3180 -or
        (Get-Metric $g206 'aux_semantic_ambiguous_objects') -ne 211 -or
        (Get-Metric $g206 'aux_semantic_unresolved_resources') -ne 1 -or
        (Get-Metric $g206 'aux_semantic_ecf_parser_differences') -ne 3 -or
        (Get-Metric $g206 'aux_semantic_ecf_missed_assignments') -ne 4 -or
        (Get-Metric $g206 'aux_package_context_hash_bound') -ne $true -or
        (Get-Metric $g206 'aux_package_context_contract_proven') -ne $true -or
        (Get-Metric $g206 'aux_package_context_strict_ambiguous_objects') -ne 211 -or
        (Get-Metric $g206 'aux_package_context_original_candidate_edges') -ne 422 -or
        (Get-Metric $g206 'aux_package_context_singleton_matches') -ne 211 -or
        (Get-Metric $g206 'aux_package_context_first_candidate_selections') -ne 0 -or
        (Get-Metric $g206 'aux_package_context_effective_resolved') -ne 3391 -or
        (Get-Metric $g206 'aux_package_context_effective_ambiguous') -ne 0 -or
        (Get-Metric $g206 'aux_package_context_effective_unresolved') -ne 1 -or
        (Get-Metric $g206 'aux_package_context_consumer_clean_regions') -ne 134 -or
        (Get-Metric $g206 'aux_package_context_semantic_adapter_approved') -ne $false -or
        (Get-Metric $g206 'aux_package_context_terminal_instances') -ne 0 -or
        (Get-Metric $g206 'aux_ecf_parser_parity_hash_bound') -ne $true -or
        (Get-Metric $g206 'aux_ecf_historical_a5_parity_instances') -ne 61 -or
        (Get-Metric $g206 'aux_ecf_historical_a5_difference_instances') -ne 3 -or
        (Get-Metric $g206 'aux_ecf_historical_a5_pair_count_delta') -ne 4 -or
        (Get-Metric $g206 'aux_ecf_a3_actual_parity_instances') -ne 51 -or
        (Get-Metric $g206 'aux_ecf_a3_actual_difference_instances') -ne 13 -or
        (Get-Metric $g206 'aux_ecf_correct_plain_filter_parity_instances') -ne 63 -or
        (Get-Metric $g206 'aux_ecf_legacy_pair_records_absent_from_a3') -ne 4 -or
        (Get-Metric $g206 'aux_ecf_reference_transform_port_differences') -ne 0 -or
        (Get-Metric $g206 'aux_ecf_reference_pair_port_differences') -ne 0 -or
        (Get-Metric $g206 'aux_ecf_legacy_runtime_executed') -ne $false -or
        (Get-Metric $g206 'aux_ecf_runtime_binary_parity_claimed') -ne $false -or
        (Get-Metric $g206 'aux_ecf_a3_outputs_modified') -ne $false -or
        (Get-Metric $g206 'aux_ecf_semantic_imports_claimed') -ne 0 -or
        (Get-Metric $g206 'asset_binding_resolution_explicit') -ne $true -or
        (Get-Metric $g206 'asset_binding_resolved_targets') -ne 21293 -or
        (Get-Metric $g206 'asset_binding_ambiguous_targets') -ne 189 -or
        (Get-Metric $g206 'asset_binding_unresolved_targets') -ne 12 -or
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
    $qualityPath, $supplementalPath, $descriptorDiagnosticPath, $auxSemanticDiagnosticPath,
    $auxPackageContextPath, $auxEcfParserParityPath, $auxMalformedXmlPath, $identityNormalizationPath,
    $bindingFailurePath, $bindingRecoveryPath,
    $auxiliaryReportPath,
    $remediationPath, $reviewPacketsPath,
    $authorityLedgerPath, $migrationPolicyPath, $migrationSchemaPath,
    $authoritySchemaPath, $reviewPacketSchemaPath, $generatorPath, $reportModelHelperPath,
    $helperPath,
    $auxSemanticHelperPath, $auxPackageContextHelperPath, $auxMalformedPythonPath, $identityNormalizationHelperPath,
    $bindingFailureHelperPath,
    $bindingRecoveryHelperPath, $wrapperPath, $negativeCasesHelperPath,
    $malformedCasesHelperPath)
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
$auxSemanticDiagnostic = Get-Content -LiteralPath $auxSemanticDiagnosticPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$auxPackageContext = Get-Content -LiteralPath $auxPackageContextPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$auxEcfParserParity = Get-Content -LiteralPath $auxEcfParserParityPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$identityNormalization = Get-Content -LiteralPath $identityNormalizationPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$bindingFailure = Get-Content -LiteralPath $bindingFailurePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$bindingRecovery = Get-Content -LiteralPath $bindingRecoveryPath -Raw -Encoding UTF8 |
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
        $Candidate.disclosure.legacy_source_lines) { return $false }
    $expectedReproduction = @('check_mode', 'repository_mount', 'network', 'capabilities',
        'no_new_privileges', 'builder_reference', 'builder_id', 'builder_user')
    $actualReproduction = @($Candidate.reproduction.PSObject.Properties.Name)
    if ($actualReproduction.Count -ne 8 -or
        @(Compare-Object $actualReproduction $expectedReproduction -CaseSensitive).Count -ne 0 -or
        $Candidate.reproduction.check_mode -or
        $Candidate.reproduction.repository_mount -ne 'read-only' -or
        $Candidate.reproduction.network -ne 'none' -or $Candidate.reproduction.capabilities -ne 'none' -or
        -not $Candidate.reproduction.no_new_privileges -or
        $Candidate.reproduction.builder_reference -cne 'tmxy-backend-builder:p0-08' -or
        $Candidate.reproduction.builder_id -cne
            'sha256:95f30cbb0f406f387a8aa0d4d56323105610ad6fc0629196bc5074847cac90a9' -or
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
$auxSemanticBinding = $report.input_bindings.aux_semantic_diagnostics
$auxPackageContextBinding = $report.input_bindings.aux_package_context
$auxEcfParserParityBinding = $report.input_bindings.aux_ecf_parser_parity
$auxMalformedXmlBinding = $report.input_bindings.aux_malformed_xml_diagnostics
$identityNormalizationBinding = $report.input_bindings.identity_normalization_safety
$bindingFailureBinding = $report.input_bindings.binding_failure_diagnostics
$bindingRecoveryBinding = $report.input_bindings.binding_recovery
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
    $auxSemanticBinding.task_id -eq $policy.aux_semantic_diagnostics.task_id -and
    $auxSemanticBinding.criterion_id -eq $policy.aux_semantic_diagnostics.criterion_id -and
    $auxSemanticBinding.evidence_revision -eq $policy.aux_semantic_diagnostics.evidence_revision -and
    $auxSemanticBinding.path -eq $policy.aux_semantic_diagnostics.path -and
    $auxSemanticBinding.sha256 -eq (Get-Sha256 $auxSemanticDiagnosticPath) -and
    $auxSemanticDiagnostic.evidence_revision -eq 'P2-20A.5' -and
    $auxSemanticDiagnostic.review_execution_result -eq 'PASS' -and
    $auxSemanticDiagnostic.diagnostic_scope_complete -eq $true -and
    $auxSemanticDiagnostic.scope_complete -eq $false -and
    $auxSemanticDiagnostic.result -eq 'BLOCKED' -and
    $auxSemanticDiagnostic.g2_06_satisfied -eq $false
$aggregateLines.Add("AUX_SEMANTIC|$($auxSemanticBinding.task_id)|$($auxSemanticBinding.criterion_id)|$($auxSemanticBinding.evidence_revision)|$($auxSemanticBinding.path)|$($auxSemanticBinding.sha256)")
$bindingsPassed = $bindingsPassed -and
    @($auxPackageContextBinding.PSObject.Properties.Name).Count -eq 12 -and
    @(Compare-Object @($auxPackageContextBinding.PSObject.Properties.Name) @(
            'task_id', 'criterion_id', 'evidence_revision', 'path', 'sha256', 'result',
            'review_execution_result', 'task_status', 'completion_criteria_satisfied',
            'diagnostic_scope_complete', 'scope_complete', 'g2_06_satisfied')).Count -eq 0 -and
    $auxPackageContextBinding.task_id -eq $policy.aux_package_context.task_id -and
    $auxPackageContextBinding.criterion_id -eq $policy.aux_package_context.criterion_id -and
    $auxPackageContextBinding.evidence_revision -eq $policy.aux_package_context.evidence_revision -and
    $auxPackageContextBinding.path -eq $policy.aux_package_context.path -and
    $auxPackageContextBinding.sha256 -eq (Get-Sha256 $auxPackageContextPath) -and
    $auxPackageContext.task_id -eq 'P2-20A' -and
    $auxPackageContext.criterion_id -eq 'G2-06' -and
    $auxPackageContext.evidence_revision -eq 'P2-20A.9' -and
    $auxPackageContext.result -eq 'BLOCKED' -and
    $auxPackageContext.review_execution_result -eq 'PASS' -and
    $auxPackageContext.task_status -eq 'BLOCKED' -and
    $auxPackageContext.completion_criteria_satisfied -eq $false -and
    $auxPackageContext.diagnostic_scope_complete -eq $true -and
    $auxPackageContext.scope_complete -eq $false -and
    $auxPackageContext.g2_06_satisfied -eq $false -and
    $auxPackageContext.p3_authorized -eq $false -and
    $auxPackageContextBinding.result -eq $auxPackageContext.result -and
    $auxPackageContextBinding.review_execution_result -eq
        $auxPackageContext.review_execution_result -and
    $auxPackageContextBinding.task_status -eq $auxPackageContext.task_status -and
    $auxPackageContextBinding.completion_criteria_satisfied -eq
        $auxPackageContext.completion_criteria_satisfied -and
    $auxPackageContextBinding.diagnostic_scope_complete -eq
        $auxPackageContext.diagnostic_scope_complete -and
    $auxPackageContextBinding.scope_complete -eq $auxPackageContext.scope_complete -and
    $auxPackageContextBinding.g2_06_satisfied -eq $auxPackageContext.g2_06_satisfied
$aggregateLines.Add("AUX_PACKAGE_CONTEXT|$($auxPackageContextBinding.task_id)|$($auxPackageContextBinding.criterion_id)|$($auxPackageContextBinding.evidence_revision)|$($auxPackageContextBinding.path)|$($auxPackageContextBinding.sha256)")
$bindingsPassed = $bindingsPassed -and
    @($auxEcfParserParityBinding.PSObject.Properties.Name).Count -eq 12 -and
    @(Compare-Object @($auxEcfParserParityBinding.PSObject.Properties.Name) @(
            'task_id', 'criterion_id', 'evidence_revision', 'path', 'sha256', 'result',
            'review_execution_result', 'task_status', 'completion_criteria_satisfied',
            'diagnostic_scope_complete', 'scope_complete', 'g2_06_satisfied')).Count -eq 0 -and
    $auxEcfParserParityBinding.task_id -eq $policy.aux_ecf_parser_parity.task_id -and
    $auxEcfParserParityBinding.criterion_id -eq $policy.aux_ecf_parser_parity.criterion_id -and
    $auxEcfParserParityBinding.evidence_revision -eq
        $policy.aux_ecf_parser_parity.evidence_revision -and
    $auxEcfParserParityBinding.path -eq $policy.aux_ecf_parser_parity.path -and
    $auxEcfParserParityBinding.sha256 -eq (Get-Sha256 $auxEcfParserParityPath) -and
    $auxEcfParserParity.evidence_revision -eq 'P2-20A.10' -and
    $auxEcfParserParity.result -eq 'BLOCKED' -and
    $auxEcfParserParity.review_execution_result -eq 'PASS' -and
    $auxEcfParserParity.task_status -eq 'BLOCKED' -and
    $auxEcfParserParity.completion_criteria_satisfied -eq $false -and
    $auxEcfParserParity.diagnostic_scope_complete -eq $true -and
    $auxEcfParserParity.scope_complete -eq $false -and
    $auxEcfParserParity.g2_06_satisfied -eq $false -and
    $auxEcfParserParityBinding.result -eq $auxEcfParserParity.result -and
    $auxEcfParserParityBinding.review_execution_result -eq
        $auxEcfParserParity.review_execution_result -and
    $auxEcfParserParityBinding.task_status -eq $auxEcfParserParity.task_status -and
    $auxEcfParserParityBinding.completion_criteria_satisfied -eq
        $auxEcfParserParity.completion_criteria_satisfied -and
    $auxEcfParserParityBinding.diagnostic_scope_complete -eq
        $auxEcfParserParity.diagnostic_scope_complete -and
    $auxEcfParserParityBinding.scope_complete -eq $auxEcfParserParity.scope_complete -and
    $auxEcfParserParityBinding.g2_06_satisfied -eq $auxEcfParserParity.g2_06_satisfied
$aggregateLines.Add("AUX_ECF_PARSER_PARITY|$($auxEcfParserParityBinding.task_id)|$($auxEcfParserParityBinding.criterion_id)|$($auxEcfParserParityBinding.evidence_revision)|$($auxEcfParserParityBinding.path)|$($auxEcfParserParityBinding.sha256)")
$bindingsPassed = $bindingsPassed -and (Test-G2MalformedXmlBinding $report $policy $root)
$aggregateLines.Add("AUX_MALFORMED_XML|P2-20A.11|$($auxMalformedXmlBinding.path)|$($auxMalformedXmlBinding.sha256)")
$bindingsPassed = $bindingsPassed -and
    $identityNormalizationBinding.task_id -eq $policy.identity_normalization_safety.task_id -and
    $identityNormalizationBinding.criterion_id -eq $policy.identity_normalization_safety.criterion_id -and
    $identityNormalizationBinding.evidence_revision -eq $policy.identity_normalization_safety.evidence_revision -and
    $identityNormalizationBinding.path -eq $policy.identity_normalization_safety.path -and
    $identityNormalizationBinding.sha256 -eq (Get-Sha256 $identityNormalizationPath) -and
    $identityNormalization.evidence_revision -eq 'P2-20A.6' -and
    $identityNormalization.review_execution_result -eq 'PASS' -and
    $identityNormalization.diagnostic_scope_complete -eq $true -and
    $identityNormalization.scope_complete -eq $false -and
    $identityNormalization.result -eq 'BLOCKED' -and
    $identityNormalization.g2_06_satisfied -eq $false -and
    $identityNormalization.measured.strict_full_semantic_equivalent_targets -eq 0 -and
    $identityNormalization.measured.candidate_selections -eq 0 -and
    $identityNormalization.measured.effective.ambiguous_targets -eq 15
$aggregateLines.Add("IDENTITY_NORMALIZATION|$($identityNormalizationBinding.task_id)|$($identityNormalizationBinding.criterion_id)|$($identityNormalizationBinding.evidence_revision)|$($identityNormalizationBinding.path)|$($identityNormalizationBinding.sha256)")
$bindingsPassed = $bindingsPassed -and $bindingFailureBinding.evidence_revision -eq 'P2-20A.7' -and
    $bindingFailureBinding.sha256 -eq (Get-Sha256 $bindingFailurePath) -and
    $bindingFailure.diagnostic_scope_complete -and -not $bindingFailure.remediation_scope_complete -and
    $bindingFailure.measured.typed_error_edges -eq 24 -and
    $bindingFailure.measured.effective.resolved_targets -eq 7 -and
    $bindingFailure.measured.effective.unresolved_targets -eq 12
$aggregateLines.Add("BINDING_FAILURE_DIAGNOSTICS|$($bindingFailureBinding.task_id)|$($bindingFailureBinding.criterion_id)|$($bindingFailureBinding.evidence_revision)|$($bindingFailureBinding.path)|$($bindingFailureBinding.sha256)")
$bindingsPassed = $bindingsPassed -and
    $bindingRecoveryBinding.evidence_revision -eq 'P2-20A.8' -and
    $bindingRecoveryBinding.sha256 -eq (Get-Sha256 $bindingRecoveryPath) -and
    $bindingRecovery.result -eq 'BLOCKED' -and
    $bindingRecovery.review_execution_result -eq 'PASS' -and
    $bindingRecovery.authority_boundary.a4_is_authoritative -eq $true -and
    $bindingRecovery.authority_boundary.a8_may_change_counts -eq $false -and
    $bindingRecovery.measured.successful.targets -eq 7 -and
    $bindingRecovery.measured.successful.candidate_edges -eq 9
$aggregateLines.Add("BINDING_RECOVERY|$($bindingRecoveryBinding.task_id)|$($bindingRecoveryBinding.criterion_id)|$($bindingRecoveryBinding.evidence_revision)|$($bindingRecoveryBinding.path)|$($bindingRecoveryBinding.sha256)")
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
Add-A 'All prerequisites supplemental diagnostics remediation and quality evidence are exactly SHA-256 bound' $bindingsPassed
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
    (Get-Metric $g206 'descriptor_diagnostic_resolved_targets') -eq 3450 -and
    (Get-Metric $g206 'descriptor_diagnostic_ambiguous_targets') -eq 189 -and
    (Get-Metric $g206 'descriptor_diagnostic_unresolved_targets') -eq 12 -and
    (Get-Metric $g206 'identity_normalization_hash_bound') -eq $true -and
    (Get-Metric $g206 'identity_case_fold_collision_targets') -eq 13 -and
    (Get-Metric $g206 'identity_case_fold_collision_edges') -eq 26 -and
    (Get-Metric $g206 'identity_non_case_targets') -eq 2 -and
    (Get-Metric $g206 'identity_non_case_edges') -eq 4 -and
    (Get-Metric $g206 'identity_strict_descriptor_equivalent_targets') -eq 0 -and
    (Get-Metric $g206 'identity_strict_full_semantic_equivalent_targets') -eq 0 -and
    (Get-Metric $g206 'identity_automatic_selected_targets') -eq 0 -and
    (Get-Metric $g206 'identity_retained_ambiguous_targets') -eq 15 -and
    (Get-Metric $g206 'identity_retained_ambiguous_edges') -eq 30 -and
    (Get-Metric $g206 'identity_retained_unresolved_targets') -eq 12 -and
    (Get-Metric $g206 'identity_retained_unresolved_edges') -eq 15 -and
    (Get-Metric $g206 'binding_recovery_cross_proof_hash_bound') -eq $true -and
    (Get-Metric $g206 'binding_recovery_attempted_targets') -eq 17 -and
    (Get-Metric $g206 'binding_recovery_attempted_edges') -eq 21 -and
    (Get-Metric $g206 'binding_recovery_successful_targets') -eq 7 -and
    (Get-Metric $g206 'binding_recovery_successful_edges') -eq 9 -and
    (Get-Metric $g206 'aux_semantic_diagnostic_hash_bound') -eq $true -and
    (Get-Metric $g206 'aux_semantic_scope_complete') -eq $false -and
    (Get-Metric $g206 'aux_semantic_g2_06_satisfied') -eq $false -and
    (Get-Metric $g206 'aux_semantic_unique_references') -eq 3180 -and
    (Get-Metric $g206 'aux_semantic_ambiguous_objects') -eq 211 -and
    (Get-Metric $g206 'aux_semantic_unresolved_resources') -eq 1 -and
    (Get-Metric $g206 'aux_semantic_ecf_parser_differences') -eq 3 -and
    (Get-Metric $g206 'aux_semantic_ecf_missed_assignments') -eq 4 -and
    (Get-Metric $g206 'aux_package_context_hash_bound') -eq $true -and
    (Get-Metric $g206 'aux_package_context_contract_proven') -eq $true -and
    (Get-Metric $g206 'aux_package_context_strict_ambiguous_objects') -eq 211 -and
    (Get-Metric $g206 'aux_package_context_original_candidate_edges') -eq 422 -and
    (Get-Metric $g206 'aux_package_context_singleton_matches') -eq 211 -and
    (Get-Metric $g206 'aux_package_context_first_candidate_selections') -eq 0 -and
    (Get-Metric $g206 'aux_package_context_effective_resolved') -eq 3391 -and
    (Get-Metric $g206 'aux_package_context_effective_ambiguous') -eq 0 -and
    (Get-Metric $g206 'aux_package_context_effective_unresolved') -eq 1 -and
    (Get-Metric $g206 'aux_package_context_consumer_clean_regions') -eq 134 -and
    (Get-Metric $g206 'aux_package_context_semantic_adapter_approved') -eq $false -and
    (Get-Metric $g206 'aux_package_context_terminal_instances') -eq 0 -and
    (Get-Metric $g206 'aux_ecf_parser_parity_hash_bound') -eq $true -and
    (Get-Metric $g206 'aux_ecf_historical_a5_parity_instances') -eq 61 -and
    (Get-Metric $g206 'aux_ecf_historical_a5_difference_instances') -eq 3 -and
    (Get-Metric $g206 'aux_ecf_historical_a5_pair_count_delta') -eq 4 -and
    (Get-Metric $g206 'aux_ecf_a3_actual_parity_instances') -eq 51 -and
    (Get-Metric $g206 'aux_ecf_a3_actual_difference_instances') -eq 13 -and
    (Get-Metric $g206 'aux_ecf_correct_plain_filter_parity_instances') -eq 63 -and
    (Get-Metric $g206 'aux_ecf_legacy_pair_records_absent_from_a3') -eq 4 -and
    (Get-Metric $g206 'aux_ecf_reference_transform_port_differences') -eq 0 -and
    (Get-Metric $g206 'aux_ecf_reference_pair_port_differences') -eq 0 -and
    (Get-Metric $g206 'aux_ecf_legacy_runtime_executed') -eq $false -and
    (Get-Metric $g206 'aux_ecf_runtime_binary_parity_claimed') -eq $false -and
    (Get-Metric $g206 'aux_ecf_a3_outputs_modified') -eq $false -and
    (Get-Metric $g206 'aux_ecf_semantic_imports_claimed') -eq 0 -and
    (Get-Metric $g206 'aux_malformed_xml_diagnostic_hash_bound') -eq $true -and
    (Get-Metric $g206 'aux_malformed_xml_contract_safe') -eq $true -and
    (Get-Metric $g206 'aux_malformed_xml_closure_ready') -eq $false -and
    (Get-Metric $g206 'aux_malformed_xml_instances') -eq 6 -and
    (Get-Metric $g206 'aux_malformed_xml_strict_document_rejections') -eq 6 -and
    (Get-Metric $g206 'aux_malformed_xml_elementtree_rejections') -eq 6 -and
    (Get-Metric $g206 'aux_malformed_xml_tinyxml_api_successes') -eq 6 -and
    (Get-Metric $g206 'aux_malformed_xml_tinyxml_full_consumption') -eq 5 -and
    (Get-Metric $g206 'aux_malformed_xml_tinyxml_silent_partial') -eq 1 -and
    (Get-Metric $g206 'aux_malformed_xml_client_input_termination_proven') -eq $false -and
    (Get-Metric $g206 'aux_malformed_xml_legacy_runtime_executed') -eq $false -and
    $supplemental.closure.asset_binding_resolution_explicit -eq $true -and
    $supplemental.closure.asset_binding.resolution_explicit -eq $true -and
    $supplemental.closure.asset_binding.resolved_targets -eq 21293 -and
    $supplemental.closure.asset_binding.ambiguous_targets -eq 189 -and
    $supplemental.closure.asset_binding.unresolved_targets -eq 12 -and
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
    (Get-Metric $g206 'asset_binding_resolved_targets') -eq 21293 -and
    (Get-Metric $g206 'asset_binding_ambiguous_targets') -eq 189 -and
    (Get-Metric $g206 'asset_binding_unresolved_targets') -eq 12 -and
    (Get-Metric $g206 'asset_binding_unknown_targets') -eq 0 -and
    (Get-Metric $g206 'asset_binding_workset_hash_bound') -eq $true -and
    (Get-Metric $g206 'first_candidate_selection_used') -eq $false -and
    (Get-Metric $g206 'asset_structure_unresolved') -eq 18 -and
    (Get-Metric $g206 'unknown_record_count') -eq 0 -and
    (Get-Metric $g206 'unknown_resolution_count') -eq 0 -and
    (Get-Metric $g206 'core_foreign_key_dangling_context') -eq 0 -and
    $g206.interpretation -match 'hash-bound core, descriptor' -and
    $g206.interpretation -match 'A\.9 resolves 3,391 consumer occurrences' -and
    $g206.interpretation -match 'A.7 classifies all 24 strict rejected asset candidate edges' -and
    $g206.interpretation -match 'A.8 cross-proves 7 targets / 9 edges' -and
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
    @($report.blockers | Where-Object {
            ([string]$_.reason -replace '4 legacy pair records absent from A\.3', '') -match
                '\babsent\b|\bmissing evidence\b'
        }).Count -eq 0 -and
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
$negativeCases = & $negativeCasesHelperPath `
    -Report $report `
    -Policy $policy `
    -Supplemental $supplemental `
    -AuxiliaryReport $auxiliaryReport `
    -Evidence $evidence `
    -Root $root `
    -SupplementalPath $supplementalPath `
    -DescriptorDiagnosticPath $descriptorDiagnosticPath `
    -AuxSemanticDiagnosticPath $auxSemanticDiagnosticPath `
    -AuxPackageContextPath $auxPackageContextPath `
    -AuxEcfParserParityPath $auxEcfParserParityPath `
    -AuxMalformedXmlPath $auxMalformedXmlPath `
    -IdentityNormalizationPath $identityNormalizationPath `
    -RemediationPath $remediationPath
Add-A 'Policy supplemental scope FK migration approval drift and unknown-field negatives fail closed' (
    $negativeCases.Count -eq 71 -and
    @($negativeCases.Values | Where-Object { $_ -ne $true }).Count -eq 0)
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
