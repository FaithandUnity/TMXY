[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\content-health-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\content-health-report-v1.schema.json'
$jsonReportPath = Join-Path $root 'Data\Reports\p2-18-content-health-report.json'
$markdownReportPath = Join-Path $root 'Data\Reports\p2-18-content-health-report.md'
$evidencePath = Join-Path $root 'Data\Inventory\p2-18-content-health.json'
$generatorPath = Join-Path $root 'Tools\TMXY.ContentHealth\content_health.py'
$wrapperPath = Join-Path $root 'Tools\TMXY.ContentHealth\New-ContentHealthReport.ps1'
$queryPath = Join-Path $root 'Tools\TMXY.ContentHealth\Find-ContentHealth.ps1'
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

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

$required = @($policyPath, $schemaPath, $jsonReportPath, $markdownReportPath, $evidencePath,
    $generatorPath, $wrapperPath, $queryPath)
foreach ($index in 1..17) {
    $match = @(Get-ChildItem -LiteralPath (Join-Path $root 'Data\Inventory') -File |
        Where-Object { $_.Name -like ('p2-{0:D2}-*.json' -f $index) })
    if ($match.Count -eq 1) { $required += $match[0].FullName }
    else { Add-A ('Exactly one P2-{0:D2} evidence file exists' -f $index) $false }
}
foreach ($path in $required) {
    Add-A "Required file $([IO.Path]::GetFileName($path))" (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject][ordered]@{
        schema_version = 1; task_id = 'P2-18'; result = 'FAIL'
        completion_criteria_satisfied = $false; assertions = $assertions
    } | ConvertTo-Json -Depth 20
    exit 1
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$report = Get-Content -LiteralPath $jsonReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
$wrapper = Get-Content -LiteralPath $wrapperPath -Raw -Encoding UTF8

Add-A 'Evidence completes P2-18 accounting' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied -and
    $evidence.summary.report_result -eq 'PASS_WITH_OPEN_CONTENT_RISKS')
Add-A 'Schema closes the report and dimension envelopes' (
    $schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and
    $schema.properties.task_id.const -eq 'P2-18' -and
    $schema.properties.dimensions.additionalProperties -eq $false)
$actualTop = @($report.PSObject.Properties.Name | Sort-Object)
$requiredTop = @($schema.required | Sort-Object)
Add-A 'Report satisfies the closed top-level schema shape' (
    $actualTop.Count -eq $requiredTop.Count -and
    @(Compare-Object $actualTop $requiredTop).Count -eq 0 -and
    $report.schema_version -eq 1 -and $report.task_id -eq 'P2-18')
Add-A 'Policy covers P2-01 through P2-17 and fixes rate semantics' (
    @($policy.required_tasks).Count -eq 17 -and $policy.required_tasks[0] -eq 'P2-01' -and
    $policy.required_tasks[16] -eq 'P2-17' -and $policy.rate_unit -eq 'parts-per-million' -and
    $policy.rate_formula -eq 'floor(numerator * 1000000 / denominator)')
Add-A 'Policy preserves semantic and authority boundaries' (
    $policy.classification_rules.opaque_package_payload_is_not_parse_failure -and
    $policy.classification_rules.nullable_object_reference_is_not_core_foreign_key_dangling -and
    $policy.classification_rules.unlinked_asset_is_not_delete_authority -and
    $policy.classification_rules.planning_coefficient_is_not_schedule_commitment -and
    $policy.completion_policy.forbids_claiming_playable_experience_without_runtime_proof -and
    $policy.completion_policy.forbids_automatic_repair_or_deletion)

$bindingsPassed = $evidence.input.completed_tasks -eq 17 -and
    @($evidence.input.inputs).Count -eq 17 -and
    $evidence.input.binding_sha256 -eq $report.scope.input_binding_sha256
foreach ($binding in $evidence.input.inputs) {
    $path = Join-Path $root ([string]$binding.path)
    $upstream = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    $bindingsPassed = $bindingsPassed -and (Get-Sha256 $path) -eq $binding.sha256 -and
        $binding.result -eq 'PASS' -and $upstream.result -eq 'PASS' -and
        $upstream.task_status -eq 'COMPLETE' -and $upstream.completion_criteria_satisfied
}
Add-A 'All 17 completed upstream artifacts have exact SHA-256 bindings' $bindingsPassed
Add-A 'JSON and Markdown report hashes sizes and lines are frozen' (
    $evidence.report.json.path -eq 'Data/Reports/p2-18-content-health-report.json' -and
    $evidence.report.markdown.path -eq 'Data/Reports/p2-18-content-health-report.md' -and
    $evidence.report.json.tracked -and $evidence.report.markdown.tracked -and
    (Get-Sha256 $jsonReportPath) -eq $evidence.report.json.sha256 -and
    (Get-Sha256 $markdownReportPath) -eq $evidence.report.markdown.sha256 -and
    (Get-Item -LiteralPath $jsonReportPath).Length -eq $evidence.report.json.bytes -and
    (Get-Item -LiteralPath $markdownReportPath).Length -eq $evidence.report.markdown.bytes -and
    (Get-LineCount $jsonReportPath) -eq $evidence.report.json.lines -and
    (Get-LineCount $markdownReportPath) -eq $evidence.report.markdown.lines)
Add-A 'Package core and table parsing populations close at 100 percent' (
    $report.dimensions.parsing.packages_recognized -eq 163 -and
    $report.dimensions.parsing.packages_recognized_complete -eq 163 -and
    $report.dimensions.parsing.packages_recognized_complete_ppm -eq 1000000 -and
    $report.dimensions.parsing.core_packages_complete -eq 12 -and
    $report.dimensions.parsing.core_packages_complete_ppm -eq 1000000 -and
    $report.dimensions.parsing.tables_decoded -eq 225 -and
    $report.dimensions.parsing.tables_decoded_ppm -eq 1000000)
Add-A 'Asset coverage distinguishes valid unresolved corrupt and unsupported' (
    $report.dimensions.parsing.assets -eq 40090 -and
    $report.dimensions.parsing.assets_structurally_valid -eq 39290 -and
    $report.dimensions.parsing.assets_structurally_valid_ppm -eq 980044 -and
    $report.dimensions.unknown_or_opaque.asset_structure_unresolved -eq 786 -and
    $report.dimensions.damage.asset_corrupt -eq 14 -and
    $report.dimensions.unknown_or_opaque.unsupported_assets -eq 0)
Add-A 'Damage accounting isolates exactly 20 artifacts without mutation' (
    $report.dimensions.damage.damaged_or_isolated_source_artifacts -eq 20 -and
    $report.dimensions.damage.asset_corrupt -eq 14 -and
    $report.dimensions.damage.auxiliary_xml_malformed_isolated -eq 6 -and
    $report.dimensions.damage.package_recognized_parse_failures -eq 0 -and
    $report.dimensions.damage.repair_or_deletion_performed -eq 0)
Add-A 'Opaque payloads are explicit and not mislabeled as parse failure' (
    $report.dimensions.unknown_or_opaque.package_object_payloads_opaque -eq 121715 -and
    $report.dimensions.damage.package_recognized_parse_failures -eq 0)
Add-A 'Package reference health preserves every ambiguous and unresolved edge' (
    $report.dimensions.references.package_edges -eq 147349 -and
    $report.dimensions.references.package_ambiguous -eq 21146 -and
    $report.dimensions.references.package_unresolved -eq 1076 -and
    $report.dimensions.references.heuristic_target_selections -eq 0)
Add-A 'Core references have zero authoritative dangling edges' (
    $report.dimensions.references.core_foreign_key_edges -eq 54561 -and
    $report.dimensions.references.core_foreign_key_dangling -eq 0 -and
    $report.dimensions.references.legacy_current_dangling -eq 0)
Add-A 'Nullable object references remain separate quantified risks' (
    $report.dimensions.references.table_object_edges -eq 113484 -and
    $report.dimensions.references.table_object_ambiguous -eq 6945 -and
    $report.dimensions.references.table_object_unresolved -eq 5161)
Add-A 'Every asset has an explicit reference state' (
    $report.dimensions.references.assets_root_reachable -eq 14058 -and
    $report.dimensions.references.assets_linked_outside_roots -eq 24119 -and
    $report.dimensions.references.assets_unlinked_identity_rule_no_match -eq 1008 -and
    $report.dimensions.references.assets_unlinked_no_identity_rule -eq 905)
Add-A 'Conversion readiness closes ready aliases and manual blocks' (
    $report.dimensions.conversion.assets -eq 40090 -and
    $report.dimensions.conversion.assets_with_ready_key -eq 39290 -and
    $report.dimensions.conversion.conversion_ready_ppm -eq 980044 -and
    $report.dimensions.conversion.distinct_ready_keys -eq 33801 -and
    $report.dimensions.conversion.alias_assignments -eq 5489 -and
    $report.dimensions.conversion.blocked_manual_jobs -eq 800)
Add-A 'Effort is quantified as planning coefficients not a schedule' (
    $report.dimensions.effort.planning_human_hours -eq 1404.695 -and
    $report.dimensions.effort.fixed_engineering_hours -eq 336.0 -and
    $report.dimensions.effort.manual_planning_human_hours -eq 617.0 -and
    $report.dimensions.effort.machine_seconds -eq 108005 -and
    $report.dimensions.effort.basis -eq 'planning coefficient, not benchmark or schedule commitment')
Add-A 'Capacity risks retain 64-bit migration and duplicate review boundaries' (
    $report.dimensions.capacity.id_components -eq 16 -and
    $report.dimensions.capacity.id_u16_overflow -eq 0 -and
    $report.dimensions.capacity.id_u16_saturated -eq 3 -and
    $report.dimensions.capacity.id_u16_near_limit -eq 2 -and
    $report.dimensions.capacity.exact_duplicate_redundant_bytes_review_only -eq 1286887829)
$riskIds = @($report.risk_register | ForEach-Object id)
Add-A 'Risk register has unique quantified items and stable severity totals' (
    @($report.risk_register).Count -eq 13 -and @($riskIds | Sort-Object -Unique).Count -eq 13 -and
    $report.risk_summary.critical -eq 0 -and $report.risk_summary.high -eq 6 -and
    $report.risk_summary.medium -eq 6 -and $report.risk_summary.low -eq 1 -and
    $report.risk_summary.open -eq 7 -and $report.risk_summary.controlled_open -eq 2 -and
    $report.risk_summary.review_only -eq 4)
Add-A 'Completion does not claim playable G2 or release readiness' (
    $report.executive_summary.content_accounting_complete -and
    -not $report.executive_summary.full_content_conversion_ready -and
    -not $report.executive_summary.playable_experience_proven -and
    -not $report.executive_summary.p2_gate_ready -and
    -not $report.decisions.g2_approved -and -not $report.decisions.release_authority)
Add-A 'Tracked report preserves the public disclosure boundary' (
    -not $report.disclosure.private_source_paths -and -not $report.disclosure.exact_primary_keys -and
    -not $report.disclosure.exact_observed_extrema -and -not $report.disclosure.raw_table_rows -and
    -not $report.disclosure.decoded_confidential_payloads -and -not $report.disclosure.legacy_source_lines -and
    -not $evidence.disclosure.private_source_paths -and -not $evidence.disclosure.exact_primary_keys)
Add-A 'Policy schema implementation and isolation are hash bound' (
    $evidence.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath) -and
    $evidence.implementation.generator_sha256 -eq (Get-Sha256 $generatorPath) -and
    $evidence.implementation.wrapper_sha256 -eq (Get-Sha256 $wrapperPath) -and
    $evidence.implementation.query_sha256 -eq (Get-Sha256 $queryPath) -and
    $generator -match 'read_text\(encoding="utf-8"\)' -and
    $wrapper -match "'--network', 'none'" -and $wrapper -match "'--read-only'" -and
    $wrapper -match "'--cap-drop', 'ALL'" -and $evidence.reproduction.builder_user -eq 'tmxy')
$query = & $queryPath -ReportPath $jsonReportPath -Severity high -State open -MaximumResults 25 |
    ConvertFrom-Json -Depth 100
Add-A 'Risk register is queryable without private values' (
    $query.result -eq 'PASS' -and $query.matches -eq 5 -and
    @($query.risks | Where-Object { $_.severity -ne 'high' -or $_.state -ne 'open' }).Count -eq 0 -and
    -not $query.disclosure.private_source_paths -and -not $query.disclosure.exact_primary_keys -and
    -not $query.disclosure.raw_values)

$localCheck = $null
if ($VerifyDerivedSources) {
    $localCheck = & $wrapperPath -RebuildRoot $root -Check | ConvertFrom-Json -Depth 100
    Add-A 'Byte-identical isolated report regeneration passes' (
        $localCheck.result -eq 'PASS' -and $localCheck.completion_criteria_satisfied -and
        $localCheck.input.binding_sha256 -eq $evidence.input.binding_sha256 -and
        $localCheck.report.json.sha256 -eq $evidence.report.json.sha256 -and
        $localCheck.report.markdown.sha256 -eq $evidence.report.markdown.sha256)
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-18'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    verify_derived_sources = [bool]$VerifyDerivedSources
    report = $evidence.report
    summary = $evidence.summary
    local_check = $localCheck
    assertions = $assertions
} | ConvertTo-Json -Depth 100
if ($failed.Count -gt 0) { exit 1 }
