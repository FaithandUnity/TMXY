[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][object]$Report,
    [Parameter(Mandatory = $true)][object]$Policy,
    [Parameter(Mandatory = $true)][object]$Supplemental,
    [Parameter(Mandatory = $true)][object]$AuxiliaryReport,
    [Parameter(Mandatory = $true)][object]$Evidence,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$SupplementalPath,
    [Parameter(Mandatory = $true)][string]$DescriptorDiagnosticPath,
    [Parameter(Mandatory = $true)][string]$AuxSemanticDiagnosticPath,
    [Parameter(Mandatory = $true)][string]$AuxPackageContextPath,
    [Parameter(Mandatory = $true)][string]$AuxEcfParserParityPath,
    [Parameter(Mandatory = $true)][string]$AuxMalformedXmlPath,
    [Parameter(Mandatory = $true)][string]$IdentityNormalizationPath,
    [Parameter(Mandatory = $true)][string]$RemediationPath
)

Set-StrictMode -Version Latest

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
        'asset_binding_ambiguous_targets') -eq 189 -and
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
$missingAuxSemanticSha = Copy-JsonObject $report
[void]$missingAuxSemanticSha.input_bindings.aux_semantic_diagnostics.PSObject.Properties.Remove('sha256')
$negativeCases.missing_aux_semantic_sha_rejected = -not (Test-AgainstSchema $missingAuxSemanticSha)
$badAuxSemanticSha = Copy-JsonObject $report
$badAuxSemanticSha.input_bindings.aux_semantic_diagnostics.sha256 = '0' * 64
$negativeCases.aux_semantic_sha_tamper_rejected =
    (Test-AgainstSchema $badAuxSemanticSha) -and
    $badAuxSemanticSha.input_bindings.aux_semantic_diagnostics.sha256 -ne
        (Get-Sha256 $auxSemanticDiagnosticPath)
$badAuxSemanticReady = Copy-JsonObject $report
Set-Metric (Get-Criterion $badAuxSemanticReady 'G2-06') 'aux_semantic_scope_complete' $true
Set-Metric (Get-Criterion $badAuxSemanticReady 'G2-06') 'aux_semantic_g2_06_satisfied' $true
$negativeCases.aux_semantic_false_readiness_rejected =
    (Test-AgainstSchema $badAuxSemanticReady) -and
    -not (Test-G2Semantics $badAuxSemanticReady $policy)
$missingAuxPackageContextSha = Copy-JsonObject $report
[void]$missingAuxPackageContextSha.input_bindings.aux_package_context.PSObject.Properties.Remove(
    'sha256')
$negativeCases.missing_aux_package_context_sha_rejected =
    -not (Test-AgainstSchema $missingAuxPackageContextSha)
$badAuxPackageContextSha = Copy-JsonObject $report
$badAuxPackageContextSha.input_bindings.aux_package_context.sha256 = '0' * 64
$negativeCases.aux_package_context_sha_tamper_rejected =
    (Test-AgainstSchema $badAuxPackageContextSha) -and
    $badAuxPackageContextSha.input_bindings.aux_package_context.sha256 -ne
        (Get-Sha256 $auxPackageContextPath)
$badAuxPackageContextReady = Copy-JsonObject $report
Set-Metric (Get-Criterion $badAuxPackageContextReady 'G2-06') `
    'aux_package_context_effective_unresolved' 0
$negativeCases.aux_package_context_false_readiness_rejected =
    (Test-AgainstSchema $badAuxPackageContextReady) -and
    -not (Test-G2Semantics $badAuxPackageContextReady $policy)
$badAuxPackageContextAuthority = Copy-JsonObject $report
Set-Metric (Get-Criterion $badAuxPackageContextAuthority 'G2-06') `
    'aux_package_context_semantic_adapter_approved' $true
Set-Metric (Get-Criterion $badAuxPackageContextAuthority 'G2-06') `
    'aux_package_context_terminal_instances' 212
$negativeCases.aux_package_context_false_authority_rejected =
    (Test-AgainstSchema $badAuxPackageContextAuthority) -and
    -not (Test-G2Semantics $badAuxPackageContextAuthority $policy)
$missingAuxEcfParserParitySha = Copy-JsonObject $report
[void]$missingAuxEcfParserParitySha.input_bindings.aux_ecf_parser_parity.PSObject.Properties.Remove(
    'sha256')
$negativeCases.missing_aux_ecf_parser_parity_sha_rejected =
    -not (Test-AgainstSchema $missingAuxEcfParserParitySha)
$badAuxEcfParserParitySha = Copy-JsonObject $report
$badAuxEcfParserParitySha.input_bindings.aux_ecf_parser_parity.sha256 = '0' * 64
$negativeCases.aux_ecf_parser_parity_sha_tamper_rejected =
    (Test-AgainstSchema $badAuxEcfParserParitySha) -and
    $badAuxEcfParserParitySha.input_bindings.aux_ecf_parser_parity.sha256 -ne
        (Get-Sha256 $AuxEcfParserParityPath)
$falseLegacyRuntime = Copy-JsonObject $report
Set-Metric (Get-Criterion $falseLegacyRuntime 'G2-06') `
    'aux_ecf_legacy_runtime_executed' $true
$negativeCases.aux_ecf_false_legacy_runtime_rejected =
    (Test-AgainstSchema $falseLegacyRuntime) -and
    -not (Test-G2Semantics $falseLegacyRuntime $policy)
$falseBinaryParity = Copy-JsonObject $report
Set-Metric (Get-Criterion $falseBinaryParity 'G2-06') `
    'aux_ecf_runtime_binary_parity_claimed' $true
$negativeCases.aux_ecf_false_binary_parity_rejected =
    (Test-AgainstSchema $falseBinaryParity) -and
    -not (Test-G2Semantics $falseBinaryParity $policy)
$falseSemanticImports = Copy-JsonObject $report
Set-Metric (Get-Criterion $falseSemanticImports 'G2-06') `
    'aux_ecf_semantic_imports_claimed' 4
$negativeCases.aux_ecf_false_semantic_imports_rejected =
    (Test-AgainstSchema $falseSemanticImports) -and
    -not (Test-G2Semantics $falseSemanticImports $policy)
$missingMalformedSha = Copy-JsonObject $report
[void]$missingMalformedSha.input_bindings.aux_malformed_xml_diagnostics.PSObject.Properties.Remove('sha256')
$negativeCases.malformed_xml_missing_sha_rejected = -not (Test-AgainstSchema $missingMalformedSha)
$badMalformedSha = Copy-JsonObject $report
$badMalformedSha.input_bindings.aux_malformed_xml_diagnostics.sha256 = '0' * 64
$negativeCases.malformed_xml_sha_drift_rejected =
    (Test-AgainstSchema $badMalformedSha) -and
    -not (Test-G2MalformedXmlBinding $badMalformedSha $Policy $Root)
$malformedRuntime = Copy-JsonObject $report
Set-Metric (Get-Criterion $malformedRuntime 'G2-06') `
    'aux_malformed_xml_legacy_runtime_executed' $true
$negativeCases.malformed_xml_runtime_promotion_rejected =
    -not (Test-G2Semantics $malformedRuntime $policy)
$malformedBinary = Copy-JsonObject $report
Set-Metric (Get-Criterion $malformedBinary 'G2-06') `
    'aux_malformed_xml_runtime_binary_parity_claimed' $true
$negativeCases.malformed_xml_binary_promotion_rejected =
    -not (Test-G2Semantics $malformedBinary $policy)
$malformedPartial = Copy-JsonObject $report
Set-Metric (Get-Criterion $malformedPartial 'G2-06') `
    'aux_malformed_xml_tinyxml_silent_partial' 0
$negativeCases.malformed_xml_partial_hiding_rejected =
    -not (Test-G2Semantics $malformedPartial $policy)
$malformedClosure = Copy-JsonObject $report
Set-Metric (Get-Criterion $malformedClosure 'G2-06') `
    'aux_malformed_xml_closure_ready' $true
$negativeCases.malformed_xml_contract_safe_as_closure_rejected =
    -not (Test-G2Semantics $malformedClosure $policy)
$malformedExtraMetric = Copy-JsonObject $report
$extraMetric = [pscustomobject][ordered]@{
    name = 'aux_malformed_xml_optimistic_extension'; value = 0; unit = 'count'
}
$malformedExtraMetric.criteria[5].metrics += $extraMetric
$negativeCases.malformed_xml_extra_metric_rejected =
    -not (Test-G2Semantics $malformedExtraMetric $policy)
$malformedGenericMetric = Copy-JsonObject $report
$malformedGenericMetric.criteria[5].metrics += [pscustomobject][ordered]@{
    name = 'malformed_xml_runtime_parity_proven'; value = $true; unit = 'boolean'
}
$negativeCases.malformed_xml_generic_metric_injection_rejected =
    -not (Test-G2Semantics $malformedGenericMetric $policy)
$malformedWrongUnit = Copy-JsonObject $report
@($malformedWrongUnit.criteria[5].metrics |
    Where-Object name -eq 'aux_malformed_xml_semantic_imports_claimed')[0].unit = 'boolean'
$negativeCases.malformed_xml_numeric_claim_unit_rejected =
    -not (Test-G2Semantics $malformedWrongUnit $policy)
$malformedNul = Copy-JsonObject $report
Set-Metric (Get-Criterion $malformedNul 'G2-06') `
    'aux_malformed_xml_client_input_termination_proven' $true
$negativeCases.malformed_xml_nul_forgery_rejected =
    -not (Test-G2Semantics $malformedNul $policy)
foreach ($case in @(
        @('repair_injection', 'aux_malformed_xml_repairs'),
        @('disposition_injection', 'aux_malformed_xml_dispositions'),
        @('semantic_import_injection', 'aux_malformed_xml_semantic_imports_claimed'),
        @('root_injection', 'aux_malformed_xml_approved_roots'))) {
    $candidate = Copy-JsonObject $report
    Set-Metric (Get-Criterion $candidate 'G2-06') $case[1] 1
    $negativeCases["malformed_xml_$($case[0])_rejected"] =
        -not (Test-G2Semantics $candidate $policy)
}
$malformedDocument = Get-Content -LiteralPath $AuxMalformedXmlPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$detailDrift = Copy-JsonObject $malformedDocument
$detailDrift.detail_export.sha256 = '0' * 64
$negativeCases.malformed_xml_detail_hash_drift_rejected =
    -not (Test-G2MalformedXmlDocument $detailDrift $Root)
$sourceDrift = Copy-JsonObject $malformedDocument
$sourceDrift.input_bindings.entries[0].sha256 = '0' * 64
$negativeCases.malformed_xml_source_hash_drift_rejected =
    -not (Test-G2MalformedXmlDocument $sourceDrift $Root)
$legacyDrift = Copy-JsonObject $malformedDocument
$legacyDrift.input_bindings.legacy_sources[0].sha256 = '0' * 64
$negativeCases.malformed_xml_legacy_hash_drift_rejected =
    -not (Test-G2MalformedXmlDocument $legacyDrift $Root)
$a11AggregateDrift = Copy-JsonObject $malformedDocument
$a11AggregateDrift.input_bindings.aggregate_sha256 = '0' * 64
$negativeCases.malformed_xml_input_aggregate_drift_rejected =
    -not (Test-G2MalformedXmlDocument $a11AggregateDrift $Root)
$legacyDuplicate = Copy-JsonObject $malformedDocument
$legacyDuplicate.input_bindings.legacy_sources[1].role =
    $legacyDuplicate.input_bindings.legacy_sources[0].role
$negativeCases.malformed_xml_legacy_role_duplicate_rejected =
    -not (Test-G2MalformedXmlDocument $legacyDuplicate $Root)
$boundaryPromotion = Copy-JsonObject $malformedDocument
$boundaryPromotion.source_derived_tinyxml.evidence_boundary.runtime_parity_claimed = $true
$negativeCases.malformed_xml_boundary_promotion_rejected =
    -not (Test-G2MalformedXmlDocument $boundaryPromotion $Root)
$environmentDrift = Copy-JsonObject $malformedDocument
$environmentDrift.source_derived_tinyxml.execution_environment.toolchain_lock_sha256 = '0' * 64
$negativeCases.malformed_xml_environment_drift_rejected =
    -not (Test-G2MalformedXmlDocument $environmentDrift $Root)
$coordinatedEnvironmentForgery = Copy-JsonObject $malformedDocument
$forgedEnvironment = $coordinatedEnvironmentForgery.source_derived_tinyxml.execution_environment
$forgedEnvironment.builder_image_reference = 'tmxy-backend-builder:forged'
$forgedEnvironment.compiler_version_output_sha256 = '0' * 64
$forgedEnvironment.client_source_set_sha256 = '1' * 64
$forgedEnvironment.server_source_set_sha256 = '2' * 64
$negativeCases.malformed_xml_coordinated_environment_forgery_rejected =
    -not (Test-G2MalformedXmlDocument $coordinatedEnvironmentForgery $Root)
$unknownMalformed = Copy-JsonObject $malformedDocument
$unknownMalformed.source_derived_tinyxml.execution_environment |
    Add-Member -NotePropertyName runtime_safe -NotePropertyValue $true
$negativeCases.malformed_xml_unknown_field_rejected =
    -not (Test-G2MalformedXmlDocument $unknownMalformed $Root)
$missingIdentitySha = Copy-JsonObject $report
[void]$missingIdentitySha.input_bindings.identity_normalization_safety.PSObject.Properties.Remove('sha256')
$negativeCases.missing_identity_normalization_sha_rejected =
    -not (Test-AgainstSchema $missingIdentitySha)
$badIdentitySha = Copy-JsonObject $report
$badIdentitySha.input_bindings.identity_normalization_safety.sha256 = '0' * 64
$negativeCases.identity_normalization_sha_tamper_rejected =
    (Test-AgainstSchema $badIdentitySha) -and
    $badIdentitySha.input_bindings.identity_normalization_safety.sha256 -ne
        (Get-Sha256 $identityNormalizationPath)
$falseIdentityEquivalence = Copy-JsonObject $report
Set-Metric (Get-Criterion $falseIdentityEquivalence 'G2-06') `
    'identity_strict_full_semantic_equivalent_targets' 1
$negativeCases.identity_false_equivalence_rejected =
    (Test-AgainstSchema $falseIdentityEquivalence) -and
    -not (Test-G2Semantics $falseIdentityEquivalence $policy)
$falseIdentitySelection = Copy-JsonObject $report
Set-Metric (Get-Criterion $falseIdentitySelection 'G2-06') `
    'identity_automatic_selected_targets' 1
$negativeCases.identity_candidate_selection_rejected =
    (Test-AgainstSchema $falseIdentitySelection) -and
    -not (Test-G2Semantics $falseIdentitySelection $policy)
$falseIdentityReduction = Copy-JsonObject $report
Set-Metric (Get-Criterion $falseIdentityReduction 'G2-06') `
    'identity_retained_ambiguous_targets' 14
$negativeCases.identity_ambiguous_reduction_rejected =
    (Test-AgainstSchema $falseIdentityReduction) -and
    -not (Test-G2Semantics $falseIdentityReduction $policy)
$missingFailureSha = Copy-JsonObject $report
[void]$missingFailureSha.input_bindings.binding_failure_diagnostics.PSObject.Properties.Remove('sha256')
$negativeCases.missing_binding_failure_sha_rejected = -not (Test-AgainstSchema $missingFailureSha)
$falseFailureRemediation = Copy-JsonObject $report
Set-Metric (Get-Criterion $falseFailureRemediation 'G2-06') 'binding_failure_remediation_scope_complete' $true
$negativeCases.binding_failure_false_remediation_rejected = -not (Test-G2Semantics $falseFailureRemediation $policy)
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
$badBuilderReference = Copy-JsonObject $evidence
$badBuilderReference.reproduction.builder_reference = 'tmxy-backend-builder:unbound'
$negativeCases.evidence_builder_reference_drift_rejected =
    -not (Test-EvidenceSemantics $badBuilderReference)
$badBuilderId = Copy-JsonObject $evidence
$badBuilderId.reproduction.builder_id = 'sha256:' + ('0' * 64)
$negativeCases.evidence_builder_id_drift_rejected =
    -not (Test-EvidenceSemantics $badBuilderId)
$unknownReproduction = Copy-JsonObject $evidence
$unknownReproduction.reproduction |
    Add-Member -NotePropertyName runtime_safe -NotePropertyValue $true
$negativeCases.evidence_reproduction_unknown_field_rejected =
    -not (Test-EvidenceSemantics $unknownReproduction)

return ,$negativeCases
