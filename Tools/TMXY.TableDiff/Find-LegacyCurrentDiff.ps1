[CmdletBinding()]
param(
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-09\p2-09-legacy-current-diff.jsonl',
    [string]$Table,
    [ValidateSet('paired', 'legacy-only')][string]$State,
    [ValidateRange(0, 100)][int]$MaximumExamples = 20
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ReportPath -PathType Leaf)) { throw "P2-09 report missing: $ReportPath" }
$matches=0;$examples=[Collections.Generic.List[object]]::new()
foreach($line in [IO.File]::ReadLines([IO.Path]::GetFullPath($ReportPath))){
    $item=$line|ConvertFrom-Json
    if($Table -and [string]$item.table -ine $Table){continue}
    if($State -and [string]$item.state -ne $State){continue}
    ++$matches
    if($examples.Count-lt $MaximumExamples){
        $examples.Add([pscustomobject][ordered]@{
            table=[string]$item.table;state=[string]$item.state
            legacy_rows=if($item.legacy){[int]$item.legacy.rows}else{0}
            current_rows=if($item.current){[int]$item.current.rows}else{0}
            shared_exact_rows=if($item.rows){[int]$item.rows.shared_exact}else{0}
            legacy_only_rows=if($item.rows){[int]$item.rows.legacy_only}else{0}
            current_only_rows=if($item.rows){[int]$item.rows.current_only}else{0}
            primary_key_applicable=if($item.primary_key){[bool]$item.primary_key.applicable}else{$false}
        })
    }
}
[pscustomobject][ordered]@{
    schema_version=1;result='PASS';matches=$matches
    query=[pscustomobject][ordered]@{table=if($Table){$Table}else{''};state=if($State){$State}else{''}
        headers_emitted=$false;row_values_emitted=$false;primary_keys_emitted=$false}
    examples=@($examples)
}|ConvertTo-Json -Depth 6
