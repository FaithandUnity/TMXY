Set-StrictMode -Version Latest

function Test-G2StaticMeshPrefixPolicy([object]$Policy) {
    $spec = $Policy.static_mesh_payload_section_prefix
    return $spec.task_id -eq 'P2-20A' -and $spec.criterion_id -eq 'G2-06' -and
        $spec.evidence_revision -eq 'P2-20A.12' -and
        $spec.path -eq 'Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.json' -and
        $Policy.fail_closed_rules.source_derived_static_mesh_prefix_proof_does_not_change_a4_or_a8_authority -eq $true -and
        $Policy.fail_closed_rules.static_mesh_prefix_proof_does_not_select_candidates_apply_adapters_or_prove_runtime_parity -eq $true
}

function Test-G2StaticMeshPrefixMetrics([object]$Criterion) {
    $expected = [ordered]@{
        static_mesh_prefix_diagnostic_hash_bound = @($true, 'boolean')
        static_mesh_prefix_inventory_hash_bound = @($true, 'boolean')
        static_mesh_prefix_detail_hash_bound = @($true, 'boolean')
        static_mesh_prefix_source_derived_contract_proven = @($true, 'boolean')
        static_mesh_prefix_runtime_parity_proven = @($false, 'boolean')
        static_mesh_prefix_targets = @(1, 'assets')
        static_mesh_prefix_candidate_edges = @(2, 'edges')
        static_mesh_prefix_strict_rejected_edges = @(2, 'edges')
        static_mesh_prefix_explicit_prefix_pass_edges = @(2, 'edges')
        static_mesh_prefix_payload_sections = @(1, 'sections')
        static_mesh_prefix_material_slots = @(2, 'slots')
        static_mesh_prefix_ignored_trailing_material_slots = @(1, 'slots')
        static_mesh_prefix_candidate_selections = @(0, 'assets')
        static_mesh_prefix_automatic_resolutions = @(0, 'assets')
        static_mesh_prefix_adapter_applied = @($false, 'boolean')
        static_mesh_prefix_authority_state_changed = @($false, 'boolean')
        static_mesh_prefix_recovery_applied = @($false, 'boolean')
        static_mesh_prefix_preserved_ambiguous_targets = @(189, 'assets')
        static_mesh_prefix_preserved_ambiguous_edges = @(546, 'edges')
        static_mesh_prefix_preserved_unresolved_targets = @(12, 'assets')
        static_mesh_prefix_preserved_unresolved_edges = @(15, 'edges')
    }
    foreach ($name in $expected.Keys) {
        $matches = @($Criterion.metrics | Where-Object name -eq $name)
        if ($matches.Count -ne 1 -or $matches[0].value -ne $expected[$name][0] -or
            $matches[0].unit -cne $expected[$name][1]) { return $false }
    }
    return $Criterion.satisfied -eq $false -and $Criterion.observed_status -eq 'BLOCKED'
}

function Test-G2StaticMeshPrefixDocument([object]$Document, [string]$Root) {
    $schemaPath = Join-Path $Root `
        'Contracts\data-schema\g2-static-mesh-payload-section-prefix-v1.schema.json'
    try {
        if (-not [bool](Test-Json -Json ($Document | ConvertTo-Json -Depth 100 -Compress) `
                    -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) { return $false }
    }
    catch { return $false }
    $measured = $Document.measured
    $relation = $Document.observed_relation
    $proof = $Document.proof_classification
    $authority = $Document.authority_boundary
    $blockers = $Document.preserved_blockers
    $policyPath = Join-Path $Root `
        'Contracts\data-schema\g2-static-mesh-payload-section-prefix-policy-v1.json'
    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $expectedLegacy = @($policy.legacy_source_roles | Sort-Object role)
    $legacy = @($Document.legacy_source_provenance.roles)
    $legacyText = (@($expectedLegacy | ForEach-Object { "$($_.role)`t$($_.sha256)" }) -join "`n") + "`n"
    $legacyPassed = $legacy.Count -eq 7 -and
        (Test-JsonEqual $legacy $expectedLegacy) -and
        $Document.legacy_source_provenance.aggregate_sha256 -ceq (Get-TextSha256 $legacyText) -and
        (Test-JsonEqual $Document.source_facts $policy.expected_source_facts)
    $productionPaths = [ordered]@{
        static_mesh_types_header = 'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_types.hpp'
        static_mesh_api_header = 'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/package_static_mesh_reader.hpp'
        static_mesh_binding_implementation = 'Tools/TMXY.StaticMesh/src/package_static_mesh_reader.cpp'
        static_mesh_payload_parser = 'Tools/TMXY.StaticMesh/src/sm_reader.cpp'
        static_mesh_error_source = 'Tools/TMXY.StaticMesh/src/static_mesh_error.cpp'
    }
    $production = @($Document.production_contract.implementation_bindings.entries)
    $productionPassed = $Document.production_contract.api -eq
        'bind_static_mesh_with_payload_section_prefix' -and $production.Count -eq 5
    $productionLines = [Collections.Generic.List[string]]::new()
    for ($index = 0; $productionPassed -and $index -lt $production.Count; ++$index) {
        $role = @($productionPaths.Keys)[$index]
        $path = Join-Path $Root $productionPaths[$role]
        $entry = $production[$index]
        $productionPassed = $entry.role -ceq $role -and
            $entry.path -ceq $productionPaths[$role] -and $entry.tracked -eq $true -and
            $entry.bytes -eq (Get-Item $path).Length -and
            $entry.lines -eq (Get-LineCount $path) -and $entry.sha256 -ceq (Get-Sha256 $path)
        $productionLines.Add("$($entry.role)`t$($entry.path)`t$(([string]$entry.tracked).ToLowerInvariant())`t$($entry.bytes)`t$($entry.lines)`t$($entry.sha256)")
    }
    $productionPassed = $productionPassed -and
        $Document.production_contract.implementation_bindings.aggregate_sha256 -ceq
            (Get-TextSha256 (($productionLines -join "`n") + "`n"))
    return $Document.evidence_revision -eq 'P2-20A.12' -and
        $Document.result -eq 'BLOCKED' -and
        $Document.review_execution_result -eq 'PASS_DIAGNOSTIC' -and
        $Document.task_status -eq 'BLOCKED' -and
        $Document.completion_criteria_satisfied -eq $false -and
        $Document.diagnostic_scope_complete -eq $true -and
        $Document.remediation_scope_complete -eq $false -and
        $Document.g2_06_satisfied -eq $false -and $Document.p3_authorized -eq $false -and
        $proof.source_basis -eq 'SOURCE_DERIVED' -and
        $proof.legacy_binary_executed -eq $false -and $proof.runtime_parity_proven -eq $false -and
        $Document.scope.targets -eq 1 -and $Document.scope.candidate_edges -eq 2 -and
        $measured.strict_rejected_edges -eq 2 -and $measured.prefix_pass_edges -eq 2 -and
        $measured.candidate_selections -eq 0 -and $measured.automatic_resolutions -eq 0 -and
        $relation.descriptor_material_slots -eq 2 -and $relation.payload_sections -eq 1 -and
        $relation.nonempty_payload_sections -eq 1 -and
        $relation.ignored_trailing_material_slots -eq 1 -and
        $authority.a4_is_authoritative -eq $true -and
        $authority.authority_state_changed -eq $false -and
        $authority.adapter_applied -eq $false -and $authority.recovery_applied -eq $false -and
        $legacyPassed -and $productionPassed -and
        $blockers.asset_effective_ambiguous_targets -eq 189 -and
        $blockers.asset_effective_ambiguous_edges -eq 546 -and
        $blockers.asset_effective_unresolved_targets -eq 12 -and
        $blockers.asset_effective_unresolved_edges -eq 15 -and
        $blockers.g2_satisfied -eq 7 -and $blockers.g2_blocked -eq 2
}

function Test-G2StaticMeshPrefixBinding(
    [object]$G2Report, [object]$Policy, [string]$Root) {
    if (-not (Test-G2StaticMeshPrefixPolicy $Policy)) { return $false }
    $binding = $G2Report.input_bindings.static_mesh_payload_section_prefix
    $reportPath = Join-Path $Root `
        'Data\Reports\p2-20a-static-mesh-payload-section-prefix-report.json'
    $inventoryPath = Join-Path $Root `
        'Data\Inventory\p2-20a-static-mesh-payload-section-prefix.json'
    $detailPath = Join-Path $Root `
        'Data\Exports\P2-20\p2-20a-static-mesh-payload-section-prefix.jsonl'
    if ($binding.task_id -ne 'P2-20A' -or $binding.criterion_id -ne 'G2-06' -or
        $binding.evidence_revision -ne 'P2-20A.12' -or
        $binding.path -cne 'Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.json' -or
        $binding.sha256 -cne (Get-Sha256 $reportPath) -or
        $binding.inventory_path -cne 'Data/Inventory/p2-20a-static-mesh-payload-section-prefix.json' -or
        $binding.inventory_sha256 -cne (Get-Sha256 $inventoryPath) -or
        $binding.detail_path -cne 'Data/Exports/P2-20/p2-20a-static-mesh-payload-section-prefix.jsonl' -or
        $binding.detail_sha256 -cne (Get-Sha256 $detailPath) -or
        $binding.result -ne 'BLOCKED' -or
        $binding.review_execution_result -ne 'PASS_DIAGNOSTIC' -or
        $binding.task_status -ne 'BLOCKED' -or
        $binding.completion_criteria_satisfied -ne $false -or
        $binding.diagnostic_scope_complete -ne $true -or
        $binding.remediation_scope_complete -ne $false -or
        $binding.g2_06_satisfied -ne $false) { return $false }
    $document = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    return (Test-G2StaticMeshPrefixDocument $document $Root) -and
        $inventory.report.path -ceq 'Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.json' -and
        $inventory.report.sha256 -ceq (Get-Sha256 $reportPath) -and
        $inventory.outputs.detail_export.path -ceq 'Data/Exports/P2-20/p2-20a-static-mesh-payload-section-prefix.jsonl' -and
        $inventory.outputs.detail_export.sha256 -ceq (Get-Sha256 $detailPath) -and
        (Test-G2StaticMeshPrefixMetrics (Get-Criterion $G2Report 'G2-06'))
}

function Get-G2StaticMeshPrefixAggregateLine([object]$Binding) {
    return "STATIC_MESH_PREFIX|$($Binding.task_id)|$($Binding.criterion_id)|$($Binding.evidence_revision)|$($Binding.path)|$($Binding.sha256)|$($Binding.inventory_path)|$($Binding.inventory_sha256)|$($Binding.detail_path)|$($Binding.detail_sha256)"
}

function Get-G2StaticMeshPrefixNegativeCases(
    [object]$Report, [object]$Policy, [string]$Root) {
    $cases = [ordered]@{}
    $promotion = Copy-JsonObject $Report
    Set-Metric (Get-Criterion $promotion 'G2-06') `
        'static_mesh_prefix_authority_state_changed' $true
    $cases.static_mesh_prefix_false_promotion_rejected =
        -not (Test-G2StaticMeshPrefixMetrics (Get-Criterion $promotion 'G2-06'))
    $reportPath = Join-Path $Root `
        'Data\Reports\p2-20a-static-mesh-payload-section-prefix-report.json'
    $document = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $unknown = Copy-JsonObject $document
    $unknown.authority_boundary |
        Add-Member -NotePropertyName optimistic_runtime_safe -NotePropertyValue $true
    $cases.static_mesh_prefix_unknown_nested_field_rejected =
        -not (Test-G2StaticMeshPrefixDocument $unknown $Root)
    $forgery = Copy-JsonObject $Report
    $forgery.input_bindings.static_mesh_payload_section_prefix.detail_sha256 = '0' * 64
    $cases.static_mesh_prefix_hash_forgery_rejected =
        -not (Test-G2StaticMeshPrefixBinding $forgery $Policy $Root)
    return ,$cases
}
