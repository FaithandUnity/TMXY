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

$policyPath = Join-Path $root 'Contracts\data-schema\g2-asset-descriptor-diagnostics-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-descriptor-diagnostics-v1.schema.json'
$reportPath = Join-Path $root 'Data\Reports\p2-20a-asset-descriptor-diagnostics-report.json'
$markdownPath = Join-Path $root 'Data\Reports\p2-20a-asset-descriptor-diagnostics-report.md'
$evidencePath = Join-Path $root 'Data\Inventory\p2-20a-asset-descriptor-diagnostics.json'
$detailPath = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-descriptor-diagnostics.jsonl'
$recoveryPlanPath = Join-Path $root `
    'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
$wrapperPath = Join-Path $root 'Tools\TMXY.G2AssetDescriptorDiagnostics\New-G2AssetDescriptorDiagnostics.ps1'
foreach ($path in @($policyPath, $schemaPath, $reportPath, $markdownPath,
        $evidencePath, $detailPath, $recoveryPlanPath, $wrapperPath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}

if ($VerifyDerivedSources) {
    $checkText = & $wrapperPath -RebuildRoot $root -LegacyClientRoot 'E:\QQXYCodeDev\天命西游' -Check
    $check = $checkText | ConvertFrom-Json
    Add-Assertion 'Deterministic isolated regeneration' `
        ($check.result -eq 'PASS_DIAGNOSTIC' -and $check.task_status -eq 'BLOCKED' -and
            [int]$check.targets -eq 3651 -and [int]$check.candidate_edges -eq 12764)
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
$report = $reportText | ConvertFrom-Json -Depth 100 -DateKind String
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$validSchema = $reportText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue
Add-Assertion 'Closed report schema' $validSchema
Add-Assertion 'Policy identity' ($policy.evidence_revision -eq 'P2-20A.4' -and
    $policy.task_id -eq 'P2-20A' -and $policy.criterion_id -eq 'G2-06')
Add-Assertion 'Frozen diagnostic scope' ([int]$policy.scope.required_targets -eq 3651 -and
    [int]$policy.scope.required_candidate_edges -eq 12764 -and
    [int]$policy.scope.required_package_candidate_objects -eq 46865)
Add-Assertion 'A.13 effective recovery plan is closed' `
    ($policy.scope.effective_recovery_plan.path -eq
        'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv' -and
        [int]$policy.scope.effective_recovery_plan.attempts -eq 21 -and
        [int]$policy.scope.effective_recovery_plan.qtx_declared_mip_payload_prefix_attempts -eq 6 -and
        @($policy.scope.effective_recovery_plan.allowed_kinds).Count -eq 3 -and
        'qtx_declared_mip_payload_prefix' -in
            @($policy.scope.effective_recovery_plan.allowed_kinds) -and
        (Get-LineCount $recoveryPlanPath) -eq 21)
$recoveryKinds = @(Get-Content -LiteralPath $recoveryPlanPath -Encoding UTF8 |
    ForEach-Object { ($_ -split "`t")[5] })
Add-Assertion 'Recovery-plan kind replacement is exact' `
    (@($recoveryKinds | Where-Object { $_ -eq 'anim_payload_frame_counts' }).Count -eq 5 -and
        @($recoveryKinds | Where-Object { $_ -eq 'qtx_complete_mip_chain' }).Count -eq 10 -and
        @($recoveryKinds | Where-Object {
                $_ -eq 'qtx_declared_mip_payload_prefix'
            }).Count -eq 6)
Add-Assertion 'Base workset frozen by hash' `
    ((Get-Sha256 (Join-Path $root $policy.scope.base_workset.path)) -eq
        [string]$policy.scope.base_workset.sha256)
Add-Assertion 'Report remains fail closed' ($report.result -eq 'BLOCKED' -and
    $report.review_execution_result -eq 'PASS' -and $report.task_status -eq 'BLOCKED' -and
    $report.completion_criteria_satisfied -eq $false -and
    $report.g2_06_satisfied -eq $false -and $report.p3_authorized -eq $false)
Add-Assertion 'Diagnostic scope complete' ($report.diagnostic_scope_complete -eq $true -and
    [int]$report.scope.targets -eq 3651 -and [int]$report.scope.candidate_edges -eq 12764)
Add-Assertion 'Exact candidate identity control' ($report.scope.candidate_identity_exact -eq $true -and
    $report.scope.production_binder_used -eq $true -and
    $report.scope.first_candidate_selection_used -eq $false)
$recoveryPlanBinding = @($report.input_bindings | Where-Object {
        $_.path -eq
            'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
    })
Add-Assertion 'A.13 effective plan is an exact report input' `
    ($recoveryPlanBinding.Count -eq 1 -and $recoveryPlanBinding[0].tracked -eq $false -and
        [int]$recoveryPlanBinding[0].lines -eq 21 -and
        [string]$recoveryPlanBinding[0].sha256 -eq (Get-Sha256 $recoveryPlanPath))
Add-Assertion 'Candidate dispositions close' `
    ([int]$report.measured.descriptor_parsed_candidates -eq 12764 -and
        [int]$report.measured.descriptor_rejected_candidates -eq 0 -and
        [int]$report.measured.binding_pass_candidates -eq 12561 -and
        [int]$report.measured.binding_rejected_candidates -eq 203 -and
        [int]$report.measured.effective_binding_pass_candidates -eq 12576 -and
        [int]$report.measured.effective_binding_rejected_candidates -eq 188 -and
        [int]$report.measured.recovery_applied_candidates -eq 15)
Add-Assertion 'Strict target and edge dispositions close' `
    ([int]$report.measured.strict_resolved_targets -eq 3443 -and
        [int]$report.measured.strict_ambiguous_targets -eq 189 -and
        [int]$report.measured.strict_unresolved_targets -eq 19 -and
        [int]$report.measured.strict_resolved_edges -eq 12194 -and
        [int]$report.measured.strict_ambiguous_edges -eq 546 -and
        [int]$report.measured.strict_unresolved_edges -eq 24)
Add-Assertion 'Target dispositions close' `
    ([int]$report.measured.resolved_targets -eq 3456 -and
        [int]$report.measured.ambiguous_targets -eq 189 -and
        [int]$report.measured.unresolved_targets -eq 6)
Add-Assertion 'Full workset reconciliation closes' `
    ([int]$report.measured.reconciled_full_workset.targets -eq 21494 -and
        [int]$report.measured.reconciled_full_workset.candidate_edges -eq 39351 -and
        [int]$report.measured.reconciled_full_workset.resolved_targets -eq 21299 -and
        [int]$report.measured.reconciled_full_workset.ambiguous_targets -eq 189 -and
        [int]$report.measured.reconciled_full_workset.unresolved_targets -eq 6 -and
        [int]$report.measured.reconciled_full_workset.resolved_edges -eq 38796 -and
        [int]$report.measured.reconciled_full_workset.ambiguous_edges -eq 546 -and
        [int]$report.measured.reconciled_full_workset.unresolved_edges -eq 9 -and
        [int]$report.measured.reconciled_full_workset.unknown_targets -eq 0 -and
        [int]$report.measured.reconciled_full_workset.unknown_edges -eq 0)
Add-Assertion 'Divergent partial rejection remains fail closed' `
    ([int]$report.measured.by_prior_resolution_basis.DIVERGENT_DESCRIPTOR_SET.targets -eq 183 -and
        [int]$report.measured.by_prior_resolution_basis.DIVERGENT_DESCRIPTOR_SET.candidate_edges -eq 534 -and
        [int]$report.measured.by_prior_resolution_basis.DIVERGENT_DESCRIPTOR_SET.ambiguous -eq 183 -and
        [int]$report.measured.by_resolution_basis_targets.OPEN_REJECTED_CANDIDATE -eq 174 -and
        [int]$report.measured.by_resolution_basis_edges.OPEN_REJECTED_CANDIDATE -eq 516)
Add-Assertion 'Coarse-equivalent transition measured' `
    ([int]$report.measured.by_prior_resolution_basis.EQUIVALENT_VALID_DESCRIPTOR_SET.targets -eq 2514 -and
        [int]$report.measured.by_prior_resolution_basis.EQUIVALENT_VALID_DESCRIPTOR_SET.resolved -eq 2508 -and
        [int]$report.measured.by_prior_resolution_basis.EQUIVALENT_VALID_DESCRIPTOR_SET.ambiguous -eq 6)
Add-Assertion 'Strict zero-valid transition records effective recovery' `
    ([int]$report.measured.by_prior_resolution_basis.DESCRIPTOR_VALIDATION_FAILED.targets -eq 19 -and
        [int]$report.measured.by_prior_resolution_basis.DESCRIPTOR_VALIDATION_FAILED.resolved -eq 13 -and
        [int]$report.measured.by_prior_resolution_basis.DESCRIPTOR_VALIDATION_FAILED.unresolved -eq 6)
Add-Assertion 'QTX prefix transitions retain family closure' `
    ([int]$report.measured.by_family.qtx.targets -eq 2324 -and
        [int]$report.measured.by_family.qtx.resolved -eq 2149 -and
        [int]$report.measured.by_family.qtx.ambiguous -eq 171 -and
        [int]$report.measured.by_family.qtx.unresolved -eq 4)
Add-Assertion 'Unique SKEM production binding measured' `
    ([int]$report.measured.by_prior_resolution_basis.UNIQUE_VALID_DESCRIPTOR.targets -eq 935 -and
        [int]$report.measured.by_prior_resolution_basis.UNIQUE_VALID_DESCRIPTOR.resolved -eq 935)
Add-Assertion 'Completion is truthfully unsatisfied' ($report.completion.satisfied -eq $false -and
    [int]$report.completion.observed_ambiguous_targets -eq 189 -and
    [int]$report.completion.observed_unresolved_targets -eq 6)
Add-Assertion 'Detail export hash bound' ((Get-LineCount $detailPath) -eq 3651 -and
    (Get-Sha256 $detailPath) -eq [string]$report.detail_export.sha256 -and
    [int64](Get-Item $detailPath).Length -eq [int64]$report.detail_export.bytes)
$prefixRecoveredCandidates = @(Get-Content -LiteralPath $detailPath -Encoding UTF8 |
    ForEach-Object { $_ | ConvertFrom-Json -Depth 100 } |
    ForEach-Object { @($_.candidates) } |
    Where-Object recovery_kind -eq 'qtx_declared_mip_payload_prefix')
Add-Assertion 'A.13 recovery preserves descriptor semantic identity' `
    ($prefixRecoveredCandidates.Count -eq 6 -and
        @($prefixRecoveredCandidates | Where-Object {
                $_.binding -ne 'REJECTED' -or $_.effective_binding -ne 'PASS' -or
                $_.recovery_applied -ne $true -or
                [string]$_.semantic_sha256 -ne [string]$_.effective_semantic_sha256
            }).Count -eq 0)
$identityAmbiguousDetail = @(Get-Content -LiteralPath $detailPath -Encoding UTF8 |
    ForEach-Object { $_ | ConvertFrom-Json -Depth 100 } |
    Where-Object resolution_basis -eq 'MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES')
$identityAmbiguousCandidates = @($identityAmbiguousDetail | ForEach-Object { @($_.candidates) })
$semanticFieldsComplete = @($identityAmbiguousCandidates | Where-Object {
        [string]$_.semantic_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$_.descriptor_semantic_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$_.identity_normalized_descriptor_semantic_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$_.identity_normalized_semantic_sha256 -cnotmatch '^[0-9a-f]{64}$'
    }).Count -eq 0
$strictNormalizedClassesRetained = @($identityAmbiguousDetail | Where-Object {
        @($_.candidates.identity_normalized_semantic_sha256 | Sort-Object -Unique).Count -ne 2
    }).Count -eq 0
Add-Assertion 'Identity-normalized diagnostics remain fail closed' `
    ($identityAmbiguousDetail.Count -eq 15 -and $identityAmbiguousCandidates.Count -eq 30 -and
        $semanticFieldsComplete -and $strictNormalizedClassesRetained)
$openRejectedDetail = @(Get-Content -LiteralPath $detailPath -Encoding UTF8 |
    ForEach-Object { $_ | ConvertFrom-Json -Depth 100 } |
    Where-Object resolution_basis -eq 'OPEN_REJECTED_CANDIDATE')
Add-Assertion 'Partial candidate rejection cannot resolve a target' `
    ($openRejectedDetail.Count -eq 174 -and
        @($openRejectedDetail | Where-Object resolution -ne 'AMBIGUOUS').Count -eq 0 -and
        @($openRejectedDetail | Where-Object {
                @($_.candidates | Where-Object effective_binding -eq 'REJECTED').Count -eq 0 -or
                @($_.candidates | Where-Object effective_binding -eq 'PASS').Count -eq 0
            }).Count -eq 0)
Add-Assertion 'Evidence report binding' ((Get-Sha256 $reportPath) -eq
    [string]$evidence.outputs.report_json.sha256)
Add-Assertion 'Evidence markdown binding' ((Get-Sha256 $markdownPath) -eq
    [string]$evidence.outputs.report_markdown.sha256)
Add-Assertion 'Evidence detail binding' ((Get-Sha256 $detailPath) -eq
    [string]$evidence.outputs.detail_export.sha256)
$implementationBindings = @($evidence.implementation.files)
$requiredA13ProductionSources = @(
    'Tools/TMXY.G2AssetDescriptorDiagnostics/apps/qtx_recovery.cpp'
    'Tools/TMXY.G2AssetDescriptorDiagnostics/apps/qtx_recovery.hpp'
    'Tools/TMXY.Texture/include/tmxy/texture/legacy_texture_descriptor_reader.hpp'
    'Tools/TMXY.Texture/include/tmxy/texture/qtx_reader.hpp'
    'Tools/TMXY.Texture/include/tmxy/texture/texture_error.hpp'
    'Tools/TMXY.Texture/include/tmxy/texture/texture_result.hpp'
    'Tools/TMXY.Texture/include/tmxy/texture/texture_types.hpp'
    'Tools/TMXY.Texture/src/block_compression.cpp'
    'Tools/TMXY.Texture/src/legacy_texture_descriptor_reader.cpp'
    'Tools/TMXY.Texture/src/qtx_reader.cpp'
    'Tools/TMXY.Texture/src/texture_decode.cpp'
    'Tools/TMXY.Texture/src/texture_decode_internal.hpp'
    'Tools/TMXY.Texture/src/texture_error.cpp'
)
$productionSourcesHashBound = @($requiredA13ProductionSources | Where-Object {
        $relativePath = $_
        $sourcePath = Join-Path $root $relativePath
        $bindings = @($implementationBindings | Where-Object path -eq $relativePath)
        $bindings.Count -ne 1 -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or
        [int64]$bindings[0].bytes -ne [int64](Get-Item -LiteralPath $sourcePath).Length -or
        [int]$bindings[0].lines -ne (Get-LineCount $sourcePath) -or
        [string]$bindings[0].sha256 -ne (Get-Sha256 $sourcePath)
    }).Count -eq 0
Add-Assertion 'A.13 direct production dependencies are source-hash bound' `
    $productionSourcesHashBound
Add-Assertion 'Locked non-root builder' ($evidence.builder.user -eq 'tmxy' -and
    $evidence.builder.image_reference -eq 'tmxy-backend-builder:p0-08' -and
    [string]$evidence.builder.image_id -cmatch '^sha256:[0-9a-f]{64}$')
Add-Assertion 'Read-only isolated execution' ($evidence.isolation.network -eq 'none' -and
    $evidence.isolation.read_only_container -eq $true -and
    $evidence.isolation.legacy_client_mount -eq 'read-only')
Add-Assertion 'Disclosure boundary' ($report.disclosure.anonymous_identities_only -eq $true -and
    $report.disclosure.private_source_paths -eq $false -and
    $report.disclosure.exact_primary_keys -eq $false -and
    $report.disclosure.decoded_confidential_payloads -eq $false)

$failed = @($assertions | Where-Object result -eq 'FAIL')
$output = [pscustomobject][ordered]@{
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
}
$output | ConvertTo-Json -Depth 20
if ($failed.Count -ne 0) { throw 'P2-20A.4 descriptor diagnostic contract failed.' }
