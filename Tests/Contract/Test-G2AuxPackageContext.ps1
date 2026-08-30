[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$SkipRegeneration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$assertions = [Collections.Generic.List[object]]::new()
$negativeCases = [ordered]@{}

function Add-A([string]$Name, [bool]$Passed) {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
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

function Test-Sha256([object]$Value) {
    return [string]$Value -cmatch '^[0-9a-f]{64}$'
}

function Copy-Json([object]$Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-JsonSchema([object]$Value, [string]$SchemaPath) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue
}

function Test-ExactFields([object]$Value, [string[]]$Expected) {
    $actual = @($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive)
    return @(Compare-Object $actual @($Expected | Sort-Object -CaseSensitive)).Count -eq 0
}

function Test-StrictCounts([object]$Value) {
    return [int]$Value.unique_total -eq 3180 -and
        [int]$Value.ambiguous_object -eq 211 -and
        [int]$Value.ambiguous_candidate_edges -eq 422 -and
        [int]$Value.unresolved_resource -eq 1 -and
        [int]$Value.first_candidate_selections -eq 0
}

function Test-EffectiveCounts([object]$Value) {
    return [int]$Value.resolved_total -eq 3391 -and
        [int]$Value.ambiguous_object -eq 0 -and
        [int]$Value.unresolved_resource -eq 1 -and
        [int]$Value.total_occurrences -eq 3392
}

function Test-PolicyBoundaries([object]$Candidate) {
    $names = @($Candidate.PSObject.Properties.Name)
    if ($names -notcontains 'required_ignored_artifact_roles' -or
        $names -notcontains 'authority_rules') { return $false }
    $expectedRoles = @('a3_detail', 'asset_catalog', 'reference_graph')
    $actualRoles = @($Candidate.required_ignored_artifact_roles)
    if ($actualRoles.Count -ne $expectedRoles.Count -or
        ($actualRoles -join "`n") -cne ($expectedRoles -join "`n")) { return $false }
    $expectedRules = @(
        'package_context_proof_is_root_approval',
        'resolved_reference_is_terminal_instance_approval',
        'shadow_equivalence_is_exclusion_authority',
        'diagnostic_can_approve_no_ref',
        'this_evidence_can_approve_g2_or_p3')
    $rules = $Candidate.authority_rules
    if ($null -eq $rules -or
        @(Compare-Object @($rules.PSObject.Properties.Name) $expectedRules `
                -CaseSensitive).Count -ne 0) {
        return $false
    }
    return @($rules.PSObject.Properties.Value | Where-Object {
            $_ -isnot [bool] -or $_ -ne $false
        }).Count -eq 0
}

function Test-ReportSemantics([object]$Candidate) {
    if ($Candidate.schema_version -ne 1 -or
        $Candidate.evidence_revision -cne 'P2-20A.9' -or
        $Candidate.task_id -cne 'P2-20A' -or
        $Candidate.criterion_id -cne 'G2-06' -or
        $Candidate.result -cne 'BLOCKED' -or
        $Candidate.review_execution_result -cne 'PASS' -or
        $Candidate.task_status -cne 'BLOCKED' -or
        $Candidate.completion_criteria_satisfied -ne $false -or
        $Candidate.scope_complete -ne $false -or
        $Candidate.g2_06_satisfied -ne $false -or
        $Candidate.p3_authorized -ne $false) { return $false }

    if (-not (Test-StrictCounts $Candidate.strict_baseline) -or
        -not (Test-EffectiveCounts $Candidate.measured.effective_resolution)) {
        return $false
    }

    $context = $Candidate.measured.package_context
    if ([int]$context.ambiguous_attempted -ne 211 -or
        [int]$context.singleton_matches -ne 211 -or
        [int]$context.zero_matches -ne 0 -or
        [int]$context.multiple_matches -ne 0 -or
        [int]$context.incompatible_context_edges -ne 211 -or
        [int]$context.first_candidate_selections -ne 0 -or
        [int]$context.order_invariant -ne 211) { return $false }

    $controls = $Candidate.consumer_controls
    if ($controls.selection_basis -cne 'PRODUCTION_PACKAGE_CONTEXT_PREFIX' -or
        $controls.package_prefix_from_observed_consumer_context -ne $true -or
        $controls.package_prefix_exact_complete_component -ne $true -or
        $controls.global_package_basename_unique_required -ne $true -or
        $controls.full_object_name_exact_match_required -ne $true -or
        $controls.candidate_order_invariant -ne $true -or
        $controls.first_candidate_selection -ne $false -or
        $controls.root_inference -ne $false -or
        $controls.shadow_instance_collapse -ne $false -or
        $controls.zero_reference_is_no_ref_approval -ne $false) { return $false }

    $technical = $Candidate.technical_state
    $authority = $Candidate.authority_state
    if ($technical.package_context_contract_proven -ne $true -or
        [int]$technical.ambiguous_object_targets_remaining -ne 0 -or
        [int]$technical.unresolved_resources_remaining -ne 1 -or
        [int]$technical.consumer_clean_region_instances -ne 134 -or
        $technical.semantic_adapter_approved -ne $false -or
        [int]$authority.approved_consumer_contracts -ne 0 -or
        [int]$authority.approved_semantic_adapters -ne 0 -or
        [int]$authority.approved_no_reference_instances -ne 0 -or
        [int]$authority.approved_roots -ne 0 -or
        [int]$authority.terminal_instances -ne 0 -or
        [int]$authority.nonterminal_instances -ne 212 -or
        $authority.technical_resolution_is_semantic_approval -ne $false) { return $false }

    $detail = $Candidate.detail_export
    if ($detail.path -cne 'Data/Exports/P2-20/p2-20a-aux-package-context.jsonl' -or
        $detail.tracked -ne $false -or [int]$detail.lines -ne 135 -or
        -not (Test-Sha256 $detail.sha256)) { return $false }

    $disclosure = $Candidate.disclosure
    return [int]$Candidate.preserved_blockers.ecf_parser_parity_gaps -eq 3 -and
        [int]$Candidate.preserved_blockers.ecf_assignments_missed -eq 4 -and
        [int]$Candidate.preserved_blockers.malformed_instances -eq 6 -and
        [int]$Candidate.preserved_blockers.approved_roots -eq 0 -and
        [int]$Candidate.preserved_blockers.nonterminal_instances -eq 212 -and
        [int]$Candidate.preserved_blockers.config_edges_unapproved -eq 8 -and
        $disclosure.tracked_aggregate_and_hash_only -eq $true -and
        $disclosure.anonymous_detail_only -eq $true -and
        $disclosure.raw_values -eq $false -and
        $disclosure.key_names -eq $false -and
        $disclosure.file_names -eq $false -and
        $disclosure.private_source_paths -eq $false -and
        $disclosure.source_line_numbers -eq $false -and
        $disclosure.legacy_source_lines -eq $false
}

function Test-DetailRecords([string[]]$Lines, [string]$SchemaPath) {
    if ($Lines.Count -ne 135) { return $false }
    $previousId = $null
    $instanceIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $proofIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $strict = @{ resolved = 0; ambiguous = 0; edges = 0; unresolved = 0 }
    $effective = @{ resolved = 0; ambiguous = 0; unresolved = 0; total = 0 }
    $proofCount = 0
    foreach ($line in $Lines) {
        try { $record = $line | ConvertFrom-Json -Depth 100 -DateKind String }
        catch { return $false }
        if (-not (Test-JsonSchema $record $SchemaPath) -or
            -not (Test-ExactFields $record @(
                    'schema_version', 'instance_id', 'technical_state',
                    'strict_counts', 'effective_counts', 'object_proofs',
                    'proof_set_sha256')) -or
            $record.schema_version -ne 1 -or -not (Test-Sha256 $record.instance_id) -or
            -not $instanceIds.Add([string]$record.instance_id) -or
            ($null -ne $previousId -and
                [StringComparer]::Ordinal.Compare($previousId,
                    [string]$record.instance_id) -ge 0) -or
            -not (Test-Sha256 $record.proof_set_sha256)) { return $false }
        $previousId = [string]$record.instance_id

        $strict.resolved += [int]$record.strict_counts.resolved
        $strict.ambiguous += [int]$record.strict_counts.ambiguous
        $strict.unresolved += [int]$record.strict_counts.unresolved
        $effective.resolved += [int]$record.effective_counts.resolved
        $effective.ambiguous += [int]$record.effective_counts.ambiguous
        $effective.unresolved += [int]$record.effective_counts.unresolved
        $effective.total += [int]$record.effective_counts.resolved +
            [int]$record.effective_counts.ambiguous +
            [int]$record.effective_counts.unresolved

        foreach ($proof in @($record.object_proofs)) {
            if (-not (Test-ExactFields $proof @(
                        'occurrence_id', 'strict_state', 'candidate_count',
                        'candidate_set_sha256', 'package_context_sha256',
                        'compatible_count', 'selected_candidate_id',
                        'order_invariant', 'proof_sha256')) -or
                -not (Test-Sha256 $proof.occurrence_id) -or
                -not $proofIds.Add([string]$proof.occurrence_id) -or
                $proof.strict_state -cne 'AMBIGUOUS' -or
                [int]$proof.candidate_count -ne 2 -or
                -not (Test-Sha256 $proof.candidate_set_sha256) -or
                -not (Test-Sha256 $proof.package_context_sha256) -or
                [int]$proof.compatible_count -ne 1 -or
                -not (Test-Sha256 $proof.selected_candidate_id) -or
                $proof.order_invariant -ne $true -or
                -not (Test-Sha256 $proof.proof_sha256)) { return $false }
            $strict.edges += [int]$proof.candidate_count
            ++$proofCount
        }
    }
    return $instanceIds.Count -eq 135 -and $proofIds.Count -eq 211 -and
        $proofCount -eq 211 -and $strict.resolved -eq 3180 -and
        $strict.ambiguous -eq 211 -and $strict.edges -eq 422 -and
        $strict.unresolved -eq 1 -and $effective.resolved -eq 3391 -and
        $effective.ambiguous -eq 0 -and $effective.unresolved -eq 1 -and
        $effective.total -eq 3392
}

function Invoke-ContainerSelfTest([string]$Root, [string]$GeneratorPath) {
    $lockPath = Join-Path $Root 'Data\Toolchain\toolchain.lock.json'
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $imageReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedImageId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $imageReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -cne $expectedImageId -or
        [string]$image[0].Config.User -cne 'tmxy') { return $null }
    $relativeGenerator = [IO.Path]::GetRelativePath($Root, $GeneratorPath).Replace('\', '/')
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $output = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$Root,dst=/workspace,readonly" `
        --tmpfs '/tmp:rw,nosuid,nodev,size=64m' $imageReference `
        python3 "/workspace/$relativeGenerator" --self-test
    if ($LASTEXITCODE -ne 0) { return $null }
    return $output | ConvertFrom-Json -Depth 100 -DateKind String
}

$relativePaths = [ordered]@{
    policy = 'Contracts/data-schema/g2-aux-package-context-policy-v1.json'
    schema = 'Contracts/data-schema/g2-aux-package-context-v1.schema.json'
    detail_schema = 'Contracts/data-schema/g2-aux-package-context-detail-v1.schema.json'
    generator = 'Tools/TMXY.G2AuxPackageContext/g2_aux_package_context.py'
    support = 'Tools/TMXY.G2AuxPackageContext/aux_package_context_support.py'
    wrapper = 'Tools/TMXY.G2AuxPackageContext/New-G2AuxPackageContext.ps1'
    readme = 'Tools/TMXY.G2AuxPackageContext/README.md'
    format = 'Docs/Formats/G2-AUX-PACKAGE-CONTEXT.md'
    report = 'Data/Reports/p2-20a-aux-package-context-report.json'
    markdown = 'Data/Reports/p2-20a-aux-package-context-report.md'
    evidence = 'Data/Inventory/p2-20a-aux-package-context.json'
    detail = 'Data/Exports/P2-20/p2-20a-aux-package-context.jsonl'
}
$paths = [ordered]@{}
foreach ($entry in $relativePaths.GetEnumerator()) {
    $paths[$entry.Key] = Join-Path $root $entry.Value
    Add-A "Required artifact $($entry.Value)" `
        (Test-Path -LiteralPath $paths[$entry.Key] -PathType Leaf)
}

$sizeLimits = [ordered]@{
    policy = 32768; schema = 65536; detail_schema = 32768
    generator = 131072; support = 98304; wrapper = 32768; readme = 16384
    format = 32768; report = 65536; markdown = 32768; evidence = 32768
    detail = 1048576
}
foreach ($entry in $sizeLimits.GetEnumerator()) {
    if (Test-Path -LiteralPath $paths[$entry.Key] -PathType Leaf) {
        $size = (Get-Item -LiteralPath $paths[$entry.Key]).Length
        Add-A "Bounded artifact size $($relativePaths[$entry.Key])" `
            ($size -gt 0 -and $size -le [int64]$entry.Value)
    }
}

if (@($assertions | Where-Object result -eq 'FAIL').Count -eq 0) {
    if (-not $SkipRegeneration) {
        $wrapperText = & $paths.wrapper -RebuildRoot $root -Check
        $wrapperResult = $wrapperText | ConvertFrom-Json -Depth 100 -DateKind String
        Add-A 'Default wrapper performs byte-identical deterministic regeneration' `
            ($wrapperResult.result -eq 'BLOCKED' -and
                $wrapperResult.review_execution_result -eq 'PASS' -and
                $wrapperResult.task_status -eq 'BLOCKED' -and
                [int]$wrapperResult.effective_resolved -eq 3391 -and
                [int]$wrapperResult.unresolved_resources -eq 1)
        $selfTest = Invoke-ContainerSelfTest $root $paths.generator
        $selfNegatives = if ($null -eq $selfTest) { @($false) } else {
            @($selfTest.negative_cases.PSObject.Properties.Value)
        }
        Add-A 'Locked non-root no-network container self-test passes all negatives' `
            ($null -ne $selfTest -and $selfTest.result -eq 'PASS' -and
                [int]$selfTest.assertions -ge 7 -and
                @($selfNegatives | Where-Object { $_ -ne $true }).Count -eq 0)
        $negativeCases.container_zero_prefix_match_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.zero_context_match_rejected -eq $true
        $negativeCases.container_multiple_prefix_matches_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.multiple_context_matches_rejected -eq $true
        $negativeCases.container_first_candidate_injection_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.first_candidate_selection_rejected -eq $true
        $negativeCases.container_root_injection_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.root_injection_rejected -eq $true
        $negativeCases.container_shadow_injection_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.shadow_collapse_rejected -eq $true
        $negativeCases.container_zero_ref_injection_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.zero_reference_promotion_rejected -eq $true
        $negativeCases.container_policy_authority_rule_mutation_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.authority_rule_mutation_rejected -eq $true
        $negativeCases.container_policy_authority_rule_type_mutation_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.authority_rule_type_mutation_rejected -eq $true
        $negativeCases.container_policy_ignored_role_mutation_rejected =
            $null -ne $selfTest -and
            $selfTest.negative_cases.ignored_artifact_role_mutation_rejected -eq $true
    }

    $policyText = Get-Content -LiteralPath $paths.policy -Raw -Encoding UTF8
    $policy = $policyText | ConvertFrom-Json -Depth 100 -DateKind String
    $reportText = Get-Content -LiteralPath $paths.report -Raw -Encoding UTF8
    $report = $reportText | ConvertFrom-Json -Depth 100 -DateKind String
    $evidenceText = Get-Content -LiteralPath $paths.evidence -Raw -Encoding UTF8
    $evidence = $evidenceText | ConvertFrom-Json -Depth 100 -DateKind String
    $detailLines = [IO.File]::ReadAllLines($paths.detail, [Text.Encoding]::UTF8)

    Add-A 'Tracked report validates against closed JSON Schema' `
        ($reportText | Test-Json -SchemaFile $paths.schema -ErrorAction SilentlyContinue)
    Add-A 'Policy identity and fail-closed authority are exact' `
        ($policy.schema_version -eq 1 -and $policy.evidence_revision -eq 'P2-20A.9' -and
            $policy.task_id -eq 'P2-20A' -and $policy.criterion_id -eq 'G2-06' -and
            (Test-StrictCounts $policy.strict_baseline) -and
            [int]$policy.expected_measured.package_context.ambiguous_attempted -eq 211 -and
            [int]$policy.expected_measured.package_context.singleton_matches -eq 211 -and
            [int]$policy.expected_measured.package_context.zero_matches -eq 0 -and
            [int]$policy.expected_measured.package_context.multiple_matches -eq 0 -and
            [int]$policy.expected_measured.package_context.incompatible_context_edges -eq 211 -and
            [int]$policy.expected_measured.package_context.first_candidate_selections -eq 0 -and
            (Test-EffectiveCounts $policy.expected_measured.effective_resolution) -and
            [int]$policy.expected_measured.effective_region_instances.resolved_only -eq 134 -and
            [int]$policy.expected_measured.effective_region_instances.unresolved_resource -eq 1 -and
            [int]$policy.authority_state.approved_consumer_contracts -eq 0 -and
            [int]$policy.authority_state.approved_roots -eq 0 -and
            [int]$policy.authority_state.terminal_instances -eq 0 -and
            [int]$policy.authority_state.nonterminal_instances -eq 212 -and
            (Test-PolicyBoundaries $policy))
    Add-A 'Strict baseline technical recovery and non-authority state are exact' `
        (Test-ReportSemantics $report)
    Add-A 'Ignored detail has exactly 135 closed anonymous records and 211 proofs' `
        (Test-DetailRecords $detailLines $paths.detail_schema)
    Add-A 'Ignored detail line count and SHA-256 are exact bound evidence' `
        ([int]$report.detail_export.lines -eq (Get-LineCount $paths.detail) -and
            $report.detail_export.sha256 -ceq (Get-Sha256 $paths.detail) -and
            [int]$evidence.detail_export.lines -eq 135 -and
            $evidence.detail_export.sha256 -ceq (Get-Sha256 $paths.detail))
    Add-A 'Tracked evidence binds report markdown policy schemas and implementation' `
        ($evidence.report_json.sha256 -ceq (Get-Sha256 $paths.report) -and
            $evidence.report_markdown.sha256 -ceq (Get-Sha256 $paths.markdown) -and
            $evidence.contracts.policy_sha256 -ceq (Get-Sha256 $paths.policy) -and
            $evidence.contracts.schema_sha256 -ceq (Get-Sha256 $paths.schema) -and
            $evidence.contracts.detail_schema_sha256 -ceq (Get-Sha256 $paths.detail_schema) -and
            $evidence.implementation.generator_sha256 -ceq (Get-Sha256 $paths.generator) -and
            $evidence.implementation.support_sha256 -ceq (Get-Sha256 $paths.support))
    Add-A 'Evidence records read-only isolated non-root execution' `
        ($evidence.isolation.network -eq 'none' -and
            $evidence.isolation.repository_mount -eq 'read-only' -and
            $evidence.isolation.legacy_source_mount -eq 'read-only' -and
            $evidence.isolation.builder_user -eq 'tmxy' -and
            $evidence.isolation.no_new_privileges -eq $true)

    $orderProofs = @($detailLines | ForEach-Object {
            @((ConvertFrom-Json $_ -Depth 100 -DateKind String).object_proofs)
        })
    $negativeCases.candidate_order_does_not_change_selection =
        $orderProofs.Count -eq 211 -and
        @($orderProofs | Where-Object order_invariant -ne $true).Count -eq 0 -and
        [int]$report.measured.package_context.order_invariant -eq 211

    $authorityRuleNames = @(
        'package_context_proof_is_root_approval',
        'resolved_reference_is_terminal_instance_approval',
        'shadow_equivalence_is_exclusion_authority',
        'diagnostic_can_approve_no_ref',
        'this_evidence_can_approve_g2_or_p3')
    $allAuthorityMutationsRejected = $true
    foreach ($ruleName in $authorityRuleNames) {
        $policyMutation = Copy-Json $policy
        $policyMutation.authority_rules.$ruleName = $true
        $allAuthorityMutationsRejected = $allAuthorityMutationsRejected -and
            -not (Test-PolicyBoundaries $policyMutation)
    }
    $negativeCases.policy_authority_rule_mutations_rejected =
        $allAuthorityMutationsRejected
    $authorityTypeMutation = Copy-Json $policy
    $authorityTypeMutation.authority_rules.diagnostic_can_approve_no_ref = 0
    $negativeCases.policy_authority_rule_type_mutation_rejected =
        -not (Test-PolicyBoundaries $authorityTypeMutation)
    $ignoredRoleOmission = Copy-Json $policy
    $ignoredRoleOmission.required_ignored_artifact_roles = @('a3_detail', 'asset_catalog')
    $ignoredRoleReorder = Copy-Json $policy
    $ignoredRoleReorder.required_ignored_artifact_roles = @(
        'asset_catalog', 'a3_detail', 'reference_graph')
    $negativeCases.policy_ignored_role_mutations_rejected =
        -not (Test-PolicyBoundaries $ignoredRoleOmission) -and
        -not (Test-PolicyBoundaries $ignoredRoleReorder)

    foreach ($prefixCount in @(0, 2)) {
        $mutated = Copy-Json $report
        $mutated.measured.package_context.singleton_matches = 210
        $mutated.measured.package_context.incompatible_context_edges = 212 - $prefixCount
        $negativeCases["prefix_match_count_${prefixCount}_fails_closed"] =
            -not (Test-ReportSemantics $mutated)
    }
    $first = Copy-Json $report
    $first.consumer_controls.first_candidate_selection = $true
    $first.measured.package_context.first_candidate_selections = 1
    $negativeCases.first_candidate_injection_rejected =
        -not (Test-JsonSchema $first $paths.schema) -and -not (Test-ReportSemantics $first)
    $rootInjection = Copy-Json $report
    $rootInjection.consumer_controls.root_inference = $true
    $rootInjection.authority_state.approved_roots = 1
    $negativeCases.root_injection_rejected =
        -not (Test-JsonSchema $rootInjection $paths.schema) -and
        -not (Test-ReportSemantics $rootInjection)
    $shadow = Copy-Json $report
    $shadow.consumer_controls.shadow_instance_collapse = $true
    $negativeCases.shadow_injection_rejected =
        -not (Test-JsonSchema $shadow $paths.schema) -and -not (Test-ReportSemantics $shadow)
    $zeroReference = Copy-Json $report
    $zeroReference.consumer_controls.zero_reference_is_no_ref_approval = $true
    $zeroReference.authority_state.approved_no_reference_instances = 1
    $negativeCases.zero_reference_injection_rejected =
        -not (Test-JsonSchema $zeroReference $paths.schema) -and
        -not (Test-ReportSemantics $zeroReference)
    $unknown = Copy-Json $report
    $unknown | Add-Member -NotePropertyName private_source_path -NotePropertyValue 'forbidden'
    $negativeCases.private_path_injection_rejected =
        -not (Test-JsonSchema $unknown $paths.schema)
    $detailLeak = $detailLines[0] | ConvertFrom-Json -Depth 100 -DateKind String
    $detailLeak | Add-Member -NotePropertyName raw_value -NotePropertyValue 'forbidden'
    $negativeCases.detail_raw_value_injection_rejected =
        -not (Test-JsonSchema $detailLeak $paths.detail_schema)
    $lineLeak = $detailLines[0] | ConvertFrom-Json -Depth 100 -DateKind String
    $lineLeak | Add-Member -NotePropertyName source_line -NotePropertyValue 1
    $negativeCases.detail_source_line_injection_rejected =
        -not (Test-JsonSchema $lineLeak $paths.detail_schema)
    Add-A 'Policy order prefix-count authority and disclosure mutations fail closed' `
        (@($negativeCases.Values | Where-Object { $_ -ne $true }).Count -eq 0)
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-20A.9'
    criterion_id = 'G2-06-AUX-PACKAGE-CONTEXT'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    contract_assertions_satisfied = $failed.Count -eq 0
    completion_criteria_satisfied = $false
    g2_06_satisfied = $false
    p3_authorized = $false
    regeneration_skipped = [bool]$SkipRegeneration
    assertions = $assertions.Count
    failures = $failed.Count
    negative_cases = [pscustomobject]$negativeCases
    details = @($assertions)
} | ConvertTo-Json -Depth 100
if ($failed.Count -ne 0) { throw 'P2-20A.9 auxiliary package-context contract failed.' }
