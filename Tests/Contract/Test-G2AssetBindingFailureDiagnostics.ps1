[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyClientRoot = 'E:\QQXYCodeDev\天命西游',
    [switch]$SkipRegeneration
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
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Copy-Json([string]$Text) {
    return $Text | ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-SchemaRejected([object]$Candidate, [string]$SchemaPath) {
    return -not (($Candidate | ConvertTo-Json -Depth 100 -Compress) |
        Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)
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

$policyPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-failure-diagnostics-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-failure-diagnostics-v1.schema.json'
$detailSchemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-failure-detail-v1.schema.json'
$reportPath = Join-Path $root 'Data\Reports\p2-20a-asset-binding-failure-diagnostics-report.json'
$markdownPath = Join-Path $root 'Data\Reports\p2-20a-asset-binding-failure-diagnostics-report.md'
$evidencePath = Join-Path $root 'Data\Inventory\p2-20a-asset-binding-failure-diagnostics.json'
$detailPath = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-failure-diagnostics.jsonl'
$a4DetailPath = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-descriptor-diagnostics.jsonl'
$wrapperPath = Join-Path $root 'Tools\TMXY.G2AssetBindingFailureDiagnostics\New-G2AssetBindingFailureDiagnostics.ps1'

foreach ($path in @($policyPath, $schemaPath, $detailSchemaPath, $reportPath, $markdownPath,
        $evidencePath, $detailPath, $a4DetailPath, $wrapperPath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}

if (-not $SkipRegeneration) {
    $check = (& $wrapperPath -RebuildRoot $root -LegacyClientRoot $LegacyClientRoot -Check) |
        ConvertFrom-Json -Depth 100
    Add-Assertion 'Deterministic isolated regeneration' `
        ($check.result -eq 'PASS_DIAGNOSTIC' -and $check.task_status -eq 'BLOCKED' -and
            [int]$check.targets -eq 19 -and [int]$check.candidate_edges -eq 24 -and
            [int]$check.typed_error_edges -eq 24 -and
            [int]$check.unclassified_error_edges -eq 0 -and
            [int]$check.effective_resolved_targets -eq 7 -and
            [int]$check.effective_resolved_edges -eq 9 -and
            [int]$check.effective_ambiguous_targets -eq 0 -and
            [int]$check.effective_ambiguous_edges -eq 0 -and
            [int]$check.effective_unresolved_targets -eq 12 -and
            [int]$check.effective_unresolved_edges -eq 15 -and
            [int]$check.candidate_selections -eq 0 -and
            [int]$check.automatic_resolutions -eq 0 -and
            [int]$check.owner_dispositions -eq 0 -and
            $check.g2_06_satisfied -eq $false -and $check.p3_authorized -eq $false)
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
$report = Copy-Json $reportText
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$details = @([IO.File]::ReadLines($detailPath) | ForEach-Object {
    $_ | ConvertFrom-Json -Depth 100
})

Add-Assertion 'Closed report schema' `
    ($reportText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
$detailSchemasPass = $true
foreach ($line in [IO.File]::ReadLines($detailPath)) {
    if (-not ($line | Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue)) {
        $detailSchemasPass = $false
        break
    }
}
Add-Assertion 'All 19 anonymous details satisfy closed schema' `
    ($detailSchemasPass -and $details.Count -eq 19 -and (Get-LineCount $detailPath) -eq 19)
$expectedRoles = @('a4_report', 'a4_detail', 'a4_evidence', 'a4_policy', 'p2_03_evidence',
    'p2_03_graph', 'p2_12_evidence', 'p2_12_catalog', 'a5_report',
    'a6_report', 'policy', 'schema', 'detail_schema')
Add-Assertion 'Thirteen ordered inputs are hash and aggregate bound' `
    (@($report.input_bindings.entries).Count -eq 13 -and
        (@($report.input_bindings.entries.role) -join ',') -ceq ($expectedRoles -join ',') -and
        (Test-InputBindings $report))
Add-Assertion 'Contract hashes are bound' `
    ([string]$report.contracts.policy_sha256 -ceq (Get-Sha256 $policyPath) -and
        [string]$report.contracts.schema_sha256 -ceq (Get-Sha256 $schemaPath) -and
        [string]$report.contracts.detail_schema_sha256 -ceq (Get-Sha256 $detailSchemaPath))
Add-Assertion 'Fail-closed status is truthful' `
    ($report.result -eq 'BLOCKED' -and $report.review_execution_result -eq 'PASS' -and
        $report.task_status -eq 'BLOCKED' -and $report.completion_criteria_satisfied -eq $false -and
        $report.diagnostic_scope_complete -eq $true -and
        $report.remediation_scope_complete -eq $false -and
        $report.g2_06_satisfied -eq $false -and $report.p3_authorized -eq $false)
Add-Assertion 'Frozen A.7 scope closes' `
    ([int]$report.scope.targets -eq 19 -and [int]$report.scope.candidate_edges -eq 24 -and
        [int]$report.scope.unique_candidates -eq 24 -and
        [int]$report.scope.descriptor_parsed_edges -eq 24 -and
        [int]$report.scope.binding_rejected_edges -eq 24 -and
        [int]$report.scope.by_family.anim.targets -eq 6 -and
        [int]$report.scope.by_family.anim.candidate_edges -eq 6 -and
        [int]$report.scope.by_family.qtx.targets -eq 12 -and
        [int]$report.scope.by_family.qtx.candidate_edges -eq 16 -and
        [int]$report.scope.by_family.sm.targets -eq 1 -and
        [int]$report.scope.by_family.sm.candidate_edges -eq 2)
Add-Assertion 'Every rejection has a typed error without disposition' `
    ([int]$report.measured.diagnosed_targets -eq 19 -and
        [int]$report.measured.diagnosed_candidate_edges -eq 24 -and
        [int]$report.measured.typed_error_edges -eq 24 -and
        [int]$report.measured.unclassified_error_edges -eq 0 -and
        [int]$report.measured.candidate_selections -eq 0 -and
        [int]$report.measured.automatic_resolutions -eq 0 -and
        [int]$report.measured.owner_dispositions -eq 0)
Add-Assertion 'Measured production error distribution is frozen' `
    ([Text.Json.Nodes.JsonNode]::DeepEquals(
        [Text.Json.Nodes.JsonNode]::Parse(
            ($report.measured.by_error | ConvertTo-Json -Depth 20 -Compress)),
        [Text.Json.Nodes.JsonNode]::Parse(
            ($policy.expected_error_counts | ConvertTo-Json -Depth 20 -Compress))))
Add-Assertion 'Strict failures retain exact effective recovery state' `
    ([int]$report.measured.effective.resolved_targets -eq 7 -and
        [int]$report.measured.effective.resolved_edges -eq 9 -and
        [int]$report.measured.effective.ambiguous_targets -eq 0 -and
        [int]$report.measured.effective.ambiguous_edges -eq 0 -and
        [int]$report.measured.effective.unresolved_targets -eq 12 -and
        [int]$report.measured.effective.unresolved_edges -eq 15)
Add-Assertion 'Other blockers remain untouched' `
    ([int]$report.preserved_blockers.identity_semantic_ambiguous_targets -eq 15 -and
        [int]$report.preserved_blockers.identity_semantic_ambiguous_edges -eq 30 -and
        [int]$report.preserved_blockers.asset_effective_ambiguous_targets -eq 189 -and
        [int]$report.preserved_blockers.asset_effective_ambiguous_edges -eq 546 -and
        [int]$report.preserved_blockers.strict_binding_failure_targets -eq 19 -and
        [int]$report.preserved_blockers.strict_binding_failure_edges -eq 24 -and
        [int]$report.preserved_blockers.asset_effective_unresolved_targets -eq 12 -and
        [int]$report.preserved_blockers.asset_effective_unresolved_edges -eq 15 -and
        [int]$report.preserved_blockers.auxiliary_nonterminal_instances -eq 212 -and
        [int]$report.preserved_blockers.conditional_required_missing -eq 29 -and
        [int]$report.preserved_blockers.migration_pending -eq 1359 -and
        [int]$report.preserved_blockers.g2_satisfied -eq 7 -and
        [int]$report.preserved_blockers.g2_blocked -eq 2)
Add-Assertion 'Machine authority is explicitly absent' `
    ($report.authority_boundary.machine_can_reproduce -eq $true -and
        $report.authority_boundary.machine_can_classify_errors -eq $true -and
        $report.authority_boundary.machine_can_select_candidate -eq $false -and
        $report.authority_boundary.machine_can_approve_disposition -eq $false -and
        $report.authority_boundary.technical_adapter_must_be_contract_proven -eq $true -and
        $report.authority_boundary.content_change_or_no_ref_requires_owner -eq $true -and
        [int]$report.authority_boundary.owner_records -eq 0 -and
        [int]$report.authority_boundary.approved_fixes -eq 0 -and
        [int]$report.authority_boundary.verified_resolutions -eq 0)

$a4Unresolved = @(Get-Content -LiteralPath $a4DetailPath -Encoding UTF8 |
    ForEach-Object { $_ | ConvertFrom-Json -Depth 100 } |
    Where-Object strict_resolution -eq 'UNRESOLVED')
$a4ById = @{}
foreach ($item in $a4Unresolved) { $a4ById[[string]$item.asset_id] = $item }
$detailReconciled = $details.Count -eq 19 -and $a4Unresolved.Count -eq 19
foreach ($item in $details) {
    if (-not $a4ById.ContainsKey([string]$item.asset_id)) { $detailReconciled = $false; break }
    $prior = $a4ById[[string]$item.asset_id]
    if ([int]$item.candidate_count -ne [int]$prior.candidate_count -or
        [string]$item.candidate_set_sha256 -cne [string]$prior.candidate_set_sha256 -or
        [string]$item.prior_resolution -cne 'UNRESOLVED' -or
        [string]$item.effective_resolution -cne [string]$prior.resolution -or
        (@($item.candidates.candidate_id | Sort-Object) -join ',') -cne
            (@($prior.candidates.candidate_id | Sort-Object) -join ',')) {
        $detailReconciled = $false
        break
    }
    foreach ($candidate in @($item.candidates)) {
        $frozen = @($prior.candidates | Where-Object candidate_id -ceq $candidate.candidate_id)
        if ($frozen.Count -ne 1 -or $frozen[0].descriptor -ne 'PARSED' -or
            $frozen[0].binding -ne 'REJECTED' -or
            [string]$candidate.body_sha256 -cne [string]$frozen[0].body_sha256 -or
            [string]$candidate.descriptor_semantic_sha256 -cne
                [string]$frozen[0].descriptor_semantic_sha256 -or
            $candidate.bind_result -ne 'REJECTED' -or
            $candidate.automatic_resolution -ne $false) {
            $detailReconciled = $false
            break
        }
    }
}
Add-Assertion 'Anonymous detail exactly reconciles A.4 19/24 set' $detailReconciled

$familySchemas = @{anim = 'AnimationError/v1'; qtx = 'TextureError/v1'; sm = 'StaticMeshError/v1'}
$typed = $true
foreach ($item in $details) {
    foreach ($candidate in @($item.candidates)) {
        if ([string]$candidate.error_schema -cne $familySchemas[[string]$item.family] -or
            [string]$candidate.error_code -cnotmatch '^[a-z][a-z0-9_]+$' -or
            [string]$candidate.error_context_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$candidate.failure_id -cnotmatch '^[0-9a-f]{64}$') {
            $typed = $false
            break
        }
    }
}
Add-Assertion 'Detail carries only family-typed anonymous failure evidence' $typed
$detailText = Get-Content -LiteralPath $detailPath -Raw -Encoding UTF8
Add-Assertion 'Detail excludes raw contexts offsets names paths and values' `
    ($detailText -cnotmatch '(?i)context[\"\s]*:|absolute_offset|requested_bytes|available_bytes|[A-Z]:\\|/legacy/|object_name|relative_path|payload_value|source_line')
Add-Assertion 'Disclosure boundary is closed' `
    ($report.disclosure.anonymous_aggregate_and_hash_only -eq $true -and
        $report.disclosure.anonymous_detail_only -eq $true -and
        $report.disclosure.raw_names -eq $false -and
        $report.disclosure.private_source_paths -eq $false -and
        $report.disclosure.raw_error_contexts -eq $false -and
        $report.disclosure.absolute_offsets -eq $false -and
        $report.disclosure.observed_payload_values -eq $false)

Add-Assertion 'Evidence output bindings match artifacts' `
    ([string]$evidence.outputs.report_json.sha256 -ceq (Get-Sha256 $reportPath) -and
        [string]$evidence.outputs.report_markdown.sha256 -ceq (Get-Sha256 $markdownPath) -and
        [string]$evidence.outputs.detail_export.sha256 -ceq (Get-Sha256 $detailPath))
$script:a7SourceMismatch = $false
$sourceAggregate = ($evidence.implementation.files | ForEach-Object {
    $path = Join-Path $root ([string]$_.path).Replace('/', '\')
    if ((Get-Sha256 $path) -cne [string]$_.sha256 -or
        [int64](Get-Item $path).Length -ne [int64]$_.bytes -or
        (Get-LineCount $path) -ne [int]$_.lines) { $script:a7SourceMismatch = $true }
    "$($_.path)`t$($_.bytes)`t$($_.lines)`t$($_.sha256)`n"
}) -join ''
Add-Assertion 'Implementation source aggregate is bound' `
    (-not $script:a7SourceMismatch -and
        (Get-TextSha256 $sourceAggregate) -ceq [string]$evidence.implementation.aggregate_sha256)
Add-Assertion 'Locked isolated builder evidence' `
    ($evidence.builder.image_reference -eq 'tmxy-backend-builder:p0-08' -and
        [string]$evidence.builder.image_id -cmatch '^sha256:[0-9a-f]{64}$' -and
        $evidence.builder.user -eq 'tmxy' -and $evidence.isolation.network -eq 'none' -and
        $evidence.isolation.read_only_container -eq $true -and
        $evidence.isolation.repository_mount -eq 'read-only' -and
        $evidence.isolation.legacy_client_mount -eq 'read-only')

$mutated = Copy-Json $reportText
$mutated.measured.effective.resolved_targets = 6
Add-Assertion 'Negative: binder pass or automatic resolution rejected' `
    (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.classification_controls.first_candidate_selection = $true
Add-Assertion 'Negative: first candidate selection rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.authority_boundary.machine_can_approve_disposition = $true
Add-Assertion 'Negative: machine authority rejected' (Test-SchemaRejected $mutated $schemaPath)
$detailMutation = Copy-Json ([IO.File]::ReadLines($detailPath) | Select-Object -First 1)
$detailMutation.candidates[0].error_schema = 'TextureError/v1'
if ($detailMutation.family -eq 'qtx') { $detailMutation.candidates[0].error_schema = 'AnimationError/v1' }
Add-Assertion 'Negative: cross-family error schema rejected by contract' `
    ([string]$detailMutation.candidates[0].error_schema -cne $familySchemas[[string]$detailMutation.family])
$detailMutation = Copy-Json ([IO.File]::ReadLines($detailPath) | Select-Object -First 1)
$detailMutation.candidates[0].error_code = 12
Add-Assertion 'Negative: numeric error ordinal rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$detailMutation = Copy-Json ([IO.File]::ReadLines($detailPath) | Select-Object -First 1)
$detailMutation.candidates[0] | Add-Member -NotePropertyName raw_context -NotePropertyValue 'forbidden'
Add-Assertion 'Negative: raw context or offset field rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$detailMutation = Copy-Json ([IO.File]::ReadLines($detailPath) | Select-Object -First 1)
$detailMutation.candidates[0].body_sha256 = '0' * 64
Add-Assertion 'Negative: candidate hash tamper differs from A.4' `
    ([string]$detailMutation.candidates[0].body_sha256 -cne
        [string]$a4ById[[string]$detailMutation.asset_id].candidates[0].body_sha256)
$mutated = Copy-Json $reportText
$mutated.measured.typed_error_edges = 23
Add-Assertion 'Negative: count reconciliation rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.preserved_blockers.asset_effective_ambiguous_targets = 188
Add-Assertion 'Negative: 189-target ambiguity reduction rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.preserved_blockers.auxiliary_nonterminal_instances = 211
Add-Assertion 'Negative: 212 auxiliary blocker reduction rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.g2_06_satisfied = $true
Add-Assertion 'Negative: false G2 approval rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.p3_authorized = $true
Add-Assertion 'Negative: false P3 authorization rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.input_bindings.entries[0].sha256 = '0' * 64
Add-Assertion 'Negative: input hash tamper rejected by binding' (-not (Test-InputBindings $mutated))
$mutated = Copy-Json $reportText
$mutated.PSObject.Properties.Remove('task_status')
Add-Assertion 'Negative: missing field rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
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
if ($failed.Count -ne 0) { throw 'P2-20A.7 binding-failure diagnostic contract failed.' }
