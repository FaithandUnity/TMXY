[CmdletBinding()]
param([string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$reportPath = Join-Path $root 'Data\Inventory\p2-01-package-inventory.json'
$toolPath = Join-Path $root 'Tools\TMXY.Package\New-FullPackageInventory.ps1'
$manifestPath = Join-Path $root 'Data\RawManifests\client-3.0.0.413.files.jsonl'
foreach ($path in @($reportPath, $toolPath, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P2-01 contract input is missing: $path"
    }
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [System.Array]::Clear($bytes, 0, $bytes.Length) }
}

$toolText = Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
foreach ($fragment in @(
        "'--network', 'none'", "'--read-only'", "'--cap-drop', 'ALL'",
        "'no-new-privileges:true'", 'client_mount = ''read-only''',
        'object_names_emitted = $false', 'object_bodies_copied = $false')) {
    if (-not $toolText.Contains($fragment, [System.StringComparison]::Ordinal)) {
        throw "P2-01 isolation contract is missing: $fragment"
    }
}

$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$files = @($report.files)
$versions = @{}
foreach ($entry in @($report.summary.versions)) {
    $versions[[string]$entry.version] = [int]$entry.files
}
$recognizedFailures = @($files | Where-Object { $_.recognized -and -not $_.parsed })
$unrecognized = @($files | Where-Object { -not $_.recognized })
$invalidHashes = @($files | Where-Object { [string]$_.sha256 -notmatch '^[a-f0-9]{64}$' })
$invalidFingerprints = @($files | Where-Object {
        [string]$_.metadata_fingerprint -notmatch '^[a-f0-9]{16}$'
    })
$inputLines = @($files | Sort-Object path | ForEach-Object {
        "$($_.path)|$($_.bytes)|$($_.sha256)"
    })
$inputSetSha = Get-TextSha256 -Value (($inputLines -join "`n") + "`n")

$moduleRoot = Join-Path $root 'Tools\TMXY.Package'
$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') -or $_.Name -eq 'CMakeLists.txt' } |
    Sort-Object FullName)
$sourceLines = foreach ($file in $sourceFiles) {
    $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$relative|$sha"
}
$sourceSha = Get-TextSha256 -Value (($sourceLines -join "`n") + "`n")
$manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$recordSum = [int64](($files | Measure-Object record_count -Sum).Sum)
$directorySum = [int64](($files | Measure-Object directory_bytes -Sum).Sum)
$unknownSum = [int64](($files | Measure-Object unknown_object_count -Sum).Sum)

$passed = [string]$report.result -eq 'PASS' -and
    [string]$report.task -eq 'P2-01' -and
    [string]$report.task_status -eq 'COMPLETE' -and
    [bool]$report.completion_criteria_satisfied -and
    $files.Count -eq 167 -and @($files.path | Sort-Object -Unique).Count -eq 167 -and
    [int]$report.summary.recognized -eq 163 -and
    [int]$report.summary.parsed -eq 163 -and $recognizedFailures.Count -eq 0 -and
    $versions['1.0'] -eq 1 -and $versions['2.0'] -eq 22 -and
    $versions['3.0'] -eq 140 -and $versions['empty'] -eq 1 -and
    $versions['unknown'] -eq 3 -and $unrecognized.Count -eq 4 -and
    @($unrecognized | Where-Object parsed).Count -eq 0 -and
    @($unrecognized | Where-Object { $_.error -notin @('empty_file', 'unknown_version') }).Count -eq 0 -and
    [int64]$report.summary.bytes -eq 42437699 -and
    $recordSum -eq 121715 -and $directorySum -eq 5510040 -and
    $unknownSum -eq 121715 -and
    $invalidHashes.Count -eq 0 -and $invalidFingerprints.Count -eq 0 -and
    [string]$report.input.manifest_sha256 -eq $manifestSha -and
    [string]$report.input.package_set_sha256 -eq $inputSetSha -and
    [int]$report.input.integrity_failures -eq 0 -and
    [int]$report.implementation.source_file_count -eq $sourceFiles.Count -and
    [string]$report.implementation.source_sha256 -eq $sourceSha -and
    -not [bool]$report.implementation.object_names_emitted -and
    -not [bool]$report.implementation.class_names_emitted -and
    -not [bool]$report.implementation.object_bodies_copied -and
    [int]$report.execution.ctest_count -eq 7 -and
    [int]$report.execution.inventory_line_count -eq 167 -and
    [string]$report.isolation.source_mount -eq 'read-only' -and
    [string]$report.isolation.client_mount -eq 'read-only' -and
    [string]$report.isolation.network -eq 'none' -and
    [string]$report.isolation.root_filesystem -eq 'read-only'

$bytes = [System.IO.File]::ReadAllBytes($reportPath)
try {
    $reportSha = [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}
finally { [System.Array]::Clear($bytes, 0, $bytes.Length) }
$result = [pscustomobject][ordered]@{
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P2-01'
    completion_criteria_satisfied = $passed
    assertions = 38
    package_files = $files.Count
    parsed_packages = [int]$report.summary.parsed
    records = $recordSum
    report_sha256 = $reportSha
    source_files_verified = $sourceFiles.Count
    legacy_payloads_copied = $false
}
$result | ConvertTo-Json -Depth 4
if (-not $passed) { throw 'P2-01 full Package inventory contract failed.' }
