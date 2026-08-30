[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$toolPath = Join-Path $root `
    'Tools\TMXY.Table\Inspect-CurrentTableRepresentativeSet.ps1'
$evidencePath = Join-Path $root `
    'Data\BuildBaseline\p1-11-current-table-representatives.json'
if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
    throw 'P1-11 representative inspection tool or evidence is missing.'
}

$toolText = Get-Content -LiteralPath $toolPath -Raw
$requiredFragments = @(
    'CredRead',
    'FromBase64String',
    'TransformFinalBlock',
    'primary_key_check',
    'empty_fields',
    'failure_classification',
    'raw_key_emitted = $false',
    'identifiers_emitted = $false',
    '[System.Array]::Clear'
)
foreach ($fragment in $requiredFragments) {
    if (-not $toolText.Contains($fragment, [System.StringComparison]::Ordinal)) {
        throw "P1-11 representative safety contract is missing: $fragment"
    }
}

$evidenceBytes = [System.IO.File]::ReadAllBytes($evidencePath)
try {
    $evidenceSha = [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($evidenceBytes)).ToLowerInvariant()
}
finally { [System.Array]::Clear($evidenceBytes, 0, $evidenceBytes.Length) }
$evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
$samples = @($evidence.samples)
$ascii = @($evidence.summary.encoding_counts | Where-Object encoding -eq 'ascii')
$gbk = @($evidence.summary.encoding_counts | Where-Object encoding -eq 'gbk')
$item = @($samples | Where-Object path -eq 'CLSVShare/item_table.tbl')
$skill = @($samples | Where-Object path -eq 'CLSVShare/skill_table.tbl')
$powergame = @($samples | Where-Object path -eq 'CLSVShare/powergame.tbl')
$passed = $evidence.result -eq 'PASS' -and
    $evidence.task -eq 'P1-11' -and
    $evidence.task_status -eq 'COMPLETE' -and
    $evidence.completion_criteria_satisfied -eq $true -and
    $evidence.selection.simple_count -eq 10 -and
    $evidence.selection.complex_count -eq 10 -and
    $evidence.selection.total_ciphertext_bytes -eq 21064736 -and
    $samples.Count -eq 20 -and
    @($samples.path | Sort-Object -Unique).Count -eq 20 -and
    $item.Count -eq 1 -and $skill.Count -eq 1 -and $powergame.Count -eq 1 -and
    $evidence.summary.decoded -eq 20 -and
    $evidence.summary.failed -eq 0 -and
    $evidence.summary.fixed_column_schema -eq 20 -and
    $evidence.summary.variable_column_schema -eq 0 -and
    $evidence.summary.unique_first_field_candidate -eq 15 -and
    $evidence.summary.composite_or_empty_first_field -eq 5 -and
    $evidence.summary.tables_with_empty_fields -eq 8 -and
    $ascii.Count -eq 1 -and $ascii[0].tables -eq 11 -and
    $gbk.Count -eq 1 -and $gbk[0].tables -eq 9 -and
    @($samples | Where-Object { $_.metrics.failure_classification -ne 'none' }).Count -eq 0 -and
    $item[0].metrics.rows -eq 29223 -and $item[0].metrics.header_columns -eq 95 -and
    $item[0].metrics.primary_key_check -eq 'unique-first-field-candidate' -and
    $item[0].metrics.empty_fields -eq 2136269 -and
    $skill[0].metrics.rows -eq 23227 -and $skill[0].metrics.header_columns -eq 65 -and
    $skill[0].metrics.primary_key_check -eq 'first-field-requires-composite-key' -and
    $skill[0].metrics.duplicate_first_field_occurrences -eq 13949 -and
    $powergame[0].metrics.rows -eq 2 -and $powergame[0].metrics.header_columns -eq 1 -and
    $evidence.secret_handling.raw_key_emitted -eq $false -and
    $evidence.secret_handling.plaintext_emitted -eq $false -and
    $evidence.secret_handling.identifiers_emitted -eq $false

$report = [pscustomobject][ordered]@{
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-11'
    completion_criteria_satisfied = $passed
    evidence_path = 'Data/BuildBaseline/p1-11-current-table-representatives.json'
    evidence_sha256 = $evidenceSha
    assertions = 35
    raw_key_required_for_contract_test = $false
    plaintext_emitted = $false
}
$report | ConvertTo-Json -Depth 4
if (-not $passed) { throw 'P1-11 current-table representative contract failed.' }
