[CmdletBinding()]
param(
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-16\p2-16-conversion-cache-plan.jsonl',
    [ValidateSet('ready', 'alias', 'blocked-manual-input')][string]$State,
    [ValidateSet('automatic', 'semi-automatic', 'manual')][string]$Tier,
    [ValidateSet('anim', 'mp3', 'qtx', 'skem', 'sm', 'ter', 'wav', 'zif')][string]$Family,
    [string]$Route,
    [ValidateRange(0, 100)][int]$MaximumExamples = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$report = [IO.Path]::GetFullPath($ReportPath)
if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
    throw "P2-16 conversion cache plan is missing: $report"
}

$matched = 0
$bytes = [int64]0
$jobs = 0
$states = @{}
$families = @{}
$examples = [Collections.Generic.List[object]]::new()
foreach ($line in [IO.File]::ReadLines($report)) {
    if (-not $line.Contains('"record":"conversion_cache_plan"',
            [StringComparison]::Ordinal)) { continue }
    $entry = $line | ConvertFrom-Json
    if ($State -and [string]$entry.state -ne $State) { continue }
    if ($Tier -and [string]$entry.tier -ne $Tier) { continue }
    if ($Family -and [string]$entry.family -ne $Family) { continue }
    if ($Route -and [string]$entry.route -ne $Route) { continue }
    ++$matched
    $bytes += [int64]$entry.bytes
    $jobs += [int][bool]$entry.conversion_job_required
    $states[[string]$entry.state] = 1 + [int]($states[[string]$entry.state] ?? 0)
    $families[[string]$entry.family] = 1 + [int]($families[[string]$entry.family] ?? 0)
    if ($examples.Count -lt $MaximumExamples) {
        $examples.Add([pscustomobject][ordered]@{
                id = [string]$entry.id
                path = [string]$entry.path
                family = [string]$entry.family
                route = [string]$entry.route
                tier = [string]$entry.tier
                state = [string]$entry.state
                conversion_job_required = [bool]$entry.conversion_job_required
                reuse_representative = [string]$entry.reuse_representative
                cache_key_assigned = -not [string]::IsNullOrWhiteSpace([string]$entry.cache_key)
            })
    }
}

[pscustomobject][ordered]@{
    schema_version = 1
    result = 'PASS'
    query = [pscustomobject][ordered]@{
        state = if ($State) { $State } else { '' }
        tier = if ($Tier) { $Tier } else { '' }
        family = if ($Family) { $Family } else { '' }
        route = if ($Route) { $Route } else { '' }
        raw_payloads_emitted = $false
        source_hashes_emitted = $false
        cache_keys_emitted = $false
    }
    matches = $matched
    bytes = $bytes
    conversion_jobs = $jobs
    states = $states
    families = $families
    examples = @($examples)
} | ConvertTo-Json -Depth 8
