[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-04-reference-formats-v0.1.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

$documents = [ordered]@{
    reference = 'Docs/Formats/REFERENCE-FORMATS-V0.1.md'
    package = 'Docs/Formats/PACKAGE-V1-FORMAT.md'
    table = 'Docs/Formats/LEGACY-TBL-BASELINE.md'
}
$reports = [ordered]@{
    package = 'Data/BuildBaseline/p1-02-package-v1.json'
    table = 'Data/BuildBaseline/p1-03-legacy-table.json'
}
foreach ($relativePath in @($documents.Values) + @($reports.Values)) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-04 required input is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$packageReport = Get-Content -LiteralPath (Join-Path $root $reports.package) -Raw -Encoding UTF8 |
    ConvertFrom-Json
$tableReport = Get-Content -LiteralPath (Join-Path $root $reports.table) -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ([string]$packageReport.result -ne 'PASS' -or [string]$packageReport.task -ne 'P1-02') {
    Add-Failure -Message 'P1-04 requires passing P1-02 machine evidence.'
}
if ([string]$tableReport.result -ne 'PASS' -or [string]$tableReport.task -ne 'P1-03') {
    Add-Failure -Message 'P1-04 requires passing P1-03 machine evidence.'
}

$referencePath = Join-Path $root $documents.reference
$content = Get-Content -LiteralPath $referencePath -Raw -Encoding UTF8
$requiredMarkers = @(
    '文档版本：0.1',
    '## 证据等级',
    '## Package 1.0',
    '### Package 1.0 未知项',
    '## 老 TBL',
    '### 老 TBL 未知项',
    'PKG1-U01',
    'LTBL-U04',
    '1691fafacd3ab5bd',
    'c60c5d8848a6a32a',
    'legacy cipher 不认证密文',
    '当前客户端新 TBL'
)
foreach ($marker in $requiredMarkers) {
    if (-not $content.Contains($marker, [System.StringComparison]::Ordinal)) {
        Add-Failure -Message "P1-04 reference document marker is missing: $marker"
    }
}
if ([int]$packageReport.frozen_sample.record_count -ne 3004 -or
    [string]$packageReport.frozen_sample.metadata_fnv1a64 -ne '1691fafacd3ab5bd') {
    Add-Failure -Message 'Package V1 frozen values no longer match reference format V0.1.'
}
if ([int]$tableReport.frozen_sample_pair.column_count -ne 10 -or
    [int]$tableReport.frozen_sample_pair.row_count -ne 57 -or
    [string]$tableReport.frozen_sample_pair.metadata_fnv1a64 -ne 'c60c5d8848a6a32a') {
    Add-Failure -Message 'Legacy TBL frozen values no longer match reference format V0.1.'
}
if ([bool]$tableReport.key_handling.embedded_in_rebuild -or
    [bool]$tableReport.key_handling.emitted_to_output) {
    Add-Failure -Message 'P1-04 cannot accept embedded or emitted legacy key material.'
}

$documentHashes = [ordered]@{}
foreach ($name in $documents.Keys) {
    $documentHashes[$name] = (Get-FileHash -LiteralPath (Join-Path $root $documents[$name]) `
        -Algorithm SHA256).Hash.ToLowerInvariant()
}
$reportHashes = [ordered]@{}
foreach ($name in $reports.Keys) {
    $reportHashes[$name] = (Get-FileHash -LiteralPath (Join-Path $root $reports[$name]) `
        -Algorithm SHA256).Hash.ToLowerInvariant()
}
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    task = 'P1-04'
    document_version = '0.1'
    covered_formats = @('Package 1.0', 'legacy QDataTable TBL')
    evidence_levels = @('L1', 'L2', 'L3', 'L4')
    unknown_item_count = 8
    document_sha256 = $documentHashes
    input_report_sha256 = $reportHashes
    secret_material_embedded = $false
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath), $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if ($failures.Count -gt 0) { throw 'P1-04 reference format documentation validation failed.' }
