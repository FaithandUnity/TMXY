Set-StrictMode -Version Latest

function Get-G2QtxCriterion([object]$Report) {
    $matches = @($Report.criteria | Where-Object id -eq 'G2-06')
    if ($matches.Count -ne 1) { return $null }
    return $matches[0]
}

function Get-G2QtxMetric([object]$Criterion, [string]$Name) {
    $matches = @($Criterion.metrics | Where-Object name -eq $Name)
    if ($matches.Count -ne 1) { return $null }
    return $matches[0]
}

function Test-G2QtxJsonEqual([object]$Left, [object]$Right) {
    return ($Left | ConvertTo-Json -Depth 100 -Compress) -ceq
        ($Right | ConvertTo-Json -Depth 100 -Compress)
}

function Test-G2QtxDeclaredMipPrefixPolicy([object]$Policy) {
    $spec = $Policy.qtx_declared_mip_payload_prefix
    return $spec.task_id -eq 'P2-20A' -and $spec.criterion_id -eq 'G2-06' -and
        $spec.evidence_revision -eq 'P2-20A.13' -and
        $spec.path -eq 'Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.json' -and
        $Policy.fail_closed_rules.source_derived_qtx_declared_mip_prefix_proof_does_not_change_a4_or_a8_authority -eq $true -and
        $Policy.fail_closed_rules.qtx_declared_mip_prefix_requires_default_strict_rejection_and_does_not_promote_ignored_tail -eq $true
}

function Test-G2QtxDeclaredMipPrefixMetrics([object]$Criterion, [string]$Root) {
    if ($null -eq $Criterion -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $false
    }
    $documentPath = Join-Path $Root `
        'Data\Reports\p2-20a-qtx-declared-mip-payload-prefix-report.json'
    $document = Get-Content -LiteralPath $documentPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $state = $document.scope.current_upstream_effective_state
    $blockers = $document.preserved_blockers
    $expected = [ordered]@{
        qtx_declared_mip_prefix_diagnostic_hash_bound = @($true, 'boolean')
        qtx_declared_mip_prefix_inventory_hash_bound = @($true, 'boolean')
        qtx_declared_mip_prefix_detail_hash_bound = @($true, 'boolean')
        qtx_declared_mip_prefix_effective_plan_hash_bound = @($true, 'boolean')
        qtx_declared_mip_prefix_production_contract_hash_bound = @($true, 'boolean')
        qtx_declared_mip_prefix_source_derived_contract_proven = @($true, 'boolean')
        qtx_declared_mip_prefix_runtime_parity_proven = @($false, 'boolean')
        qtx_declared_mip_prefix_targets = @(6, 'assets')
        qtx_declared_mip_prefix_candidate_edges = @(6, 'edges')
        qtx_declared_mip_prefix_strict_default_rejected_edges = @(6, 'edges')
        qtx_declared_mip_prefix_explicit_prefix_pass_edges = @(6, 'edges')
        qtx_declared_mip_prefix_full_payload_boundary_edges = @(6, 'edges')
        qtx_declared_mip_prefix_dds_prefix_only_edges = @(6, 'edges')
        qtx_declared_mip_prefix_ignored_tail_hashes = @(6, 'hashes')
        qtx_declared_mip_prefix_input_payload_bytes = @(786456, 'bytes')
        qtx_declared_mip_prefix_consumed_payload_bytes = @(589824, 'bytes')
        qtx_declared_mip_prefix_ignored_payload_bytes = @(196632, 'bytes')
        qtx_declared_mip_prefix_candidate_selections = @(0, 'assets')
        qtx_declared_mip_prefix_automatic_resolutions = @(0, 'assets')
        qtx_declared_mip_prefix_authority_state_changed = @($false, 'boolean')
        qtx_declared_mip_prefix_recovery_applied = @($false, 'boolean')
        qtx_declared_mip_prefix_upstream_phase = @([string]$state.phase, 'state')
        qtx_declared_mip_prefix_upstream_selected_targets_resolved = @([int]$state.selected_targets_resolved, 'assets')
        qtx_declared_mip_prefix_upstream_selected_edges_pass = @([int]$state.selected_edges_pass, 'edges')
        qtx_declared_mip_prefix_preserved_ambiguous_targets = @([int]$blockers.asset_effective_ambiguous_targets, 'assets')
        qtx_declared_mip_prefix_preserved_ambiguous_edges = @([int]$blockers.asset_effective_ambiguous_edges, 'edges')
        qtx_declared_mip_prefix_preserved_unresolved_targets = @([int]$blockers.asset_effective_unresolved_targets, 'assets')
        qtx_declared_mip_prefix_preserved_unresolved_edges = @([int]$blockers.asset_effective_unresolved_edges, 'edges')
    }
    foreach ($name in $expected.Keys) {
        $metric = Get-G2QtxMetric $Criterion $name
        if ($null -eq $metric -or $metric.value -ne $expected[$name][0] -or
            $metric.unit -cne $expected[$name][1]) { return $false }
    }
    return $Criterion.satisfied -eq $false -and $Criterion.observed_status -eq 'BLOCKED'
}

function Test-G2QtxBindingSet([object]$Set, [object]$Paths, [string]$Root) {
    $entries = @($Set.entries)
    if ($entries.Count -ne $Paths.Count) { return $false }
    $lines = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $entries.Count; ++$index) {
        $role = @($Paths.Keys)[$index]
        $spec = $Paths[$role]
        $path = Join-Path $Root $spec[0]
        $entry = $entries[$index]
        if ($entry.role -cne $role -or $entry.path -cne $spec[0] -or
            $entry.tracked -ne $spec[1] -or $entry.bytes -ne (Get-Item $path).Length -or
            $entry.lines -ne (Get-LineCount $path) -or $entry.sha256 -cne (Get-Sha256 $path)) {
            return $false
        }
        $lines.Add("$($entry.role)`t$($entry.path)`t$(([string]$entry.tracked).ToLowerInvariant())`t$($entry.bytes)`t$($entry.lines)`t$($entry.sha256)")
    }
    return $Set.aggregate_sha256 -ceq (Get-TextSha256 (($lines -join "`n") + "`n"))
}

function Test-G2QtxDeclaredMipPrefixDocument([object]$Document, [string]$Root) {
    $schemaPath = Join-Path $Root `
        'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-v1.schema.json'
    try {
        if (-not [bool](Test-Json -Json ($Document | ConvertTo-Json -Depth 100 -Compress) `
                    -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) { return $false }
    }
    catch { return $false }
    $policyPath = Join-Path $Root `
        'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-policy-v1.json'
    $detailSchemaPath = Join-Path $Root `
        'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-detail-v1.schema.json'
    $detailPath = Join-Path $Root `
        'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix.jsonl'
    $planPath = Join-Path $Root `
        'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $detailLines = @([IO.File]::ReadAllLines($detailPath, [Text.Encoding]::UTF8))
    if ($detailLines.Count -ne 6 -or $Document.detail_export.path -cne
        'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix.jsonl' -or
        $Document.detail_export.sha256 -cne (Get-Sha256 $detailPath) -or
        $Document.effective_recovery_plan.path -cne
        'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv' -or
        $Document.effective_recovery_plan.sha256 -cne (Get-Sha256 $planPath) -or
        (Get-LineCount $planPath) -ne 21) { return $false }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in $detailLines) {
        try {
            if (-not [bool](Test-Json -Json $line -SchemaFile $detailSchemaPath `
                        -ErrorAction SilentlyContinue)) { return $false }
            $row = $line | ConvertFrom-Json -Depth 100 -DateKind String
        }
        catch { return $false }
        $candidate = $row.candidate
        if (-not $seen.Add([string]$row.asset_id) -or $row.source_strict_resolution -ne 'UNRESOLVED' -or
            $row.a13_resolution_change -ne $false -or $row.authority_state_changed -ne $false -or
            $candidate.strict_binding -ne 'REJECTED' -or
            $candidate.strict_error_code -ne 'payload_size_mismatch' -or
            $candidate.strict_prefix_binding -ne 'PASS' -or
            $candidate.explicit_prefix_binding -ne 'PASS' -or
            $candidate.input_payload_bytes -ne
                ($candidate.consumed_payload_bytes + $candidate.ignored_payload_bytes) -or
            $candidate.dds_payload_bytes -ne $candidate.consumed_payload_bytes -or
            $candidate.dds_payload_sha256 -cne $candidate.consumed_payload_sha256 -or
            -not $candidate.dds_payload_prefix_only -or
            -not $candidate.ignored_tail_excluded_from_dds -or
            $candidate.recovery_applied -or $candidate.adapter_applied) { return $false }
    }
    $inputPaths = [ordered]@{
        a4_report = @('Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json', $true)
        a4_inventory = @('Data/Inventory/p2-20a-asset-descriptor-diagnostics.json', $true)
        a4_detail = @('Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl', $false)
        a7_report = @('Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json', $true)
        a7_inventory = @('Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json', $true)
        a7_detail = @('Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl', $false)
        a8_report = @('Data/Reports/p2-20a-asset-binding-recovery-report.json', $true)
        a8_inventory = @('Data/Inventory/p2-20a-asset-binding-recovery.json', $true)
        a8_detail = @('Data/Exports/P2-20/p2-20a-asset-binding-recovery.jsonl', $false)
        core_report = @('Data/Reports/p2-20a-core-resource-closure-report.json', $true)
        core_inventory = @('Data/Inventory/p2-20a-core-resource-closure.json', $true)
        core_detail = @('Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl', $false)
        base_plan_contract = @('Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv', $true)
        p2_03_inventory = @('Data/Inventory/p2-03-package-dependency-graph.json', $true)
        p2_03_graph = @('Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl', $false)
        p2_12_inventory = @('Data/Inventory/p2-12-full-asset-inventory.json', $true)
        p2_12_catalog = @('Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl', $false)
        policy = @('Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-policy-v1.json', $true)
        schema = @('Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-v1.schema.json', $true)
        detail_schema = @('Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-detail-v1.schema.json', $true)
    }
    $productionPaths = [ordered]@{
        texture_types_header = @('Tools/TMXY.Texture/include/tmxy/texture/texture_types.hpp', $true)
        qtx_reader_header = @('Tools/TMXY.Texture/include/tmxy/texture/qtx_reader.hpp', $true)
        qtx_reader_implementation = @('Tools/TMXY.Texture/src/qtx_reader.cpp', $true)
        texture_decode_internal_header = @('Tools/TMXY.Texture/src/texture_decode_internal.hpp', $true)
        texture_decode_implementation = @('Tools/TMXY.Texture/src/texture_decode.cpp', $true)
        dds_writer_implementation = @('Tools/TMXY.Texture/src/dds_writer.cpp', $true)
        texture_export_implementation = @('Tools/TMXY.Texture/src/texture_export.cpp', $true)
        texture_error_implementation = @('Tools/TMXY.Texture/src/texture_error.cpp', $true)
    }
    $a7 = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Root $inputPaths.a7_report[0]) |
        ConvertFrom-Json -Depth 100 -DateKind String
    $a8 = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Root $inputPaths.a8_report[0]) |
        ConvertFrom-Json -Depth 100 -DateKind String
    $core = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Root $inputPaths.core_report[0]) |
        ConvertFrom-Json -Depth 100 -DateKind String
    $asset = $core.closure.asset_binding
    $state = $Document.scope.current_upstream_effective_state
    $blockers = $Document.preserved_blockers
    $commonBlockers = [ordered]@{}
    foreach ($property in $a8.preserved_blockers.PSObject.Properties) {
        $commonBlockers[$property.Name] = $blockers.($property.Name)
    }
    return $Document.evidence_revision -eq 'P2-20A.13' -and
        $Document.result -eq 'BLOCKED' -and $Document.review_execution_result -eq 'PASS_DIAGNOSTIC' -and
        $Document.task_status -eq 'BLOCKED' -and -not $Document.completion_criteria_satisfied -and
        $Document.diagnostic_scope_complete -and -not $Document.remediation_scope_complete -and
        -not $Document.g2_06_satisfied -and -not $Document.p3_authorized -and
        $Document.proof_classification.source_basis -eq 'SOURCE_DERIVED' -and
        -not $Document.proof_classification.legacy_binary_executed -and
        -not $Document.proof_classification.runtime_parity_proven -and
        $Document.scope.targets -eq 6 -and $Document.scope.candidate_edges -eq 6 -and
        $Document.measured.strict_default_rejected_edges -eq 6 -and
        $Document.measured.explicit_prefix_pass_edges -eq 6 -and
        $Document.measured.dds_prefix_only_edges -eq 6 -and
        $Document.measured.ignored_tail_hashes -eq 6 -and
        -not $Document.authority_boundary.authority_state_changed -and
        -not $Document.authority_boundary.adapter_applied -and
        -not $Document.authority_boundary.recovery_applied -and
        $Document.production_contract.api -eq
            'tmxy::texture::QtxReader::parse_with_declared_mip_payload_prefix' -and
        $Document.production_contract.default_api_remains_strict -and
        (Test-G2QtxBindingSet $Document.input_bindings $inputPaths $Root) -and
        (Test-G2QtxBindingSet $Document.production_contract.implementation_bindings $productionPaths $Root) -and
        $Document.contracts.policy_sha256 -ceq (Get-Sha256 $policyPath) -and
        $Document.contracts.schema_sha256 -ceq (Get-Sha256 $schemaPath) -and
        $Document.contracts.detail_schema_sha256 -ceq (Get-Sha256 $detailSchemaPath) -and
        $Document.contracts.base_plan_contract_sha256 -ceq
            (Get-Sha256 (Join-Path $Root `
                'Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv')) -and
        (Test-G2QtxJsonEqual $blockers $a7.preserved_blockers) -and
        (Test-G2QtxJsonEqual ([pscustomobject]$commonBlockers) $a8.preserved_blockers) -and
        $blockers.asset_effective_ambiguous_targets -eq $asset.ambiguous_targets -and
        $blockers.asset_effective_ambiguous_edges -eq $asset.ambiguous_edges -and
        $blockers.asset_effective_unresolved_targets -eq $asset.unresolved_targets -and
        $blockers.asset_effective_unresolved_edges -eq $asset.unresolved_edges -and
        $state.phase -eq 'POST_APPLICATION' -and $state.selected_targets_resolved -eq 6 -and
        $state.selected_edges_pass -eq 6 -and $state.selected_recovery_applied_edges -eq 6 -and
        (Test-G2QtxJsonEqual $Document.source_facts $policy.expected_source_facts) -and
        (Test-G2QtxJsonEqual $Document.disclosure $policy.disclosure)
}

function Test-G2QtxDeclaredMipPrefixBinding(
    [object]$G2Report, [object]$Policy, [string]$Root) {
    if (-not (Test-G2QtxDeclaredMipPrefixPolicy $Policy)) { return $false }
    $binding = $G2Report.input_bindings.qtx_declared_mip_payload_prefix
    $reportPath = Join-Path $Root `
        'Data\Reports\p2-20a-qtx-declared-mip-payload-prefix-report.json'
    $inventoryPath = Join-Path $Root `
        'Data\Inventory\p2-20a-qtx-declared-mip-payload-prefix.json'
    $detailPath = Join-Path $Root `
        'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix.jsonl'
    $planPath = Join-Path $Root `
        'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
    if ($binding.task_id -ne 'P2-20A' -or $binding.criterion_id -ne 'G2-06' -or
        $binding.evidence_revision -ne 'P2-20A.13' -or
        $binding.path -cne 'Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.json' -or
        $binding.sha256 -cne (Get-Sha256 $reportPath) -or
        $binding.inventory_path -cne 'Data/Inventory/p2-20a-qtx-declared-mip-payload-prefix.json' -or
        $binding.inventory_sha256 -cne (Get-Sha256 $inventoryPath) -or
        $binding.detail_path -cne 'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix.jsonl' -or
        $binding.detail_sha256 -cne (Get-Sha256 $detailPath) -or
        $binding.effective_recovery_plan_path -cne
            'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv' -or
        $binding.effective_recovery_plan_sha256 -cne (Get-Sha256 $planPath) -or
        $binding.result -ne 'BLOCKED' -or $binding.review_execution_result -ne 'PASS_DIAGNOSTIC' -or
        $binding.task_status -ne 'BLOCKED' -or $binding.completion_criteria_satisfied -ne $false -or
        $binding.diagnostic_scope_complete -ne $true -or
        $binding.remediation_scope_complete -ne $false -or
        $binding.g2_06_satisfied -ne $false -or $binding.p3_authorized -ne $false) { return $false }
    $document = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    return (Test-G2QtxDeclaredMipPrefixDocument $document $Root) -and
        $inventory.report.path -ceq 'Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.json' -and
        $inventory.report.sha256 -ceq (Get-Sha256 $reportPath) -and
        $inventory.outputs.detail_export.sha256 -ceq (Get-Sha256 $detailPath) -and
        $inventory.outputs.effective_recovery_plan.sha256 -ceq (Get-Sha256 $planPath) -and
        -not $inventory.authority_boundary.authority_state_changed -and
        -not $inventory.g2_06_satisfied -and -not $inventory.p3_authorized -and
        (Test-G2QtxDeclaredMipPrefixMetrics (Get-G2QtxCriterion $G2Report) $Root)
}

function Get-G2QtxDeclaredMipPrefixAggregateLine([object]$Binding) {
    return "QTX_DECLARED_MIP_PREFIX|$($Binding.task_id)|$($Binding.criterion_id)|$($Binding.evidence_revision)|$($Binding.path)|$($Binding.sha256)|$($Binding.inventory_path)|$($Binding.inventory_sha256)|$($Binding.detail_path)|$($Binding.detail_sha256)|$($Binding.effective_recovery_plan_path)|$($Binding.effective_recovery_plan_sha256)"
}

function Get-G2QtxDeclaredMipPrefixNegativeCases(
    [object]$Report, [object]$Policy, [string]$Root) {
    $cases = [ordered]@{}
    $authority = Copy-JsonObject $Report
    (Get-G2QtxMetric (Get-G2QtxCriterion $authority) `
        'qtx_declared_mip_prefix_authority_state_changed').value = $true
    $cases.qtx_declared_mip_prefix_false_authority_rejected =
        -not (Test-G2QtxDeclaredMipPrefixMetrics (Get-G2QtxCriterion $authority) $Root)
    $strict = Copy-JsonObject $Report
    (Get-G2QtxMetric (Get-G2QtxCriterion $strict) `
        'qtx_declared_mip_prefix_strict_default_rejected_edges').value = 5
    $cases.qtx_declared_mip_prefix_default_strict_forgery_rejected =
        -not (Test-G2QtxDeclaredMipPrefixMetrics (Get-G2QtxCriterion $strict) $Root)
    $reportPath = Join-Path $Root `
        'Data\Reports\p2-20a-qtx-declared-mip-payload-prefix-report.json'
    $document = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $unknown = Copy-JsonObject $document
    $unknown.authority_boundary | Add-Member -NotePropertyName optimistic_runtime_safe -NotePropertyValue $true
    $cases.qtx_declared_mip_prefix_unknown_nested_field_rejected =
        -not (Test-G2QtxDeclaredMipPrefixDocument $unknown $Root)
    $phase = Copy-JsonObject $document
    $phase.scope.current_upstream_effective_state.phase = 'PRE_APPLICATION'
    $phase.scope.current_upstream_effective_state.selected_targets_resolved = 0
    $phase.scope.current_upstream_effective_state.selected_edges_pass = 0
    $phase.scope.current_upstream_effective_state.selected_recovery_applied_edges = 0
    $cases.qtx_declared_mip_prefix_upstream_phase_forgery_rejected =
        -not (Test-G2QtxDeclaredMipPrefixDocument $phase $Root)
    $hash = Copy-JsonObject $Report
    $hash.input_bindings.qtx_declared_mip_payload_prefix.detail_sha256 = '0' * 64
    $cases.qtx_declared_mip_prefix_hash_forgery_rejected =
        -not (Test-G2QtxDeclaredMipPrefixBinding $hash $Policy $Root)
    return ,$cases
}
