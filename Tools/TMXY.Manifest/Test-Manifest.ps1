[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath,

    [switch]$VerifySourceFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedSummary = (Resolve-Path -LiteralPath $SummaryPath).Path
$summary = Get-Content -LiteralPath $resolvedSummary -Raw -Encoding UTF8 | ConvertFrom-Json
$manifestPath = Join-Path (Split-Path -Parent $resolvedSummary) $summary.files_manifest
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Manifest file does not exist: $manifestPath"
}

$actualManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualManifestHash -ne $summary.files_manifest_sha256) {
    throw "Manifest SHA-256 mismatch for $manifestPath"
}

$root = [string]$summary.source_root
$rootPrefix = $root.TrimEnd([char[]]'\/') + [System.IO.Path]::DirectorySeparatorChar
$seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$previousPath = $null
[int64]$lineCount = 0
[int64]$totalBytes = 0

foreach ($line in [System.IO.File]::ReadLines($manifestPath)) {
    $lineCount++
    $entry = $line | ConvertFrom-Json
    $relativePath = [string]$entry.path

    if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath)) {
        throw "Invalid relative path at line ${lineCount}: $relativePath"
    }
    if ($relativePath.Contains('\') -or $relativePath.Split('/') -contains '..') {
        throw "Unsafe or non-normalized path at line ${lineCount}: $relativePath"
    }
    if (-not $seenPaths.Add($relativePath)) {
        throw "Duplicate path at line ${lineCount}: $relativePath"
    }
    if ($null -ne $previousPath -and [string]::Compare($previousPath, $relativePath, [System.StringComparison]::OrdinalIgnoreCase) -gt 0) {
        throw "Manifest paths are not sorted at line ${lineCount}: $relativePath"
    }
    if ([int64]$entry.size -lt 0) {
        throw "Negative file size at line ${lineCount}: $relativePath"
    }
    if ([string]$entry.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw "Invalid SHA-256 at line ${lineCount}: $relativePath"
    }

    if ($VerifySourceFiles) {
        $candidate = Join-Path $root $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $fullPath = [System.IO.Path]::GetFullPath($candidate)
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Source path escaped root at line ${lineCount}: $relativePath"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Source file is missing: $relativePath"
        }
        $file = Get-Item -LiteralPath $fullPath -Force
        if ([int64]$file.Length -ne [int64]$entry.size) {
            throw "Source file size changed: $relativePath"
        }
        $sourceHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sourceHash -ne [string]$entry.sha256) {
            throw "Source file SHA-256 changed: $relativePath"
        }
    }

    $totalBytes += [int64]$entry.size
    $previousPath = $relativePath
}

if ($lineCount -ne [int64]$summary.file_count) {
    throw "File count mismatch: expected $($summary.file_count), actual $lineCount"
}
if ($totalBytes -ne [int64]$summary.total_bytes) {
    throw "Total byte count mismatch: expected $($summary.total_bytes), actual $totalBytes"
}

if ($VerifySourceFiles) {
    $currentFiles = @(
        Get-ChildItem -LiteralPath $root -File -Recurse -Force |
            Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }
    )
    if ($currentFiles.Count -ne [int64]$summary.file_count) {
        throw "Current source file count changed: expected $($summary.file_count), actual $($currentFiles.Count)"
    }
}

Write-Output ([ordered]@{
    valid = $true
    name = [string]$summary.name
    files = $lineCount
    bytes = $totalBytes
    manifest_sha256 = $actualManifestHash
    source_files_verified = [bool]$VerifySourceFiles
} | ConvertTo-Json -Compress)

