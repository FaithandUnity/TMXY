[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$assertions = [Collections.Generic.List[object]]::new()

function Add-A([string]$Name, [bool]$Passed) {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
        })
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256([string]$Value) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Copy-Json([object]$Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-JsonEqual([object]$Left, [object]$Right) {
    return ($Left | ConvertTo-Json -Depth 100 -Compress) -ceq
        ($Right | ConvertTo-Json -Depth 100 -Compress)
}

$policyPath = Join-Path $root 'Contracts\data-schema\g2-aux-semantic-diagnostics-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\g2-aux-semantic-diagnostics-v1.schema.json'
$reportPath = Join-Path $root 'Data\Reports\p2-20a-aux-semantic-diagnostics-report.json'
$markdownPath = Join-Path $root 'Data\Reports\p2-20a-aux-semantic-diagnostics-report.md'
$evidencePath = Join-Path $root 'Data\Inventory\p2-20a-aux-semantic-diagnostics.json'
$wrapperPath = Join-Path $root 'Tools\TMXY.G2AuxSemanticDiagnostics\New-G2AuxSemanticDiagnostics.ps1'
$generatorPath = Join-Path $root 'Tools\TMXY.G2AuxSemanticDiagnostics\g2_aux_semantic_diagnostics.py'
$supportPath = Join-Path $root 'Tools\TMXY.G2AuxSemanticDiagnostics\g2_aux_semantic_support.py'
foreach ($path in @($policyPath, $schemaPath, $reportPath, $markdownPath,
        $evidencePath, $wrapperPath, $generatorPath, $supportPath)) {
    Add-A "Required artifact $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}

if ($VerifyDerivedSources) {
    $checkText = & $wrapperPath -RebuildRoot $root -LegacySourceRoot 'E:\QQXYCodeDev' -Check
    $check = $checkText | ConvertFrom-Json
    Add-A 'Isolated deterministic regeneration' ($check.result -eq 'PASS_DIAGNOSTIC' -and
        $check.task_status -eq 'BLOCKED' -and [int]$check.file_instances -eq 212)
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
$report = $reportText | ConvertFrom-Json -Depth 100 -DateKind String
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$inputPaths = [ordered]@{
    auxiliary_inventory = 'Data/Inventory/p2-05-auxiliary-config-inventory.json'
    three_layer_inventory = 'Data/Inventory/p2-06-three-layer-data.json'
    lexical_report = 'Data/Reports/p2-20a-aux-config-reference-report.json'
    package_inventory = 'Data/Inventory/p2-01-package-inventory.json'
    asset_inventory = 'Data/Inventory/p2-12-full-asset-inventory.json'
    reference_closure = 'Data/Inventory/p2-13-reference-closure.json'
    policy = 'Contracts/data-schema/g2-aux-semantic-diagnostics-policy-v1.json'
    schema = 'Contracts/data-schema/g2-aux-semantic-diagnostics-v1.schema.json'
}
$expectedEntries = @($inputPaths.GetEnumerator() | ForEach-Object {
        [pscustomobject][ordered]@{
            role = $_.Key
            sha256 = Get-Sha256 (Join-Path $root $_.Value)
        }
    })
$aggregateText = (@($expectedEntries | ForEach-Object { "$($_.role)`t$($_.sha256)" }) -join "`n") + "`n"
$expectedLegacy = @($policy.legacy_source_bindings.PSObject.Properties |
    Sort-Object Name | ForEach-Object {
        [pscustomobject][ordered]@{ role = $_.Name; sha256 = [string]$_.Value }
    })
function Test-InputBindings([object]$Candidate) {
    return [string]$Candidate.aggregate_sha256 -ceq (Get-TextSha256 $aggregateText) -and
        (Test-JsonEqual @($Candidate.entries) $expectedEntries) -and
        (Test-JsonEqual @($Candidate.legacy_sources) $expectedLegacy)
}
Add-A 'Closed JSON Schema' ($reportText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
Add-A 'Policy identity' ($policy.evidence_revision -eq 'P2-20A.5' -and
    $policy.task_id -eq 'P2-20A' -and $policy.criterion_id -eq 'G2-06')
Add-A 'Fail-closed authority state' ($report.result -eq 'BLOCKED' -and
    $report.review_execution_result -eq 'PASS' -and $report.task_status -eq 'BLOCKED' -and
    $report.completion_criteria_satisfied -eq $false -and $report.scope_complete -eq $false -and
    $report.g2_06_satisfied -eq $false -and $report.p3_authorized -eq $false -and
    $report.semantic_state.ordinary_development_authorization_is_semantic_approval -eq $false)
Add-A 'Region consumer measurements' ([int]$report.measured.region_strict_instances -eq 135 -and
    [int]$report.measured.region_semantic_references.unique_total -eq 3180 -and
    [int]$report.measured.region_semantic_references.unique_file -eq 3042 -and
    [int]$report.measured.region_semantic_references.unique_object -eq 4 -and
    [int]$report.measured.region_semantic_references.unique_package_root -eq 134 -and
    [int]$report.measured.region_semantic_references.ambiguous_object -eq 211 -and
    [int]$report.measured.region_semantic_references.unresolved_resource -eq 1)
Add-A 'Ambiguous objects are retained and divergent' `
    ([int]$report.measured.region_semantic_references.ambiguous_object_candidate_edges -eq 422 -and
        [int]$report.measured.region_semantic_references.ambiguous_object_divergent_bodies -eq 211 -and
        [int]$report.measured.region_semantic_references.first_candidate_selections -eq 0)
Add-A 'ECF parser parity measurements' ([int]$report.measured.ecf.instances -eq 64 -and
    [int]$report.measured.ecf.mixed_newline_differences -eq 3 -and
    [int]$report.measured.ecf.legacy_assignments_missed_by_a3_parser -eq 4 -and
    [int]$report.measured.ecf.runtime_with_candidates -eq 15 -and
    [int]$report.measured.ecf.runtime_without_candidates -eq 21 -and
    [int]$report.measured.ecf.editor_without_candidates -eq 28)
Add-A 'All source instances are byte and SHA verified and populations close arithmetically' `
    ([int]$report.measured.source_instances_verified -eq 212 -and
        [int]$report.measured.parsed_shared_help_zero_lexical -eq 7 -and
        [int]$report.measured.malformed_instances -eq 6 -and
        ([int]$report.measured.region_strict_instances + [int]$report.measured.ecf.instances +
            [int]$report.measured.parsed_shared_help_zero_lexical +
            [int]$report.measured.malformed_instances) -eq 212)
Add-A 'All inputs aggregate roles and legacy consumers are exactly hash bound' `
    (Test-InputBindings $report.input_bindings)
Add-A 'Policy and Schema hashes are exact' `
    ($report.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
        $report.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath))
Add-A 'Evidence binds tracked reports' `
    ($evidence.report_json.sha256 -eq (Get-Sha256 $reportPath) -and
        $evidence.report_markdown.sha256 -eq (Get-Sha256 $markdownPath) -and
        (Test-JsonEqual $evidence.measured $report.measured) -and
        $evidence.implementation.generator_sha256 -eq (Get-Sha256 $generatorPath) -and
        $evidence.implementation.support_sha256 -eq (Get-Sha256 $supportPath))
Add-A 'Blocker mapping is exact ordered and unique' `
    (Test-JsonEqual @($report.blockers) @(
            [pscustomobject][ordered]@{ reason_code = 'AMBIGUOUS_OBJECT_TARGETS'; count = 211 },
            [pscustomobject][ordered]@{ reason_code = 'UNRESOLVED_RESOURCE_TARGETS'; count = 1 },
            [pscustomobject][ordered]@{ reason_code = 'LEGACY_PARSER_PARITY_GAPS'; count = 3 },
            [pscustomobject][ordered]@{ reason_code = 'MALFORMED_INPUTS_UNDISPOSED'; count = 6 },
            [pscustomobject][ordered]@{ reason_code = 'APPROVED_ROOT_SET_EMPTY'; count = 0 },
            [pscustomobject][ordered]@{ reason_code = 'CONSUMER_CONTRACTS_UNAPPROVED'; count = 212 }
        ))
Add-A 'Read-only isolated execution' ($evidence.isolation.network -eq 'none' -and
    $evidence.isolation.repository_mount -eq 'read-only' -and
    $evidence.isolation.legacy_source_mount -eq 'read-only' -and
    $evidence.isolation.builder_user -eq 'tmxy' -and
    $evidence.isolation.no_new_privileges -eq $true)
Add-A 'Disclosure boundary' ($report.disclosure.anonymous_aggregate_and_hash_only -eq $true -and
    $report.disclosure.raw_values -eq $false -and $report.disclosure.key_names -eq $false -and
    $report.disclosure.file_names -eq $false -and $report.disclosure.private_source_paths -eq $false -and
    $report.disclosure.source_line_numbers -eq $false -and $report.disclosure.legacy_source_lines -eq $false -and
    $report.disclosure.exact_primary_keys -eq $false -and $report.disclosure.decoded_payloads -eq $false)
Add-A 'G2 projection remains 7 of 9 blocked' ([int]$report.g2_projection.criteria_total -eq 9 -and
    [int]$report.g2_projection.satisfied -eq 7 -and [int]$report.g2_projection.blocked -eq 2 -and
    $report.g2_projection.g2_decision -eq 'BLOCKED')

$mixed = Copy-Json $report
$mixed.measured.ecf.mixed_newline_differences = 0
Add-A 'Negative: mixed-newline drift cannot be erased' `
    (-not (($mixed | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$first = Copy-Json $report
$first.parser_and_consumer_controls.first_candidate_selection = $true
Add-A 'Negative: first candidate is rejected' `
    (-not (($first | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$zero = Copy-Json $report
$zero.parser_and_consumer_controls.zero_match_is_no_reference = $true
Add-A 'Negative: zero-match no-ref promotion is rejected' `
    (-not (($zero | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$shadow = Copy-Json $report
$shadow.parser_and_consumer_controls.shadow_without_roots_is_no_reference = $true
Add-A 'Negative: rootless shadow exclusion is rejected' `
    (-not (($shadow | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$malformed = Copy-Json $report
$malformed.parser_and_consumer_controls.malformed_auto_fix = $true
Add-A 'Negative: malformed auto-fix is rejected' `
    (-not (($malformed | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$unknown = Copy-Json $report
$unknown | Add-Member -NotePropertyName unexpected -NotePropertyValue 1
Add-A 'Negative: unknown report field is rejected' `
    (-not (($unknown | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$duplicateRole = Copy-Json $report
$duplicateRole.input_bindings.entries[1].role = $duplicateRole.input_bindings.entries[0].role
Add-A 'Negative: duplicate or reordered input roles are rejected' `
    (-not (Test-InputBindings $duplicateRole.input_bindings) -and
        -not (($duplicateRole | ConvertTo-Json -Depth 100) |
            Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$blockerTamper = Copy-Json $report
$blockerTamper.blockers[0].count = 210
Add-A 'Negative: blocker count tampering is rejected' `
    (-not (($blockerTamper | ConvertTo-Json -Depth 100) |
        Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    review_result = 'BLOCKED'
    contract_assertions_satisfied = $failed.Count -eq 0
    completion_criteria_satisfied = $false
    g2_06_satisfied = $false
    p3_authorized = $false
    assertions = $assertions.Count
    failures = $failed.Count
    details = $assertions
} | ConvertTo-Json -Depth 20
if ($failed.Count -ne 0) { throw 'P2-20A.5 auxiliary semantic diagnostic contract failed.' }
