[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$LegacyClientSourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [string]$LegacyToolSourceRoot = 'E:\QQXYCodeDev\ToolCode',
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

function Test-BindingSet([object]$BindingSet, [string[]]$ExpectedRoles) {
    $entries = @($BindingSet.entries)
    if ($entries.Count -ne $ExpectedRoles.Count -or
        ($entries.role -join ',') -cne ($ExpectedRoles -join ',')) {
        return $false
    }
    $builder = [Text.StringBuilder]::new()
    foreach ($entry in $entries) {
        $path = Join-Path $root ([string]$entry.path).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            [int64]$entry.bytes -ne [int64](Get-Item -LiteralPath $path).Length -or
            [int]$entry.lines -ne (Get-LineCount $path) -or
            [string]$entry.sha256 -cne (Get-Sha256 $path)) {
            return $false
        }
        $tracked = ([bool]$entry.tracked).ToString().ToLowerInvariant()
        [void]$builder.Append(
            "$($entry.role)`t$($entry.path)`t$tracked`t$($entry.bytes)`t$($entry.lines)`t$($entry.sha256)`n")
    }
    return [string]$BindingSet.aggregate_sha256 -ceq (Get-TextSha256 $builder.ToString())
}

function Test-OutputBinding([object]$Binding, [string]$ExpectedPath, [bool]$Tracked) {
    $path = Join-Path $root $ExpectedPath.Replace('/', '\')
    return [string]$Binding.path -ceq $ExpectedPath -and
        [bool]$Binding.tracked -eq $Tracked -and
        (Test-Path -LiteralPath $path -PathType Leaf) -and
        [int64]$Binding.bytes -eq [int64](Get-Item -LiteralPath $path).Length -and
        [int]$Binding.lines -eq (Get-LineCount $path) -and
        [string]$Binding.sha256 -ceq (Get-Sha256 $path)
}

function Test-LegacyProvenance([object]$Candidate, [object]$Policy) {
    $expected = @($Policy.legacy_source_roles | Sort-Object role)
    $actual = @($Candidate.roles)
    if ($actual.Count -ne 7 -or ($actual.role -join ',') -cne ($expected.role -join ',') -or
        ($actual.sha256 -join ',') -cne ($expected.sha256 -join ',')) {
        return $false
    }
    $canonical = ($actual | ForEach-Object { "$($_.role)`t$($_.sha256)`n" }) -join ''
    return [string]$Candidate.aggregate_sha256 -ceq (Get-TextSha256 $canonical)
}

$module = Join-Path $root 'Tools\TMXY.G2StaticMeshPayloadSectionPrefix'
$wrapperPath = Join-Path $module 'New-G2StaticMeshPayloadSectionPrefix.ps1'
$generatorPath = Join-Path $module 'g2_static_mesh_payload_section_prefix.py'
$commonPath = Join-Path $module 'static_mesh_prefix_common.py'
$probePath = Join-Path $module 'apps\prefix_probe_main.cpp'
$readmePath = Join-Path $module 'README.md'
$cmakePath = Join-Path $module 'CMakeLists.txt'
$policyPath = Join-Path $root `
    'Contracts\data-schema\g2-static-mesh-payload-section-prefix-policy-v1.json'
$schemaPath = Join-Path $root `
    'Contracts\data-schema\g2-static-mesh-payload-section-prefix-v1.schema.json'
$detailSchemaPath = Join-Path $root `
    'Contracts\data-schema\g2-static-mesh-payload-section-prefix-detail-v1.schema.json'
$formatPath = Join-Path $root 'Docs\Formats\G2-STATIC-MESH-PAYLOAD-SECTION-PREFIX.md'
$reportPath = Join-Path $root `
    'Data\Reports\p2-20a-static-mesh-payload-section-prefix-report.json'
$markdownPath = Join-Path $root `
    'Data\Reports\p2-20a-static-mesh-payload-section-prefix-report.md'
$detailPath = Join-Path $root `
    'Data\Exports\P2-20\p2-20a-static-mesh-payload-section-prefix.jsonl'
$evidencePath = Join-Path $root `
    'Data\Inventory\p2-20a-static-mesh-payload-section-prefix.json'

foreach ($required in @($wrapperPath, $generatorPath, $commonPath, $probePath, $readmePath,
        $cmakePath, $policyPath, $schemaPath, $detailSchemaPath, $formatPath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($required))" `
        (Test-Path -LiteralPath $required -PathType Leaf)
}

if ($VerifyDerivedSources -and -not $SkipRegeneration) {
    $check = (& $wrapperPath -RebuildRoot $root -LegacyClientRoot $LegacyClientRoot `
        -LegacyClientSourceRoot $LegacyClientSourceRoot `
        -LegacyToolSourceRoot $LegacyToolSourceRoot -Check) | ConvertFrom-Json -Depth 100
    Add-Assertion 'Deterministic isolated regeneration' `
        ($check.result -eq 'PASS_DIAGNOSTIC' -and $check.task_status -eq 'BLOCKED' -and
            [int]$check.targets -eq 1 -and [int]$check.candidate_edges -eq 2 -and
            [int]$check.strict_rejected_edges -eq 2 -and [int]$check.prefix_pass_edges -eq 2 -and
            [int]$check.body_variants -eq 1 -and [int]$check.descriptor_semantic_variants -eq 1 -and
            [int]$check.strict_semantic_variants -eq 1 -and [int]$check.prefix_semantic_variants -eq 1 -and
            [int]$check.candidate_selections -eq 0 -and [int]$check.automatic_resolutions -eq 0 -and
            $check.authority_state_changed -eq $false -and $check.adapter_applied -eq $false -and
            $check.recovery_applied -eq $false -and $check.source_basis -eq 'SOURCE_DERIVED' -and
            $check.legacy_binary_executed -eq $false -and $check.runtime_parity_proven -eq $false -and
            $check.g2_06_satisfied -eq $false -and $check.p3_authorized -eq $false)
}

foreach ($required in @($reportPath, $markdownPath, $detailPath, $evidencePath)) {
    Add-Assertion "Generated file $([IO.Path]::GetFileName($required))" `
        (Test-Path -LiteralPath $required -PathType Leaf)
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100
$reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
$report = Copy-Json $reportText
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$detailLines = @([IO.File]::ReadLines($detailPath))
$detail = Copy-Json $detailLines[0]

Add-Assertion 'Closed report schema' `
    ($reportText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
Add-Assertion 'Exactly one closed ignored detail row' `
    ($detailLines.Count -eq 1 -and
        ($detailLines[0] | Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue))

$inputRoles = @('a4_report', 'a4_inventory', 'a4_detail', 'a7_report', 'a7_inventory',
    'a7_detail', 'a8_report', 'a8_inventory', 'a8_detail', 'p2_12_catalog', 'policy',
    'schema', 'detail_schema')
Add-Assertion 'Thirteen ordered upstream and contract inputs are hash bound' `
    (Test-BindingSet $report.input_bindings $inputRoles)
$productionRoles = @('static_mesh_types_header', 'static_mesh_api_header',
    'static_mesh_binding_implementation', 'static_mesh_payload_parser',
    'static_mesh_error_source')
Add-Assertion 'Closed production implementation set is hash bound' `
    ($report.production_contract.api -eq 'bind_static_mesh_with_payload_section_prefix' -and
        (Test-BindingSet $report.production_contract.implementation_bindings $productionRoles))
Add-Assertion 'Contract files are directly hash bound' `
    ([string]$report.contracts.policy_sha256 -ceq (Get-Sha256 $policyPath) -and
        [string]$report.contracts.schema_sha256 -ceq (Get-Sha256 $schemaPath) -and
        [string]$report.contracts.detail_schema_sha256 -ceq (Get-Sha256 $detailSchemaPath))
Add-Assertion 'Frozen policy and schema revision bytes are exact' `
    ((Get-Sha256 $policyPath) -ceq
        '4d32105f28c16156741cb1b5b0a586d24613a71e7aeca52a534d2a677292789e' -and
        (Get-Sha256 $schemaPath) -ceq
        '077ad4f71ef4d45ae4033f93fedc049dbe50771a576b43b22376c8c6a5e7ba6e' -and
        (Get-Sha256 $detailSchemaPath) -ceq
        '6b1f4651870eb599df86eff0d004deb9128b10e09bf2b859e7672a5065c062c8')
Add-Assertion 'Seven legacy roles expose hashes only and match policy' `
    (Test-LegacyProvenance $report.legacy_source_provenance $policy)

$sourceFacts = @('exporter_material_section_ordinal_alignment',
    'factory_zero_face_section_omission', 'renderer_iteration_bounded_by_payload_sections',
    'same_index_material_lookup', 'trailing_material_slot_not_consumed',
    'payload_section_order_preserved')
$unprovenSourceFacts = @($sourceFacts | Where-Object {
    $report.source_facts.PSObject.Properties[$_].Value -ne $true -or
    $policy.expected_source_facts.PSObject.Properties[$_].Value -ne $true
})
Add-Assertion 'All six hash-locked source facts are proven' `
    ($unprovenSourceFacts.Count -eq 0)
Add-Assertion 'Source proof does not claim binary or runtime parity' `
    ($report.proof_classification.source_basis -eq 'SOURCE_DERIVED' -and
        $report.proof_classification.legacy_binary_executed -eq $false -and
        $report.proof_classification.runtime_parity_proven -eq $false)
Add-Assertion 'Frozen scope and exact relation are reproduced' `
    ([int]$report.scope.targets -eq 1 -and [int]$report.scope.candidate_edges -eq 2 -and
        [int]$report.scope.unique_candidates -eq 2 -and
        $report.scope.candidate_ids_distinct -eq $true -and
        $report.scope.candidate_set_exact -eq $true -and
        $report.observed_relation.recovery_kind -eq 'sm_payload_section_prefix' -and
        $report.observed_relation.basis -eq 'payload_section_prefix_contract' -and
        [int]$report.observed_relation.descriptor_material_slots -eq 2 -and
        [int]$report.observed_relation.payload_sections -eq 1 -and
        [int]$report.observed_relation.nonempty_payload_sections -eq 1 -and
        [int]$report.observed_relation.ignored_trailing_material_slots -eq 1 -and
        $report.observed_relation.dense_material_slots -eq $true -and
        [int]$report.observed_relation.observed_edges -eq 2)
Add-Assertion 'Strict rejection and prefix diagnostic pass reconcile' `
    ([int]$report.measured.source_assets_reverified -eq 1 -and
        [int]$report.measured.package_files_hashed -eq 2 -and
        [int]$report.measured.candidate_bodies_reverified -eq 2 -and
        [int]$report.measured.strict_rejected_edges -eq 2 -and
        [int]$report.measured.material_slot_mismatch_edges -eq 2 -and
        [int]$report.measured.prefix_pass_edges -eq 2 -and
        [int]$report.measured.body_variants -eq 1 -and
        [int]$report.measured.descriptor_semantic_variants -eq 1 -and
        [int]$report.measured.strict_semantic_variants -eq 1 -and
        [int]$report.measured.prefix_semantic_variants -eq 1)
Add-Assertion 'Authority and resolution remain unchanged' `
    ($report.result -eq 'BLOCKED' -and $report.review_execution_result -eq 'PASS_DIAGNOSTIC' -and
        $report.task_status -eq 'BLOCKED' -and $report.completion_criteria_satisfied -eq $false -and
        $report.g2_06_satisfied -eq $false -and $report.p3_authorized -eq $false -and
        $report.authority_boundary.a4_is_authoritative -eq $true -and
        $report.authority_boundary.authority_state_changed -eq $false -and
        $report.authority_boundary.adapter_applied -eq $false -and
        $report.authority_boundary.recovery_applied -eq $false -and
        $report.authority_boundary.machine_can_select_candidate -eq $false -and
        $report.authority_boundary.machine_can_approve_disposition -eq $false -and
        [int]$report.measured.candidate_selections -eq 0 -and
        [int]$report.measured.automatic_resolutions -eq 0 -and
        [int]$report.measured.owner_dispositions -eq 0 -and
        [int]$report.measured.content_dispositions -eq 0)
Add-Assertion 'Global blockers remain exact' `
    ([int]$report.preserved_blockers.asset_effective_ambiguous_targets -eq 189 -and
        [int]$report.preserved_blockers.asset_effective_ambiguous_edges -eq 546 -and
        [int]$report.preserved_blockers.asset_effective_unresolved_targets -eq 12 -and
        [int]$report.preserved_blockers.asset_effective_unresolved_edges -eq 15 -and
        [int]$report.preserved_blockers.g2_satisfied -eq 7 -and
        [int]$report.preserved_blockers.g2_blocked -eq 2)

$ids = @($detail.candidates.candidate_id | Sort-Object)
Add-Assertion 'Ignored detail has two distinct exact candidates with no selection' `
    ($detail.candidate_count -eq 2 -and @($ids | Select-Object -Unique).Count -eq 2 -and
        [string]$detail.candidate_set_sha256 -ceq (Get-TextSha256 (($ids -join "`n") + "`n")) -and
        $detail.effective_resolution -eq 'UNRESOLVED' -and
        $detail.candidate_selected -eq $false -and $detail.automatic_resolution -eq $false -and
        $detail.authority_state_changed -eq $false)
Add-Assertion 'Every detail edge carries the exact relation without application' `
    (@($detail.candidates | Where-Object {
        $_.strict_binding -ne 'REJECTED' -or $_.strict_error_code -ne 'material_slot_mismatch' -or
        $_.prefix_binding -ne 'PASS' -or [int]$_.declared_material_slots -ne 2 -or
        [int]$_.payload_sections -ne 1 -or [int]$_.nonempty_payload_sections -ne 1 -or
        [int]$_.ignored_trailing_material_slots -ne 1 -or
        $_.slot_basis -ne 'payload_section_prefix_contract' -or
        $_.recovery_applied -ne $false -or $_.adapter_applied -ne $false -or
        $_.content_disposition -ne 'NONE'
    }).Count -eq 0)
Add-Assertion 'Evidence binds report Markdown and ignored detail outputs' `
    ((Test-OutputBinding $evidence.report `
        'Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.json' $true) -and
        (Test-OutputBinding $evidence.report_markdown `
            'Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.md' $true) -and
        (Test-OutputBinding $evidence.outputs.detail_export `
            'Data/Exports/P2-20/p2-20a-static-mesh-payload-section-prefix.jsonl' $false))
$implementationPaths = @(
    'Tools/TMXY.G2StaticMeshPayloadSectionPrefix/CMakeLists.txt',
    'Tools/TMXY.G2StaticMeshPayloadSectionPrefix/README.md',
    'Tools/TMXY.G2StaticMeshPayloadSectionPrefix/New-G2StaticMeshPayloadSectionPrefix.ps1',
    'Tools/TMXY.G2StaticMeshPayloadSectionPrefix/g2_static_mesh_payload_section_prefix.py',
    'Tools/TMXY.G2StaticMeshPayloadSectionPrefix/static_mesh_prefix_common.py',
    'Tools/TMXY.G2StaticMeshPayloadSectionPrefix/apps/prefix_probe_main.cpp',
    'Contracts/data-schema/g2-static-mesh-payload-section-prefix-policy-v1.json',
    'Contracts/data-schema/g2-static-mesh-payload-section-prefix-v1.schema.json',
    'Contracts/data-schema/g2-static-mesh-payload-section-prefix-detail-v1.schema.json',
    'Docs/Formats/G2-STATIC-MESH-PAYLOAD-SECTION-PREFIX.md',
    'Tests/Contract/Test-G2StaticMeshPayloadSectionPrefix.ps1',
    'Tools/TMXY.G2AssetBindingFailureDiagnostics/apps/probe_support.cpp',
    'Tools/TMXY.G2AssetBindingFailureDiagnostics/apps/probe_support.hpp',
    'Tools/TMXY.G2AssetDescriptorDiagnostics/semantic_hash.cpp',
    'Tools/TMXY.G2AssetDescriptorDiagnostics/semantic_hash.hpp',
    'Tools/TMXY.G2AssetDescriptorDiagnostics/sha256.cpp',
    'Tools/TMXY.G2AssetDescriptorDiagnostics/sha256.hpp',
    'Tools/TMXY.AssetInventory/apps/descriptor_semantic_signature.cpp',
    'Tools/TMXY.AssetInventory/apps/descriptor_semantic_signature.hpp')
$implementationEntries = @($evidence.implementation.files)
$implementationRoles = @(1..$implementationPaths.Count |
    ForEach-Object { 'implementation_{0:d2}' -f $_ })
$implementationBinding = [pscustomobject]@{
    entries = $implementationEntries
    aggregate_sha256 = $evidence.implementation.aggregate_sha256
}
Add-Assertion 'Exact implementation files and aggregate are independently bound' `
    (($implementationEntries.path -join "`n") -ceq ($implementationPaths -join "`n") -and
        @($implementationEntries | Where-Object { -not [bool]$_.tracked }).Count -eq 0 -and
        (Test-BindingSet $implementationBinding $implementationRoles) -and
        [int]$evidence.implementation.generator_self_test_assertions -eq 20 -and
        $evidence.implementation.probe_startup_self_tests -eq $true)
Add-Assertion 'Locked non-root isolated builder is recorded' `
    ($evidence.builder.image_reference -eq 'tmxy-backend-builder:p0-08' -and
        [string]$evidence.builder.image_id -cmatch '^sha256:[0-9a-f]{64}$' -and
        $evidence.builder.user -eq 'tmxy' -and $evidence.isolation.network -eq 'none' -and
        $evidence.isolation.read_only_container -eq $true -and
        $evidence.isolation.repository_mount -eq 'read-only' -and
        $evidence.isolation.legacy_asset_mount -eq 'read-only' -and
        $evidence.isolation.legacy_source_mounts -eq 'read-only-files')

$trackedOutputText = (Get-Content -LiteralPath $policyPath, $reportPath, $markdownPath,
    $evidencePath -Raw -Encoding UTF8) -join "`n"
Add-Assertion 'Tracked evidence excludes legacy paths lines and authority leakage' `
    ($trackedOutputText -cnotmatch '(?i)[A-Z]:\\|/legacy-|"source_line"\s*:|"exact_primary_key_value"\s*:|"g2_06_satisfied"\s*:\s*true|"p3_authorized"\s*:\s*true')
Add-Assertion 'Implementation files respect size gates' `
    ((Get-LineCount $generatorPath) -le 500 -and (Get-LineCount $commonPath) -le 500 -and
        (Get-LineCount $wrapperPath) -le 500 -and (Get-LineCount $probePath) -le 500 -and
        (Get-LineCount $PSCommandPath) -le 1000)

$mutated = Copy-Json $reportText
$mutated | Add-Member unknown_root $false
Add-Assertion 'Negative: unknown report root field rejected' (Test-SchemaRejected $mutated $schemaPath)
$mutated = Copy-Json $reportText
$mutated.production_contract.implementation_bindings.entries[0] | Add-Member unknown_nested $false
Add-Assertion 'Negative: unknown nested field rejected' (Test-SchemaRejected $mutated $schemaPath)
$detailMutation = Copy-Json $detailLines[0]
$detailMutation.candidates[0] | Add-Member unknown_nested $false
Add-Assertion 'Negative: unknown detail candidate field rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)

foreach ($case in @(
    @{name = 'forged measured count'; mutate = { param($x) $x.measured.prefix_pass_edges = 1 }},
    @{name = 'forged relation'; mutate = { param($x) $x.observed_relation.payload_sections = 2 }},
    @{name = 'false runtime parity'; mutate = { param($x) $x.proof_classification.runtime_parity_proven = $true }},
    @{name = 'false binary execution'; mutate = { param($x) $x.proof_classification.legacy_binary_executed = $true }},
    @{name = 'false authority change'; mutate = { param($x) $x.authority_boundary.authority_state_changed = $true }},
    @{name = 'false adapter application'; mutate = { param($x) $x.authority_boundary.adapter_applied = $true }},
    @{name = 'false recovery application'; mutate = { param($x) $x.authority_boundary.recovery_applied = $true }},
    @{name = 'false G2'; mutate = { param($x) $x.g2_06_satisfied = $true }},
    @{name = 'false P3'; mutate = { param($x) $x.p3_authorized = $true }},
    @{name = 'candidate selection'; mutate = { param($x) $x.measured.candidate_selections = 1 }}
)) {
    $mutated = Copy-Json $reportText
    & $case.mutate $mutated
    Add-Assertion "Negative: $($case.name) rejected" (Test-SchemaRejected $mutated $schemaPath)
}

$detailMutation = Copy-Json $detailLines[0]
$detailMutation.effective_resolution = 'RESOLVED'
Add-Assertion 'Negative: false effective resolution rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$detailMutation = Copy-Json $detailLines[0]
$detailMutation.candidate_selected = $true
Add-Assertion 'Negative: candidate selection in detail rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$detailMutation = Copy-Json $detailLines[0]
$detailMutation.candidates = @($detailMutation.candidates | Select-Object -First 1)
Add-Assertion 'Negative: missing candidate rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$detailMutation = Copy-Json $detailLines[0]
$detailMutation.candidates = @($detailMutation.candidates) + @($detailMutation.candidates[0])
Add-Assertion 'Negative: extra candidate rejected' `
    (Test-SchemaRejected $detailMutation $detailSchemaPath)
$detailMutation = Copy-Json $detailLines[0]
$detailMutation.candidates[0].body_sha256 = '0' * 64
Add-Assertion 'Negative: candidate hash forgery differs from bound detail' `
    ([string]$detailMutation.candidates[0].body_sha256 -cne
        [string]$detail.candidates[0].body_sha256)

$sourceMutation = Copy-Json ($report.legacy_source_provenance | ConvertTo-Json -Depth 20)
$sourceMutation.roles[0].sha256 = '0' * 64
Add-Assertion 'Negative: legacy role source hash drift rejected' `
    (-not (Test-LegacyProvenance $sourceMutation $policy))
$sourceMutation = Copy-Json ($report.legacy_source_provenance | ConvertTo-Json -Depth 20)
$sourceMutation.roles[0].role = 'legacy_forged_role'
Add-Assertion 'Negative: forged legacy source role rejected' `
    (-not (Test-LegacyProvenance $sourceMutation $policy))
$bindingMutation = Copy-Json ($report.detail_export | ConvertTo-Json -Depth 20)
$bindingMutation.sha256 = '0' * 64
Add-Assertion 'Negative: output hash tamper rejected by file binding' `
    (-not (Test-OutputBinding $bindingMutation `
        'Data/Exports/P2-20/p2-20a-static-mesh-payload-section-prefix.jsonl' $false))

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    evidence_revision = 'P2-20A.12-contract'
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
if ($failed.Count -ne 0) { throw 'P2-20A.12 static-mesh prefix contract failed.' }
