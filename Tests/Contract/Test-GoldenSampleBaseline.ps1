[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [switch]$VerifySourceFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Test-RelativePortablePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return -not [System.IO.Path]::IsPathRooted($Path) -and
        $Path -notmatch '(^|/)\.\.(/|$)' -and
        $Path -notmatch '\\'
}

function Resolve-SourcePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $candidate = [System.IO.Path]::GetFullPath(
        (Join-Path $client $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
    $prefix = $client + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes client root: $RelativePath"
    }
    return $candidate
}

$selectionPath = Join-Path $root 'Data\GoldenSamples\p0-golden-selection.json'
$baselinePath = Join-Path $root 'Data\GoldenSamples\p0-golden-samples.json'
$manifestPath = Join-Path $root 'Data\RawManifests\client-3.0.0.413.files.jsonl'
foreach ($required in @($selectionPath, $baselinePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        Add-Failure -Message "Required golden-sample input is missing: $required"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$selection = Get-Content -LiteralPath $selectionPath -Raw | ConvertFrom-Json
$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
if ([int]$selection.schema_version -ne 1 -or [int]$baseline.schema_version -ne 1) {
    Add-Failure -Message 'Golden-sample schema version must be 1.'
}
if ([string]$selection.copy_policy -ne 'reference_only' -or
    [string]$baseline.copy_policy -ne 'reference_only') {
    Add-Failure -Message 'Golden samples must remain reference-only.'
}

$manifestAvailable = Test-Path -LiteralPath $manifestPath -PathType Leaf
if ([string]$selection.manifest_sha256 -ne [string]$baseline.manifest.sha256) {
    Add-Failure -Message 'Selection and baseline frozen Manifest hashes differ.'
}
if ($manifestAvailable) {
    $manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($manifestSha -ne [string]$selection.manifest_sha256) {
        Add-Failure -Message 'Available frozen Manifest hash does not match the selection.'
    }
}
elseif ($VerifySourceFiles) {
    Add-Failure -Message 'Source verification requires the local frozen Manifest.'
}
$selectionSha = (Get-FileHash -LiteralPath $selectionPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($selectionSha -ne [string]$baseline.selection.sha256) {
    Add-Failure -Message 'Generated baseline is stale relative to the reviewed selection.'
}

$selectionIds = @($selection.samples | ForEach-Object { [string]$_.id })
$selectionPaths = @($selection.samples | ForEach-Object { [string]$_.path })
$baselineIds = @($baseline.samples | ForEach-Object { [string]$_.id })
if (@($selectionIds | Sort-Object -Unique).Count -ne $selectionIds.Count) {
    Add-Failure -Message 'Selection contains duplicate sample ids.'
}
if (@($selectionPaths | Sort-Object -Unique).Count -ne $selectionPaths.Count) {
    Add-Failure -Message 'Selection contains duplicate sample paths.'
}
if ($selectionIds.Count -ne $baselineIds.Count -or
    @(Compare-Object $selectionIds $baselineIds).Count -ne 0) {
    Add-Failure -Message 'Selection and generated baseline sample ids differ.'
}

$requiredKinds = @(
    'package', 'table', 'texture', 'static_mesh', 'skeletal_mesh',
    'animation', 'terrain', 'navigation', 'audio')
$observedKinds = @($baseline.samples | ForEach-Object { [string]$_.kind } | Sort-Object -Unique)
foreach ($kind in $requiredKinds) {
    if ($observedKinds -notcontains $kind) { Add-Failure -Message "Required sample kind is absent: $kind" }
}

$requiredRoles = @(
    'package_version_1', 'package_version_2', 'package_version_3',
    'zero_length_boundary', 'transparent_candidate', 'multi_material_candidate',
    'multi_bone_candidate', 'adjacent_terrain_tiles', 'scene_candidate',
    'table_simple', 'table_complex', 'asset_global_minimum', 'asset_global_maximum')
$roles = @($baseline.samples | ForEach-Object { @($_.roles) } | Sort-Object -Unique)
foreach ($role in $requiredRoles) {
    if ($roles -notcontains $role) { Add-Failure -Message "Required sample role is absent: $role" }
}

$semanticCandidateRoles = @('transparent_candidate', 'multi_material_candidate', 'multi_bone_candidate')
foreach ($sample in $baseline.samples) {
    $path = [string]$sample.path
    if (-not (Test-RelativePortablePath -Path $path)) {
        Add-Failure -Message "Sample path is not portable and relative: $path"
    }
    if ([string]$sample.sha256 -notmatch '^[a-f0-9]{64}$' -or [int64]$sample.size -lt 0) {
        Add-Failure -Message "Sample integrity metadata is invalid: $path"
    }
    $candidateRoles = @($sample.roles | Where-Object { $_ -in $semanticCandidateRoles })
    if ($candidateRoles.Count -gt 0 -and [string]$sample.evidence_level -ne 'L4') {
        Add-Failure -Message "Unconfirmed semantic candidate must remain L4: $path"
    }
    if (-not [bool]$sample.source_verified) {
        Add-Failure -Message "Generated sample was not source-verified: $path"
    }
}

$inventory = $baseline.summary.package_inventory
$expectedPackageCounts = [ordered]@{ '1.0' = 1; '2.0' = 22; '3.0' = 140; empty = 1; unknown = 3 }
$packageTotal = 0
foreach ($key in $expectedPackageCounts.Keys) {
    $actual = [int]$inventory.version_counts.$key
    $packageTotal += $actual
    if ($actual -ne $expectedPackageCounts[$key]) {
        Add-Failure -Message "Package $key count is $actual; expected $($expectedPackageCounts[$key])."
    }
}
if ([int]$inventory.scanned_file_count -ne $packageTotal -or $packageTotal -ne 167) {
    Add-Failure -Message 'Package inventory total must remain 167 files.'
}

$terrainAdjacent = @($baseline.samples | Where-Object { $_.roles -contains 'adjacent_terrain_tiles' })
if ($terrainAdjacent.Count -lt 3) {
    Add-Failure -Message 'At least three adjacent terrain samples are required.'
}

$forbiddenPayloadExtensions = @('.anim', '.ecf', '.mp3', '.qtx', '.skem', '.sm', '.tbl', '.ter', '.wav', '.zif')
$unexpectedPayloads = @(Get-ChildItem -LiteralPath (Join-Path $root 'Data\GoldenSamples') -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in $forbiddenPayloadExtensions })
if ($unexpectedPayloads.Count -gt 0) {
    Add-Failure -Message 'GoldenSamples contains copied legacy payloads instead of metadata references.'
}

$verifiedFiles = 0
if ($VerifySourceFiles) {
    if (-not (Test-Path -LiteralPath $client -PathType Container)) {
        Add-Failure -Message 'Source verification requires the read-only client root.'
    }
    foreach ($sample in $baseline.samples) {
        $sourcePath = Resolve-SourcePath -RelativePath ([string]$sample.path)
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Add-Failure -Message "Referenced source file is missing: $($sample.path)"
            continue
        }
        $file = Get-Item -LiteralPath $sourcePath
        $sha = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($file.Length -ne [int64]$sample.size -or $sha -ne [string]$sample.sha256) {
            Add-Failure -Message "Referenced source file differs from baseline: $($sample.path)"
        }
        $verifiedFiles++
    }
}

$report = [pscustomobject][ordered]@{
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    sample_count = @($baseline.samples).Count
    required_kind_count = $requiredKinds.Count
    required_role_count = $requiredRoles.Count
    manifest_file_verified = $manifestAvailable
    source_files_verified = $verifiedFiles
    copy_policy = [string]$baseline.copy_policy
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 4
if ($failures.Count -gt 0) {
    throw "Golden-sample baseline validation failed with $($failures.Count) error(s)."
}
