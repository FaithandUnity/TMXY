[CmdletBinding(DefaultParameterSetName = 'LogicalName')]
param(
    [string]$GraphPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-03\p2-03-package-dependency-graph.jsonl',
    [Parameter(Mandatory = $true, ParameterSetName = 'LogicalName')][string]$LogicalName,
    [Parameter(Mandatory = $true, ParameterSetName = 'NameHex')][string]$NameHex,
    [Parameter(Mandatory = $true, ParameterSetName = 'NodeId')][string]$NodeId,
    [ValidateRange(0, 100)][int]$MaximumExamples = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$graph = [System.IO.Path]::GetFullPath($GraphPath)
if (-not (Test-Path -LiteralPath $graph -PathType Leaf)) {
    throw "P2-03 dependency graph is missing: $graph"
}

function Get-ByteSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    try {
        return [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
    }
    finally { [System.Array]::Clear($Bytes, 0, $Bytes.Length) }
}

function Get-AsciiLowerByteSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $lowered = [byte[]]::new($Bytes.Length)
    for ($index = 0; $index -lt $Bytes.Length; ++$index) {
        $value = $Bytes[$index]
        $lowered[$index] = if ($value -ge 65 -and $value -le 90) { $value + 32 } else { $value }
    }
    try { return Get-ByteSha256 -Bytes $lowered }
    finally { [System.Array]::Clear($lowered, 0, $lowered.Length) }
}

function Test-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    return $Value -cmatch '^[a-f0-9]{64}$'
}

$queryNameHash = ''
$queryLowerNameHash = ''
$queryNodeId = ''
switch ($PSCmdlet.ParameterSetName) {
    'LogicalName' {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($LogicalName)
        $queryNameHash = Get-ByteSha256 -Bytes $bytes
        $queryLowerNameHash = Get-AsciiLowerByteSha256 -Bytes $bytes
    }
    'NameHex' {
        if ($NameHex -cnotmatch '^(?:[a-f0-9]{2})+$') {
            throw 'NameHex must contain a non-empty even number of lowercase hex digits.'
        }
        $bytes = [System.Convert]::FromHexString($NameHex)
        $queryNameHash = Get-ByteSha256 -Bytes $bytes
        $queryLowerNameHash = Get-AsciiLowerByteSha256 -Bytes $bytes
    }
    'NodeId' {
        if (-not (Test-LowerSha256 -Value $NodeId)) {
            throw 'NodeId must be a lowercase SHA-256 value.'
        }
        $queryNodeId = $NodeId
    }
}

$nodes = [System.Collections.Generic.List[object]]::new()
foreach ($line in [System.IO.File]::ReadLines($graph)) {
    if (-not $line.Contains('"record":"node"', [System.StringComparison]::Ordinal)) {
        break
    }
    $matches = if ($queryNodeId.Length -gt 0) {
        $line.Contains($queryNodeId, [System.StringComparison]::Ordinal)
    }
    else {
        $line.Contains($queryNameHash, [System.StringComparison]::Ordinal) -or
        $line.Contains($queryLowerNameHash, [System.StringComparison]::Ordinal)
    }
    if (-not $matches) { continue }
    $entry = $line | ConvertFrom-Json
    if (($queryNodeId.Length -gt 0 -and [string]$entry.id -eq $queryNodeId) -or
        ($queryNameHash.Length -gt 0 -and
            ([string]$entry.logical_name_sha256 -eq $queryNameHash -or
                [string]$entry.logical_name_ascii_lower_sha256 -eq $queryLowerNameHash))) {
        $nodes.Add($entry)
    }
}

if ($queryNameHash.Length -eq 0 -and $nodes.Count -eq 1) {
    $queryNameHash = [string]$nodes[0].logical_name_sha256
    $queryLowerNameHash = [string]$nodes[0].logical_name_ascii_lower_sha256
}
$nodeIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($node in $nodes) { [void]$nodeIds.Add([string]$node.id) }

$incoming = [System.Collections.Generic.List[object]]::new()
$outgoing = [System.Collections.Generic.List[object]]::new()
$incomingKinds = @{}
$outgoingKinds = @{}
foreach ($line in [System.IO.File]::ReadLines($graph)) {
    if (-not $line.Contains('"record":"edge"', [System.StringComparison]::Ordinal)) { continue }
    $possibleIncoming = $queryNameHash.Length -gt 0 -and
        ($line.Contains($queryNameHash, [System.StringComparison]::Ordinal) -or
            $line.Contains($queryLowerNameHash, [System.StringComparison]::Ordinal))
    $possibleOutgoing = $false
    foreach ($id in $nodeIds) {
        if ($line.Contains($id, [System.StringComparison]::Ordinal)) {
            $possibleOutgoing = $true
            break
        }
    }
    if (-not $possibleIncoming -and -not $possibleOutgoing) { continue }
    $entry = $line | ConvertFrom-Json
    if ($possibleIncoming -and
        ([string]$entry.target_logical_name_sha256 -eq $queryNameHash -or
            [string]$entry.target_logical_name_ascii_lower_sha256 -eq $queryLowerNameHash)) {
        $kind = [string]$entry.kind
        $incomingKinds[$kind] = 1 + [int]($incomingKinds[$kind] ?? 0)
        if ($incoming.Count -lt $MaximumExamples) { $incoming.Add($entry) }
    }
    if ($possibleOutgoing -and $nodeIds.Contains([string]$entry.source)) {
        $kind = [string]$entry.kind
        $outgoingKinds[$kind] = 1 + [int]($outgoingKinds[$kind] ?? 0)
        if ($outgoing.Count -lt $MaximumExamples) { $outgoing.Add($entry) }
    }
}

$incomingCount = [int](($incomingKinds.Values | Measure-Object -Sum).Sum ?? 0)
$outgoingCount = [int](($outgoingKinds.Values | Measure-Object -Sum).Sum ?? 0)
$result = [pscustomobject][ordered]@{
    schema_version = 1
    result = 'PASS'
    query = [pscustomobject][ordered]@{
        parameter_set = $PSCmdlet.ParameterSetName
        logical_name_sha256 = $queryNameHash
        logical_name_ascii_lower_sha256 = $queryLowerNameHash
        node_id = $queryNodeId
        raw_name_emitted = $false
    }
    matched_nodes = $nodes.Count
    nodes = @($nodes)
    incoming = [pscustomobject][ordered]@{
        count = $incomingCount
        by_kind = $incomingKinds
        examples = @($incoming)
    }
    outgoing = [pscustomobject][ordered]@{
        count = $outgoingCount
        by_kind = $outgoingKinds
        examples = @($outgoing)
    }
}
$result | ConvertTo-Json -Depth 8
