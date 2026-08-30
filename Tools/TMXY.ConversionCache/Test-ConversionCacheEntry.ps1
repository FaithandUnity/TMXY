[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$ArtifactRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$plan = [IO.Path]::GetFullPath($PlanPath)
$manifest = [IO.Path]::GetFullPath($ManifestPath)
$artifacts = [IO.Path]::GetFullPath($ArtifactRoot).TrimEnd([char[]]'\/')
foreach ($path in @($plan, $manifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Cache input missing: $path" }
}
if (-not (Test-Path -LiteralPath $artifacts -PathType Container)) {
    throw "Cache artifact root missing: $artifacts"
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$entries = @{}
$duplicates = 0
foreach ($line in [IO.File]::ReadLines($manifest)) {
    $entry = $line | ConvertFrom-Json
    if ([string]$entry.record -ne 'conversion_cache_artifact') { continue }
    $key = [string]$entry.cache_key
    if ($entries.ContainsKey($key)) { ++$duplicates; continue }
    $entries[$key] = $entry
}

$hits = 0
$misses = 0
$corrupt = 0
$blocked = 0
$aliases = 0
$readyJobs = 0
$artifactPrefix = $artifacts + [IO.Path]::DirectorySeparatorChar
foreach ($line in [IO.File]::ReadLines($plan)) {
    $item = $line | ConvertFrom-Json
    if ([string]$item.record -ne 'conversion_cache_plan') { continue }
    if ([string]$item.state -eq 'blocked-manual-input') { ++$blocked; continue }
    if ([string]$item.state -eq 'alias') { ++$aliases; continue }
    ++$readyJobs
    $key = [string]$item.cache_key
    if (-not $entries.ContainsKey($key)) { ++$misses; continue }
    $candidate = $entries[$key]
    $relative = [string]$candidate.artifact
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains('..')) {
        ++$corrupt
        continue
    }
    $artifact = [IO.Path]::GetFullPath((Join-Path $artifacts $relative))
    if (-not $artifact.StartsWith($artifactPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $artifact -PathType Leaf) -or
        (Get-Item -LiteralPath $artifact).Length -ne [int64]$candidate.bytes -or
        (Get-Sha256 $artifact) -ne [string]$candidate.sha256) {
        ++$corrupt
        continue
    }
    ++$hits
}

$result = $duplicates -eq 0 -and $corrupt -eq 0
[pscustomobject][ordered]@{
    schema_version = 1
    result = if ($result) { 'PASS' } else { 'FAIL' }
    ready_jobs = $readyJobs
    verified_hits = $hits
    misses = $misses
    corrupt = $corrupt
    blocked_manual_jobs = $blocked
    aliases = $aliases
    duplicate_manifest_keys = $duplicates
    output_sha256_verified = $hits
    untrusted_shared_cache_write = $false
} | ConvertTo-Json -Depth 5
if (-not $result) { exit 1 }
