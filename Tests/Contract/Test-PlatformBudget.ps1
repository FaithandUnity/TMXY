[CmdletBinding()]
param([string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$budgetPath = Join-Path $root 'Data\Performance\p0-platform-budget.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

$budget = Get-Content -LiteralPath $budgetPath -Raw | ConvertFrom-Json
if ([int]$budget.schema_version -ne 1 -or
    [string]$budget.status -ne 'frozen_engineering_baseline') {
    Add-Failure -Message 'Platform budget must use frozen schema version 1.'
}
if ([string]$budget.client.platform -ne 'Windows 11 x64' -or
    [string]$budget.backend.platform -ne 'Linux x64 OCI') {
    Add-Failure -Message 'Client and backend target platforms differ from the frozen architecture.'
}
if ([string]$budget.client.graphics_api -ne 'DirectX 12' -or
    [string]$budget.client.shader_model -ne 'SM6') {
    Add-Failure -Message 'Client graphics baseline must remain DirectX 12/SM6.'
}

$recommended = $budget.client.recommended_profile
$minimum = $budget.client.minimum_profile
if ([int]$recommended.target_fps -lt [int]$minimum.target_fps -or
    [int]$recommended.system_memory_gib -lt [int]$minimum.system_memory_gib -or
    [int]$recommended.dedicated_vram_gib -lt [int]$minimum.dedicated_vram_gib) {
    Add-Failure -Message 'Recommended client profile cannot be weaker than minimum.'
}
$frame = $budget.client.frame_budget_ms_at_1080p
if ([double]$frame.frame -gt 16.67 -or [double]$frame.game_thread -le 0 -or
    [double]$frame.render_thread -le 0 -or [double]$frame.gpu -le 0) {
    Add-Failure -Message '1080p frame-time budget is invalid.'
}

$capacity = $budget.backend.capacity
if ([int]$capacity.platform_concurrent_sessions -lt 10000 -or
    [int]$capacity.gateway_connections_per_instance -lt 10000 -or
    [int]$capacity.world_sessions_per_instance -lt 1000 -or
    [int]$capacity.headroom_percent -lt 20) {
    Add-Failure -Message 'Backend capacity or headroom fell below the frozen baseline.'
}
$availability = $budget.backend.availability
if ([double]$availability.monthly_service_slo_percent -lt 99.9 -or
    [int]$availability.rpo_minutes -gt 5 -or [int]$availability.rto_minutes -gt 30) {
    Add-Failure -Message 'Availability, RPO, or RTO target regressed.'
}
$validation = $budget.validation_policy
if (-not [bool]$validation.representative_scene_required -or
    -not [bool]$validation.production_like_database_required -or
    [int]$validation.minimum_test_duration_minutes -lt 60 -or
    -not [bool]$validation.pass_requires_all_budgets) {
    Add-Failure -Message 'Performance validation policy is incomplete.'
}

$report = [pscustomobject][ordered]@{
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    client_target = "$($recommended.resolution)@$($recommended.target_fps)"
    platform_concurrent_sessions = [int]$capacity.platform_concurrent_sessions
    rpo_minutes = [int]$availability.rpo_minutes
    rto_minutes = [int]$availability.rto_minutes
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 4
if ($failures.Count -gt 0) { throw 'Platform budget contract failed.' }
