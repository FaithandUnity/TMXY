[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$SelectionFile = 'Data/GoldenSamples/p0-golden-selection.json',
    [string]$OutputFile = 'Data/GoldenSamples/p0-golden-samples.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Path must be relative: $RelativePath"
    }

    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $candidate = [System.IO.Path]::GetFullPath(
        (Join-Path $fullRoot $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes its root: $RelativePath"
    }
    return $candidate
}

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-PackageVersion {
    param([Parameter(Mandatory = $true)][string]$Path)

    $file = Get-Item -LiteralPath $Path
    if ($file.Length -eq 0) { return 'empty' }

    $stream = [System.IO.File]::Open(
        $file.FullName,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    try {
        $buffer = [byte[]]::new([Math]::Min(96, [int]$file.Length))
        $read = $stream.Read($buffer, 0, $buffer.Length)
    }
    finally {
        $stream.Dispose()
    }

    $header = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
    if ($header -match 'QRENDER PACKAGE VER\s+([123]\.0)') {
        return $Matches[1]
    }
    return 'unknown'
}

function Convert-CountsToObject {
    param([Parameter(Mandatory = $true)][hashtable]$Counts)
    $result = [ordered]@{}
    foreach ($key in @($Counts.Keys | Sort-Object)) {
        $result[$key] = $Counts[$key]
    }
    return [pscustomobject]$result
}

function Write-Utf8LfJson {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $json = ($Value | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

$rebuild = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$selectionPath = Resolve-ContainedPath -Root $rebuild -RelativePath $SelectionFile
$outputPath = Resolve-ContainedPath -Root $rebuild -RelativePath $OutputFile

if (-not (Test-Path -LiteralPath $client -PathType Container)) {
    throw "Read-only client root is missing: $client"
}
$selection = Get-Content -LiteralPath $selectionPath -Raw | ConvertFrom-Json
if ([int]$selection.schema_version -ne 1) { throw 'Unsupported selection schema.' }
if ([string]$selection.copy_policy -ne 'reference_only') {
    throw 'Golden samples must use reference_only copy policy.'
}

$manifestPath = Resolve-ContainedPath -Root $rebuild -RelativePath ([string]$selection.manifest_file)
$manifestSha = Get-LowerSha256 -Path $manifestPath
if ($manifestSha -ne [string]$selection.manifest_sha256) {
    throw "Frozen Manifest SHA-256 mismatch: $manifestSha"
}

$selectedPaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
$selectedIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($sample in $selection.samples) {
    $normalized = ([string]$sample.path).Replace('\', '/')
    if (-not $selectedPaths.Add($normalized)) { throw "Duplicate sample path: $normalized" }
    if (-not $selectedIds.Add([string]$sample.id)) { throw "Duplicate sample id: $($sample.id)" }
}

$manifestRows = @{}
Get-Content -LiteralPath $manifestPath -ReadCount 1000 | ForEach-Object {
    foreach ($line in $_) {
        $row = $line | ConvertFrom-Json
        if ($selectedPaths.Contains([string]$row.path)) {
            $manifestRows[[string]$row.path] = $row
        }
    }
}
if ($manifestRows.Count -ne $selectedPaths.Count) {
    $missing = @($selectedPaths | Where-Object { -not $manifestRows.ContainsKey($_) })
    throw "Selection contains paths absent from the frozen Manifest: $($missing -join ', ')"
}

$kindCounts = @{}
$evidenceCounts = @{}
$allRoles = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$sampleResults = [System.Collections.Generic.List[object]]::new()
$selectedBytes = [int64]0

foreach ($sample in $selection.samples) {
    $relativePath = ([string]$sample.path).Replace('\', '/')
    $sourcePath = Resolve-ContainedPath -Root $client -RelativePath $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Selected source file is missing: $relativePath"
    }

    $manifestRow = $manifestRows[$relativePath]
    $sourceFile = Get-Item -LiteralPath $sourcePath
    if ([int64]$sourceFile.Length -ne [int64]$manifestRow.size) {
        throw "Source size differs from the frozen Manifest: $relativePath"
    }
    $actualSha = Get-LowerSha256 -Path $sourcePath
    if ($actualSha -ne [string]$manifestRow.sha256) {
        throw "Source SHA-256 differs from the frozen Manifest: $relativePath"
    }

    $kind = [string]$sample.kind
    $evidenceLevel = [string]$sample.evidence_level
    $kindCounts[$kind] = 1 + [int]($kindCounts[$kind] ?? 0)
    $evidenceCounts[$evidenceLevel] = 1 + [int]($evidenceCounts[$evidenceLevel] ?? 0)
    foreach ($role in @($sample.roles)) { [void]$allRoles.Add([string]$role) }
    $selectedBytes += [int64]$manifestRow.size

    $packageVersion = $null
    if ($kind -eq 'package') {
        $packageVersion = Get-PackageVersion -Path $sourcePath
        if ($packageVersion -ne [string]$sample.expected_package_version) {
            throw "Package version mismatch for $relativePath`: $packageVersion"
        }
    }

    $sampleResults.Add([pscustomobject][ordered]@{
        id = [string]$sample.id
        kind = $kind
        path = $relativePath
        roles = @($sample.roles)
        evidence_level = $evidenceLevel
        rationale = [string]$sample.rationale
        size = [int64]$manifestRow.size
        sha256 = [string]$manifestRow.sha256
        source_verified = $true
        package_version = $packageVersion
    })
}

$packageCounts = @{ '1.0' = 0; '2.0' = 0; '3.0' = 0; empty = 0; unknown = 0 }
$packageRoot = Join-Path $client 'Packages'
$packageFiles = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File)
foreach ($packageFile in $packageFiles) {
    $version = Get-PackageVersion -Path $packageFile.FullName
    if (-not $packageCounts.ContainsKey($version)) { $version = 'unknown' }
    $packageCounts[$version]++
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    source_set = [string]$selection.source_set
    client_version = [string]$selection.client_version
    copy_policy = 'reference_only'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    selection = [pscustomobject][ordered]@{
        file = $SelectionFile.Replace('\', '/')
        sha256 = Get-LowerSha256 -Path $selectionPath
    }
    manifest = [pscustomobject][ordered]@{
        file = ([string]$selection.manifest_file).Replace('\', '/')
        sha256 = $manifestSha
    }
    source_verification = [pscustomobject][ordered]@{
        mode = 'sha256_and_size'
        verified_file_count = $sampleResults.Count
    }
    summary = [pscustomobject][ordered]@{
        sample_count = $sampleResults.Count
        selected_bytes = $selectedBytes
        kind_counts = Convert-CountsToObject -Counts $kindCounts
        evidence_level_counts = Convert-CountsToObject -Counts $evidenceCounts
        distinct_roles = @($allRoles | Sort-Object)
        package_inventory = [pscustomobject][ordered]@{
            scanned_file_count = $packageFiles.Count
            version_counts = [pscustomobject][ordered]@{
                '1.0' = $packageCounts['1.0']
                '2.0' = $packageCounts['2.0']
                '3.0' = $packageCounts['3.0']
                empty = $packageCounts.empty
                unknown = $packageCounts.unknown
            }
        }
    }
    samples = @($sampleResults)
}

Write-Utf8LfJson -Value $report -Path $outputPath
$report | ConvertTo-Json -Depth 5
