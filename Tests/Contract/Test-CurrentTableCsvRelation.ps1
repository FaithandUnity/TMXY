[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$toolPath = Join-Path $root 'Tools\TMXY.Table\Compare-CurrentItemResidual.ps1'
$evidencePath = Join-Path $root `
    'Data\BuildBaseline\p1-10-current-item-csv-relation.json'
if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
    throw 'P1-10 comparison tool or evidence is missing.'
}

$toolText = Get-Content -LiteralPath $toolPath -Raw
$requiredFragments = @(
    'CredRead',
    'FromBase64String',
    'TransformFinalBlock',
    'Get-RowIndex',
    'raw_key_emitted = $false',
    'plaintext_emitted = $false',
    '[System.Array]::Clear'
)
foreach ($fragment in $requiredFragments) {
    if (-not $toolText.Contains($fragment, [System.StringComparison]::Ordinal)) {
        throw "P1-10 comparison safety contract is missing: $fragment"
    }
}

$evidenceBytes = [System.IO.File]::ReadAllBytes($evidencePath)
try {
    $evidenceSha = [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($evidenceBytes)).ToLowerInvariant()
}
finally {
    [System.Array]::Clear($evidenceBytes, 0, $evidenceBytes.Length)
}
$evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
$passed = $evidence.result -eq 'PASS' -and
    $evidence.task -eq 'P1-10' -and
    $evidence.task_status -eq 'COMPLETE' -and
    $evidence.completion_criteria_satisfied -eq $true -and
    $evidence.processing.double_aes128_decode -eq $true -and
    $evidence.processing.current_payload_bytes -eq 7046695 -and
    $evidence.processing.current_strict_gbk -eq $true -and
    $evidence.processing.residual_strict_gbk -eq $true -and
    $evidence.processing.raw_key_emitted -eq $false -and
    $evidence.processing.plaintext_emitted -eq $false -and
    $evidence.schema_relation.header_exact_match -eq $true -and
    $evidence.schema_relation.current_columns -eq 95 -and
    $evidence.schema_relation.residual_columns -eq 95 -and
    $evidence.schema_relation.current_rows -eq 29223 -and
    $evidence.schema_relation.residual_rows -eq 27289 -and
    $evidence.primary_key_relation.current_unique -eq $true -and
    $evidence.primary_key_relation.residual_unique -eq $true -and
    $evidence.primary_key_relation.shared -eq 27288 -and
    $evidence.primary_key_relation.identical_rows -eq 26272 -and
    $evidence.primary_key_relation.changed_rows -eq 1016 -and
    $evidence.primary_key_relation.current_only -eq 1935 -and
    $evidence.primary_key_relation.residual_only -eq 1 -and
    $evidence.positional_relation.common_prefix_bytes -eq 13769 -and
    $evidence.positional_relation.first_different_line_ordinal -eq 60 -and
    $evidence.conclusion.exact_replacement -eq $false -and
    $evidence.conclusion.residual_can_replace_current_table -eq $false

$report = [pscustomobject][ordered]@{
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-10'
    completion_criteria_satisfied = $passed
    evidence_path = 'Data/BuildBaseline/p1-10-current-item-csv-relation.json'
    evidence_sha256 = $evidenceSha
    assertions = 28
    raw_key_required_for_contract_test = $false
    plaintext_emitted = $false
}
$report | ConvertTo-Json -Depth 4
if (-not $passed) { throw 'P1-10 current/residual CSV relation contract failed.' }
