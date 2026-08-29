[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
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

function Get-TextSha256([string]$Value) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString(
            $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
    }
    finally { $algorithm.Dispose() }
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Test-InputBindings([object]$Candidate) {
    $builder = [Text.StringBuilder]::new()
    foreach ($entry in @($Candidate.input_bindings.entries)) {
        $path = Join-Path $root ([string]$entry.path).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            [int64]$entry.bytes -ne [int64](Get-Item -LiteralPath $path).Length -or
            [int]$entry.lines -ne (Get-LineCount $path) -or
            [string]$entry.sha256 -cne (Get-Sha256 $path)) {
            return $false
        }
        [void]$builder.Append(
            "$($entry.role)`t$($entry.path)`t$([bool]$entry.tracked)`t$($entry.bytes)`t$($entry.lines)`t$($entry.sha256)`n")
    }
    return [string]$Candidate.input_bindings.aggregate_sha256 -ceq
        (Get-TextSha256 $builder.ToString())
}

function Copy-Report([string]$Text) {
    return $Text | ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-SchemaRejected([object]$Candidate, [string]$SchemaPath) {
    $text = $Candidate | ConvertTo-Json -Depth 100 -Compress
    return -not ($text | Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)
}

$policyPath = Join-Path $root 'Contracts\data-schema\g2-asset-identity-normalization-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-identity-normalization-v1.schema.json'
$wrapperPath = Join-Path $root 'Tools\TMXY.G2AssetIdentityNormalization\New-G2AssetIdentityNormalization.ps1'
$generatorPath = Join-Path $root 'Tools\TMXY.G2AssetIdentityNormalization\identity_normalization.py'
$evidencePath = Join-Path $root 'Data\Inventory\p2-20a-asset-identity-normalization.json'
& {
    foreach ($required in @($policyPath, $schemaPath, $wrapperPath, $generatorPath, $evidencePath)) {
        Add-Assertion "Required file $([IO.Path]::GetFileName($required))" `
            (Test-Path -LiteralPath $required -PathType Leaf)
    }

    $firstSummary = (& $wrapperPath -RebuildRoot $root -Check) |
        ConvertFrom-Json -Depth 100
    $secondSummary = (& $wrapperPath -RebuildRoot $root -Check) |
        ConvertFrom-Json -Depth 100
    Add-Assertion 'Isolated generator summary remains fail closed' `
        ($firstSummary.result -eq 'PASS_DIAGNOSTIC' -and
            $firstSummary.task_status -eq 'BLOCKED' -and
            [int]$firstSummary.case_fold_collision_targets -eq 13 -and
            [int]$firstSummary.strict_semantic_equivalent_targets -eq 0 -and
            [int]$firstSummary.effective_ambiguous_targets -eq 15 -and
            [int]$firstSummary.candidate_selections -eq 0 -and
            $firstSummary.g2_06_satisfied -eq $false -and
            $firstSummary.p3_authorized -eq $false)

    $reportName = 'p2-20a-asset-identity-normalization-report.json'
    $detailName = 'p2-20a-asset-identity-normalization.jsonl'
    $markdownName = 'p2-20a-asset-identity-normalization-report.md'
    Add-Assertion "Deterministic output $reportName" `
        ([string]$firstSummary.report_sha256 -ceq [string]$secondSummary.report_sha256)
    Add-Assertion "Deterministic output $detailName" `
        ([string]$firstSummary.detail_sha256 -ceq [string]$secondSummary.detail_sha256)
    Add-Assertion "Deterministic output $markdownName" `
        ([string]$firstSummary.markdown_sha256 -ceq [string]$secondSummary.markdown_sha256)

    $reportPath = Join-Path $root "Data\Reports\$reportName"
    $detailPath = Join-Path $root "Data\Exports\P2-20\$detailName"
    $reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
    $report = Copy-Report $reportText
    $evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100
    Add-Assertion 'Closed report schema' `
        ($reportText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
    Add-Assertion 'Seven inputs are hash and aggregate bound' `
        (@($report.input_bindings.entries).Count -eq 7 -and (Test-InputBindings $report))
    Add-Assertion 'Policy and schema hashes are bound' `
        ([string]$report.contracts.policy_sha256 -ceq (Get-Sha256 $policyPath) -and
            [string]$report.contracts.schema_sha256 -ceq (Get-Sha256 $schemaPath))
    Add-Assertion 'Measured policy closes exactly' `
        ([Text.Json.Nodes.JsonNode]::DeepEquals(
                [Text.Json.Nodes.JsonNode]::Parse(
                    ($report.measured | ConvertTo-Json -Depth 100 -Compress)),
                [Text.Json.Nodes.JsonNode]::Parse(
                    ($policy.expected_measured | ConvertTo-Json -Depth 100 -Compress))))
    Add-Assertion 'Identity classification is measured without selection' `
        ([int]$report.measured.case_fold_collision_targets -eq 13 -and
            [int]$report.measured.case_fold_collision_edges -eq 26 -and
            [int]$report.measured.non_case_identity_targets -eq 2 -and
            [int]$report.measured.non_case_identity_edges -eq 4 -and
            [int]$report.measured.candidate_selections -eq 0)
    Add-Assertion 'Strict semantics retain every ambiguity' `
        ([int]$report.measured.strict_descriptor_equivalent_targets -eq 0 -and
            [int]$report.measured.strict_full_semantic_equivalent_targets -eq 0 -and
            [int]$report.measured.effective.resolved_targets -eq 0 -and
            [int]$report.measured.effective.ambiguous_targets -eq 15 -and
            [int]$report.measured.effective.ambiguous_edges -eq 30)
    Add-Assertion 'G2 and P3 remain unauthorized' `
        ($report.result -eq 'BLOCKED' -and $report.review_execution_result -eq 'PASS' -and
            $report.completion_criteria_satisfied -eq $false -and
            $report.scope_complete -eq $false -and $report.g2_06_satisfied -eq $false -and
            $report.p3_authorized -eq $false -and $report.g2_projection.g2_decision -eq 'BLOCKED' -and
            [int]$report.g2_projection.satisfied -eq 7 -and [int]$report.g2_projection.blocked -eq 2)
    Add-Assertion 'Strict normalization controls are explicit' `
        ($report.normalization_controls.ascii_lower_identity_grouping_only -eq $true -and
            $report.normalization_controls.unicode_casefold -eq $false -and
            $report.normalization_controls.locale_sensitive_mapping -eq $false -and
            $report.normalization_controls.identity_grouping_is_semantic_equivalence -eq $false -and
            $report.normalization_controls.nested_references_preserved -eq $true -and
            $report.normalization_controls.unknown_properties_preserved -eq $true -and
            $report.normalization_controls.floating_point_bits_preserved -eq $true -and
            $report.normalization_controls.field_order_preserved -eq $true -and
            $report.normalization_controls.coarse_equivalence_substitution -eq $false)

    $details = @([IO.File]::ReadLines($detailPath) | ForEach-Object {
            $_ | ConvertFrom-Json -Depth 100
        })
    $detailFields = @('asset_id', 'ascii_lower_identity_variants', 'candidate_count',
        'candidate_selected', 'candidate_set_sha256', 'candidates',
        'case_fold_identity_collision', 'effective_resolution', 'exact_identity_variants',
        'first_candidate_selection_used', 'raw_semantic_variants',
        'strict_descriptor_semantic_variants', 'strict_full_semantic_variants') | Sort-Object
    $candidateFields = @('body_sha256', 'candidate_id',
        'identity_normalized_descriptor_semantic_sha256', 'identity_normalized_semantic_sha256',
        'logical_name_ascii_lower_sha256', 'logical_name_sha256', 'semantic_sha256') | Sort-Object
    $detailClosed = $true
    foreach ($item in $details) {
        if ((@($item.PSObject.Properties.Name | Sort-Object) -join ',') -cne
            ($detailFields -join ',') -or
            [string]$item.asset_id -cnotmatch '^[0-9a-f]{64}$' -or
            $item.candidate_selected -ne $false -or
            $item.first_candidate_selection_used -ne $false -or
            $item.effective_resolution -ne 'AMBIGUOUS' -or @($item.candidates).Count -ne 2) {
            $detailClosed = $false
            break
        }
        foreach ($candidate in @($item.candidates)) {
            if ((@($candidate.PSObject.Properties.Name | Sort-Object) -join ',') -cne
                ($candidateFields -join ',') -or
                @($candidate.PSObject.Properties.Value | Where-Object {
                        [string]$_ -cnotmatch '^[0-9a-f]{64}$'
                    }).Count -ne 0) {
                $detailClosed = $false
                break
            }
        }
    }
    Add-Assertion 'Ignored detail is closed anonymous hash evidence' `
        ($details.Count -eq 15 -and (Get-LineCount $detailPath) -eq 15 -and $detailClosed -and
            (Get-Sha256 $detailPath) -ceq [string]$report.detail_export.sha256)
    $detailText = Get-Content -LiteralPath $detailPath -Raw -Encoding UTF8
    Add-Assertion 'Ignored detail excludes names paths and raw source data' `
        ($detailText -cnotmatch '(?i)[A-Z]:\\|/legacy/|logical_name[\"\s]*:|object_name|primary_key|source_line')
    Add-Assertion 'Disclosure boundary remains closed' `
        ($report.disclosure.anonymous_aggregate_and_hash_only -eq $true -and
            $report.disclosure.anonymous_ids_in_ignored_detail_only -eq $true -and
            $report.disclosure.raw_names -eq $false -and
            $report.disclosure.private_source_paths -eq $false -and
            $report.disclosure.exact_primary_keys -eq $false -and
            $report.disclosure.raw_table_rows -eq $false -and
            $report.disclosure.legacy_source_lines -eq $false -and
            $report.disclosure.decoded_confidential_payloads -eq $false)
    Add-Assertion 'Tracked machine evidence binds outputs implementation and isolation' `
        ($evidence.evidence_revision -eq 'P2-20A.6' -and
            $evidence.result -eq 'BLOCKED' -and $evidence.review_execution_result -eq 'PASS' -and
            $evidence.diagnostic_scope_complete -eq $true -and
            $evidence.g2_06_satisfied -eq $false -and $evidence.p3_authorized -eq $false -and
            $evidence.outputs.report_json.sha256 -eq (Get-Sha256 $reportPath) -and
            $evidence.outputs.detail_export.sha256 -eq (Get-Sha256 $detailPath) -and
            $evidence.implementation.generator_sha256 -eq (Get-Sha256 $generatorPath) -and
            $evidence.implementation.wrapper_sha256 -eq (Get-Sha256 $wrapperPath) -and
            $evidence.builder.user -eq 'tmxy' -and
            $evidence.isolation.repository_mount -eq 'read-only' -and
            $evidence.isolation.network -eq 'none' -and
            $evidence.isolation.capabilities -eq 'none' -and
            $evidence.isolation.no_new_privileges -eq $true)

    $mutated = Copy-Report $reportText
    $mutated.scope.first_candidate_selection_used = $true
    Add-Assertion 'Negative: first candidate selection rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.measured.strict_full_semantic_equivalent_targets = 1
    $mutated.measured.effective.resolved_targets = 1
    Add-Assertion 'Negative: forced equivalence rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.PSObject.Properties.Remove('task_status')
    Add-Assertion 'Negative: missing required field rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.input_bindings.entries[0].sha256 = '0' * 64
    Add-Assertion 'Negative: input hash tamper rejected by binding' `
        (-not (Test-InputBindings $mutated))
    $mutated = Copy-Report $reportText
    $mutated.g2_06_satisfied = $true
    Add-Assertion 'Negative: false G2 approval rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.p3_authorized = $true
    Add-Assertion 'Negative: false P3 authorization rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.normalization_controls.unicode_casefold = $true
    Add-Assertion 'Negative: non-ASCII fold rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.normalization_controls.locale_sensitive_mapping = $true
    Add-Assertion 'Negative: locale-sensitive fold rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.normalization_controls.nested_references_preserved = $false
    Add-Assertion 'Negative: nested-reference omission rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.normalization_controls.unknown_properties_preserved = $false
    Add-Assertion 'Negative: unknown-property omission rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.normalization_controls.floating_point_bits_preserved = $false
    Add-Assertion 'Negative: floating-point normalization rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.normalization_controls.field_order_preserved = $false
    Add-Assertion 'Negative: field reordering rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated.normalization_controls.coarse_equivalence_substitution = $true
    Add-Assertion 'Negative: coarse equivalence rejected' (Test-SchemaRejected $mutated $schemaPath)
    $mutated = Copy-Report $reportText
    $mutated | Add-Member -NotePropertyName unauthorized_extension -NotePropertyValue $true
    Add-Assertion 'Negative: unknown field rejected' (Test-SchemaRejected $mutated $schemaPath)

    $failed = @($assertions | Where-Object result -eq 'FAIL')
    [pscustomobject][ordered]@{
        schema_version = 1
        result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
        review_execution_result = 'PASS_DIAGNOSTIC'
        task_status = 'BLOCKED'
        contract_assertions_satisfied = $failed.Count -eq 0
        completion_criteria_satisfied = $false
        g2_06_satisfied = $false
        p3_authorized = $false
        assertions = $assertions.Count
        failures = $failed.Count
        details = $assertions
    } | ConvertTo-Json -Depth 20
    if ($failed.Count -ne 0) { throw 'P2-20A.6 identity-normalization contract failed.' }
}
