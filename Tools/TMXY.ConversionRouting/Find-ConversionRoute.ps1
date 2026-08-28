[CmdletBinding()]
param(
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-15\p2-15-conversion-routing.jsonl',
    [ValidateSet('automatic-qualified-interchange', 'automatic-standard-audio',
        'semi-automatic-navigation-adaptation', 'manual-descriptor-recovery',
        'manual-repair-or-replace')][string]$Route,
    [ValidateSet('automatic', 'semi-automatic', 'manual')][string]$Tier,
    [ValidateSet('P0-first-playable-slice', 'P1-linked-content',
        'P2-unlinked-review', 'P3-identity-rule-gap')][string]$Priority,
    [ValidateSet('unique', 'safe-reuse-representative', 'safe-reuse-alias',
        'exact-duplicate-review-only')][string]$DuplicateHandling,
    [ValidateSet('anim', 'mp3', 'qtx', 'skem', 'sm', 'ter', 'wav', 'zif')]
    [string]$Family,
    [ValidateRange(0, 100)][int]$MaximumExamples = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$report = [IO.Path]::GetFullPath($ReportPath)
if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
    throw "P2-15 conversion routing report is missing: $report"
}

$matched = 0
$bytes = [int64]0
$jobs = 0
$routes = @{}
$tiers = @{}
$priorities = @{}
$duplicates = @{}
$examples = [Collections.Generic.List[object]]::new()
foreach ($line in [IO.File]::ReadLines($report)) {
    if (-not $line.Contains('"record":"conversion_route"', [StringComparison]::Ordinal)) {
        continue
    }
    $entry = $line | ConvertFrom-Json
    if ($Route -and [string]$entry.route -ne $Route) { continue }
    if ($Tier -and [string]$entry.tier -ne $Tier) { continue }
    if ($Priority -and [string]$entry.priority -ne $Priority) { continue }
    if ($DuplicateHandling -and
        [string]$entry.duplicate_handling -ne $DuplicateHandling) { continue }
    if ($Family -and [string]$entry.family -ne $Family) { continue }
    ++$matched
    $bytes += [int64]$entry.bytes
    $jobs += [int][bool]$entry.conversion_job_required
    foreach ($pair in @(@($routes, [string]$entry.route), @($tiers, [string]$entry.tier),
            @($priorities, [string]$entry.priority),
            @($duplicates, [string]$entry.duplicate_handling))) {
        $pair[0][$pair[1]] = 1 + [int]($pair[0][$pair[1]] ?? 0)
    }
    if ($examples.Count -lt $MaximumExamples) {
        $examples.Add([pscustomobject][ordered]@{
                id = [string]$entry.id
                path = [string]$entry.path
                family = [string]$entry.family
                structure = [string]$entry.structure
                route = [string]$entry.route
                tier = [string]$entry.tier
                priority = [string]$entry.priority
                duplicate_handling = [string]$entry.duplicate_handling
                conversion_job_required = [bool]$entry.conversion_job_required
                reuse_representative = [string]$entry.reuse_representative
                delete_eligible = [bool]$entry.delete_eligible
            })
    }
}

[pscustomobject][ordered]@{
    schema_version = 1
    result = 'PASS'
    query = [pscustomobject][ordered]@{
        route = if ($Route) { $Route } else { '' }
        tier = if ($Tier) { $Tier } else { '' }
        priority = if ($Priority) { $Priority } else { '' }
        duplicate_handling = if ($DuplicateHandling) { $DuplicateHandling } else { '' }
        family = if ($Family) { $Family } else { '' }
        raw_payloads_emitted = $false
        source_hashes_emitted = $false
    }
    matches = $matched
    bytes = $bytes
    conversion_jobs = $jobs
    routes = $routes
    tiers = $tiers
    priorities = $priorities
    duplicate_handling = $duplicates
    examples = @($examples)
} | ConvertTo-Json -Depth 8
