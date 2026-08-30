[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20 temporary root escaped Rebuild.'
}
$runRoot = Join-Path $localRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length + 1)).Replace('\', '/')
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Get-TextSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Copy-Output([string]$Source, [string]$Target) {
    $directory = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
}

try {
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2Review'
    . (Join-Path $root 'Tests\Contract\G2Review-QtxDeclaredMipPrefixCases.ps1')
    $generatorPath = Join-Path $moduleRoot 'g2_review.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-review-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-review-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generatorPath, $policyPath, $schemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20 input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20 requires the qualified non-root Clang 21 builder image.'
    }

    $jsonName = 'p2-20-g2-review-report.json'
    $markdownName = 'p2-20-g2-review-report.md'
    $generatedJson = Join-Path $runRoot $jsonName
    $generatedMarkdown = Join-Path $runRoot $markdownName
    $trackedJson = Join-Path $root "Data\Reports\$jsonName"
    $trackedMarkdown = Join-Path $root "Data\Reports\$markdownName"
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $arguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=32m',
        $builderReference, 'python3', '/workspace/Tools/TMXY.G2Review/g2_review.py',
        '--root', '/workspace',
        '--policy', '/workspace/Contracts/data-schema/g2-review-policy-v1.json',
        '--schema', '/workspace/Contracts/data-schema/g2-review-v1.schema.json',
        '--json-output', "/output/$jsonName",
        '--markdown-output', "/output/$markdownName"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20 isolated report generation failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfText = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$root,dst=/workspace,readonly" `
        $builderReference python3 /workspace/Tools/TMXY.G2Review/g2_review.py --self-test
    if ($LASTEXITCODE -ne 0) { throw 'P2-20 generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json -Depth 100
    $summaryApproved = [int]$summary.blocked -eq 0
    $expectedResult = if ($summaryApproved) { 'PASS' } else { 'BLOCKED' }
    if ($summary.result -ne $expectedResult -or $summary.review_execution_result -ne 'PASS' -or
        [int]$summary.satisfied + [int]$summary.blocked -ne 9 -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -lt 10) {
        throw 'P2-20 generator summary or self-test failed.'
    }
    $valid = Get-Content -LiteralPath $generatedJson -Raw -Encoding UTF8 |
        Test-Json -SchemaFile $schemaPath
    if (-not $valid) { throw 'P2-20 generated report failed its closed JSON Schema.' }

    $targets = [ordered]@{ json = $trackedJson; markdown = $trackedMarkdown }
    $generated = [ordered]@{ json = $generatedJson; markdown = $generatedMarkdown }
    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked P2-20 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    $report = Get-Content -LiteralPath $trackedJson -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $descriptorDiagnostic = Get-Content -LiteralPath (Join-Path $root 'Data\Reports\p2-20a-asset-descriptor-diagnostics-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
    $bindingFailure = Get-Content -LiteralPath (Join-Path $root 'Data\Reports\p2-20a-asset-binding-failure-diagnostics-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
    $bindingRecovery = Get-Content -LiteralPath (Join-Path $root 'Data\Reports\p2-20a-asset-binding-recovery-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
    $descriptorMeasured = $descriptorDiagnostic.measured
    $descriptorReconciled = $descriptorMeasured.reconciled_full_workset
    $bindingFailureEffective = $bindingFailure.measured.effective
    $bindingRecoveryMeasured = $bindingRecovery.measured
    $g206 = @($report.criteria | Where-Object id -eq 'G2-06')
    if ($g206.Count -ne 1) { throw 'P2-20 G2-06 criterion is missing or duplicated.' }
    $g206Metrics = @{}
    foreach ($item in $g206[0].metrics) { $g206Metrics[[string]$item.name] = $item.value }
    if ($g206Metrics.auxiliary_reference_evidence_hash_bound -ne $true -or
        [int]$g206Metrics.auxiliary_file_instances -ne 212 -or
        [int]$g206Metrics.auxiliary_nonterminal_file_instances -ne 212 -or
        [int]$g206Metrics.auxiliary_candidate_only -ne 171 -or
        [int]$g206Metrics.auxiliary_editor_undecided -ne 35 -or
        [int]$g206Metrics.auxiliary_malformed_blocked -ne 6 -or
        [int]$g206Metrics.auxiliary_semantic_approved -ne 0 -or
        [int]$g206Metrics.auxiliary_no_ref_approved -ne 0 -or
        [int]$g206Metrics.auxiliary_approved_roots -ne 0 -or
        [string]$g206Metrics.auxiliary_semantic_status -ne 'UNASSESSED' -or
        $g206Metrics.auxiliary_config_closure_complete -ne $false -or
        $g206Metrics.auxiliary_cycle_detection_complete -ne $false) {
        throw 'P2-20 A.3 auxiliary evidence did not remain hash-bound and fail closed.'
    }
    if ($g206Metrics.descriptor_diagnostic_hash_bound -ne $true -or
        [int]$g206Metrics.descriptor_diagnostic_targets -ne [int]$descriptorDiagnostic.scope.targets -or
        [int]$g206Metrics.descriptor_diagnostic_candidate_edges -ne [int]$descriptorDiagnostic.scope.candidate_edges -or
        [int]$g206Metrics.descriptor_diagnostic_resolved_targets -ne [int]$descriptorMeasured.resolved_targets -or
        [int]$g206Metrics.descriptor_diagnostic_ambiguous_targets -ne [int]$descriptorMeasured.ambiguous_targets -or
        [int]$g206Metrics.descriptor_diagnostic_unresolved_targets -ne [int]$descriptorMeasured.unresolved_targets -or
        [int]$g206Metrics.asset_binding_resolved_targets -ne [int]$descriptorReconciled.resolved_targets -or
        [int]$g206Metrics.asset_binding_ambiguous_targets -ne [int]$descriptorReconciled.ambiguous_targets -or
        [int]$g206Metrics.asset_binding_unresolved_targets -ne [int]$descriptorReconciled.unresolved_targets) {
        throw 'P2-20 A.4 descriptor evidence did not remain hash-bound and fail closed.'
    }
    if ($g206Metrics.aux_semantic_diagnostic_hash_bound -ne $true -or
        $g206Metrics.aux_semantic_scope_complete -ne $false -or
        $g206Metrics.aux_semantic_g2_06_satisfied -ne $false -or
        [int]$g206Metrics.aux_semantic_unique_references -ne 3180 -or
        [int]$g206Metrics.aux_semantic_ambiguous_objects -ne 211 -or
        [int]$g206Metrics.aux_semantic_unresolved_resources -ne 1 -or
        [int]$g206Metrics.aux_semantic_ecf_parser_differences -ne 3 -or
        [int]$g206Metrics.aux_semantic_ecf_missed_assignments -ne 4) {
        throw 'P2-20 A.5 auxiliary semantic evidence did not remain hash-bound and fail closed.'
    }
    if ($g206Metrics.aux_package_context_hash_bound -ne $true -or
        $g206Metrics.aux_package_context_contract_proven -ne $true -or
        [int]$g206Metrics.aux_package_context_strict_ambiguous_objects -ne 211 -or
        [int]$g206Metrics.aux_package_context_original_candidate_edges -ne 422 -or
        [int]$g206Metrics.aux_package_context_singleton_matches -ne 211 -or
        [int]$g206Metrics.aux_package_context_first_candidate_selections -ne 0 -or
        [int]$g206Metrics.aux_package_context_effective_resolved -ne 3391 -or
        [int]$g206Metrics.aux_package_context_effective_ambiguous -ne 0 -or
        [int]$g206Metrics.aux_package_context_effective_unresolved -ne 1 -or
        [int]$g206Metrics.aux_package_context_consumer_clean_regions -ne 134 -or
        $g206Metrics.aux_package_context_semantic_adapter_approved -ne $false -or
        [int]$g206Metrics.aux_package_context_terminal_instances -ne 0) {
        throw 'P2-20 A.9 auxiliary package-context evidence drifted or crossed its authority boundary.'
    }
    $auxEcfBinding = $report.input_bindings.aux_ecf_parser_parity
    $auxEcfPath = Join-Path $root 'Data\Reports\p2-20a-aux-ecf-parser-parity-report.json'
    if ($auxEcfBinding.task_id -ne 'P2-20A' -or
        $auxEcfBinding.criterion_id -ne 'G2-06' -or
        $auxEcfBinding.evidence_revision -ne 'P2-20A.10' -or
        $auxEcfBinding.path -ne
            'Data/Reports/p2-20a-aux-ecf-parser-parity-report.json' -or
        $auxEcfBinding.sha256 -ne (Get-Sha256 $auxEcfPath) -or
        $auxEcfBinding.result -ne 'BLOCKED' -or
        $auxEcfBinding.review_execution_result -ne 'PASS' -or
        $auxEcfBinding.task_status -ne 'BLOCKED' -or
        $auxEcfBinding.completion_criteria_satisfied -ne $false -or
        $auxEcfBinding.diagnostic_scope_complete -ne $true -or
        $auxEcfBinding.scope_complete -ne $false -or
        $auxEcfBinding.g2_06_satisfied -ne $false -or
        $g206Metrics.aux_ecf_parser_parity_hash_bound -ne $true -or
        [int]$g206Metrics.aux_ecf_historical_a5_parity_instances -ne 61 -or
        [int]$g206Metrics.aux_ecf_historical_a5_difference_instances -ne 3 -or
        [int]$g206Metrics.aux_ecf_historical_a5_pair_count_delta -ne 4 -or
        [int]$g206Metrics.aux_ecf_a3_actual_parity_instances -ne 51 -or
        [int]$g206Metrics.aux_ecf_a3_actual_difference_instances -ne 13 -or
        [int]$g206Metrics.aux_ecf_correct_plain_filter_parity_instances -ne 63 -or
        [int]$g206Metrics.aux_ecf_legacy_pair_records_absent_from_a3 -ne 4 -or
        [int]$g206Metrics.aux_ecf_reference_transform_port_differences -ne 0 -or
        [int]$g206Metrics.aux_ecf_reference_pair_port_differences -ne 0 -or
        $g206Metrics.aux_ecf_legacy_runtime_executed -ne $false -or
        $g206Metrics.aux_ecf_runtime_binary_parity_claimed -ne $false -or
        $g206Metrics.aux_ecf_a3_outputs_modified -ne $false -or
        [int]$g206Metrics.aux_ecf_semantic_imports_claimed -ne 0) {
        throw 'P2-20 A.10 ECF parser-parity evidence drifted or crossed its authority boundary.'
    }
    $auxMalformedBinding = $report.input_bindings.aux_malformed_xml_diagnostics
    $auxMalformedPath = Join-Path $root `
        'Data\Reports\p2-20a-aux-malformed-xml-diagnostics-report.json'
    if ($auxMalformedBinding.task_id -ne 'P2-20A' -or
        $auxMalformedBinding.criterion_id -ne 'G2-06' -or
        $auxMalformedBinding.evidence_revision -ne 'P2-20A.11' -or
        $auxMalformedBinding.path -ne
            'Data/Reports/p2-20a-aux-malformed-xml-diagnostics-report.json' -or
        $auxMalformedBinding.sha256 -ne (Get-Sha256 $auxMalformedPath) -or
        $auxMalformedBinding.result -ne 'BLOCKED' -or
        $auxMalformedBinding.review_execution_result -ne 'PASS' -or
        $auxMalformedBinding.task_status -ne 'BLOCKED' -or
        $auxMalformedBinding.completion_criteria_satisfied -ne $false -or
        $auxMalformedBinding.diagnostic_scope_complete -ne $true -or
        $auxMalformedBinding.scope_complete -ne $false -or
        $auxMalformedBinding.g2_06_satisfied -ne $false -or
        $g206Metrics.aux_malformed_xml_diagnostic_hash_bound -ne $true -or
        $g206Metrics.aux_malformed_xml_contract_safe -ne $true -or
        $g206Metrics.aux_malformed_xml_closure_ready -ne $false -or
        [int]$g206Metrics.aux_malformed_xml_instances -ne 6 -or
        [int64]$g206Metrics.aux_malformed_xml_source_bytes -ne 1082028 -or
        [int]$g206Metrics.aux_malformed_xml_strict_document_rejections -ne 6 -or
        [int]$g206Metrics.aux_malformed_xml_strict_fragment_rejections -ne 6 -or
        [int]$g206Metrics.aux_malformed_xml_elementtree_rejections -ne 6 -or
        [int]$g206Metrics.aux_malformed_xml_tinyxml_api_successes -ne 6 -or
        [int]$g206Metrics.aux_malformed_xml_tinyxml_full_consumption -ne 5 -or
        [int]$g206Metrics.aux_malformed_xml_tinyxml_silent_partial -ne 1 -or
        [int]$g206Metrics.aux_malformed_xml_client_server_agreement -ne 6 -or
        [int]$g206Metrics.aux_malformed_xml_consumer_bound -ne 5 -or
        [int]$g206Metrics.aux_malformed_xml_consumer_unresolved -ne 1 -or
        $g206Metrics.aux_malformed_xml_client_input_termination_proven -ne $false -or
        $g206Metrics.aux_malformed_xml_legacy_runtime_executed -ne $false -or
        $g206Metrics.aux_malformed_xml_runtime_binary_parity_claimed -ne $false -or
        $g206Metrics.aux_malformed_xml_windows_crt_parity_claimed -ne $false -or
        [int]$g206Metrics.aux_malformed_xml_repairs -ne 0 -or
        [int]$g206Metrics.aux_malformed_xml_deletions -ne 0 -or
        [int]$g206Metrics.aux_malformed_xml_dispositions -ne 0 -or
        [int]$g206Metrics.aux_malformed_xml_approved_adapters -ne 0 -or
        [int]$g206Metrics.aux_malformed_xml_approved_no_reference -ne 0 -or
        [int]$g206Metrics.aux_malformed_xml_approved_roots -ne 0 -or
        [int]$g206Metrics.aux_malformed_xml_semantic_imports_claimed -ne 0 -or
        [int]$g206Metrics.aux_malformed_xml_terminal_dispositions -ne 0 -or
        [int]$g206Metrics.aux_malformed_xml_malformed_blocked -ne 6) {
        throw 'P2-20 A.11 malformed-XML diagnostic drifted or crossed its authority boundary.'
    }
    if ($g206Metrics.identity_normalization_hash_bound -ne $true -or
        [int]$g206Metrics.identity_case_fold_collision_targets -ne 13 -or
        [int]$g206Metrics.identity_case_fold_collision_edges -ne 26 -or
        [int]$g206Metrics.identity_non_case_targets -ne 2 -or
        [int]$g206Metrics.identity_non_case_edges -ne 4 -or
        [int]$g206Metrics.identity_strict_descriptor_equivalent_targets -ne 0 -or
        [int]$g206Metrics.identity_strict_full_semantic_equivalent_targets -ne 0 -or
        [int]$g206Metrics.identity_automatic_selected_targets -ne 0 -or
        [int]$g206Metrics.identity_retained_ambiguous_targets -ne 15 -or
        [int]$g206Metrics.identity_retained_ambiguous_edges -ne 30 -or
        [int]$g206Metrics.identity_retained_unresolved_targets -ne 6 -or
        [int]$g206Metrics.identity_retained_unresolved_edges -ne 9) {
        throw 'P2-20 A.6 identity-normalization evidence did not remain hash-bound and fail closed.'
    }
    if ($g206Metrics.binding_failure_diagnostic_hash_bound -ne $true -or
        $g206Metrics.binding_failure_diagnostic_scope_complete -ne $true -or
        $g206Metrics.binding_failure_remediation_scope_complete -ne $false -or
        [int]$g206Metrics.binding_failure_diagnosed_targets -ne [int]$bindingFailure.measured.diagnosed_targets -or
        [int]$g206Metrics.binding_failure_diagnosed_edges -ne [int]$bindingFailure.measured.diagnosed_candidate_edges -or
        [int]$g206Metrics.binding_failure_typed_error_edges -ne [int]$bindingFailure.measured.typed_error_edges -or
        [int]$g206Metrics.binding_failure_unclassified_error_edges -ne [int]$bindingFailure.measured.unclassified_error_edges -or
        [int]$g206Metrics.binding_failure_effective_resolved_targets -ne [int]$bindingFailureEffective.resolved_targets -or
        [int]$g206Metrics.binding_failure_effective_resolved_edges -ne [int]$bindingFailureEffective.resolved_edges -or
        [int]$g206Metrics.binding_failure_effective_ambiguous_targets -ne [int]$bindingFailureEffective.ambiguous_targets -or
        [int]$g206Metrics.binding_failure_effective_ambiguous_edges -ne [int]$bindingFailureEffective.ambiguous_edges -or
        [int]$g206Metrics.binding_failure_effective_unresolved_targets -ne [int]$bindingFailureEffective.unresolved_targets -or
        [int]$g206Metrics.binding_failure_effective_unresolved_edges -ne [int]$bindingFailureEffective.unresolved_edges -or
        [int]$g206Metrics.binding_failure_candidate_selections -ne 0 -or
        [int]$g206Metrics.binding_failure_automatic_resolutions -ne 0 -or
        [int]$g206Metrics.binding_failure_owner_dispositions -ne 0 -or
        $g206Metrics.binding_recovery_cross_proof_hash_bound -ne $true -or
        [int]$g206Metrics.binding_recovery_attempted_targets -ne [int]$bindingRecoveryMeasured.attempted.targets -or
        [int]$g206Metrics.binding_recovery_attempted_edges -ne [int]$bindingRecoveryMeasured.attempted.candidate_edges -or
        [int]$g206Metrics.binding_recovery_successful_targets -ne [int]$bindingRecoveryMeasured.successful.targets -or
        [int]$g206Metrics.binding_recovery_successful_edges -ne [int]$bindingRecoveryMeasured.successful.candidate_edges) {
        throw 'P2-20 A.7/A.8 binding diagnosis or recovery cross-proof drifted.'
    }
    $staticMeshPrefixBinding = $report.input_bindings.static_mesh_payload_section_prefix
    $staticMeshPrefixReport = Join-Path $root `
        'Data\Reports\p2-20a-static-mesh-payload-section-prefix-report.json'
    $staticMeshPrefixInventory = Join-Path $root `
        'Data\Inventory\p2-20a-static-mesh-payload-section-prefix.json'
    $staticMeshPrefixDetail = Join-Path $root `
        'Data\Exports\P2-20\p2-20a-static-mesh-payload-section-prefix.jsonl'
    $staticMeshPrefixDocument = Get-Content -LiteralPath $staticMeshPrefixReport `
        -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
    $staticMeshBlockers = $staticMeshPrefixDocument.preserved_blockers
    if ($staticMeshPrefixBinding.task_id -ne 'P2-20A' -or
        $staticMeshPrefixBinding.criterion_id -ne 'G2-06' -or
        $staticMeshPrefixBinding.evidence_revision -ne 'P2-20A.12' -or
        $staticMeshPrefixBinding.path -ne
            'Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.json' -or
        $staticMeshPrefixBinding.sha256 -ne (Get-Sha256 $staticMeshPrefixReport) -or
        $staticMeshPrefixBinding.inventory_path -ne
            'Data/Inventory/p2-20a-static-mesh-payload-section-prefix.json' -or
        $staticMeshPrefixBinding.inventory_sha256 -ne (Get-Sha256 $staticMeshPrefixInventory) -or
        $staticMeshPrefixBinding.detail_path -ne
            'Data/Exports/P2-20/p2-20a-static-mesh-payload-section-prefix.jsonl' -or
        $staticMeshPrefixBinding.detail_sha256 -ne (Get-Sha256 $staticMeshPrefixDetail) -or
        $staticMeshPrefixBinding.result -ne 'BLOCKED' -or
        $staticMeshPrefixBinding.review_execution_result -ne 'PASS_DIAGNOSTIC' -or
        $staticMeshPrefixBinding.task_status -ne 'BLOCKED' -or
        $staticMeshPrefixBinding.completion_criteria_satisfied -ne $false -or
        $staticMeshPrefixBinding.diagnostic_scope_complete -ne $true -or
        $staticMeshPrefixBinding.remediation_scope_complete -ne $false -or
        $staticMeshPrefixBinding.g2_06_satisfied -ne $false -or
        $g206Metrics.static_mesh_prefix_diagnostic_hash_bound -ne $true -or
        $g206Metrics.static_mesh_prefix_inventory_hash_bound -ne $true -or
        $g206Metrics.static_mesh_prefix_detail_hash_bound -ne $true -or
        $g206Metrics.static_mesh_prefix_source_derived_contract_proven -ne $true -or
        $g206Metrics.static_mesh_prefix_runtime_parity_proven -ne $false -or
        [int]$g206Metrics.static_mesh_prefix_targets -ne 1 -or
        [int]$g206Metrics.static_mesh_prefix_candidate_edges -ne 2 -or
        [int]$g206Metrics.static_mesh_prefix_strict_rejected_edges -ne 2 -or
        [int]$g206Metrics.static_mesh_prefix_explicit_prefix_pass_edges -ne 2 -or
        [int]$g206Metrics.static_mesh_prefix_payload_sections -ne 1 -or
        [int]$g206Metrics.static_mesh_prefix_material_slots -ne 2 -or
        [int]$g206Metrics.static_mesh_prefix_ignored_trailing_material_slots -ne 1 -or
        [int]$g206Metrics.static_mesh_prefix_candidate_selections -ne 0 -or
        [int]$g206Metrics.static_mesh_prefix_automatic_resolutions -ne 0 -or
        $g206Metrics.static_mesh_prefix_adapter_applied -ne $false -or
        $g206Metrics.static_mesh_prefix_authority_state_changed -ne $false -or
        $g206Metrics.static_mesh_prefix_recovery_applied -ne $false -or
        [int]$g206Metrics.static_mesh_prefix_preserved_ambiguous_targets -ne
            [int]$staticMeshBlockers.asset_effective_ambiguous_targets -or
        [int]$g206Metrics.static_mesh_prefix_preserved_ambiguous_edges -ne
            [int]$staticMeshBlockers.asset_effective_ambiguous_edges -or
        [int]$g206Metrics.static_mesh_prefix_preserved_unresolved_targets -ne
            [int]$staticMeshBlockers.asset_effective_unresolved_targets -or
        [int]$g206Metrics.static_mesh_prefix_preserved_unresolved_edges -ne
            [int]$staticMeshBlockers.asset_effective_unresolved_edges -or
        [int]$staticMeshBlockers.asset_effective_ambiguous_targets -ne
            [int]$descriptorReconciled.ambiguous_targets -or
        [int]$staticMeshBlockers.asset_effective_ambiguous_edges -ne
            [int]$descriptorReconciled.ambiguous_edges -or
        [int]$staticMeshBlockers.asset_effective_unresolved_targets -ne
            [int]$descriptorReconciled.unresolved_targets -or
        [int]$staticMeshBlockers.asset_effective_unresolved_edges -ne
            [int]$descriptorReconciled.unresolved_edges -or
        [int]$staticMeshBlockers.asset_effective_unresolved_targets -ne
            [int]$bindingFailureEffective.unresolved_targets -or
        [int]$staticMeshBlockers.asset_effective_unresolved_edges -ne
            [int]$bindingFailureEffective.unresolved_edges) {
        throw 'P2-20 A.12 prefix proof drifted or crossed its authority boundary.'
    }
    if (-not (Test-G2QtxDeclaredMipPrefixBinding $report `
                (Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String) $root)) {
        throw 'P2-20 A.13 QTX prefix proof drifted or crossed its authority boundary.'
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    $evidencePath = Join-Path $root 'Data\Inventory\p2-20-g2-review.json'
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [string]$report.captured_utc
        task_id = 'P2-20'
        result = [string]$report.result
        review_execution_result = 'PASS'
        task_status = [string]$report.task_status
        completion_criteria_satisfied = [bool]$report.completion_criteria_satisfied
        gate = 'G2'
        gate_decision = [string]$report.gate_decision
        g2_approved = [bool]$report.g2_approved
        p3_authorized = [bool]$report.p3_authorized
        input = [pscustomobject][ordered]@{
            source_build = [string]$report.source_build
            bindings = $report.input_bindings
        }
        report = [pscustomobject][ordered]@{
            json = [pscustomobject][ordered]@{
                path = Get-Relative $trackedJson
                tracked = $true
                bytes = [int64](Get-Item -LiteralPath $trackedJson).Length
                lines = Get-LineCount $trackedJson
                sha256 = Get-Sha256 $trackedJson
            }
            markdown = [pscustomobject][ordered]@{
                path = Get-Relative $trackedMarkdown
                tracked = $true
                bytes = [int64](Get-Item -LiteralPath $trackedMarkdown).Length
                lines = Get-LineCount $trackedMarkdown
                sha256 = Get-Sha256 $trackedMarkdown
            }
        }
        summary = $report.summary
        blockers = $report.blockers
        budget_interpretation = $report.budget_interpretation
        authority_boundaries = $report.authority_boundaries
        security = $report.security
        contracts = [pscustomobject][ordered]@{
            policy = Get-Relative $policyPath
            policy_sha256 = Get-Sha256 $policyPath
            schema = Get-Relative $schemaPath
            schema_sha256 = Get-Sha256 $schemaPath
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceSha
            generator = Get-Relative $generatorPath
            generator_sha256 = Get-Sha256 $generatorPath
            wrapper = Get-Relative $MyInvocation.MyCommand.Path
            wrapper_sha256 = Get-Sha256 $MyInvocation.MyCommand.Path
            self_test_assertions = [int]$selfTest.assertions
        }
        disclosure = $report.disclosure
        reproduction = [pscustomobject][ordered]@{
            check_mode = $false
            repository_mount = 'read-only'
            network = 'none'
            capabilities = 'none'
            no_new_privileges = $true
            builder_reference = $builderReference
            builder_id = $expectedBuilderId
            builder_user = 'tmxy'
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = if ($report.g2_approved) { @('P3') } else { @('P2-20A-remediation', 'P2-20B-owner-decisions', 'P2-20-g2-rerun') }
            detail = if ($report.g2_approved) {
                'G2 is approved from complete hash-bound evidence; proceed only within the separately governed P3 scope.'
            }
            else {
                'Close the quantified G2-06 resource gaps and obtain explicit approved G2-07 decisions, then rerun the fail-closed G2 review. P3 remains unauthorized.'
            }
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-20 evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        $frozenCanonical = $frozen | ConvertTo-Json -Depth 100 -Compress
        $generatedCanonical = $evidence | ConvertTo-Json -Depth 100 -Compress
        if ($frozenCanonical -cne $generatedCanonical) {
            throw 'Tracked P2-20 evidence differs from deterministic full-object regeneration.'
        }
    }
    else {
        $json = ($evidence | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n")
        [IO.File]::WriteAllText($evidencePath, $json + "`n", [Text.UTF8Encoding]::new($false))
    }
    $evidence | ConvertTo-Json -Depth 100
}
finally {
    $resolvedRun = [IO.Path]::GetFullPath($runRoot)
    if ($resolvedRun.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedRun -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRun -Recurse -Force
    }
}
