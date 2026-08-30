[CmdletBinding()]
param([string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$path = Join-Path $root 'Data\Governance\p1-resourcing.json'
$waiverPath = Join-Path $root 'Data\Governance\p1-local-start-waiver.json'
$g1AuthorizationPath = Join-Path $root 'Data\Governance\p1-g1-stage-authorization.json'
$readinessPath = Join-Path $root 'Data\BuildBaseline\p0-readiness.json'
$charter = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$waiver = Get-Content -LiteralPath $waiverPath -Raw | ConvertFrom-Json
$g1Authorization = Get-Content -LiteralPath $g1AuthorizationPath -Raw | ConvertFrom-Json
$readiness = Get-Content -LiteralPath $readinessPath -Raw | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

if ([int]$charter.schema_version -ne 1 -or
    [string]$charter.status -ne 'frozen_execution_charter') {
    Add-Failure -Message 'P1 execution charter schema or status is invalid.'
}
if (-not [string]$charter.execution_owner -or -not [string]$charter.acceptance_owner) {
    Add-Failure -Message 'P1 execution and acceptance owners must be explicit.'
}
if ([int]$charter.duration_weeks.minimum -ne 4 -or
    [int]$charter.duration_weeks.maximum -ne 8 -or
    -not [bool]$charter.review_cadence.weekly_evidence_review) {
    Add-Failure -Message 'P1 duration or weekly review cadence drifted.'
}

$taskIds = @($charter.workstreams | ForEach-Object { @($_.tasks) })
$expectedTaskIds = 1..28 | ForEach-Object { 'P1-{0:D2}' -f $_ }
$missing = @(Compare-Object $expectedTaskIds $taskIds | Where-Object { $_.SideIndicator -eq '<=' })
$extra = @(Compare-Object $expectedTaskIds $taskIds | Where-Object { $_.SideIndicator -eq '=>' })
if ($taskIds.Count -ne 28 -or $missing.Count -gt 0 -or $extra.Count -gt 0 -or
    @($taskIds | Sort-Object -Unique).Count -ne 28) {
    Add-Failure -Message 'P1-01 through P1-28 must each have exactly one workstream.'
}

$limits = $charter.experiment_limits
foreach ($property in @(
        'legacy_directories_read_only', 'outputs_only_under_rebuild',
        'no_bulk_asset_import_before_G1', 'no_legacy_runtime_dependency',
        'no_secret_in_source_log_or_report', 'unknown_fields_preserved',
        'evidence_levels_required')) {
    if (-not [bool]$limits.$property) { Add-Failure -Message "Required P1 limit is disabled: $property" }
}
if (@($charter.stop_conditions).Count -lt 5 -or
    [string]$charter.start_condition -ne 'G0_READY_AND_P0_16_APPROVED') {
    Add-Failure -Message 'P1 stop or start conditions are incomplete.'
}

$waiverExpires = [DateTimeOffset]::Parse([string]$waiver.expires_local)
$waiverActive = [int]$waiver.schema_version -eq 1 -and
    [string]$waiver.waiver_id -eq 'WVR-0001' -and
    [string]$waiver.status -eq 'active_time_bounded' -and
    $waiverExpires -gt [DateTimeOffset]::Now -and
    [string]$waiver.scope.allowed_tasks -eq 'P1-01_through_P1-27_local_evidence' -and
    [bool]$waiver.scope.read_only_legacy_analysis -and
    [bool]$waiver.scope.local_evidence_and_verified_backups -and
    [bool]$waiver.prohibited.mark_p0_12_or_p0_16_complete -and
    [bool]$waiver.prohibited.approve_g0_or_g1 -and
    [bool]$waiver.prohibited.configure_remote_or_push -and
    [bool]$waiver.prohibited.bulk_asset_import_before_g1 -and
    [bool]$waiver.prohibited.write_legacy_directories
$g0Ready = [string]$readiness.result -eq 'READY_FOR_G0_REVIEW'
if (-not $g0Ready -and -not $waiverActive) {
    Add-Failure -Message 'P1 local development requires G0 readiness or an active bounded waiver.'
}
if ([string]$charter.local_start_waiver.id -ne [string]$waiver.waiver_id -or
    [string]$charter.local_start_waiver.scope -ne [string]$waiver.scope.allowed_tasks) {
    Add-Failure -Message 'P1 charter and local-start waiver are not bound.'
}
$g1AuthorizationBound = [string]$charter.g1_stage_authorization.id -eq
        [string]$g1Authorization.authorization_id -and
    [string]$charter.g1_stage_authorization.scope -eq 'P1-28_and_G1_format_gate_only' -and
    [string]$g1Authorization.status -eq 'approved' -and
    [string]$g1Authorization.approved_by -eq 'project_lead' -and
    [bool]$g1Authorization.scope.execute_p1_28 -and
    [bool]$g1Authorization.scope.approve_g1_format_gate_when_all_technical_checks_pass -and
    [bool]$g1Authorization.wvr_0001_exception.other_waiver_boundaries_unchanged -and
    -not [bool]$g1Authorization.boundaries.approve_g0 -and
    -not [bool]$g1Authorization.boundaries.claim_release_authority
if (-not $g1AuthorizationBound) {
    Add-Failure -Message 'P1-28/G1 stage authorization is missing or exceeds its boundary.'
}

$report = [pscustomobject][ordered]@{
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    assigned_task_count = $taskIds.Count
    workstream_count = @($charter.workstreams).Count
    duration_weeks = '4-8'
    start_condition = [string]$charter.start_condition
    effective_start_mode = if ($g0Ready) { 'g0_ready' } else { 'local_time_bounded_waiver' }
    local_waiver_expires = $waiverExpires.ToString('o')
    g1_stage_authorization = [string]$g1Authorization.authorization_id
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 4
if ($failures.Count -gt 0) { throw 'P1 execution charter validation failed.' }
