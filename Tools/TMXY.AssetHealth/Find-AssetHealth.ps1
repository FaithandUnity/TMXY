[CmdletBinding(DefaultParameterSetName = 'Filter')]
param(
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-14\p2-14-asset-health.jsonl',
    [Parameter(ParameterSetName = 'Filter')]
    [ValidateSet('root_reachable', 'linked_outside_declared_roots',
        'unlinked_identity_rule_no_match', 'unlinked_no_identity_rule')]
    [string]$ReferenceState,
    [Parameter(ParameterSetName = 'Filter')]
    [ValidateSet('anim', 'mp3', 'qtx', 'skem', 'sm', 'ter', 'wav', 'zif')]
    [string]$Family,
    [Parameter(Mandatory = $true, ParameterSetName = 'Group')]
    [ValidatePattern('^[0-9a-f]{64}$')][string]$GroupId,
    [ValidateRange(0, 100)][int]$MaximumExamples = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$report = [IO.Path]::GetFullPath($ReportPath)
if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
    throw "P2-14 asset health report is missing: $report"
}

$memberIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$groupKind = ''
if ($PSCmdlet.ParameterSetName -eq 'Group') {
    foreach ($line in [IO.File]::ReadLines($report)) {
        if (-not $line.Contains($GroupId, [StringComparison]::Ordinal)) { continue }
        $entry = $line | ConvertFrom-Json
        if ([string]$entry.id -ne $GroupId -or
            [string]$entry.record -notin @('exact_duplicate_group', 'structural_review_group')) {
            continue
        }
        $groupKind = [string]$entry.record
        foreach ($id in $entry.members) { [void]$memberIds.Add([string]$id) }
        break
    }
    if ($memberIds.Count -eq 0) { throw 'P2-14 query matched no duplicate/review group.' }
}

$matched = 0
$counts = @{}
$examples = [Collections.Generic.List[object]]::new()
foreach ($line in [IO.File]::ReadLines($report)) {
    if (-not $line.Contains('"record":"asset_health"', [StringComparison]::Ordinal)) {
        continue
    }
    $entry = $line | ConvertFrom-Json
    if ($PSCmdlet.ParameterSetName -eq 'Group') {
        if (-not $memberIds.Contains([string]$entry.id)) { continue }
    }
    else {
        if ($ReferenceState -and [string]$entry.reference_state -ne $ReferenceState) { continue }
        if ($Family -and [string]$entry.family -ne $Family) { continue }
    }
    ++$matched
    $state = [string]$entry.reference_state
    $counts[$state] = 1 + [int]($counts[$state] ?? 0)
    if ($examples.Count -lt $MaximumExamples) {
        $examples.Add([pscustomobject][ordered]@{
                id = [string]$entry.id
                path = [string]$entry.path
                family = [string]$entry.family
                bytes = [int64]$entry.bytes
                structure = [string]$entry.structure
                reference_state = $state
                exact_duplicate_group = [string]$entry.exact_duplicate_group
                structural_review_group = [string]$entry.structural_review_group
                delete_eligible = [bool]$entry.delete_eligible
            })
    }
}

[pscustomobject][ordered]@{
    schema_version = 1
    result = 'PASS'
    query = [pscustomobject][ordered]@{
        parameter_set = $PSCmdlet.ParameterSetName
        reference_state = if ($ReferenceState) { $ReferenceState } else { '' }
        family = if ($Family) { $Family } else { '' }
        group_id = if ($PSCmdlet.ParameterSetName -eq 'Group') { $GroupId } else { '' }
        group_kind = $groupKind
        raw_payloads_emitted = $false
        source_hashes_emitted = $false
    }
    matches = $matched
    reference_states = $counts
    examples = @($examples)
} | ConvertTo-Json -Depth 8
