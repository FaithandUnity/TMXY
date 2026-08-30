[CmdletBinding()]
param([string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$generatorPath = Join-Path $root 'Tests\Review\New-G1FormatReview.ps1'
$reportPath = Join-Path $root 'Data\BuildBaseline\p1-28-g1-format-review.json'
$authorizationPath = Join-Path $root 'Data\Governance\p1-g1-stage-authorization.json'
foreach ($path in @($generatorPath, $reportPath, $authorizationPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P1-28/G1 contract input is missing: $path"
    }
}

& $generatorPath -RebuildRoot $root -OutputPath $reportPath | Out-Null

$temporaryPath = Join-Path $root (
    'Data\BuildBaseline\.p1-28-g1-contract-{0}.json' -f [Guid]::NewGuid().ToString('N'))
try {
    & $generatorPath -RebuildRoot $root -OutputPath $temporaryPath | Out-Null
    $expected = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $actual = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected.captured_utc = 'normalized'
    $actual.captured_utc = 'normalized'
    $expectedJson = $expected | ConvertTo-Json -Depth 12 -Compress
    $actualJson = $actual | ConvertTo-Json -Depth 12 -Compress
    $authorization = Get-Content -LiteralPath $authorizationPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $passed = $expectedJson -ceq $actualJson -and
        [string]$expected.result -eq 'PASS' -and
        [string]$expected.task -eq 'P1-28' -and
        [string]$expected.task_status -eq 'COMPLETE' -and
        [bool]$expected.completion_criteria_satisfied -and
        [string]$expected.gate_decision -eq 'APPROVED' -and
        [int]$expected.prerequisites.completed -eq 27 -and
        [int]$expected.prerequisites.required -eq 27 -and
        @($expected.prerequisites.tasks | Where-Object { -not $_.passed }).Count -eq 0 -and
        [int]$expected.check_summary.passed -eq 8 -and
        [int]$expected.check_summary.required -eq 8 -and
        @($expected.check_summary.failed_ids).Count -eq 0 -and
        [int]$expected.unknown_items.total -eq 10 -and
        [int]$expected.unknown_items.owned -eq 10 -and
        [int]$expected.unknown_items.isolated -eq 10 -and
        -not [bool]$expected.security.raw_key_emitted -and
        -not [bool]$expected.authority_boundaries.g0_approved -and
        -not [bool]$expected.authority_boundaries.release_authority -and
        [string]$authorization.approved_by -eq 'project_lead' -and
        [bool]$authorization.scope.execute_p1_28
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

$reportBytes = [System.IO.File]::ReadAllBytes($reportPath)
try {
    $reportSha = [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($reportBytes)).ToLowerInvariant()
}
finally { [System.Array]::Clear($reportBytes, 0, $reportBytes.Length) }
$result = [pscustomobject][ordered]@{
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-28'
    gate = 'G1'
    completion_criteria_satisfied = $passed
    assertions = 25
    report_sha256 = $reportSha
    regenerated_semantic_match = $expectedJson -ceq $actualJson
    raw_key_required = $false
}
$result | ConvertTo-Json -Depth 4
if (-not $passed) { throw 'P1-28/G1 format review contract failed.' }
