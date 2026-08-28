[CmdletBinding()]
param([string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$reportPath = Join-Path $root 'Data\Inventory\p2-02-package-boundary-completeness.json'
$toolPath = Join-Path $root 'Tools\TMXY.Package\New-PackageBoundaryCompleteness.ps1'
$p201Path = Join-Path $root 'Data\Inventory\p2-01-package-inventory.json'
$goldenPath = Join-Path $root 'Data\GoldenSamples\p0-golden-samples.json'
foreach ($path in @($reportPath, $toolPath, $p201Path, $goldenPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P2-02 contract input is missing: $path"
    }
}

$toolText = Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
foreach ($fragment in @(
        "'--network', 'none'", "'--read-only'", "'--cap-drop', 'ALL'",
        "'no-new-privileges:true'", 'head -c "$((bytes - 1))"',
        "printf '\0'", 'client_mount = ''read-only''',
        'object_names_emitted = $false', 'object_bodies_copied = $false')) {
    if (-not $toolText.Contains($fragment, [System.StringComparison]::Ordinal)) {
        throw "P2-02 safety or mutation contract is missing: $fragment"
    }
}

foreach ($reader in @(
        'Tools/TMXY.Package/src/package_v1_reader.cpp',
        'Tools/TMXY.Package/src/package_v2_reader.cpp',
        'Tools/TMXY.Package/src/package_v3_reader.cpp')) {
    $readerText = Get-Content -LiteralPath (Join-Path $root $reader) -Raw -Encoding UTF8
    foreach ($fragment in @('record->offset != cursor', 'cursor != header.file_size')) {
        if (-not $readerText.Contains($fragment, [System.StringComparison]::Ordinal)) {
            throw "P2-02 parser invariant is missing from ${reader}: $fragment"
        }
    }
}
foreach ($reader in @(
        'Tools/TMXY.Package/src/package_v2_reader.cpp',
        'Tools/TMXY.Package/src/package_v3_reader.cpp')) {
    $readerText = Get-Content -LiteralPath (Join-Path $root $reader) -Raw -Encoding UTF8
    if (-not $readerText.Contains('directory_reader.remaining() != 0U',
            [System.StringComparison]::Ordinal)) {
        throw "P2-02 directory exhaustion invariant is missing from $reader"
    }
}

$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$packages = @($report.packages)
$nonPackages = @($report.non_packages)
$corePackages = @($packages | Where-Object core)
$versions = @{}
foreach ($entry in @($packages | Group-Object version)) { $versions[$entry.Name] = $entry.Count }
$invalidPackages = @($packages | Where-Object {
        -not $_.boundary_complete -or [int64]$_.covered_bytes -ne [int64]$_.bytes -or
        [int64]$_.uncovered_bytes -ne 0 -or [int64]$_.header_bytes -lt 0 -or
        [int64]$_.object_bytes -lt 0 -or
        [int64]$_.header_bytes + [int64]$_.object_bytes -ne [int64]$_.bytes -or
        -not $_.truncated_tail.rejected -or
        [string]$_.truncated_tail.error -ne 'object_range_out_of_file' -or
        -not $_.appended_tail.rejected -or
        [string]$_.appended_tail.error -ne 'non_contiguous_object_range' -or
        [string]$_.sha256 -notmatch '^[a-f0-9]{64}$'
    })

$golden = Get-Content -LiteralPath $goldenPath -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedCore = @($golden.samples | Where-Object {
        [string]$_.kind -eq 'package' -and [bool]$_.source_verified -and
        [string]$_.package_version -in @('1.0', '2.0', '3.0')
    } | ForEach-Object { [string]$_.path } | Sort-Object -Unique)
$reportedCore = @($report.core_definition.paths | Sort-Object -Unique)
$coreFlagsMatch = $expectedCore.Count -eq $reportedCore.Count -and
    @(Compare-Object $expectedCore $reportedCore).Count -eq 0 -and
    $corePackages.Count -eq $expectedCore.Count -and
    @(Compare-Object $expectedCore @($corePackages.path | Sort-Object -Unique)).Count -eq 0

$expectedNonPackages = @(
    'Packages/edtiactions06',
    'Packages/UI/.svn/all-wcprops',
    'Packages/UI/.svn/entries',
    'Packages/UI/.svn/prop-base/interface.svn-base'
)
$nonPackagePaths = @($nonPackages.path | Sort-Object -Unique)
$nonPackageClassificationValid = @($nonPackages | Where-Object {
        ($_.path -eq 'Packages/edtiactions06' -and
            ($_.classification -ne 'empty' -or $_.error -ne 'empty_file')) -or
        ($_.path -ne 'Packages/edtiactions06' -and
            ($_.classification -ne 'unknown' -or $_.error -ne 'unknown_version'))
    }).Count -eq 0

$p201Sha = (Get-FileHash -LiteralPath $p201Path -Algorithm SHA256).Hash.ToLowerInvariant()
$goldenSha = (Get-FileHash -LiteralPath $goldenPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sourceBytes = [int64](($packages | Measure-Object bytes -Sum).Sum)
$headerBytes = [int64](($packages | Measure-Object header_bytes -Sum).Sum)
$objectBytes = [int64](($packages | Measure-Object object_bytes -Sum).Sum)
$recordCount = [int64](($packages | Measure-Object record_count -Sum).Sum)

$passed = [string]$report.result -eq 'PASS' -and [string]$report.task -eq 'P2-02' -and
    [string]$report.task_status -eq 'COMPLETE' -and
    [bool]$report.completion_criteria_satisfied -and
    $packages.Count -eq 163 -and @($packages.path | Sort-Object -Unique).Count -eq 163 -and
    $nonPackages.Count -eq 4 -and
    @(Compare-Object $expectedNonPackages $nonPackagePaths).Count -eq 0 -and
    $nonPackageClassificationValid -and
    $versions['1.0'] -eq 1 -and $versions['2.0'] -eq 22 -and $versions['3.0'] -eq 140 -and
    $invalidPackages.Count -eq 0 -and $coreFlagsMatch -and $corePackages.Count -eq 12 -and
    [int]$report.summary.files_classified -eq 167 -and
    [int]$report.summary.recognized_packages -eq 163 -and
    [int]$report.summary.complete_packages -eq 163 -and
    [int]$report.summary.complete_parse_rate_ppm -eq 1000000 -and
    [int]$report.summary.required_parse_rate_ppm -eq 999000 -and
    [int]$report.summary.core_packages -eq 12 -and
    [int]$report.summary.complete_core_packages -eq 12 -and
    [int]$report.summary.core_parse_rate_ppm -eq 1000000 -and
    [int]$report.summary.required_core_rate_ppm -eq 1000000 -and
    $recordCount -eq 121715 -and $sourceBytes -eq 42437084 -and
    $headerBytes -eq 5514738 -and $objectBytes -eq 36922346 -and
    [int64]$report.summary.records -eq $recordCount -and
    [int64]$report.summary.source_bytes -eq $sourceBytes -and
    [int64]$report.summary.header_bytes -eq $headerBytes -and
    [int64]$report.summary.object_bytes -eq $objectBytes -and
    [int64]$report.summary.covered_bytes -eq $sourceBytes -and
    [int64]$report.summary.uncovered_bytes -eq 0 -and
    [int]$report.summary.mutation_checks -eq 326 -and
    [int]$report.summary.mutation_rejections -eq 326 -and
    [int]$report.summary.silent_truncation_accepts -eq 0 -and
    [int]$report.summary.silent_trailing_byte_accepts -eq 0 -and
    [string]$report.input.p2_01_inventory_sha256 -eq $p201Sha -and
    [string]$report.input.golden_samples_sha256 -eq $goldenSha -and
    [int]$report.input.integrity_failures -eq 0 -and
    @($report.parser_invariants).Count -eq 4 -and
    [int]$report.execution.ctest_count -eq 7 -and
    [int]$report.execution.original_scans -eq 167 -and
    [int]$report.execution.mutation_scans -eq 332 -and
    -not [bool]$report.disclosure.object_names_emitted -and
    -not [bool]$report.disclosure.class_names_emitted -and
    -not [bool]$report.disclosure.object_bodies_copied -and
    [string]$report.isolation.source_mount -eq 'read-only' -and
    [string]$report.isolation.client_mount -eq 'read-only' -and
    [string]$report.isolation.network -eq 'none' -and
    [string]$report.isolation.root_filesystem -eq 'read-only'

$reportSha = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash.ToLowerInvariant()
$result = [pscustomobject][ordered]@{
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P2-02'
    completion_criteria_satisfied = $passed
    assertions = 52
    classified_files = 167
    complete_packages = @($packages | Where-Object boundary_complete).Count
    complete_core_packages = @($corePackages | Where-Object boundary_complete).Count
    mutation_rejections = 326 - $invalidPackages.Count
    report_sha256 = $reportSha
    legacy_payloads_copied = $false
}
$result | ConvertTo-Json -Depth 4
if (-not $passed) { throw 'P2-02 Package boundary completeness contract failed.' }
