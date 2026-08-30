[CmdletBinding()]
param(
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-10\p2-10-canonical-id-map.jsonl',
    [string]$Domain,
    [ValidateSet('active', 'tombstone')][string]$Status,
    [ValidateSet('preserve_shared', 'adopt_current', 'preserve_legacy_tombstone')][string]$Action,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$CanonicalIdSha256,
    [ValidateRange(1, 100)][int]$Limit = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "Canonical ID map not found: $ReportPath"
}

$matches = [Collections.Generic.List[object]]::new()
$count = 0
foreach ($line in [IO.File]::ReadLines($ReportPath)) {
    $record = $line | ConvertFrom-Json
    if ($Domain -and $record.domain -ine $Domain) { continue }
    if ($Status -and $record.status -ne $Status) { continue }
    if ($Action -and $record.action -ne $Action) { continue }
    if ($CanonicalIdSha256 -and $record.canonical_id_sha256 -ne $CanonicalIdSha256) { continue }
    ++$count
    if ($matches.Count -lt $Limit) {
        $matches.Add([pscustomobject][ordered]@{
                domain = [string]$record.domain
                status = [string]$record.status
                action = [string]$record.action
                canonical_id_sha256 = [string]$record.canonical_id_sha256
                legacy_present = [bool]$record.legacy_present
                current_present = [bool]$record.current_present
            })
    }
}

[pscustomobject][ordered]@{
    result = 'PASS'
    matches = $count
    examples = $matches
    query = [pscustomobject][ordered]@{
        primary_keys_emitted = $false
        row_values_emitted = $false
        digest_only = $true
    }
} | ConvertTo-Json -Depth 8
