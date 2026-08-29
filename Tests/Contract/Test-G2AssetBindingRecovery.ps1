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

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
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
$attemptPath = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery-eligible-attempts.tsv'
$preparePath = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery-prepare.json'
$reportPath = Join-Path $root 'Data\Reports\p2-20a-asset-binding-recovery-report.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-20a-asset-binding-recovery.json'

foreach ($required in @($generator, $common, $wrapper, $readme, $policyPath, $schemaPath,
        $detailSchemaPath, $formatPath)) {
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
$rows = @([IO.File]::ReadLines($attemptPath))
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
        [string]$manifest.attempt_tsv_sha256 -ceq (Get-Sha256 $attemptPath))
Add-Assertion 'Attempt is explicitly not success or authority' `
    ($manifest.meaning -eq 'UPPER_BOUND_ATTEMPT_ONLY' -and
        $null -eq $manifest.successful_recoveries -and
        $manifest.a4_authoritative -eq $true -and $manifest.attempt_is_success -eq $false -and
        $manifest.g2_06_satisfied -eq $false -and $manifest.p3_authorized -eq $false)

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Add-Assertion 'Fail-closed recovery policy' `
    ($policy.frozen_scope.targets -eq 19 -and $policy.frozen_scope.candidate_edges -eq 24 -and
        $policy.controls.attempt_is_success -eq $false -and
        $policy.controls.qtx_error_alone_proves_complete_mip_chain -eq $false -and
        $policy.controls.anim_error_alone_proves_full_payload_validity -eq $false -and
        $policy.success_requirements.a4_is_authoritative -eq $true -and
        $policy.success_requirements.a4_a7_descriptor_semantic_sha256_match_required -eq $true -and
        $policy.success_requirements.qtx_stored_mip_must_be_explicit -eq $true -and
        $policy.success_requirements.qtx_stored_mip_must_equal_declared -eq $true -and
        $policy.success_requirements.qtx_effective_mip_must_be_less_than_declared -eq $true -and
        $policy.success_requirements.qtx_unique_complete_prefix_required -eq $true -and
        $policy.success_requirements.unknown_recovery_basis_rejected -eq $true -and
        $policy.success_requirements.a8_may_change_authoritative_counts -eq $false -and
        [int]$policy.preserved_blockers.asset_effective_ambiguous_targets -eq 189 -and
        [int]$policy.preserved_blockers.asset_effective_ambiguous_edges -eq 546 -and
        [int]$policy.preserved_blockers.asset_effective_unresolved_targets -eq 12 -and
        [int]$policy.preserved_blockers.asset_effective_unresolved_edges -eq 15)
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
        }
    })
}
Add-Assertion 'Closed ignored-detail schema accepts valid proof' `
    (($sampleDetail | ConvertTo-Json -Depth 20 -Compress) |
        Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue)
$sampleDetail.candidates[0] | Add-Member raw_path 'forbidden'
Add-Assertion 'Closed ignored-detail schema rejects unknown disclosure field' `
    (-not (($sampleDetail | ConvertTo-Json -Depth 20 -Compress) |
        Test-Json -SchemaFile $detailSchemaPath -ErrorAction SilentlyContinue))

$trackedSources = (Get-Content -LiteralPath $generator, $common, $wrapper, $readme, $policyPath,
    $schemaPath, $detailSchemaPath, $formatPath -Raw -Encoding UTF8) -join "`n"
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
    Add-Assertion 'Final report preserves A.4 authority and G2 blockers' `
        ($report.result -eq 'BLOCKED' -and $report.g2_06_satisfied -eq $false -and
            $report.p3_authorized -eq $false -and
            $report.authority_boundary.a4_is_authoritative -eq $true -and
            $report.authority_boundary.a8_may_change_counts -eq $false -and
            [int]$report.measured.successful.targets -eq 7 -and
            [int]$report.measured.successful.candidate_edges -eq 9 -and
            [int]$report.measured.effective_resolution.resolved.targets -eq 7 -and
            [int]$report.measured.effective_resolution.resolved.candidate_edges -eq 9 -and
            [int]$report.measured.effective_resolution.ambiguous.targets -eq 0 -and
            [int]$report.measured.effective_resolution.unresolved.targets -eq 12 -and
            [int]$report.measured.effective_resolution.unresolved.candidate_edges -eq 15 -and
            [int]$report.preserved_blockers.asset_effective_ambiguous_targets -eq 189 -and
            [int]$report.preserved_blockers.asset_effective_unresolved_targets -eq 12)
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
