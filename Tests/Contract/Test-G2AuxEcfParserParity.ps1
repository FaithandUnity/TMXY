[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources,
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

function Copy-Json([object]$Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-JsonSchema([object]$Value, [string]$SchemaPath) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue
}

function Test-Sha256([object]$Value) {
    return [string]$Value -cmatch '^[0-9a-f]{64}$'
}

function Test-ExactFields([object]$Value, [string[]]$Expected) {
    $actual = @($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive)
    return @(Compare-Object $actual @($Expected | Sort-Object -CaseSensitive) `
            -CaseSensitive).Count -eq 0
}

function Test-ReportSemantics([object]$Candidate) {
    if ($Candidate.schema_version -ne 1 -or $Candidate.evidence_revision -cne 'P2-20A.10' -or
        $Candidate.result -cne 'BLOCKED' -or $Candidate.review_execution_result -cne 'PASS' -or
        $Candidate.task_status -cne 'BLOCKED' -or
        [bool]$Candidate.completion_criteria_satisfied -or
        -not [bool]$Candidate.diagnostic_scope_complete -or [bool]$Candidate.scope_complete -or
        [bool]$Candidate.g2_06_satisfied -or [bool]$Candidate.p3_authorized) { return $false }
    $history = $Candidate.historical_a5
    $source = $Candidate.source_derived
    $actual = $source.a3_actual_vs_reference
    $filtered = $source.correct_plain_a3_filter_vs_legacy
    if ($history.evidence_revision -cne 'P2-20A.5' -or
        -not [bool]$history.immutable_baseline -or [int]$history.parity_instances -ne 61 -or
        [int]$history.difference_instances -ne 3 -or [int]$history.legacy_pair_count_delta -ne 4 -or
        [int]$history.a3_only_pair_records -ne 3 -or [int]$history.legacy_only_pair_records -ne 7 -or
        [int]$actual.parity_instances -ne 51 -or [int]$actual.difference_instances -ne 13 -or
        [int]$actual.left_pair_records -ne 2065 -or [int]$actual.right_pair_records -ne 2069 -or
        [int]$actual.shared_pair_records -ne 2052 -or [int]$actual.left_only_pair_records -ne 13 -or
        [int]$actual.right_only_pair_records -ne 17 -or
        [int]$filtered.parity_instances -ne 63 -or [int]$filtered.difference_instances -ne 1 -or
        [int]$filtered.left_only_pair_records -ne 0 -or [int]$filtered.right_only_pair_records -ne 4) {
        return $false
    }
    if ($source.derivation_scope -cne 'SOURCE_DERIVED_DIAGNOSTIC_ONLY' -or
        [int]$source.population.instances -ne 64 -or [int]$source.population.source_bytes -ne 57011 -or
        [int]$source.reference_transform_ports.parity_instances -ne 64 -or
        [int]$source.reference_transform_ports.frozen_a3_body_difference_instances -ne 13 -or
        [int]$source.reference_pair_ports.parity_instances -ne 64 -or
        [int]$source.reference_pair_ports.reference_pair_records -ne 2069 -or
        [int]$source.newline.crlf_only_instances -ne 64 -or [int]$source.newline.mixed_instances -ne 0 -or
        [int]$source.newline.lone_lf -ne 0 -or [int]$source.newline.lone_cr -ne 0 -or
        [int]$source.newline.nul -ne 0) { return $false }
    if ($Candidate.detail_export.path -cne
        'Data/Exports/P2-20/p2-20a-aux-ecf-parser-parity.jsonl' -or
        [bool]$Candidate.detail_export.tracked -or [int]$Candidate.detail_export.lines -ne 64) {
        return $false
    }
    $runtime = $Candidate.runtime_boundaries
    if (@($runtime.PSObject.Properties.Value | Where-Object { $_ -isnot [bool] -or $_ }).Count -ne 0) {
        return $false
    }
    $controls = $Candidate.candidate_projections.controls
    if (-not [bool]$controls.candidate_only -or -not [bool]$controls.frozen_indexes_only -or
        @($controls.PSObject.Properties | Where-Object {
                $_.Name -notin @('candidate_only', 'frozen_indexes_only') -and [int]$_.Value -ne 0
            }).Count -ne 0) { return $false }
    return $Candidate.g2_projection.g2_decision -ceq 'BLOCKED' -and
        [int]$Candidate.g2_projection.satisfied -eq 7 -and
        [int]$Candidate.g2_projection.blocked -eq 2
}

$paths = [ordered]@{
    policy = Join-Path $root 'Contracts\data-schema\g2-aux-ecf-parser-parity-policy-v1.json'
    schema = Join-Path $root 'Contracts\data-schema\g2-aux-ecf-parser-parity-v1.schema.json'
    detail_schema = Join-Path $root 'Contracts\data-schema\g2-aux-ecf-parser-parity-detail-v1.schema.json'
    report = Join-Path $root 'Data\Reports\p2-20a-aux-ecf-parser-parity-report.json'
    markdown = Join-Path $root 'Data\Reports\p2-20a-aux-ecf-parser-parity-report.md'
    evidence = Join-Path $root 'Data\Inventory\p2-20a-aux-ecf-parser-parity.json'
    detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-aux-ecf-parser-parity.jsonl'
    wrapper = Join-Path $root 'Tools\TMXY.G2AuxEcfParserParity\New-G2AuxEcfParserParity.ps1'
    generator = Join-Path $root 'Tools\TMXY.G2AuxEcfParserParity\g2_aux_ecf_parser_parity.py'
    support = Join-Path $root 'Tools\TMXY.G2AuxEcfParserParity\aux_ecf_parser_parity_support.py'
}

foreach ($entry in $paths.GetEnumerator()) {
    Add-A "artifact_exists_$($entry.Key)" (Test-Path -LiteralPath $entry.Value -PathType Leaf)
}

if (-not $SkipRegeneration) {
    $regenerated = & $paths.wrapper -RebuildRoot $root `
        -LegacySourceRoot 'E:\QQXYCodeDev\ClientCode' -Check |
        ConvertFrom-Json -Depth 50
    Add-A 'deterministic_regeneration' (
        $regenerated.result -ceq 'BLOCKED' -and
        $regenerated.review_execution_result -ceq 'PASS' -and
        [int]$regenerated.a3_actual_difference_instances -eq 13 -and
        [int]$regenerated.legacy_pair_records_absent_from_a3 -eq 4 -and
        -not [bool]$regenerated.legacy_runtime_executed -and
        -not [bool]$regenerated.runtime_binary_parity_claimed)
}

$policy = Get-Content -LiteralPath $paths.policy -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$report = Get-Content -LiteralPath $paths.report -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$evidence = Get-Content -LiteralPath $paths.evidence -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String

Add-A 'report_schema_closed' (Test-JsonSchema $report $paths.schema)
Add-A 'report_semantics_closed' (Test-ReportSemantics $report)
Add-A 'policy_identity' (
    $policy.schema_version -eq 1 -and $policy.evidence_revision -ceq 'P2-20A.10' -and
    $policy.task_id -ceq 'P2-20A' -and $policy.criterion_id -ceq 'G2-06')
Add-A 'report_evidence_cross_binding' (
    $evidence.evidence_revision -ceq 'P2-20A.10' -and $evidence.result -ceq 'BLOCKED' -and
    $evidence.review_execution_result -ceq 'PASS' -and
    [int]$evidence.report_json.bytes -eq (Get-Item -LiteralPath $paths.report).Length -and
    $evidence.report_json.sha256 -ceq (Get-Sha256 $paths.report) -and
    [int]$evidence.report_markdown.bytes -eq (Get-Item -LiteralPath $paths.markdown).Length -and
    $evidence.report_markdown.sha256 -ceq (Get-Sha256 $paths.markdown) -and
    ($evidence.historical_a5 | ConvertTo-Json -Depth 20 -Compress) -ceq
        ($report.historical_a5 | ConvertTo-Json -Depth 20 -Compress) -and
    ($evidence.source_derived | ConvertTo-Json -Depth 30 -Compress) -ceq
        ($report.source_derived | ConvertTo-Json -Depth 30 -Compress) -and
    ($evidence.runtime_boundaries | ConvertTo-Json -Depth 10 -Compress) -ceq
        ($report.runtime_boundaries | ConvertTo-Json -Depth 10 -Compress))
Add-A 'contract_hashes_bound' (
    $report.contracts.policy_sha256 -ceq (Get-Sha256 $paths.policy) -and
    $report.contracts.schema_sha256 -ceq (Get-Sha256 $paths.schema) -and
    $report.contracts.detail_schema_sha256 -ceq (Get-Sha256 $paths.detail_schema) -and
    $evidence.implementation.generator_sha256 -ceq (Get-Sha256 $paths.generator) -and
    $evidence.implementation.support_sha256 -ceq (Get-Sha256 $paths.support) -and
    [int]$evidence.implementation.self_test_assertions -ge 24)

$requiredRoles = @(
    'auxiliary_inventory', 'a3_report', 'a3_evidence', 'a3_parser_implementation',
    'a5_report', 'a5_evidence', 'a5_policy', 'a5_support_implementation',
    'a9_report', 'a9_evidence', 'asset_inventory', 'reference_closure',
    'p2_05_transform_implementation', 'policy', 'schema', 'detail_schema',
    'a3_detail', 'asset_catalog', 'reference_graph')
$actualRoles = @($report.input_bindings.entries.role) + @($report.input_bindings.ignored_artifacts.role)
Add-A 'ordered_input_roles_closed' (
    ($actualRoles -join "`n") -ceq ($requiredRoles -join "`n") -and
    (@($policy.required_input_roles) -join "`n") -ceq ($requiredRoles -join "`n"))
$inputHashesValid = @($report.input_bindings.entries | Where-Object {
        -not (Test-Sha256 $_.sha256)
    }).Count -eq 0
Add-A 'tracked_input_hashes_valid' $inputHashesValid

$ignoredExpected = [ordered]@{
    a3_detail = 'Data/Exports/P2-20/p2-20a-aux-config-reference-candidates.jsonl'
    asset_catalog = 'Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl'
    reference_graph = 'Data/Exports/P2-13/p2-13-reference-closure.jsonl'
}
$ignoredValid = @($report.input_bindings.ignored_artifacts).Count -eq 3
foreach ($binding in $report.input_bindings.ignored_artifacts) {
    $expected = $ignoredExpected[[string]$binding.role]
    $full = if ($null -ne $expected) { Join-Path $root $expected.Replace('/', '\') } else { '' }
    $ignoredValid = $ignoredValid -and $null -ne $expected -and
        [string]$binding.path -ceq $expected -and -not [bool]$binding.tracked -and
        (Test-Path -LiteralPath $full -PathType Leaf) -and
        [int]$binding.bytes -eq (Get-Item -LiteralPath $full).Length -and
        [int]$binding.lines -eq (Get-LineCount $full) -and
        [string]$binding.sha256 -ceq (Get-Sha256 $full)
}
Add-A 'ignored_artifact_bindings_closed' $ignoredValid

$legacyRoles = @('configuration_platform_contract', 'cstring_contract',
    'encrypted_config_reader', 'line_and_pair_parser', 'reflection_config_loader', 'string_contract')
Add-A 'legacy_source_hash_bindings_closed' (
    (@($report.input_bindings.legacy_sources.role) -join "`n") -ceq ($legacyRoles -join "`n") -and
    @($report.input_bindings.legacy_sources | Where-Object {
            -not (Test-Sha256 $_.sha256)
        }).Count -eq 0)

$detailLines = [Collections.Generic.List[object]]::new()
$detailValid = $true
foreach ($line in [IO.File]::ReadLines($paths.detail)) {
    $record = $line | ConvertFrom-Json -Depth 100 -DateKind String
    $detailLines.Add($record)
    if (-not (Test-JsonSchema $record $paths.detail_schema)) { $detailValid = $false }
}
Add-A 'detail_schema_closed_for_all_records' ($detailValid -and $detailLines.Count -eq 64)
Add-A 'detail_binding_closed' (
    $report.detail_export.path -ceq 'Data/Exports/P2-20/p2-20a-aux-ecf-parser-parity.jsonl' -and
    -not [bool]$report.detail_export.tracked -and [int]$report.detail_export.lines -eq 64 -and
    [int]$report.detail_export.bytes -eq (Get-Item -LiteralPath $paths.detail).Length -and
    $report.detail_export.sha256 -ceq (Get-Sha256 $paths.detail) -and
    ($evidence.detail_export | ConvertTo-Json -Compress) -ceq
        ($report.detail_export | ConvertTo-Json -Compress))
Add-A 'detail_population_and_partition_closed' (
    @($detailLines.instance_id | Sort-Object -Unique).Count -eq 64 -and
    @($detailLines | Where-Object length_remainder -eq 0).Count -eq 15 -and
    @($detailLines | Where-Object length_remainder -eq 1).Count -eq 21 -and
    @($detailLines | Where-Object length_remainder -eq 2).Count -eq 14 -and
    @($detailLines | Where-Object length_remainder -eq 3).Count -eq 14 -and
    @($detailLines | Where-Object { -not $_.current_transform_matches_reference }).Count -eq 13 -and
    @($detailLines | Where-Object { -not $_.current_a3_pairs_match_reference }).Count -eq 13 -and
    @($detailLines | Where-Object { -not $_.correct_plain_a3_filter_matches_reference }).Count -eq 1 -and
    @($detailLines | Where-Object { -not $_.transform_ports_equal -or
                -not $_.reference_pair_ports_equal -or $_.newline_profile -cne 'CRLF_ONLY' }).Count -eq 0)

$detailRelative = 'Data/Exports/P2-20/p2-20a-aux-ecf-parser-parity.jsonl'
$trackedDetail = @(git -C $root ls-files --error-unmatch -- $detailRelative 2>$null)
$detailIgnored = @(git -C $root check-ignore -- $detailRelative 2>$null)
Add-A 'detail_is_ignored_and_untracked' (
    $trackedDetail.Count -eq 0 -and $detailIgnored.Count -eq 1 -and
    $detailIgnored[0] -ceq $detailRelative)
$candidateEcf = @(git -C $root ls-files --cached --others --exclude-standard -- '*.ecf')
Add-A 'no_ecf_payload_tracked_or_candidate' ($candidateEcf.Count -eq 0)

$unknownReport = Copy-Json $report
$unknownReport | Add-Member -NotePropertyName raw_value -NotePropertyValue 'forbidden'
$negativeCases.unknown_report_field_rejected = -not (Test-JsonSchema $unknownReport $paths.schema)
$runtimePromotion = Copy-Json $report
$runtimePromotion.runtime_boundaries.legacy_runtime_executed = $true
$negativeCases.runtime_execution_promotion_rejected =
    -not (Test-JsonSchema $runtimePromotion $paths.schema) -and
    -not (Test-ReportSemantics $runtimePromotion)
$binaryPromotion = Copy-Json $report
$binaryPromotion.runtime_boundaries.runtime_binary_parity_claimed = $true
$negativeCases.binary_parity_promotion_rejected =
    -not (Test-JsonSchema $binaryPromotion $paths.schema) -and
    -not (Test-ReportSemantics $binaryPromotion)
$rootPromotion = Copy-Json $report
$rootPromotion.candidate_projections.controls.approved_roots = 1
$negativeCases.root_injection_rejected =
    -not (Test-JsonSchema $rootPromotion $paths.schema) -and
    -not (Test-ReportSemantics $rootPromotion)
$pathEscape = Copy-Json $report
$pathEscape.detail_export.path = 'E:\private\payload.jsonl'
$negativeCases.absolute_detail_path_rejected =
    -not (Test-JsonSchema $pathEscape $paths.schema) -and
    -not (Test-ReportSemantics $pathEscape)
$firstDetail = $detailLines[0]
foreach ($field in @('raw_value', 'key_name', 'file_name', 'private_path',
        'source_line', 'legacy_source_line', 'decoded_payload')) {
    $leak = Copy-Json $firstDetail
    $leak | Add-Member -NotePropertyName $field -NotePropertyValue 'forbidden'
    $negativeCases["detail_${field}_rejected"] = -not (Test-JsonSchema $leak $paths.detail_schema)
}
$negativeCases.missing_detail_identity_rejected = $false
$missingIdentity = Copy-Json $firstDetail
$missingIdentity.PSObject.Properties.Remove('instance_id')
$negativeCases.missing_detail_identity_rejected = -not (Test-JsonSchema $missingIdentity $paths.detail_schema)
$negativeCases.ecf_payload_absent = $candidateEcf.Count -eq 0
Add-A 'negative_contracts_satisfied' (
    @($negativeCases.Values | Where-Object { -not $_ }).Count -eq 0)

$trackedDisclosure = (Get-Content -LiteralPath $paths.report -Raw -Encoding UTF8) +
    (Get-Content -LiteralPath $paths.evidence -Raw -Encoding UTF8) +
    (Get-Content -LiteralPath $paths.detail -Raw -Encoding UTF8)
Add-A 'tracked_and_detail_disclosure_closed' (
    $trackedDisclosure -cnotmatch '(?i)ClientCode|ServerCode|ToolCode|[A-Z]:\\' -and
    $report.disclosure.tracked_aggregate_and_hash_only -and
    $report.disclosure.anonymous_detail_only -and
    @($report.disclosure.PSObject.Properties | Where-Object {
            $_.Name -notin @('tracked_aggregate_and_hash_only', 'anonymous_detail_only') -and
            ($_.Value -isnot [bool] -or $_.Value)
        }).Count -eq 0)

$failed = @($assertions | Where-Object result -eq 'FAIL')
$result = [ordered]@{
    schema_version = 1
    task_id = 'P2-20A.10'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    contract_assertions_satisfied = $failed.Count -eq 0
    failures = $failed.Count
    completion_criteria_satisfied = $false
    g2_06_satisfied = $false
    p3_authorized = $false
    evidence_result = [string]$report.result
    review_execution_result = [string]$report.review_execution_result
    diagnostic_scope_complete = [bool]$report.diagnostic_scope_complete
    a3_actual_parity_instances = [int]$report.source_derived.a3_actual_vs_reference.parity_instances
    a3_actual_difference_instances = [int]$report.source_derived.a3_actual_vs_reference.difference_instances
    correct_plain_filter_parity_instances = [int]$report.source_derived.correct_plain_a3_filter_vs_legacy.parity_instances
    legacy_pair_records_absent_from_a3 = [int]$report.source_derived.correct_plain_a3_filter_vs_legacy.right_only_pair_records
    legacy_runtime_executed = [bool]$report.runtime_boundaries.legacy_runtime_executed
    runtime_binary_parity_claimed = [bool]$report.runtime_boundaries.runtime_binary_parity_claimed
    assertions = $assertions
    negative_cases = $negativeCases
}
$result | ConvertTo-Json -Depth 100 -Compress
if ($failed.Count -ne 0) { throw 'P2-20A.10 ECF parser-parity contract failed.' }
