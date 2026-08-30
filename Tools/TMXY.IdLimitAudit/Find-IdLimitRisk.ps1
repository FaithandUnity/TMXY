[CmdletBinding()]
param(
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-11\p2-11-id-limit-audit.jsonl',
    [ValidateSet('id_component_audit', 'legacy_source_limit_signal')][string]$Record,
    [string]$Risk,
    [string]$Rule,
    [ValidateRange(1, 100)][int]$Limit = 20
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "ID limit audit not found: $ReportPath" }
$examples = [Collections.Generic.List[object]]::new(); $count = 0
foreach ($line in [IO.File]::ReadLines($ReportPath)) {
    $item = $line | ConvertFrom-Json
    if ($Record -and $item.record -ne $Record) { continue }
    if ($Risk -and ($item.record -ne 'id_component_audit' -or $Risk -notin @($item.risks))) { continue }
    if ($Rule -and ($item.record -ne 'legacy_source_limit_signal' -or $item.rule -ne $Rule)) { continue }
    ++$count
    if ($examples.Count -ge $Limit) { continue }
    if ($item.record -eq 'id_component_audit') {
        $examples.Add([pscustomobject][ordered]@{ record = [string]$item.record; domain = [string]$item.domain; column_id = [string]$item.column_id; type = [string]$item.type; risks = @($item.risks) })
    }
    else {
        $examples.Add([pscustomobject][ordered]@{ record = [string]$item.record; root = [string]$item.root; rule = [string]$item.rule; hit_count = [int]$item.hit_count; source_sha256 = [string]$item.source_sha256 })
    }
}
[pscustomobject][ordered]@{
    result = 'PASS'; matches = $count; examples = $examples
    query = [pscustomobject][ordered]@{ primary_keys_emitted = $false; min_max_values_emitted = $false; source_paths_emitted = $false; source_lines_emitted = $false }
} | ConvertTo-Json -Depth 8
