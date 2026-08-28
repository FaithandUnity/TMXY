[CmdletBinding(DefaultParameterSetName = 'RootKind')]
param(
    [string]$GraphPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-13\p2-13-reference-closure.jsonl',
    [Parameter(Mandatory = $true, ParameterSetName = 'RootKind')]
    [ValidateSet('character', 'scene', 'skill')][string]$RootKind,
    [Parameter(Mandatory = $true, ParameterSetName = 'NodeId')][string]$NodeId,
    [ValidateRange(0, 8)][int]$MaximumDepth = 4,
    [ValidateRange(1, 100)][int]$MaximumRoots = 1,
    [ValidateRange(0, 100)][int]$MaximumExamples = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$graph = [IO.Path]::GetFullPath($GraphPath)
if (-not (Test-Path -LiteralPath $graph -PathType Leaf)) {
    throw "P2-13 closure graph is missing: $graph"
}
if ($PSCmdlet.ParameterSetName -eq 'NodeId' -and $NodeId -cnotmatch '^[0-9a-f]{64}$') {
    throw 'NodeId must be a lowercase SHA-256 value.'
}

$roots = [Collections.Generic.List[string]]::new()
if ($PSCmdlet.ParameterSetName -eq 'NodeId') { $roots.Add($NodeId) }
else {
    foreach ($line in [IO.File]::ReadLines($graph)) {
        if (-not $line.Contains('"record":"root"', [StringComparison]::Ordinal)) { continue }
        $entry = $line | ConvertFrom-Json
        if ([string]$entry.root_kind -eq $RootKind) {
            $roots.Add([string]$entry.target)
            if ($roots.Count -ge $MaximumRoots) { break }
        }
    }
}
if ($roots.Count -eq 0) { throw 'P2-13 query matched no roots.' }

$visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$frontier = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($root in $roots) { [void]$visited.Add($root); [void]$frontier.Add($root) }
$edgeKinds = @{}
$resolution = @{}
$examples = [Collections.Generic.List[object]]::new()
$depthReached = 0
for ($depth = 0; $depth -lt $MaximumDepth -and $frontier.Count -gt 0; ++$depth) {
    $next = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadLines($graph)) {
        if (-not $line.Contains('"source":', [StringComparison]::Ordinal)) { continue }
        $possible = $false
        foreach ($source in $frontier) {
            if ($line.Contains($source, [StringComparison]::Ordinal)) { $possible = $true; break }
        }
        if (-not $possible) { continue }
        $entry = $line | ConvertFrom-Json
        if (-not $frontier.Contains([string]$entry.source)) { continue }
        $record = [string]$entry.record
        $edgeKinds[$record] = 1 + [int]($edgeKinds[$record] ?? 0)
        if ($entry.PSObject.Properties.Name -contains 'resolution') {
            $state = [string]$entry.resolution
            $resolution[$state] = 1 + [int]($resolution[$state] ?? 0)
        }
        $targets = if ($entry.PSObject.Properties.Name -contains 'targets') {
            @($entry.targets | ForEach-Object { [string]$_ })
        }
        elseif ($entry.PSObject.Properties.Name -contains 'target') { @([string]$entry.target) }
        else { @() }
        foreach ($target in $targets) {
            if ($target -cmatch '^[0-9a-f]{64}$' -and $visited.Add($target)) {
                [void]$next.Add($target)
            }
        }
        if ($examples.Count -lt $MaximumExamples) {
            $examples.Add([pscustomobject][ordered]@{
                    depth = $depth + 1
                    record = $record
                    source = [string]$entry.source
                    targets = $targets
                    resolution = if ($entry.PSObject.Properties.Name -contains 'resolution') {
                        [string]$entry.resolution
                    }
                    else { 'not_applicable' }
                })
        }
    }
    $frontier = $next
    $depthReached = $depth + 1
}

$nodeKinds = @{}
$visitedExamples = [Collections.Generic.List[string]]::new()
foreach ($line in [IO.File]::ReadLines($graph)) {
    if (-not $line.Contains('"id":', [StringComparison]::Ordinal)) { continue }
    $possible = $false
    foreach ($id in $visited) {
        if ($line.Contains($id, [StringComparison]::Ordinal)) { $possible = $true; break }
    }
    if (-not $possible) { continue }
    $entry = $line | ConvertFrom-Json
    if (-not ($entry.PSObject.Properties.Name -contains 'id') -or
        -not $visited.Contains([string]$entry.id)) { continue }
    $kind = [string]$entry.record
    $nodeKinds[$kind] = 1 + [int]($nodeKinds[$kind] ?? 0)
    if ($visitedExamples.Count -lt $MaximumExamples) { $visitedExamples.Add([string]$entry.id) }
}

[pscustomobject][ordered]@{
    schema_version = 1
    result = 'PASS'
    query = [pscustomobject][ordered]@{
        parameter_set = $PSCmdlet.ParameterSetName
        root_kind = if ($PSCmdlet.ParameterSetName -eq 'RootKind') { $RootKind } else { '' }
        roots = @($roots)
        maximum_depth = $MaximumDepth
        raw_values_emitted = $false
        raw_primary_keys_emitted = $false
        raw_package_names_emitted = $false
    }
    traversal = [pscustomobject][ordered]@{
        depth_reached = $depthReached
        visited_nodes = $visited.Count
        node_kinds = $nodeKinds
        edge_kinds = $edgeKinds
        resolution = $resolution
        visited_examples = @($visitedExamples)
        edge_examples = @($examples)
    }
} | ConvertTo-Json -Depth 10
