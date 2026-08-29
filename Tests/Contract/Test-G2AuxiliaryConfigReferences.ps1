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

function Get-TextSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
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

function Test-ClosedFields($Value, [string[]]$Expected) {
    $actual = @($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive)
    return @(Compare-Object $actual @($Expected | Sort-Object -CaseSensitive)).Count -eq 0
}

function Test-Sha256([object]$Value) {
    return [string]$Value -cmatch '^[0-9a-f]{64}$'
}

function Test-JsonSchema($Value, [string]$SchemaPath) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue
}

function Test-PolicySemantics($Candidate) {
    $measured = $Candidate.measured_lexical_candidates
    $requirements = $Candidate.parser_and_matching_requirements
    $completion = $Candidate.completion_requirements
    $observation = $Candidate.current_observation
    $authority = $Candidate.authority_rules
    return $Candidate.schema_version -eq 1 -and
        $Candidate.evidence_revision -ceq 'P2-20A.3' -and
        $Candidate.task_id -ceq 'P2-20A' -and
        $Candidate.criterion_id -ceq 'G2-06' -and
        @(Compare-Object @($Candidate.required_input_roles) @(
                'auxiliary_config_inventory', 'full_asset_inventory',
                'reference_closure', 'asset_health', 'conversion_routing',
                'content_health')).Count -eq 0 -and
        $measured.measurement_authority -ceq 'LEXICAL_ONLY' -and
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
        $requirements.enumerate_every_file_instance -eq $true -and
        $requirements.preserve_duplicate_file_instances -eq $true -and
        $requirements.preserve_duplicate_ecf_assignment_order -eq $true -and
        $requirements.xml_dtd_enabled -eq $false -and
        $requirements.xml_external_resolver_enabled -eq $false -and
        $requirements.exact_complete_scalar_matching -eq $true -and
        $requirements.substring_matching -eq $false -and
        $requirements.basename_matching -eq $false -and
        $requirements.extension_only_matching -eq $false -and
        $requirements.first_candidate_selection -eq $false -and
        $requirements.retain_all_ambiguous_candidates -eq $true -and
        $requirements.malformed_implies_zero_references -eq $false -and
        [int]$completion.file_instances_covered -eq 212 -and
        [int]$completion.terminal_adapter_file_instances -eq 212 -and
        [int]$completion.semantic_unknown_occurrences -eq 0 -and
        [int]$completion.semantic_ambiguous_occurrences -eq 0 -and
        [int]$completion.semantic_unresolved_occurrences -eq 0 -and
        [int]$completion.first_candidate_selections -eq 0 -and
        $completion.scope_complete -eq $true -and
        [int]$observation.approved_semantic_adapters -eq 0 -and
        [int]$observation.approved_no_ref_files -eq 0 -and
        [int]$observation.approved_roots -eq 0 -and
        $observation.scope_complete -eq $false -and
        $observation.result -ceq 'BLOCKED' -and
        $observation.review_execution_result -ceq 'PASS' -and
        $observation.task_status -ceq 'BLOCKED' -and
        $observation.completion_criteria_satisfied -eq $false -and
        $observation.g2_06_satisfied -eq $false -and
        $observation.p3_authorized -eq $false -and
        $authority.machine_candidate_is_approval -eq $false -and
        $authority.absence_of_match_is_no_ref_approval -eq $false -and
        $authority.malformed_input_can_be_auto_excluded -eq $false -and
        $authority.ambiguous_first_candidate_can_be_selected -eq $false -and
        $authority.this_evidence_can_approve_g2 -eq $false -and
        $authority.this_evidence_can_authorize_p3_or_release -eq $false
}

function Test-ReportSemantics($Candidate) {
    if ($Candidate.result -cne 'BLOCKED' -or
        $Candidate.review_execution_result -cne 'PASS' -or
        $Candidate.task_status -cne 'BLOCKED' -or
        $Candidate.completion_criteria_satisfied -ne $false -or
        $Candidate.scope_complete -ne $false -or
        $Candidate.g2_06_satisfied -ne $false -or
        $Candidate.p3_authorized -ne $false) { return $false }

    $measured = $Candidate.measured_lexical_candidates
    if ($measured.measurement_authority -cne 'LEXICAL_ONLY' -or
        [int]$measured.file_instances -ne 212 -or
        [int]$measured.unique_content_bodies -ne 196 -or
        [int]$measured.parsed_file_instances -ne 206 -or
        [int]$measured.malformed_file_instances -ne 6 -or
        [int]$measured.scalar_positions -ne 39522 -or
        [int]$measured.nonempty_scalar_positions -ne 39498 -or
        [int]$measured.asset_exact_occurrences -ne 3043 -or
        [int]$measured.package_exact_occurrences -ne 638 -or
        [int]$measured.package_unique_occurrences -ne 218 -or
        [int]$measured.package_ambiguous_occurrences -ne 420 -or
        [int]$measured.package_ambiguous_candidate_edges -ne 1136 -or
        [int]$measured.config_exact_edges -ne 8 -or
        -not (Test-Sha256 $measured.file_instance_set_sha256) -or
        -not (Test-Sha256 $measured.lexical_occurrence_set_sha256)) { return $false }

    $controls = $Candidate.parser_and_matching_controls
    if ($controls.every_file_instance_enumerated -ne $true -or
        $controls.duplicate_file_instances_preserved -ne $true -or
        $controls.duplicate_ecf_assignments_preserve_order -ne $true -or
        $controls.xml_dtd_enabled -ne $false -or
        $controls.xml_external_resolver_enabled -ne $false -or
        $controls.exact_complete_scalar_matching -ne $true -or
        $controls.substring_matching -ne $false -or
        $controls.basename_matching -ne $false -or
        $controls.extension_only_matching -ne $false -or
        $controls.first_candidate_selection -ne $false -or
        $controls.ambiguous_candidates_all_retained -ne $true -or
        $controls.config_closure_detection -ne $true -or
        $controls.config_cycle_detection -ne $true -or
        $controls.malformed_implies_zero_references -ne $false) { return $false }

    $instances = @($Candidate.file_instances)
    $instanceIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $contentIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $states = @{ 'candidate-only' = 0; 'malformed-blocked' = 0; 'editor-undecided' = 0 }
    $parser = @{ parsed = 0; malformed = 0 }
    $lexical = @{ asset = 0; package = 0; config = 0; edges = 0 }
    $fields = @(
        'adapter_contract_sha256', 'adapter_state', 'approved_root_count',
        'approved_root_set_sha256', 'authority_record_sha256', 'content_sha256',
        'instance_sha256', 'lexical_counts', 'occurrence_set_sha256',
        'parser_state', 'reason_code'
    )
    foreach ($instance in $instances) {
        $state = [string]$instance.adapter_state
        $parserState = [string]$instance.parser_state
        if (-not (Test-ClosedFields $instance $fields) -or
            -not (Test-Sha256 $instance.instance_sha256) -or
            -not (Test-Sha256 $instance.content_sha256) -or
            -not $instanceIds.Add([string]$instance.instance_sha256) -or
            $state -notin @('candidate-only', 'malformed-blocked', 'editor-undecided') -or
            $parserState -notin @('parsed', 'malformed') -or
            $null -ne $instance.adapter_contract_sha256 -or
            $null -ne $instance.authority_record_sha256 -or
            [int]$instance.approved_root_count -ne 0 -or
            $null -ne $instance.approved_root_set_sha256) { return $false }
        [void]$contentIds.Add([string]$instance.content_sha256)
        ++$states[$state]
        ++$parser[$parserState]
        $lexical.asset += [int]$instance.lexical_counts.asset_exact
        $lexical.package += [int]$instance.lexical_counts.package_exact
        $lexical.config += [int]$instance.lexical_counts.config_exact
        $lexical.edges += [int]$instance.lexical_counts.candidate_edges
        $matchCount = [int]$instance.lexical_counts.asset_exact +
            [int]$instance.lexical_counts.package_exact +
            [int]$instance.lexical_counts.config_exact
        if ($state -eq 'malformed-blocked' -and
            ($parserState -ne 'malformed' -or $matchCount -ne 0 -or
             $null -ne $instance.occurrence_set_sha256 -or
             $instance.reason_code -cne 'MALFORMED_INPUT_REQUIRES_DISPOSITION')) { return $false }
        if ($state -eq 'candidate-only' -and
            ($parserState -ne 'parsed' -or
             ($matchCount -eq 0 -and $null -ne $instance.occurrence_set_sha256) -or
             ($matchCount -gt 0 -and -not (Test-Sha256 $instance.occurrence_set_sha256)) -or
             $instance.reason_code -cne 'LEXICAL_CANDIDATES_NOT_SEMANTICALLY_APPROVED')) {
            return $false
        }
        if ($state -eq 'editor-undecided' -and
            ($parserState -ne 'parsed' -or $matchCount -ne 0 -or
             $null -ne $instance.occurrence_set_sha256 -or
             $instance.reason_code -cne 'NO_MATCH_DOES_NOT_PROVE_NO_REFERENCE')) { return $false }
    }
    $adapter = $Candidate.adapter_state_summary
    if ($instances.Count -ne 212 -or $instanceIds.Count -ne 212 -or
        $contentIds.Count -ne 196 -or $parser.parsed -ne 206 -or $parser.malformed -ne 6 -or
        $states.'malformed-blocked' -ne 6 -or $states.'candidate-only' -ne 171 -or
        $states.'editor-undecided' -ne 35 -or
        $lexical.asset -ne 3043 -or $lexical.package -ne 638 -or $lexical.config -ne 8 -or
        [int]$adapter.file_instances -ne 212 -or [int]$adapter.terminal_file_instances -ne 0 -or
        [int]$adapter.nonterminal_file_instances -ne 212 -or
        [int]$adapter.semantic_approved -ne 0 -or [int]$adapter.no_ref_approved -ne 0 -or
        [int]$adapter.candidate_only -ne $states.'candidate-only' -or
        [int]$adapter.malformed_blocked -ne 6 -or
        [int]$adapter.editor_undecided -ne $states.'editor-undecided' -or
        [int]$adapter.approved_roots -ne 0) { return $false }

    $semantic = $Candidate.semantic_resolution
    $closure = $Candidate.config_closure
    if ($semantic.status -cne 'UNASSESSED' -or
        $null -ne $semantic.unknown_occurrences -or
        $null -ne $semantic.ambiguous_occurrences -or
        $null -ne $semantic.unresolved_occurrences -or
        $null -ne $semantic.resolved_occurrences -or
        [int]$semantic.first_candidate_selections -ne 0 -or
        [int]$semantic.heuristic_target_selections -ne 0 -or
        $semantic.all_ambiguous_candidates_retained -ne $true -or
        $semantic.reason_code -cne 'SEMANTIC_ADAPTERS_NOT_APPROVED' -or
        [int]$closure.lexical_edges -ne 8 -or [int]$closure.approved_root_count -ne 0 -or
        $null -ne $closure.approved_root_set_sha256 -or
        $null -ne $closure.semantic_edge_set_sha256 -or $null -ne $closure.closure_set_sha256 -or
        $closure.closure_complete -ne $false -or $closure.cycle_detection_complete -ne $false -or
        $null -ne $closure.cycle_count -or $null -ne $closure.unresolved_cycle_count) { return $false }

    $expectedAssumptions = @(
        'LEXICAL_CANDIDATE_IS_NOT_SEMANTIC_REFERENCE',
        'NO_MATCH_IS_NOT_NO_REFERENCE_APPROVAL',
        'DUPLICATE_CONTENT_DOES_NOT_COLLAPSE_FILE_INSTANCES',
        'MALFORMED_INPUT_IS_NOT_ZERO_REFERENCE',
        'AMBIGUOUS_CANDIDATE_HAS_NO_SELECTION_AUTHORITY'
    )
    $blockerCounts = @{
        SEMANTIC_ADAPTERS_UNAPPROVED = 212
        APPROVED_ROOT_SET_EMPTY = 0
        MALFORMED_INPUTS_UNDISPOSED = 6
        SEMANTIC_METRICS_UNAVAILABLE = 3
        CONFIG_CLOSURE_UNAPPROVED = 8
        AUXILIARY_SCOPE_INCOMPLETE = 1
    }
    if (@(Compare-Object @($Candidate.assumptions) $expectedAssumptions).Count -ne 0 -or
        @($Candidate.blockers).Count -ne 6) { return $false }
    foreach ($blocker in @($Candidate.blockers)) {
        if (-not $blockerCounts.ContainsKey([string]$blocker.reason_code) -or
            [int]$blocker.count -ne [int]$blockerCounts[[string]$blocker.reason_code] -or
            $blocker.blocking -ne $true) { return $false }
    }

    $completion = $Candidate.completion
    $authority = $Candidate.authority_boundaries
    $disclosure = $Candidate.disclosure
    return $completion.file_coverage_complete -eq $true -and
        $completion.duplicate_file_instances_preserved -eq $true -and
        $completion.duplicate_ecf_assignment_order_preserved -eq $true -and
        $completion.semantic_adapters_terminal -eq $false -and
        $completion.malformed_disposition_complete -eq $false -and
        $completion.semantic_resolution_complete -eq $false -and
        $completion.config_closure_complete -eq $false -and
        $completion.cycle_detection_complete -eq $false -and
        $completion.all_inputs_hash_bound -eq $true -and
        $completion.first_candidate_selection_absent -eq $true -and
        $completion.scope_complete -eq $false -and $completion.satisfied -eq $false -and
        $authority.machine_candidate_is_approval -eq $false -and
        [int]$authority.approved_semantic_adapters -eq 0 -and
        [int]$authority.approved_no_ref_files -eq 0 -and
        [int]$authority.approved_roots -eq 0 -and
        $authority.g2_06_satisfied -eq $false -and $authority.g2_approved -eq $false -and
        $authority.p3_authorized -eq $false -and $authority.release_authority -eq $false -and
        $disclosure.anonymous_hash_count_reason_only -eq $true -and
        $disclosure.raw_scalar_values -eq $false -and $disclosure.key_names -eq $false -and
        $disclosure.file_names -eq $false -and $disclosure.private_source_paths -eq $false -and
        $disclosure.source_line_numbers -eq $false -and $disclosure.exact_primary_keys -eq $false -and
        $disclosure.exact_observed_extrema -eq $false -and $disclosure.raw_table_rows -eq $false -and
        $disclosure.legacy_source_lines -eq $false -and $disclosure.decoded_payloads -eq $false
}

function Test-InputBindings($Candidate, $Policy, [string]$Root) {
    $paths = [ordered]@{
        auxiliary_config_inventory = 'Data/Inventory/p2-05-auxiliary-config-inventory.json'
        full_asset_inventory = 'Data/Inventory/p2-12-full-asset-inventory.json'
        reference_closure = 'Data/Inventory/p2-13-reference-closure.json'
        asset_health = 'Data/Inventory/p2-14-asset-health.json'
        conversion_routing = 'Data/Inventory/p2-15-conversion-routing.json'
        content_health = 'Data/Inventory/p2-18-content-health.json'
    }
    $entries = @($Candidate.input_bindings.entries)
    if ($entries.Count -ne 6 -or
        @(Compare-Object @($Policy.required_input_roles) @($paths.Keys)).Count -ne 0) {
        return $false
    }
    $aggregate = [Text.StringBuilder]::new()
    for ($index = 0; $index -lt $entries.Count; ++$index) {
        $role = [string]$Policy.required_input_roles[$index]
        $entry = $entries[$index]
        $path = Join-Path $Root $paths[$role]
        if ($entry.role -cne $role -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
            $entry.sha256 -cne (Get-Sha256 $path)) { return $false }
        [void]$aggregate.Append($role).Append("`t").Append([string]$entry.sha256).Append("`n")
    }
    return $Candidate.input_bindings.aggregate_sha256 -ceq
        (Get-TextSha256 $aggregate.ToString())
}

function Test-ObjectEqual($Left, $Right) {
    return ($Left | ConvertTo-Json -Depth 100 -Compress) -ceq
        ($Right | ConvertTo-Json -Depth 100 -Compress)
}

function Test-TrackedOutput($Descriptor, [string]$ExpectedPath, [bool]$Tracked,
    [string]$Root) {
    $path = Join-Path $Root $ExpectedPath
    return (Test-ClosedFields $Descriptor @('path', 'tracked', 'bytes', 'lines', 'sha256')) -and
        $Descriptor.path -ceq $ExpectedPath -and $Descriptor.tracked -eq $Tracked -and
        [int64]$Descriptor.bytes -eq [int64](Get-Item -LiteralPath $path).Length -and
        [int]$Descriptor.lines -eq (Get-LineCount $path) -and
        $Descriptor.sha256 -ceq (Get-Sha256 $path)
}

function Test-GovernanceAndEvidence($Governance, $Evidence, $Report,
    [string]$Root, [bool]$VerifyDetail) {
    $reportRelative = 'Data/Reports/p2-20a-aux-config-reference-report.json'
    $markdownRelative = 'Data/Reports/p2-20a-aux-config-reference-report.md'
    $governanceRelative = 'Data/Governance/p2-g2-aux-config-reference.json'
    $detailRelative = 'Data/Exports/P2-20/p2-20a-aux-config-reference-candidates.jsonl'
    $reportPath = Join-Path $Root $reportRelative
    $governancePath = Join-Path $Root $governanceRelative
    $policyPath = Join-Path $Root 'Contracts/data-schema/g2-auxiliary-config-reference-policy-v1.json'
    $schemaPath = Join-Path $Root 'Contracts/data-schema/g2-auxiliary-config-reference-v1.schema.json'
    $moduleRoot = Join-Path $Root 'Tools/TMXY.G2AuxConfigClosure'
    $generatorPath = Join-Path $moduleRoot 'g2_aux_config.py'
    $wrapperPath = Join-Path $moduleRoot 'New-G2AuxiliaryConfigClosure.ps1'
    $detail = $Evidence.outputs.anonymous_candidate_export
    $governanceOk =
        (Test-ClosedFields $Governance @(
            'schema_version', 'evidence_revision', 'task_id', 'criterion_id', 'result',
            'review_execution_result', 'completion_criteria_satisfied', 'scope_complete',
            'report', 'anonymous_candidate_export', 'authority')) -and
        $Governance.schema_version -eq 1 -and $Governance.evidence_revision -ceq 'P2-20A.3' -and
        $Governance.task_id -ceq 'P2-20A' -and $Governance.criterion_id -ceq 'G2-06' -and
        $Governance.result -ceq 'BLOCKED' -and $Governance.review_execution_result -ceq 'PASS' -and
        $Governance.completion_criteria_satisfied -eq $false -and $Governance.scope_complete -eq $false -and
        $Governance.report.path -ceq $reportRelative -and
        $Governance.report.sha256 -ceq (Get-Sha256 $reportPath) -and
        $Governance.anonymous_candidate_export.tracked -eq $false -and
        [int]$Governance.anonymous_candidate_export.count -eq 3907 -and
        $Governance.anonymous_candidate_export.sha256 -ceq
            '109ba4364c8716d040528769ab33ebdc8da43ac48307c3a17822387ea644d4d5' -and
        $Governance.authority.approved_semantic_adapters -eq 0 -and
        $Governance.authority.approved_no_ref_files -eq 0 -and
        $Governance.authority.approved_roots -eq 0 -and
        $Governance.authority.g2_06_satisfied -eq $false -and
        $Governance.authority.g2_approved -eq $false -and
        $Governance.authority.p3_authorized -eq $false -and
        $Governance.authority.release_authority -eq $false

    $trackedOutputsOk =
        (Test-TrackedOutput $Evidence.outputs.report_json $reportRelative $true $Root) -and
        (Test-TrackedOutput $Evidence.outputs.report_markdown $markdownRelative $true $Root) -and
        (Test-TrackedOutput $Evidence.outputs.governance $governanceRelative $true $Root)
    $detailOk = $detail.path -ceq $detailRelative -and $detail.tracked -eq $false -and
        [int64]$detail.bytes -eq 3321747 -and [int]$detail.lines -eq 3907 -and
        $detail.sha256 -ceq '109ba4364c8716d040528769ab33ebdc8da43ac48307c3a17822387ea644d4d5'
    if ($VerifyDetail) {
        $detailOk = $detailOk -and
            (Test-TrackedOutput $detail $detailRelative $false $Root)
    }

    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
            "$relative|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    $implementationOk = $Evidence.implementation.source_files -eq 6 -and
        $Evidence.implementation.source_sha256 -ceq $sourceSha -and
        $Evidence.implementation.generator -ceq 'Tools/TMXY.G2AuxConfigClosure/g2_aux_config.py' -and
        $Evidence.implementation.generator_sha256 -ceq (Get-Sha256 $generatorPath) -and
        $Evidence.implementation.wrapper -ceq 'Tools/TMXY.G2AuxConfigClosure/New-G2AuxiliaryConfigClosure.ps1' -and
        $Evidence.implementation.wrapper_sha256 -ceq (Get-Sha256 $wrapperPath) -and
        [int]$Evidence.implementation.self_test_assertions -eq 22

    return $governanceOk -and $trackedOutputsOk -and $detailOk -and $implementationOk -and
        $Evidence.schema_version -eq 1 -and $Evidence.evidence_revision -ceq 'P2-20A.3' -and
        $Evidence.task_id -ceq 'P2-20A' -and $Evidence.criterion_id -ceq 'G2-06' -and
        $Evidence.result -ceq 'BLOCKED' -and $Evidence.review_execution_result -ceq 'PASS' -and
        $Evidence.task_status -ceq 'BLOCKED' -and $Evidence.completion_criteria_satisfied -eq $false -and
        $Evidence.scope_complete -eq $false -and $Evidence.g2_06_satisfied -eq $false -and
        $Evidence.p3_authorized -eq $false -and
        (Test-ObjectEqual $Evidence.input_bindings $Report.input_bindings) -and
        (Test-ObjectEqual $Evidence.measured_lexical_candidates $Report.measured_lexical_candidates) -and
        (Test-ObjectEqual $Evidence.adapter_state_summary $Report.adapter_state_summary) -and
        (Test-ObjectEqual $Evidence.semantic_resolution $Report.semantic_resolution) -and
        (Test-ObjectEqual $Evidence.config_closure $Report.config_closure) -and
        (Test-ObjectEqual $Evidence.blockers $Report.blockers) -and
        (Test-ObjectEqual $Evidence.authority_boundaries $Report.authority_boundaries) -and
        (Test-ObjectEqual $Evidence.disclosure $Report.disclosure) -and
        $Evidence.contracts.policy_sha256 -ceq (Get-Sha256 $policyPath) -and
        $Evidence.contracts.schema_sha256 -ceq (Get-Sha256 $schemaPath) -and
        $Evidence.reproduction.check_mode -eq $false -and
        $Evidence.reproduction.repository_mount -ceq 'read-only' -and
        $Evidence.reproduction.network -ceq 'none' -and
        $Evidence.reproduction.capabilities -ceq 'none' -and
        $Evidence.reproduction.no_new_privileges -eq $true
}

function Get-CanonicalArraySha256([object[]]$Values) {
    $ordered = [object[]]@($Values | Sort-Object -CaseSensitive)
    return Get-TextSha256 (ConvertTo-Json -InputObject $ordered -Compress)
}

function Test-DetailRecords([string[]]$Lines) {
    if ($Lines.Count -ne 3907) { return $false }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $sourceFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $counts = @{
        file = 0; candidate = 0; blocker = 0; parsed = 0; malformed = 0
        scalar = 0; nonempty = 0; resource = 0; config = 0
        asset = 0; package = 0; config_target = 0; unique = 0; ambiguous = 0
        asset_edges = 0; package_edges = 0; config_edges = 0; approved_roots = 0
        candidate_only = 0; editor_undecided = 0; malformed_blocked = 0
    }
    $previousKey = $null
    $fileFields = @(
        'adapter_id', 'adapter_status', 'closed_reason', 'closed_record',
        'config_candidate_occurrences', 'member_id', 'nonempty_scalar_locations',
        'parsed', 'record', 'resource_candidate_occurrences', 'scalar_locations',
        'schema_version', 'source_file_id', 'source_kind', 'source_role'
    )
    $candidateFields = @(
        'adapter_id', 'adapter_status', 'candidate_count', 'candidate_ids',
        'candidate_set_sha256', 'closed_reason', 'closed_record', 'member_id',
        'record', 'resolution', 'scalar_location_id', 'schema_version',
        'semantic_root_approved', 'source_file_id', 'source_kind', 'source_role',
        'source_scalar_kind', 'target_kind'
    )
    $blockerFields = @(
        'adapter_id', 'adapter_status', 'blocker_code', 'closed_reason',
        'closed_record', 'member_id', 'record', 'schema_version',
        'source_file_id', 'source_kind', 'source_role'
    )
    $roles = @(
        'client-editor-tooling', 'client-help-data', 'client-region-nested-shadow-copy',
        'client-region-runtime-data', 'client-runtime-or-engine',
        'shared-configuration-data'
    )
    $adapters = @(
        'editor-ecf-scope-review-v1', 'help-xml-no-reference-review-v1',
        'region-xml-exact-candidate-v1', 'runtime-ecf-exact-candidate-v1',
        'shared-xml-no-reference-review-v1', 'xml-tolerant-adapter-required-v1'
    )
    foreach ($line in $Lines) {
        try { $record = $line | ConvertFrom-Json -Depth 30 -DateKind String }
        catch { return $false }
        $kind = [string]$record.record
        $memberId = [string]$record.member_id
        $sortKey = "$kind`t$memberId"
        if ($null -ne $previousKey -and
            [StringComparer]::Ordinal.Compare($previousKey, $sortKey) -ge 0) { return $false }
        $previousKey = $sortKey
        if ($record.schema_version -ne 1 -or $record.closed_record -ne $true -or
            -not (Test-Sha256 $memberId) -or -not $ids.Add($memberId) -or
            -not (Test-Sha256 $record.source_file_id) -or
            [string]$record.adapter_id -cnotin $adapters -or
            [string]$record.source_kind -notin @('ecf', 'xml') -or
            [string]$record.source_role -cnotin $roles) { return $false }

        switch ($kind) {
            'auxiliary_config_file_scope' {
                if (-not (Test-ClosedFields $record $fileFields) -or
                    [string]$record.adapter_status -notin @(
                        'candidate-only', 'editor-undecided', 'malformed-blocked') -or
                    [int]$record.scalar_locations -lt 0 -or
                    [int]$record.nonempty_scalar_locations -lt 0 -or
                    [int]$record.nonempty_scalar_locations -gt [int]$record.scalar_locations -or
                    [int]$record.resource_candidate_occurrences -lt 0 -or
                    [int]$record.config_candidate_occurrences -lt 0 -or
                    -not $sourceFiles.Add([string]$record.source_file_id)) { return $false }
                ++$counts.file
                $counts.scalar += [int]$record.scalar_locations
                $counts.nonempty += [int]$record.nonempty_scalar_locations
                $counts.resource += [int]$record.resource_candidate_occurrences
                $counts.config += [int]$record.config_candidate_occurrences
                ++$counts[([string]$record.adapter_status).Replace('-', '_')]
                if ($record.parsed) { ++$counts.parsed } else { ++$counts.malformed }
            }
            'auxiliary_config_reference_candidate' {
                $candidateIds = [object[]]@($record.candidate_ids)
                $distinct = [object[]]@($candidateIds | Sort-Object -CaseSensitive -Unique)
                $target = [string]$record.target_kind
                $resolution = [string]$record.resolution
                if (-not (Test-ClosedFields $record $candidateFields) -or
                    -not (Test-Sha256 $record.scalar_location_id) -or
                    $record.semantic_root_approved -ne $false -or
                    [string]$record.adapter_status -cne 'candidate-only' -or
                    [string]$record.source_scalar_kind -notin @('ecf-assignment', 'xml-attribute') -or
                    $target -notin @('asset', 'package', 'config') -or
                    $resolution -notin @('unique', 'ambiguous') -or
                    [int]$record.candidate_count -ne $candidateIds.Count -or
                    $candidateIds.Count -ne $distinct.Count -or
                    @($candidateIds).Count -eq 0 -or
                    @(Compare-Object $candidateIds $distinct -SyncWindow 0).Count -ne 0 -or
                    @($candidateIds | Where-Object { -not (Test-Sha256 $_) }).Count -ne 0 -or
                    $record.candidate_set_sha256 -cne (Get-CanonicalArraySha256 $candidateIds) -or
                    ($resolution -eq 'unique' -and $candidateIds.Count -ne 1) -or
                    ($resolution -eq 'ambiguous' -and $candidateIds.Count -le 1)) { return $false }
                ++$counts.candidate
                switch ($target) {
                    asset { ++$counts.asset }
                    package { ++$counts.package }
                    config { ++$counts.config_target }
                }
                ++$counts[$resolution]
                $counts[($target + '_edges')] += $candidateIds.Count
                $counts.approved_roots += [int][bool]$record.semantic_root_approved
            }
            'auxiliary_config_scope_blocker' {
                if (-not (Test-ClosedFields $record $blockerFields) -or
                    [string]$record.adapter_status -cne 'malformed-blocked' -or
                    [string]$record.blocker_code -cne
                        'strict-xml-malformed-requires-byte-preserving-adapter' -or
                    [string]$record.closed_reason -cne
                        'malformed-input-is-not-repaired-or-treated-as-no-reference') {
                    return $false
                }
                ++$counts.blocker
            }
            default { return $false }
        }
    }
    return $ids.Count -eq 3907 -and $sourceFiles.Count -eq 212 -and
        $counts.file -eq 212 -and $counts.candidate -eq 3689 -and $counts.blocker -eq 6 -and
        $counts.parsed -eq 206 -and $counts.malformed -eq 6 -and
        $counts.candidate_only -eq 171 -and $counts.editor_undecided -eq 35 -and
        $counts.malformed_blocked -eq 6 -and
        $counts.scalar -eq 39522 -and $counts.nonempty -eq 39498 -and
        $counts.resource -eq 3681 -and $counts.config -eq 8 -and
        $counts.asset -eq 3043 -and $counts.package -eq 638 -and
        $counts.config_target -eq 8 -and $counts.unique -eq 3269 -and
        $counts.ambiguous -eq 420 -and $counts.asset_edges -eq 3043 -and
        $counts.package_edges -eq 1136 -and $counts.config_edges -eq 8 -and
        $counts.approved_roots -eq 0
}

$required = @(
    'Contracts/data-schema/g2-auxiliary-config-reference-policy-v1.json',
    'Contracts/data-schema/g2-auxiliary-config-reference-v1.schema.json',
    'Tools/TMXY.G2AuxConfigClosure/New-G2AuxiliaryConfigClosure.ps1',
    'Data/Reports/p2-20a-aux-config-reference-report.json',
    'Data/Reports/p2-20a-aux-config-reference-report.md',
    'Data/Governance/p2-g2-aux-config-reference.json',
    'Data/Inventory/p2-20a-aux-config-reference-evidence.json'
)
$negativeCases = [ordered]@{}
if ($VerifyDerivedSources) {
    $required += 'Data/Exports/P2-20/p2-20a-aux-config-reference-candidates.jsonl'
}
foreach ($relative in $required) {
    Add-Assertion "Required file $relative" (
        Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)
}

$policyPath = Join-Path $root 'Contracts/data-schema/g2-auxiliary-config-reference-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts/data-schema/g2-auxiliary-config-reference-v1.schema.json'
$reportPath = Join-Path $root 'Data/Reports/p2-20a-aux-config-reference-report.json'
$markdownPath = Join-Path $root 'Data/Reports/p2-20a-aux-config-reference-report.md'
$governancePath = Join-Path $root 'Data/Governance/p2-g2-aux-config-reference.json'
$evidencePath = Join-Path $root 'Data/Inventory/p2-20a-aux-config-reference-evidence.json'
$detailPath = Join-Path $root 'Data/Exports/P2-20/p2-20a-aux-config-reference-candidates.jsonl'
$wrapperPath = Join-Path $root 'Tools/TMXY.G2AuxConfigClosure/New-G2AuxiliaryConfigClosure.ps1'

# Semantic assertions are appended after the policy, schema, generator and
# evidence interfaces are present. Keep this contract fail closed while those
# independently generated artifacts are still being assembled.
if (@($assertions | Where-Object result -eq 'FAIL').Count -eq 0) {
    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $governance = Get-Content -LiteralPath $governancePath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String

    Add-Assertion 'Policy preserves measured facts and forbids semantic promotion' (
        Test-PolicySemantics $policy)
    Add-Assertion 'Report validates against the closed JSON Schema' (
        Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)
    $unknown = Copy-Document $report
    $unknown | Add-Member -NotePropertyName unexpected -NotePropertyValue $true
    Add-Assertion 'Closed Schema rejects an unknown top-level field' (
        -not (Test-JsonSchema $unknown $schemaPath))
    Add-Assertion 'Report preserves all measured file instances candidates and blockers' (
        Test-ReportSemantics $report)
    Add-Assertion 'Six upstream inputs and their aggregate are exact SHA-256 bound' (
        Test-InputBindings $report $policy $root)
    Add-Assertion 'Policy and Schema hashes are bound by the tracked report' (
        $report.contracts.policy_sha256 -ceq (Get-Sha256 $policyPath) -and
        $report.contracts.schema_sha256 -ceq (Get-Sha256 $schemaPath))
    Add-Assertion 'Governance and machine evidence bind every tracked output implementation and authority boundary' (
        Test-GovernanceAndEvidence $governance $evidence $report $root ([bool]$VerifyDerivedSources))

    $negativeCases.unknown_field_rejected = -not (Test-JsonSchema $unknown $schemaPath)
    $missingInstance = Copy-Document $report
    $missingInstance.file_instances = @($missingInstance.file_instances | Select-Object -First 211)
    $negativeCases.missing_file_instance_rejected =
        -not (Test-JsonSchema $missingInstance $schemaPath) -and
        -not (Test-ReportSemantics $missingInstance)
    $blobSubstitution = Copy-Document $report
    $blobSubstitution.measured_lexical_candidates.file_instances = 196
    $blobSubstitution.file_instances = @($blobSubstitution.file_instances | Select-Object -First 196)
    $negativeCases.unique_blob_substitution_rejected =
        -not (Test-JsonSchema $blobSubstitution $schemaPath) -and
        -not (Test-ReportSemantics $blobSubstitution)
    $malformedZero = Copy-Document $report
    $malformedZero.measured_lexical_candidates.malformed_file_instances = 0
    $malformedZero.measured_lexical_candidates.parsed_file_instances = 212
    $malformedZero.adapter_state_summary.malformed_blocked = 0
    $negativeCases.malformed_zero_forgery_rejected =
        -not (Test-JsonSchema $malformedZero $schemaPath) -and
        -not (Test-ReportSemantics $malformedZero)
    $unknownAdapterComplete = Copy-Document $report
    $unknownAdapterComplete.scope_complete = $true
    $unknownAdapterComplete.g2_06_satisfied = $true
    $unknownAdapterComplete.completion_criteria_satisfied = $true
    $negativeCases.unapproved_adapter_scope_completion_rejected =
        -not (Test-JsonSchema $unknownAdapterComplete $schemaPath) -and
        -not (Test-ReportSemantics $unknownAdapterComplete)
    foreach ($mode in @('substring_matching', 'basename_matching', 'extension_only_matching')) {
        $promoted = Copy-Document $report
        $promoted.parser_and_matching_controls.$mode = $true
        $negativeCases[($mode + '_promotion_rejected')] =
            -not (Test-JsonSchema $promoted $schemaPath) -and
            -not (Test-ReportSemantics $promoted)
    }
    $firstCandidate = Copy-Document $report
    $firstCandidate.parser_and_matching_controls.first_candidate_selection = $true
    $firstCandidate.semantic_resolution.first_candidate_selections = 1
    $negativeCases.first_candidate_selection_rejected =
        -not (Test-JsonSchema $firstCandidate $schemaPath) -and
        -not (Test-ReportSemantics $firstCandidate)
    $dropAssignment = Copy-Document $report
    $dropAssignment.parser_and_matching_controls.duplicate_ecf_assignments_preserve_order = $false
    $negativeCases.repeated_assignment_omission_rejected =
        -not (Test-JsonSchema $dropAssignment $schemaPath) -and
        -not (Test-ReportSemantics $dropAssignment)
    $reorderAssignment = Copy-Document $report
    $reorderAssignment.completion.duplicate_ecf_assignment_order_preserved = $false
    $negativeCases.repeated_assignment_reordering_rejected =
        -not (Test-JsonSchema $reorderAssignment $schemaPath) -and
        -not (Test-ReportSemantics $reorderAssignment)
    $deleteDuplicate = Copy-Document $report
    $deleteDuplicate.parser_and_matching_controls.duplicate_file_instances_preserved = $false
    $deleteDuplicate.authority_boundaries | Add-Member -NotePropertyName `
        automatic_delete_authority -NotePropertyValue $true
    $negativeCases.duplicate_or_shadow_deletion_rejected =
        -not (Test-JsonSchema $deleteDuplicate $schemaPath) -and
        -not (Test-ReportSemantics $deleteDuplicate)
    $countTamper = Copy-Document $report
    $countTamper.measured_lexical_candidates.scalar_positions = 39523
    $negativeCases.measured_count_tamper_rejected =
        -not (Test-JsonSchema $countTamper $schemaPath) -and
        -not (Test-ReportSemantics $countTamper)
    $staleNonempty = Copy-Document $report
    $staleNonempty.measured_lexical_candidates.nonempty_scalar_positions = 39500
    $negativeCases.stale_39500_nonempty_count_rejected =
        -not (Test-JsonSchema $staleNonempty $schemaPath) -and
        -not (Test-ReportSemantics $staleNonempty)
    $shaTamper = Copy-Document $report
    $shaTamper.input_bindings.entries[0].sha256 = '0' * 64
    $negativeCases.input_sha_tamper_rejected =
        (Test-JsonSchema $shaTamper $schemaPath) -and
        -not (Test-InputBindings $shaTamper $policy $root)
    $governanceTamper = Copy-Document $governance
    $governanceTamper.report.sha256 = '0' * 64
    $negativeCases.governance_report_sha_tamper_rejected =
        -not (Test-GovernanceAndEvidence $governanceTamper $evidence $report $root $false)
    $evidenceTamper = Copy-Document $evidence
    $evidenceTamper.outputs.anonymous_candidate_export.lines = 3906
    $negativeCases.evidence_detail_count_tamper_rejected =
        -not (Test-GovernanceAndEvidence $governance $evidenceTamper $report $root $false)
    $candidateLoss = Copy-Document $report
    $candidateLoss.measured_lexical_candidates.package_ambiguous_candidate_edges = 1135
    $candidateLoss.parser_and_matching_controls.ambiguous_candidates_all_retained = $false
    $negativeCases.ambiguous_candidate_omission_rejected =
        -not (Test-JsonSchema $candidateLoss $schemaPath) -and
        -not (Test-ReportSemantics $candidateLoss)
    $noMatchApproval = Copy-Document $report
    $undecided = @($noMatchApproval.file_instances |
            Where-Object adapter_state -eq 'editor-undecided' | Select-Object -First 1)
    if ($undecided.Count -eq 1) {
        $undecided[0].adapter_state = 'no-ref-approved'
        $undecided[0].reason_code = 'NO_REFERENCE_DISPOSITION_APPROVED'
        $undecided[0].authority_record_sha256 = '0' * 64
    }
    $negativeCases.no_match_as_no_ref_approval_rejected =
        $undecided.Count -eq 1 -and -not (Test-JsonSchema $noMatchApproval $schemaPath) -and
        -not (Test-ReportSemantics $noMatchApproval)

    $leakFields = [ordered]@{
        raw_scalar_value = 'forbidden'
        key_name = 'forbidden'
        file_name = 'forbidden'
        private_source_path = 'forbidden'
        source_line_number = 1
        exact_primary_key = 'forbidden'
        exact_observed_extrema = 1
    }
    $leaksRejected = $true
    foreach ($entry in $leakFields.GetEnumerator()) {
        $leak = Copy-Document $report
        $leak.file_instances[0] | Add-Member -NotePropertyName $entry.Key `
            -NotePropertyValue $entry.Value
        $leaksRejected = $leaksRejected -and -not (Test-JsonSchema $leak $schemaPath)
    }
    $negativeCases.sensitive_value_key_path_line_primary_key_extrema_leak_rejected =
        $leaksRejected
    Add-Assertion 'Coverage matching authority duplicate and disclosure negatives fail closed' (
        @($negativeCases.Values | Where-Object { -not $_ }).Count -eq 0)

    if ($VerifyDerivedSources) {
        $detailLines = [IO.File]::ReadAllLines($detailPath, [Text.Encoding]::UTF8)
        Add-Assertion 'Ignored detail is complete anonymous canonical unique and candidate-complete' (
            (Test-DetailRecords $detailLines))
        $detailOmission = [string[]]@($detailLines | Select-Object -Skip 1)
        $negativeCases.detail_member_omission_rejected =
            -not (Test-DetailRecords $detailOmission)
        $detailDuplicate = [string[]]@($detailLines + $detailLines[0])
        $negativeCases.detail_member_duplicate_rejected =
            -not (Test-DetailRecords $detailDuplicate)
        $detailReordered = [string[]]$detailLines.Clone()
        $temporary = $detailReordered[0]
        $detailReordered[0] = $detailReordered[1]
        $detailReordered[1] = $temporary
        $negativeCases.detail_record_reordering_rejected =
            -not (Test-DetailRecords $detailReordered)
        $candidateIndex = -1
        for ($index = 0; $index -lt $detailLines.Count; ++$index) {
            if ($detailLines[$index] -match '"record":"auxiliary_config_reference_candidate"' -and
                $detailLines[$index] -match '"resolution":"ambiguous"') {
                $candidateIndex = $index
                break
            }
        }
        if ($candidateIndex -ge 0) {
            $candidateMutation = $detailLines[$candidateIndex] |
                ConvertFrom-Json -Depth 30 -DateKind String
            $candidateMutation.candidate_ids = @($candidateMutation.candidate_ids[0])
            $candidateMutation.candidate_count = 1
            $candidateMutation.resolution = 'unique'
            $candidateMutation.candidate_set_sha256 =
                Get-CanonicalArraySha256 @($candidateMutation.candidate_ids)
            $firstCandidateLines = [string[]]$detailLines.Clone()
            $firstCandidateLines[$candidateIndex] =
                $candidateMutation | ConvertTo-Json -Depth 30 -Compress
            $negativeCases.detail_first_candidate_selection_rejected =
                -not (Test-DetailRecords $firstCandidateLines)
            $candidateMutation | Add-Member -NotePropertyName raw_scalar_value `
                -NotePropertyValue 'forbidden'
            $leakLines = [string[]]$detailLines.Clone()
            $leakLines[$candidateIndex] = $candidateMutation | ConvertTo-Json -Depth 30 -Compress
            $negativeCases.detail_raw_value_leak_rejected =
                -not (Test-DetailRecords $leakLines)
        }
        else {
            $negativeCases.detail_first_candidate_selection_rejected = $false
            $negativeCases.detail_raw_value_leak_rejected = $false
        }
        Add-Assertion 'Ignored detail omission duplicate reorder first-candidate and leak negatives fail closed' (
            @($negativeCases.Values | Where-Object { -not $_ }).Count -eq 0)
        & $wrapperPath -RebuildRoot $root -Check | Out-Null
        Add-Assertion 'Byte-identical isolated regeneration passes wrapper check mode' $true
    }
}

$failures = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-20A.3'
    criterion_id = 'G2-06-AUX-CONFIG'
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    contract_assertions_satisfied = $failures.Count -eq 0
    completion_criteria_satisfied = $false
    g2_approved = $false
    p3_authorized = $false
    verify_derived_sources = [bool]$VerifyDerivedSources
    assertions_passed = @($assertions | Where-Object result -eq 'PASS').Count
    assertions_failed = $failures.Count
    negative_cases = [pscustomobject]$negativeCases
    assertions = @($assertions)
} | ConvertTo-Json -Depth 100
if ($failures.Count -gt 0) { exit 1 }
