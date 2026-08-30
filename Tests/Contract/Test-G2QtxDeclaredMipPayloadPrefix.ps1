[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$LegacyClientSourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [switch]$VerifyDerivedSources,
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

function Test-BindingSet([object]$BindingSet, [object[]]$Expected) {
    $entries = @($BindingSet.entries)
    if ($entries.Count -ne $Expected.Count) { return $false }
    $builder = [Text.StringBuilder]::new()
    for ($index = 0; $index -lt $entries.Count; ++$index) {
        $entry = $entries[$index]
        $expectedEntry = $Expected[$index]
        if ([string]$entry.role -cne [string]$expectedEntry.role -or
            [string]$entry.path -cne [string]$expectedEntry.path -or
            [bool]$entry.tracked -ne [bool]$expectedEntry.tracked) { return $false }
        $path = Join-Path $root ([string]$entry.path).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            [int64]$entry.bytes -ne [int64](Get-Item -LiteralPath $path).Length -or
            [int]$entry.lines -ne (Get-LineCount $path) -or
            [string]$entry.sha256 -cne (Get-Sha256 $path)) { return $false }
        $tracked = ([bool]$entry.tracked).ToString().ToLowerInvariant()
        [void]$builder.Append(
            "$($entry.role)`t$($entry.path)`t$tracked`t$($entry.bytes)`t$($entry.lines)`t$($entry.sha256)`n")
    }
    return [string]$BindingSet.aggregate_sha256 -ceq (Get-TextSha256 $builder.ToString())
}

function Test-OutputBinding([object]$Binding, [string]$ExpectedPath, [bool]$Tracked) {
    $path = Join-Path $root $ExpectedPath.Replace('/', '\')
    return [string]$Binding.path -ceq $ExpectedPath -and [bool]$Binding.tracked -eq $Tracked -and
        (Test-Path -LiteralPath $path -PathType Leaf) -and
        [int64]$Binding.bytes -eq [int64](Get-Item -LiteralPath $path).Length -and
        [int]$Binding.lines -eq (Get-LineCount $path) -and
        [string]$Binding.sha256 -ceq (Get-Sha256 $path)
}

function Test-LegacyProvenance([object]$Candidate, [object]$Policy) {
    $expected = @($Policy.legacy_source_roles | Sort-Object role)
    $actual = @($Candidate.roles)
    if ($actual.Count -ne 2 -or ($actual.role -join ',') -cne ($expected.role -join ',') -or
        ($actual.sha256 -join ',') -cne ($expected.sha256 -join ',')) { return $false }
    $canonical = ($actual | ForEach-Object { "$($_.role)`t$($_.sha256)`n" }) -join ''
    return [string]$Candidate.aggregate_sha256 -ceq (Get-TextSha256 $canonical)
}

$module = Join-Path $root 'Tools\TMXY.G2QtxDeclaredMipPayloadPrefix'
$wrapperPath = Join-Path $module 'New-G2QtxDeclaredMipPayloadPrefix.ps1'
$generatorPath = Join-Path $module 'g2_qtx_declared_mip_payload_prefix.py'
$commonPath = Join-Path $module 'qtx_declared_mip_prefix_common.py'
$probePath = Join-Path $module 'apps\qtx_declared_mip_prefix_probe_main.cpp'
$readmePath = Join-Path $module 'README.md'
$cmakePath = Join-Path $module 'CMakeLists.txt'
$policyPath = Join-Path $root `
    'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-policy-v1.json'
$schemaPath = Join-Path $root `
    'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-v1.schema.json'
$detailSchemaPath = Join-Path $root `
    'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-detail-v1.schema.json'
$formatPath = Join-Path $root 'Docs\Formats\G2-QTX-DECLARED-MIP-PAYLOAD-PREFIX.md'
$reportPath = Join-Path $root `
    'Data\Reports\p2-20a-qtx-declared-mip-payload-prefix-report.json'
$markdownPath = Join-Path $root `
    'Data\Reports\p2-20a-qtx-declared-mip-payload-prefix-report.md'
$detailPath = Join-Path $root `
    'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix.jsonl'
$planPath = Join-Path $root `
    'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
$basePlanPath = Join-Path $root `
    'Contracts\data-schema\g2-asset-binding-recovery-base-plan-v1.tsv'
$evidencePath = Join-Path $root `
    'Data\Inventory\p2-20a-qtx-declared-mip-payload-prefix.json'

foreach ($required in @($wrapperPath, $generatorPath, $commonPath, $probePath, $readmePath,
        $cmakePath, $policyPath, $schemaPath, $detailSchemaPath, $basePlanPath, $formatPath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($required))" `
        (Test-Path -LiteralPath $required -PathType Leaf)
}
$commonText = Get-Content -LiteralPath $commonPath -Raw -Encoding UTF8
$wrapperText = Get-Content -LiteralPath $wrapperPath -Raw -Encoding UTF8
$prepareInputBlock = [regex]::Match($commonText,
    '(?s)PREPARE_INPUTS\s*=\s*\[(.*?)\]\s*CONTRACT_INPUTS').Groups[1].Value
Add-Assertion 'Prepare dependency set is acyclic and excludes effective-state reports' `
    ($prepareInputBlock -match 'base_plan_contract' -and
        $commonText -match 'g2-asset-binding-recovery-base-plan-v1\.tsv' -and
        $prepareInputBlock -match 'p2_03_graph' -and
        $prepareInputBlock -match 'p2_12_catalog' -and $prepareInputBlock -match 'policy' -and
        $prepareInputBlock -notmatch 'a8_base_plan|asset-binding-recovery-eligible-attempts|a4_|a7_|a8_report|a8_inventory|a8_detail|core_' -and
        $wrapperText -notmatch 'allow-pre-application-state|a7Generator|a7Prepare')
Add-Assertion 'Recovery-cycle bootstrap uses the exact tracked anonymous contract' `
    ((Get-LineCount $basePlanPath) -eq 21 -and
        (Get-Item -LiteralPath $basePlanPath).Length -eq 6504 -and
        (Get-Sha256 $basePlanPath) -ceq
            '4f256efc82fadda9528d502ed77dce890c8cf914e827f089422fc5c38d10fb99' -and
        $commonText -notmatch 'Data/Exports/P2-20/p2-20a-asset-binding-recovery-eligible-attempts\.tsv')
Add-Assertion 'Finalize reads but never republishes the prepared plan' `
    ($wrapperText -match "--effective-plan',\s*'/workspace/Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'" -and
        $wrapperText -match [regex]::Escape("foreach (`$name in @('detail', 'json', 'markdown', 'evidence'))") -and
        $wrapperText -match 'Published P2-20A\.13 effective plan differs from acyclic regeneration')

if ($VerifyDerivedSources -and -not $SkipRegeneration) {
    $prepareCheck = (& $wrapperPath -RebuildRoot $root -Mode Prepare -Check) |
        ConvertFrom-Json -Depth 100
    Add-Assertion 'Acyclic effective-plan regeneration' `
        ($prepareCheck.result -eq 'PASS' -and
            $prepareCheck.meaning -eq 'ACYCLIC_EFFECTIVE_PLAN_ONLY' -and
            [int]$prepareCheck.effective_plan_rows -eq 21 -and
            [int]$prepareCheck.effective_plan_changed_rows -eq 6 -and
            [int]$prepareCheck.effective_plan_unchanged_rows -eq 15)
    $check = (& $wrapperPath -RebuildRoot $root -LegacyClientRoot $LegacyClientRoot `
        -LegacyClientSourceRoot $LegacyClientSourceRoot -Mode Finalize -Check) |
        ConvertFrom-Json -Depth 100
    Add-Assertion 'Deterministic isolated regeneration' `
        ($check.result -eq 'PASS_DIAGNOSTIC' -and $check.task_status -eq 'BLOCKED' -and
            [int]$check.targets -eq 6 -and [int]$check.candidate_edges -eq 6 -and
            [int]$check.strict_rejected_edges -eq 6 -and
            [int]$check.explicit_prefix_pass_edges -eq 6 -and
            [int]$check.dds_prefix_only_edges -eq 6 -and
            [int]$check.effective_plan_rows -eq 21 -and
            [int]$check.effective_plan_changed_rows -eq 6 -and
            $check.upstream_effective_phase -eq 'POST_APPLICATION' -and
            [int]$check.candidate_selections -eq 0 -and [int]$check.automatic_resolutions -eq 0 -and
            $check.authority_state_changed -eq $false -and $check.adapter_applied -eq $false -and
            $check.recovery_applied -eq $false -and $check.source_basis -eq 'SOURCE_DERIVED' -and
            $check.legacy_binary_executed -eq $false -and $check.runtime_parity_proven -eq $false -and
            $check.g2_06_satisfied -eq $false -and $check.p3_authorized -eq $false)
}

foreach ($required in @($reportPath, $markdownPath, $detailPath, $planPath, $evidencePath)) {
    Add-Assertion "Generated file $([IO.Path]::GetFileName($required))" `
        (Test-Path -LiteralPath $required -PathType Leaf)
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
$report = Copy-Json $reportText
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$detailLines = @([IO.File]::ReadLines($detailPath))
$details = @($detailLines | ForEach-Object { Copy-Json $_ })

Add-Assertion 'Closed report schema' `
    ($reportText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
$invalidDetails = @($detailLines | Where-Object {
    -not ($_ | Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue) })
Add-Assertion 'Exactly six closed ignored detail rows' `
    ($detailLines.Count -eq 6 -and $invalidDetails.Count -eq 0)

$inputExpected = @(
    @{role='a4_report';path='Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json';tracked=$true},
    @{role='a4_inventory';path='Data/Inventory/p2-20a-asset-descriptor-diagnostics.json';tracked=$true},
    @{role='a4_detail';path='Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl';tracked=$false},
    @{role='a7_report';path='Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json';tracked=$true},
    @{role='a7_inventory';path='Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json';tracked=$true},
    @{role='a7_detail';path='Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl';tracked=$false},
    @{role='a8_report';path='Data/Reports/p2-20a-asset-binding-recovery-report.json';tracked=$true},
    @{role='a8_inventory';path='Data/Inventory/p2-20a-asset-binding-recovery.json';tracked=$true},
    @{role='a8_detail';path='Data/Exports/P2-20/p2-20a-asset-binding-recovery.jsonl';tracked=$false},
    @{role='core_report';path='Data/Reports/p2-20a-core-resource-closure-report.json';tracked=$true},
    @{role='core_inventory';path='Data/Inventory/p2-20a-core-resource-closure.json';tracked=$true},
    @{role='core_detail';path='Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl';tracked=$false},
    @{role='base_plan_contract';path='Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv';tracked=$true},
    @{role='p2_03_inventory';path='Data/Inventory/p2-03-package-dependency-graph.json';tracked=$true},
    @{role='p2_03_graph';path='Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl';tracked=$false},
    @{role='p2_12_inventory';path='Data/Inventory/p2-12-full-asset-inventory.json';tracked=$true},
    @{role='p2_12_catalog';path='Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl';tracked=$false},
    @{role='policy';path='Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-policy-v1.json';tracked=$true},
    @{role='schema';path='Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-v1.schema.json';tracked=$true},
    @{role='detail_schema';path='Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-detail-v1.schema.json';tracked=$true}
)
Add-Assertion 'Twenty ordered upstream source and contract inputs are hash bound' `
    (Test-BindingSet $report.input_bindings $inputExpected)
$productionExpected = @(
    @{role='texture_types_header';path='Tools/TMXY.Texture/include/tmxy/texture/texture_types.hpp';tracked=$true},
    @{role='qtx_reader_header';path='Tools/TMXY.Texture/include/tmxy/texture/qtx_reader.hpp';tracked=$true},
    @{role='qtx_reader_implementation';path='Tools/TMXY.Texture/src/qtx_reader.cpp';tracked=$true},
    @{role='texture_decode_internal_header';path='Tools/TMXY.Texture/src/texture_decode_internal.hpp';tracked=$true},
    @{role='texture_decode_implementation';path='Tools/TMXY.Texture/src/texture_decode.cpp';tracked=$true},
    @{role='dds_writer_implementation';path='Tools/TMXY.Texture/src/dds_writer.cpp';tracked=$true},
    @{role='texture_export_implementation';path='Tools/TMXY.Texture/src/texture_export.cpp';tracked=$true},
    @{role='texture_error_implementation';path='Tools/TMXY.Texture/src/texture_error.cpp';tracked=$true}
)
Add-Assertion 'Explicit production API and eight implementation files are hash bound' `
    ($report.production_contract.api -eq `
        'tmxy::texture::QtxReader::parse_with_declared_mip_payload_prefix' -and
        $report.production_contract.default_api_remains_strict -eq $true -and
        (Test-BindingSet $report.production_contract.implementation_bindings $productionExpected))
Add-Assertion 'Contract files are directly hash bound' `
    ([string]$report.contracts.policy_sha256 -ceq (Get-Sha256 $policyPath) -and
        [string]$report.contracts.schema_sha256 -ceq (Get-Sha256 $schemaPath) -and
        [string]$report.contracts.detail_schema_sha256 -ceq (Get-Sha256 $detailSchemaPath) -and
        [string]$report.contracts.base_plan_contract_sha256 -ceq
            (Get-Sha256 $basePlanPath))
Add-Assertion 'Frozen policy and schema revision bytes are exact' `
    ((Get-Sha256 $policyPath) -ceq
        '67e2cb3f2ebf6843177df09fb086249f1c3ab4d6f81a8fa31b5af27b456123f5' -and
     (Get-Sha256 $schemaPath) -ceq
        '56c7dc13c9af0feaf38384e344d5107fad4f15b3ca841ec07b8a01d9c852cb46' -and
     (Get-Sha256 $detailSchemaPath) -ceq
        '911196c1f6e03cc7bf33ea84a954b404d8b7cc7a7b2533c7ebad435cab7db63f')
Add-Assertion 'Two anonymous legacy source roles match frozen policy' `
    (Test-LegacyProvenance $report.legacy_source_provenance $policy)

Add-Assertion 'Frozen selected and excluded scope is exact' `
    ($policy.base_plan_contract.path -eq
        'Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv' -and
        $policy.base_plan_contract.tracked -eq $true -and
        [int]$policy.base_plan_contract.rows -eq 21 -and
        [int64]$policy.base_plan_contract.bytes -eq 6504 -and
        [string]$policy.base_plan_contract.sha256 -ceq (Get-Sha256 $basePlanPath) -and
        @($policy.selected_targets).Count -eq 6 -and
        @($policy.selected_targets.candidate_id | Select-Object -Unique).Count -eq 6 -and
        @($policy.excluded_unresolved_targets).Count -eq 4 -and
        @($policy.excluded_unresolved_targets.candidate_ids).Count -eq 6 -and
        [int]$report.scope.targets -eq 6 -and [int]$report.scope.candidate_edges -eq 6 -and
        [int]$report.scope.excluded_unresolved_targets -eq 4 -and
        [int]$report.scope.excluded_unresolved_edges -eq 6 -and
        $report.scope.excluded_scope_selected -eq $false)
Add-Assertion 'Final reconciliation requires coherent post-application state' `
    ($policy.proof_requirements.acyclic_prepare_uses_tracked_base_plan_contract_p2_12_p2_03 -eq $true -and
        $policy.proof_requirements.final_reconciliation_requires_post_application -eq $true -and
        $report.scope.current_upstream_effective_state.phase -eq 'POST_APPLICATION' -and
        [int]$report.scope.current_upstream_effective_state.selected_targets_resolved -eq 6 -and
        [int]$report.scope.current_upstream_effective_state.selected_edges_pass -eq 6)

$formats = $details.candidate.format | Group-Object | ForEach-Object { @{name=$_.Name;count=$_.Count} }
Add-Assertion 'Exact DXT1 and DXT5 boundary patterns are reproduced' `
    (@($details | Where-Object {$_.candidate.format -eq 'dxt1' -and
        [int]$_.candidate.width -eq 512 -and [int]$_.candidate.payload_boundary_mip_count -eq 10 -and
        [int]$_.candidate.maximum_natural_mip_count -eq 10 -and
        [int64]$_.candidate.input_payload_bytes -eq 174776 -and
        [int64]$_.candidate.consumed_payload_bytes -eq 131072 -and
        [int64]$_.candidate.ignored_payload_bytes -eq 43704}).Count -eq 3 -and
     @($details | Where-Object {$_.candidate.format -eq 'dxt5' -and
        [int]$_.candidate.width -eq 256 -and [int]$_.candidate.payload_boundary_mip_count -eq 7 -and
        [int]$_.candidate.maximum_natural_mip_count -eq 9 -and
        [int64]$_.candidate.input_payload_bytes -eq 87376 -and
        [int64]$_.candidate.consumed_payload_bytes -eq 65536 -and
        [int64]$_.candidate.ignored_payload_bytes -eq 21840}).Count -eq 3)
Add-Assertion 'All details prove strict reject explicit pass and prefix-only DDS' `
    (@($details | Where-Object {$_.source_strict_resolution -ne 'UNRESOLVED' -or
        $_.a13_resolution_change -ne $false -or $_.candidate.strict_binding -ne 'REJECTED' -or
        $_.candidate.strict_error_code -ne 'payload_size_mismatch' -or
        $_.candidate.strict_prefix_binding -ne 'PASS' -or
        $_.candidate.explicit_prefix_binding -ne 'PASS' -or
        $_.candidate.dds_payload_prefix_only -ne $true -or
        $_.candidate.ignored_tail_excluded_from_dds -ne $true -or
        $_.candidate.dds_payload_sha256 -cne $_.candidate.consumed_payload_sha256 -or
        [int64]$_.candidate.dds_bytes -ne 128 + [int64]$_.candidate.consumed_payload_bytes}).Count -eq 0)

$baseRows = @([IO.File]::ReadLines($basePlanPath))
$effectiveRows = @([IO.File]::ReadLines($planPath))
$selectedPlanRows = @{}
foreach ($item in @($policy.selected_targets)) {
    $selectedPlanRows["$($item.asset_id)`t$($item.candidate_id)"] = $item
}
$changedRows = 0
$planValid = $baseRows.Count -eq 21 -and $effectiveRows.Count -eq 21
for ($index = 0; $planValid -and $index -lt 21; ++$index) {
    $before = @($baseRows[$index] -split "`t")
    $after = @($effectiveRows[$index] -split "`t")
    if ($before.Count -ne 7 -or $after.Count -ne 7 -or
        ($before[0..4] + $before[6] -join "`t") -cne
        ($after[0..4] + $after[6] -join "`t")) { $planValid = $false; break }
    $key = "$($before[0])`t$($before[1])"
    if ($before[5] -cne $after[5]) {
        ++$changedRows
        if (-not $selectedPlanRows.ContainsKey($key) -or
            $before[2] -cne [string]$selectedPlanRows[$key].body_sha256 -or
            $before[3] -cne [string]$selectedPlanRows[$key].source_sha256 -or
            $before[5] -cne 'qtx_complete_mip_chain' -or
            $after[5] -cne 'qtx_declared_mip_payload_prefix') { $planValid = $false }
    }
    elseif ($selectedPlanRows.ContainsKey($key)) { $planValid = $false }
}
Add-Assertion 'Effective plan preserves 21 rows and changes exactly six selected recovery kinds' `
    ($planValid -and $selectedPlanRows.Count -eq 6 -and $changedRows -eq 6)
Add-Assertion 'Detail and effective plan output bindings are exact' `
    ((Test-OutputBinding $report.detail_export `
        'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix.jsonl' $false) -and
     (Test-OutputBinding $report.effective_recovery_plan `
        'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv' $false))

$inventoryFields = @('schema_version','evidence_revision','captured_utc','result',
    'review_execution_result','task_status','g2_06_satisfied','p3_authorized','measured','report',
    'report_markdown','outputs','contracts','implementation','builder','isolation',
    'proof_classification','authority_boundary','preserved_blockers','disclosure')
Add-Assertion 'Inventory root and outputs are closed' `
    (($evidence.PSObject.Properties.Name -join ',') -ceq ($inventoryFields -join ',') -and
        ($evidence.outputs.PSObject.Properties.Name -join ',') -ceq
            'detail_export,effective_recovery_plan' -and
        (Test-OutputBinding $evidence.report `
            'Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.json' $true) -and
        (Test-OutputBinding $evidence.report_markdown `
            'Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.md' $true))
Add-Assertion 'Inventory binds nineteen ordered implementation files' `
    (@($evidence.implementation.files).Count -eq 19 -and
        [int]$evidence.implementation.generator_self_test_assertions -eq 23 -and
        $evidence.implementation.probe_startup_self_tests -eq $true)
Add-Assertion 'Isolation and authority remain fail closed' `
    ($evidence.isolation.network -eq 'none' -and $evidence.isolation.read_only_container -eq $true -and
        $report.proof_classification.source_basis -eq 'SOURCE_DERIVED' -and
        $report.proof_classification.legacy_binary_executed -eq $false -and
        $report.proof_classification.runtime_parity_proven -eq $false -and
        $report.authority_boundary.authority_state_changed -eq $false -and
        $report.authority_boundary.adapter_applied -eq $false -and
        $report.authority_boundary.recovery_applied -eq $false -and
        $report.g2_06_satisfied -eq $false -and $report.p3_authorized -eq $false)
Add-Assertion 'Implementation files respect size gates' `
    ((Get-LineCount $generatorPath) -le 500 -and (Get-LineCount $commonPath) -le 500 -and
        (Get-LineCount $wrapperPath) -le 1000 -and (Get-LineCount $probePath) -le 1000 -and
        (Get-LineCount $PSCommandPath) -le 1000)

$mutated = Copy-Json $reportText
$mutated | Add-Member unknown_root $false
Add-Assertion 'Negative: unknown report root field rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.production_contract.implementation_bindings.entries[0] | Add-Member unknown_nested $false
Add-Assertion 'Negative: unknown nested binding field rejected' (Test-SchemaRejected $mutated $schemaPath)
foreach ($case in @(
    @{name='forged consumed bytes';mutate={param($x)$x.measured.consumed_payload_bytes=589823}},
    @{name='forged changed rows';mutate={param($x)$x.measured.effective_plan_changed_rows=5}},
    @{name='false runtime parity';mutate={param($x)$x.proof_classification.runtime_parity_proven=$true}},
    @{name='false recovery application';mutate={param($x)$x.authority_boundary.recovery_applied=$true}},
    @{name='false G2';mutate={param($x)$x.g2_06_satisfied=$true}},
    @{name='false P3';mutate={param($x)$x.p3_authorized=$true}},
    @{name='transitional PRE state';mutate={param($x)
        $x.scope.current_upstream_effective_state.phase='PRE_APPLICATION'
        $x.scope.current_upstream_effective_state.selected_targets_resolved=0
        $x.scope.current_upstream_effective_state.selected_edges_pass=0
        $x.scope.current_upstream_effective_state.selected_recovery_applied_edges=0}}
)) {
    $mutated = Copy-Json $reportText
    & $case.mutate $mutated
    Add-Assertion "Negative: $($case.name) rejected" (Test-SchemaRejected $mutated $schemaPath)
}
$detailMutation = Copy-Json $detailLines[0]
$detailMutation.candidate.ignored_payload_bytes = [int64]$detailMutation.candidate.ignored_payload_bytes - 1
Add-Assertion 'Negative: inconsistent ignored boundary rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$detailMutation = Copy-Json $detailLines[0]
$detailMutation.candidate.dds_payload_prefix_only = $false
Add-Assertion 'Negative: non-prefix DDS claim rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$detailMutation = Copy-Json $detailLines[0]
$detailMutation.a13_resolution_change = $true
Add-Assertion 'Negative: A13 resolution-change claim rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$bindingMutation = Copy-Json ($report.effective_recovery_plan | ConvertTo-Json -Depth 20)
$bindingMutation.sha256 = '0' * 64
Add-Assertion 'Negative: effective-plan hash tamper rejected' `
    (-not (Test-OutputBinding $bindingMutation `
        'Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv' $false))

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    evidence_revision = 'P2-20A.13-contract'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    review_execution_result = 'PASS_DIAGNOSTIC'
    task_status = 'BLOCKED'
    contract_assertions_satisfied = $failed.Count -eq 0
    completion_criteria_satisfied = $false
    g2_06_satisfied = $false
    p3_authorized = $false
    assertions = $assertions.Count
    passed = $assertions.Count - $failed.Count
    failed = $failed.Count
    details = $assertions
} | ConvertTo-Json -Depth 20
if ($failed.Count -ne 0) { throw 'P2-20A.13 QTX declared-mip prefix contract failed.' }
