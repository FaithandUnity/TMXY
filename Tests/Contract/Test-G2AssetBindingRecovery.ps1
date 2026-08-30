[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$SkipRegeneration,
    [switch]$FinalizeExpected
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

function Copy-JsonObject([object]$Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-InputBindingSet([object]$Set, [object[]]$Expected) {
    $entries = @($Set.entries)
    if ($entries.Count -ne $Expected.Count) { return $false }
    $canonical = [Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Expected.Count; ++$index) {
        $entry, $spec = $entries[$index], $Expected[$index]
        $path = Join-Path $root ([string]$spec.path).Replace('/', '\')
        if ($entry.role -cne $spec.role -or $entry.path -cne $spec.path -or
            [bool]$entry.tracked -ne [bool]$spec.tracked -or
            [int64]$entry.bytes -ne (Get-Item -LiteralPath $path).Length -or
            [int]$entry.lines -ne (Get-LineCount $path) -or
            $entry.sha256 -cne (Get-Sha256 $path)) { return $false }
        $tracked = ([bool]$entry.tracked).ToString().ToLowerInvariant()
        [void]$canonical.Append("$($entry.role)`t$($entry.path)`t$tracked`t$($entry.bytes)`t$($entry.lines)`t$($entry.sha256)`n")
    }
    return $Set.aggregate_sha256 -ceq (Get-TextSha256 $canonical.ToString())
}

$module = Join-Path $root 'Tools\TMXY.G2AssetBindingRecovery'
$generator = Join-Path $module 'g2_asset_binding_recovery.py'
$common = Join-Path $module 'recovery_common.py'
$wrapper = Join-Path $module 'New-G2AssetBindingRecovery.ps1'
$readme = Join-Path $module 'README.md'
$policyPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-recovery-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-recovery-v1.schema.json'
$detailSchemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-recovery-detail-v1.schema.json'
$formatPath = Join-Path $root 'Docs\Formats\G2-ASSET-BINDING-RECOVERY.md'
$basePlanContractPath = Join-Path $root `
    'Contracts\data-schema\g2-asset-binding-recovery-base-plan-v1.tsv'
$attemptPath = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery-eligible-attempts.tsv'
$effectivePath = Join-Path $root 'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
$preparePath = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery-prepare.json'
$reportPath = Join-Path $root 'Data\Reports\p2-20a-asset-binding-recovery-report.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-20a-asset-binding-recovery.json'
$detailPath = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery.jsonl'
$inputExpected = @(
    @{role='a7_report';path='Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json';tracked=$true},
    @{role='a7_inventory';path='Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json';tracked=$true},
    @{role='a7_detail';path='Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl';tracked=$false},
    @{role='p2_12_catalog';path='Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl';tracked=$false},
    @{role='base_plan_contract';path='Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv';tracked=$true},
    @{role='attempt_tsv';path='Data/Exports/P2-20/p2-20a-asset-binding-recovery-eligible-attempts.tsv';tracked=$false},
    @{role='effective_plan_tsv';path='Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv';tracked=$false},
    @{role='qtx_prefix_policy';path='Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-policy-v1.json';tracked=$true},
    @{role='a4_report';path='Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json';tracked=$true},
    @{role='a4_inventory';path='Data/Inventory/p2-20a-asset-descriptor-diagnostics.json';tracked=$true},
    @{role='a4_effective_detail';path='Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl';tracked=$false},
    @{role='policy';path='Contracts/data-schema/g2-asset-binding-recovery-policy-v1.json';tracked=$true},
    @{role='schema';path='Contracts/data-schema/g2-asset-binding-recovery-v1.schema.json';tracked=$true},
    @{role='detail_schema';path='Contracts/data-schema/g2-asset-binding-recovery-detail-v1.schema.json';tracked=$true}
)

foreach ($required in @($generator, $common, $wrapper, $readme, $policyPath, $schemaPath,
        $detailSchemaPath, $basePlanContractPath, $formatPath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($required))" `
        (Test-Path -LiteralPath $required -PathType Leaf)
}

$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$builder = [string]$lock.backend_toolchain.container_image_reference
$selfText = docker run --rm --network none --read-only --cap-drop ALL `
    --security-opt no-new-privileges `
    --mount "type=bind,src=$root,dst=/workspace,readonly" `
    --tmpfs '/tmp:rw,nosuid,nodev,size=16m' $builder python3 `
    /workspace/Tools/TMXY.G2AssetBindingRecovery/g2_asset_binding_recovery.py --self-test
$self = $selfText | ConvertFrom-Json -Depth 20
Add-Assertion 'Generator self-test' `
    ($self.result -eq 'PASS' -and [int]$self.assertions -ge 13)

if (-not $SkipRegeneration) {
    $prepare = (& $wrapper -RebuildRoot $root -Mode Prepare) | ConvertFrom-Json -Depth 20
    Add-Assertion 'Deterministic A.7-bound preparation' `
        ($prepare.result -eq 'PASS' -and $prepare.meaning -eq 'UPPER_BOUND_ATTEMPT_ONLY' -and
            [int]$prepare.targets -eq 17 -and [int]$prepare.candidate_edges -eq 21)
}

Add-Assertion 'Ignored attempt and manifest outputs exist' `
    ((Test-Path -LiteralPath $attemptPath -PathType Leaf) -and
        (Test-Path -LiteralPath $preparePath -PathType Leaf))
Add-Assertion 'Live A.7-derived attempt is byte-equal to tracked anonymous contract' `
    ((Get-Sha256 $attemptPath) -ceq (Get-Sha256 $basePlanContractPath) -and
        (Get-Item -LiteralPath $attemptPath).Length -eq
            (Get-Item -LiteralPath $basePlanContractPath).Length)
$rows = @([IO.File]::ReadLines($basePlanContractPath))
$closedRows = $rows.Count -eq 21
$prior = ''
$byRule = @{}
foreach ($line in $rows) {
    $fields = @($line.Split("`t"))
    if ($fields.Count -ne 7 -or $fields[0] -cnotmatch '^[0-9a-f]{64}$' -or
        $fields[1] -cnotmatch '^[0-9a-f]{64}$' -or
        $fields[2] -cnotmatch '^[0-9a-f]{64}$' -or
        $fields[3] -cnotmatch '^[0-9a-f]{64}$') {
        $closedRows = $false
        continue
    }
    $key = "$($fields[4])/$($fields[5])/$($fields[6])"
    if (-not $byRule.ContainsKey($key)) { $byRule[$key] = 0 }
    $byRule[$key]++
    $sortKey = "$($fields[0])`t$($fields[1])"
    if ($prior -and [StringComparer]::Ordinal.Compare($prior, $sortKey) -ge 0) {
        $closedRows = $false
    }
    $prior = $sortKey
}
Add-Assertion 'Headerless seven-column ordered attempt contract' $closedRows
Add-Assertion 'Attempt upper bound has exact rule distribution' `
    ($byRule.Count -eq 2 -and
        $byRule['qtx/qtx_complete_mip_chain/payload_size_mismatch'] -eq 16 -and
        $byRule['anim/anim_payload_frame_counts/frame_count_mismatch'] -eq 5)

$effectiveRows = @([IO.File]::ReadLines($effectivePath))
$selectedPolicyPath = Join-Path $root 'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-policy-v1.json'
$selectedPolicy = Get-Content -LiteralPath $selectedPolicyPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100
$selectedKeys = @{}
foreach ($item in @($selectedPolicy.selected_targets)) {
    $selectedKeys["$($item.asset_id)`t$($item.candidate_id)"] = $item
}
$overlayClosed = $effectiveRows.Count -eq 21 -and $selectedKeys.Count -eq 6
$changed = 0
for ($index = 0; $index -lt $rows.Count; ++$index) {
    $base = @($rows[$index].Split("`t"))
    $effective = @($effectiveRows[$index].Split("`t"))
    $key = "$($base[0])`t$($base[1])"
    $sameExceptKind = $base.Count -eq 7 -and $effective.Count -eq 7 -and
        $base[0] -ceq $effective[0] -and $base[1] -ceq $effective[1] -and
        $base[2] -ceq $effective[2] -and $base[3] -ceq $effective[3] -and
        $base[4] -ceq $effective[4] -and $base[6] -ceq $effective[6]
    if (-not $sameExceptKind) { $overlayClosed = $false; continue }
    if ($selectedKeys.ContainsKey($key)) {
        if ($base[5] -cne 'qtx_complete_mip_chain' -or
            $effective[5] -cne 'qtx_declared_mip_payload_prefix') {
            $overlayClosed = $false
        }
        ++$changed
    }
    elseif ($base[5] -cne $effective[5]) { $overlayClosed = $false }
}
Add-Assertion 'A.13 effective plan changes exactly six selected recovery-kind cells' `
    ($overlayClosed -and $changed -eq 6)

$manifest = Get-Content -LiteralPath $preparePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 50 -DateKind String
$a7ReportPath = Join-Path $root 'Data\Reports\p2-20a-asset-binding-failure-diagnostics-report.json'
$a7InventoryPath = Join-Path $root 'Data\Inventory\p2-20a-asset-binding-failure-diagnostics.json'
$a7Report = Get-Content -LiteralPath $a7ReportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$a7DetailPath = Join-Path $root ([string]$a7Report.detail_export.path).Replace('/', '\')
Add-Assertion 'Prepare manifest binds A.7 report inventory and ignored detail' `
    ([string]$manifest.a7_report_sha256 -ceq (Get-Sha256 $a7ReportPath) -and
        [string]$manifest.a7_inventory_sha256 -ceq (Get-Sha256 $a7InventoryPath) -and
        [string]$manifest.a7_detail_sha256 -ceq (Get-Sha256 $a7DetailPath) -and
        [string]$manifest.attempt_tsv_sha256 -ceq (Get-Sha256 $attemptPath) -and
        [string]$manifest.base_plan_contract_path -ceq
            'Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv' -and
        [string]$manifest.base_plan_contract_sha256 -ceq
            (Get-Sha256 $basePlanContractPath) -and
        $manifest.base_plan_contract_tracked -eq $true -and
        $manifest.attempt_matches_base_plan_contract -eq $true)
Add-Assertion 'Attempt is explicitly not success or authority' `
    ($manifest.meaning -eq 'UPPER_BOUND_ATTEMPT_ONLY' -and
        $null -eq $manifest.successful_recoveries -and
        $manifest.a4_authoritative -eq $true -and $manifest.attempt_is_success -eq $false -and
        $manifest.g2_06_satisfied -eq $false -and $manifest.p3_authorized -eq $false)

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Add-Assertion 'Fail-closed recovery policy' `
    ($policy.base_plan_contract.path -eq
        'Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv' -and
        $policy.base_plan_contract.tracked -eq $true -and
        [int]$policy.base_plan_contract.rows -eq 21 -and
        [int64]$policy.base_plan_contract.bytes -eq 6504 -and
        [string]$policy.base_plan_contract.sha256 -ceq (Get-Sha256 $basePlanContractPath) -and
        $policy.base_plan_contract.live_attempt_must_byte_equal -eq $true -and
        $policy.frozen_scope.targets -eq 19 -and $policy.frozen_scope.candidate_edges -eq 24 -and
        $policy.controls.attempt_is_success -eq $false -and
        $policy.controls.qtx_error_alone_proves_complete_mip_chain -eq $false -and
        $policy.controls.anim_error_alone_proves_full_payload_validity -eq $false -and
        $policy.success_requirements.a4_is_authoritative -eq $true -and
        $policy.success_requirements.a4_a7_descriptor_semantic_sha256_match_required -eq $true -and
        $policy.success_requirements.qtx_stored_mip_must_be_explicit -eq $true -and
        $policy.success_requirements.qtx_stored_mip_must_equal_declared -eq $true -and
        $policy.success_requirements.qtx_complete_chain_effective_mip_must_be_less_than_declared -eq $true -and
        $policy.success_requirements.qtx_declared_prefix_effective_mip_must_equal_declared -eq $true -and
        $policy.success_requirements.qtx_declared_prefix_consumes_declared_payload_only -eq $true -and
        $policy.success_requirements.qtx_unique_complete_prefix_required -eq $true -and
        $policy.success_requirements.unknown_recovery_basis_rejected -eq $true -and
        $policy.success_requirements.a8_may_change_authoritative_counts -eq $false -and
        [int]$policy.preserved_blockers.asset_effective_ambiguous_targets -eq 189 -and
        [int]$policy.preserved_blockers.asset_effective_ambiguous_edges -eq 546 -and
        [int]$policy.preserved_blockers.asset_effective_unresolved_targets -eq 6 -and
        [int]$policy.preserved_blockers.asset_effective_unresolved_edges -eq 9)
Add-Assertion 'Policy fixes seven plan columns' `
    ((@($policy.plan_columns) -join ',') -ceq
        'asset_id,candidate_id,body_sha256,source_sha256,family,recovery_kind,strict_error_code')

$sampleDetail = [pscustomobject][ordered]@{
    asset_id = 'a' * 64
    family = 'qtx'
    attempted_edges = 1
    successful_edges = 1
    effective_resolution = 'RESOLVED'
    candidates = @([pscustomobject][ordered]@{
        candidate_id = 'b' * 64
        body_sha256 = 'c' * 64
        descriptor_semantic_sha256 = 'e' * 64
        attempted = $true
        recovery_kind = 'qtx_complete_mip_chain'
        strict_error_code = 'payload_size_mismatch'
        effective_binding = 'PASS'
        recovery_applied = $true
        effective_semantic_sha256 = 'd' * 64
        qtx_recovery_contract = [pscustomobject][ordered]@{
            stored_explicit = $true
            stored_equals_declared = $true
            effective_less_than_declared = $true
            unique_complete_prefix = $true
            declared_payload_prefix = $false
        }
    })
}
Add-Assertion 'Closed ignored-detail schema accepts valid proof' `
    (($sampleDetail | ConvertTo-Json -Depth 20 -Compress) |
        Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue)
$declaredPrefixDetail = Copy-JsonObject $sampleDetail
$declaredPrefixDetail.candidates[0].recovery_kind = 'qtx_declared_mip_payload_prefix'
$declaredPrefixDetail.candidates[0].qtx_recovery_contract.effective_less_than_declared = $false
$declaredPrefixDetail.candidates[0].qtx_recovery_contract.declared_payload_prefix = $true
Add-Assertion 'Closed ignored-detail schema accepts declared-prefix proof' `
    (($declaredPrefixDetail | ConvertTo-Json -Depth 20 -Compress) |
        Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue)
foreach ($fixture in @(
    @{ name = 'declared-prefix effective-less flag'; mutate = {
        param($x) $x.candidates[0].qtx_recovery_contract.effective_less_than_declared = $true } },
    @{ name = 'declared-prefix discriminator flag'; mutate = {
        param($x) $x.candidates[0].qtx_recovery_contract.declared_payload_prefix = $false } },
    @{ name = 'declared-prefix recovery-applied flag'; mutate = {
        param($x) $x.candidates[0].recovery_applied = $false } },
    @{ name = 'declared-prefix effective binding'; mutate = {
        param($x) $x.candidates[0].effective_binding = 'REJECTED' } },
    @{ name = 'declared-prefix semantic identity'; mutate = {
        param($x) $x.candidates[0].effective_semantic_sha256 = $null } },
    @{ name = 'declared-prefix recovery-kind discriminator'; mutate = {
        param($x) $x.candidates[0].recovery_kind = 'qtx_complete_mip_chain' } }
)) {
    $contradiction = Copy-JsonObject $declaredPrefixDetail
    & $fixture.mutate $contradiction
    Add-Assertion "Closed ignored-detail schema rejects contradictory $($fixture.name)" `
        (-not (($contradiction | ConvertTo-Json -Depth 20 -Compress) |
            Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue))
}
$sampleDetail.candidates[0] | Add-Member raw_path 'forbidden'
Add-Assertion 'Closed ignored-detail schema rejects unknown disclosure field' `
    (-not (($sampleDetail | ConvertTo-Json -Depth 20 -Compress) |
        Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue))

$trackedSources = (Get-Content -LiteralPath $generator, $common, $wrapper, $readme, $policyPath,
    $schemaPath, $detailSchemaPath, $basePlanContractPath, $formatPath -Raw -Encoding UTF8) -join "`n"
Add-Assertion 'Tracked framework excludes private paths values and authority claims' `
    ($trackedSources -cnotmatch '(?i)[A-Z]:\\QQXYCodeDev\\(ClientCode|ServerCode|ToolCode|DevDoc|天命西游)|exact_primary_key_value|declared_frame_count\s*[:=]\s*\d|observed_mip_count\s*[:=]\s*\d|g2_06_satisfied["'']?\s*[:=]\s*true')
Add-Assertion 'Implementation files respect size gates' `
    ((Get-LineCount $generator) -le 500 -and (Get-LineCount $common) -le 500 -and
        (Get-LineCount $wrapper) -le 500 -and (Get-LineCount $PSCommandPath) -le 1000)

if ($FinalizeExpected) {
    Add-Assertion 'Tracked finalized report and inventory exist' `
        ((Test-Path -LiteralPath $reportPath -PathType Leaf) -and
            (Test-Path -LiteralPath $evidencePath -PathType Leaf))
    $reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
    Add-Assertion 'Final report satisfies closed schema' `
        ($reportText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
    $report = $reportText | ConvertFrom-Json -Depth 100 -DateKind String
    $detailLines = @([IO.File]::ReadLines($detailPath))
    $detailObjects = [Collections.Generic.List[object]]::new()
    $invalidDetailRows = 0
    foreach ($line in $detailLines) {
        if (-not ($line | Test-Json -SchemaFile $detailSchemaPath `
                -ErrorAction SilentlyContinue)) {
            ++$invalidDetailRows
            continue
        }
        [void]$detailObjects.Add(($line | ConvertFrom-Json -Depth 100 -DateKind String))
    }
    Add-Assertion 'Every generated ignored-detail JSONL row satisfies the closed schema' `
        ($detailLines.Count -gt 0 -and $invalidDetailRows -eq 0 -and
            $detailObjects.Count -eq $detailLines.Count -and
            [int]$report.outputs.detail_export.lines -eq $detailLines.Count -and
            [string]$report.outputs.detail_export.sha256 -ceq (Get-Sha256 $detailPath))
    $declaredPrefixCandidates = @($detailObjects | ForEach-Object { @($_.candidates) } |
        Where-Object recovery_kind -CEQ 'qtx_declared_mip_payload_prefix')
    $contradictoryPrefixCandidates = @($declaredPrefixCandidates | Where-Object {
        $_.effective_binding -cne 'PASS' -or $_.recovery_applied -ne $true -or
        [string]$_.effective_semantic_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $null -eq $_.qtx_recovery_contract -or
        $_.qtx_recovery_contract.effective_less_than_declared -ne $false -or
        $_.qtx_recovery_contract.declared_payload_prefix -ne $true
    })
    Add-Assertion 'Generated detail includes coherent declared-prefix proof' `
        ($declaredPrefixCandidates.Count -gt 0 -and $contradictoryPrefixCandidates.Count -eq 0)
    $baseBindings = @($report.input_bindings.entries |
        Where-Object role -CEQ 'base_plan_contract')
    $liveBindings = @($report.input_bindings.entries | Where-Object role -CEQ 'attempt_tsv')
    Add-Assertion 'Final report closes all fourteen producer-order input bindings' `
        (Test-InputBindingSet $report.input_bindings $inputExpected)
    $nonPlanMutation = Copy-JsonObject $report.input_bindings
    $nonPlanMutation.entries[0].sha256 = '0' * 64
    Add-Assertion 'Negative: non-plan input binding mutation is rejected' `
        (-not (Test-InputBindingSet $nonPlanMutation $inputExpected))
    $aggregateMutation = Copy-JsonObject $report.input_bindings
    $aggregateMutation.aggregate_sha256 = '0' * 64
    Add-Assertion 'Negative: input aggregate mutation is rejected' `
        (-not (Test-InputBindingSet $aggregateMutation $inputExpected))
    Add-Assertion 'Final report dual-binds byte-equal tracked and live base plans' `
        ($baseBindings.Count -eq 1 -and $liveBindings.Count -eq 1 -and
            $baseBindings[0].path -ceq
                'Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv' -and
            $baseBindings[0].tracked -eq $true -and
            $liveBindings[0].path -ceq
                'Data/Exports/P2-20/p2-20a-asset-binding-recovery-eligible-attempts.tsv' -and
            $liveBindings[0].tracked -eq $false -and
            $baseBindings[0].sha256 -ceq (Get-Sha256 $basePlanContractPath) -and
            $liveBindings[0].sha256 -ceq (Get-Sha256 $attemptPath) -and
            $report.contracts.base_plan_contract_sha256 -ceq
                (Get-Sha256 $basePlanContractPath) -and
            $report.disclosure.tracked_aggregate_hash_and_anonymous_contract_only -eq $true -and
            $report.disclosure.tracked_anonymous_base_plan_contract -eq $true)
    Add-Assertion 'Final report preserves A.4 authority and G2 blockers' `
        ($report.result -eq 'BLOCKED' -and $report.g2_06_satisfied -eq $false -and
            $report.p3_authorized -eq $false -and
            $report.authority_boundary.a4_is_authoritative -eq $true -and
            $report.authority_boundary.a8_may_change_counts -eq $false -and
            [int]$report.measured.successful.targets -eq 13 -and
            [int]$report.measured.successful.candidate_edges -eq 15 -and
            [int]$report.measured.effective_resolution.resolved.targets -eq 13 -and
            [int]$report.measured.effective_resolution.resolved.candidate_edges -eq 15 -and
            [int]$report.measured.effective_resolution.ambiguous.targets -eq 0 -and
            [int]$report.measured.effective_resolution.unresolved.targets -eq 6 -and
            [int]$report.measured.effective_resolution.unresolved.candidate_edges -eq 9 -and
            [int]$report.preserved_blockers.asset_effective_ambiguous_targets -eq 189 -and
            [int]$report.preserved_blockers.asset_effective_unresolved_targets -eq 6 -and
            [string]$report.outputs.effective_plan_tsv.sha256 -ceq (Get-Sha256 $effectivePath))
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    evidence_revision = 'P2-20A.8-contract'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    assertions = $assertions.Count
    passed = $assertions.Count - $failed.Count
    failed = $failed.Count
    details = $assertions
} | ConvertTo-Json -Depth 20

if ($failed.Count -ne 0) { exit 1 }
