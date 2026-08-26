[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Name,

    [string]$ProductVersion = 'unknown'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$rootItem = Get-Item -LiteralPath $resolvedRoot -Force
if (-not $rootItem.PSIsContainer) {
    throw "Root must be a directory: $resolvedRoot"
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
$outputItem = Get-Item -LiteralPath $resolvedOutput -Force
if (-not $outputItem.PSIsContainer) {
    throw "OutputDirectory must be a directory: $resolvedOutput"
}

$rootPrefix = $resolvedRoot.TrimEnd([char[]]'\/') + [System.IO.Path]::DirectorySeparatorChar
$manifestPath = Join-Path $resolvedOutput "$Name.files.jsonl"
$summaryPath = Join-Path $resolvedOutput "$Name.summary.json"
$temporaryPath = Join-Path $resolvedOutput "$Name.files.jsonl.tmp"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$allFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse -Force)
$relativeFilePaths = New-Object 'System.Collections.Generic.List[string]'
$fileByRelativePath = New-Object 'System.Collections.Generic.Dictionary[string,System.IO.FileInfo]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($candidateFile in $allFiles) {
    if (-not ($candidateFile.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        if (-not $candidateFile.FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "File escaped the requested root: $($candidateFile.FullName)"
        }
        $candidateRelativePath = $candidateFile.FullName.Substring($rootPrefix.Length).Replace('\', '/')
        if ($fileByRelativePath.ContainsKey($candidateRelativePath)) {
            throw "Duplicate normalized relative path: $candidateRelativePath"
        }
        $fileByRelativePath.Add($candidateRelativePath, $candidateFile)
        $relativeFilePaths.Add($candidateRelativePath)
    }
}
$relativeFilePaths.Sort([System.StringComparer]::OrdinalIgnoreCase)
$orderedFiles = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
foreach ($relativeFilePath in $relativeFilePaths) {
    $orderedFiles.Add($fileByRelativePath[$relativeFilePath])
}
$files = $orderedFiles.ToArray()

$skippedReparsePoints = @(
    $allFiles |
        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } |
        ForEach-Object { $_.FullName.Substring($rootPrefix.Length).Replace('\', '/') }
)

$writer = New-Object System.IO.StreamWriter($temporaryPath, $false, $utf8NoBom)
$totalBytes = [int64]0
$extensionStats = @{}
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]
        if (-not $file.FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "File escaped the requested root: $($file.FullName)"
        }

        $relativePath = $file.FullName.Substring($rootPrefix.Length).Replace('\', '/')
        $sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry = [ordered]@{
            path = $relativePath
            size = [int64]$file.Length
            last_write_utc = $file.LastWriteTimeUtc.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            sha256 = $sha256
        }
        $writer.WriteLine(($entry | ConvertTo-Json -Compress))
        $totalBytes += [int64]$file.Length

        $extension = $file.Extension.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($extension)) {
            $extension = '<none>'
        }
        if (-not $extensionStats.ContainsKey($extension)) {
            $extensionStats[$extension] = [ordered]@{ count = [int64]0; bytes = [int64]0 }
        }
        $extensionStats[$extension].count++
        $extensionStats[$extension].bytes += [int64]$file.Length

        if ((($index + 1) % 1000) -eq 0) {
            Write-Output ("[{0}] hashed {1}/{2} files" -f $Name, ($index + 1), $files.Count)
        }
    }
}
finally {
    $writer.Dispose()
    $stopwatch.Stop()
}

Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force
$manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

$orderedExtensionStats = [ordered]@{}
foreach ($extension in ($extensionStats.Keys | Sort-Object)) {
    $orderedExtensionStats[$extension] = $extensionStats[$extension]
}

$summary = [ordered]@{
    schema_version = 1
    name = $Name
    source_root = $resolvedRoot
    product_version = $ProductVersion
    generated_utc = [DateTime]::UtcNow.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    elapsed_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    file_count = [int64]$files.Count
    total_bytes = $totalBytes
    files_manifest = [System.IO.Path]::GetFileName($manifestPath)
    files_manifest_sha256 = $manifestSha256
    skipped_reparse_points = $skippedReparsePoints
    extensions = $orderedExtensionStats
}

[System.IO.File]::WriteAllText(
    $summaryPath,
    (($summary | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"),
    $utf8NoBom
)

Write-Output ([ordered]@{
    name = $Name
    root = $resolvedRoot
    files = [int64]$files.Count
    bytes = $totalBytes
    manifest_sha256 = $manifestSha256
    elapsed_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
} | ConvertTo-Json -Compress)
