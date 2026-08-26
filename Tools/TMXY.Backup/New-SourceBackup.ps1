[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev',
    [string]$Label = 'current-results'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8Lf {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText(
        $Path,
        $normalized,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ZipEntrySha256 {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$Entry
    )

    $zipEntry = $Archive.GetEntry($Entry)
    if ($null -eq $zipEntry) {
        throw "Archive entry is missing: $Entry"
    }
    $stream = $zipEntry.Open()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($stream)
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
    return [System.Convert]::ToHexString($hashBytes).ToLowerInvariant()
}

if ($Label -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw 'Label must contain only ASCII letters, digits, dots, underscores, or hyphens.'
}

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$rebuild = [System.IO.Path]::GetFullPath((Join-Path $workspace 'Rebuild')).TrimEnd([char[]]'\/')
$backupRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $rebuild 'Data\Backups')
).TrimEnd([char[]]'\/')
$expectedBackupPrefix = $rebuild + [System.IO.Path]::DirectorySeparatorChar
if (-not $backupRoot.StartsWith(
        $expectedBackupPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'Backup root escaped Rebuild.'
}
if (-not (Test-Path -LiteralPath (Join-Path $rebuild '.git'))) {
    throw 'Rebuild is not an initialized Git repository.'
}
if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
}

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmssfff')
$backupName = "tmxy-rebuild-$Label-$stamp"
$archivePath = Join-Path $backupRoot "$backupName.zip"
$inputListPath = Join-Path $backupRoot "$backupName.inputs.txt"
$sourceHashPath = Join-Path $backupRoot "$backupName.files.sha256"
$archiveHashPath = Join-Path $backupRoot "$backupName.zip.sha256"
$manifestPath = Join-Path $backupRoot "$backupName.manifest.json"

$relativeInputs = [System.Collections.Generic.List[string]]::new()
$repoCandidates = @(
    & git -C $rebuild ls-files --cached --others --exclude-standard
)
if ($LASTEXITCODE -ne 0) {
    throw 'Git could not enumerate backup inputs.'
}
foreach ($relativePath in $repoCandidates) {
    $relativeInputs.Add('Rebuild/' + $relativePath.Replace('\', '/'))
}
$relativeInputs.Add('实施计划.md')
$relativeInputs.Add('实施计划表.md')

$gitFiles = Get-ChildItem -LiteralPath (Join-Path $rebuild '.git') -Recurse -File -Force
foreach ($file in $gitFiles) {
    $relativePath = $file.FullName.Substring($workspace.Length + 1).Replace('\', '/')
    $relativeInputs.Add($relativePath)
}
$inputs = @($relativeInputs | Sort-Object -Unique)

$hashRecords = [System.Collections.Generic.List[object]]::new()
$hashLines = [System.Collections.Generic.List[string]]::new()
$workspacePrefix = $workspace + [System.IO.Path]::DirectorySeparatorChar
foreach ($relativePath in $inputs) {
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $workspace $relativePath))
    if (-not $fullPath.StartsWith(
            $workspacePrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Input escaped workspace: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Backup input is missing: $relativePath"
    }

    $item = Get-Item -LiteralPath $fullPath
    $hash = Get-Sha256 -Path $fullPath
    $hashRecords.Add([pscustomobject][ordered]@{
        path = $relativePath
        bytes = [int64]$item.Length
        sha256 = $hash
    })
    $hashLines.Add("$hash  $relativePath")
}

Write-Utf8Lf -Path $inputListPath -Content (($inputs -join "`n") + "`n")
Write-Utf8Lf -Path $sourceHashPath -Content (($hashLines -join "`n") + "`n")

$archiveStream = [System.IO.File]::Open(
    $archivePath,
    [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
)
$archive = [System.IO.Compression.ZipArchive]::new(
    $archiveStream,
    [System.IO.Compression.ZipArchiveMode]::Create,
    $false,
    [System.Text.Encoding]::UTF8
)
try {
    foreach ($record in $hashRecords) {
        $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $workspace $record.path))
        $entry = $archive.CreateEntry(
            $record.path,
            [System.IO.Compression.CompressionLevel]::Optimal
        )
        $sourceStream = [System.IO.File]::OpenRead($sourcePath)
        $entryStream = $entry.Open()
        try {
            $sourceStream.CopyTo($entryStream)
        }
        finally {
            $entryStream.Dispose()
            $sourceStream.Dispose()
        }
    }
}
finally {
    $archive.Dispose()
    $archiveStream.Dispose()
}

$verificationFailures = [System.Collections.Generic.List[string]]::new()
$verificationArchive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($record in $hashRecords) {
        $entryHash = Get-ZipEntrySha256 `
            -Archive $verificationArchive `
            -Entry $record.path
        if ($entryHash -ne $record.sha256) {
            $verificationFailures.Add("Hash mismatch: $($record.path)")
        }
    }
}
finally {
    $verificationArchive.Dispose()
}
if ($verificationFailures.Count -gt 0) {
    throw "Backup verification failed: $($verificationFailures -join '; ')"
}

$archiveItem = Get-Item -LiteralPath $archivePath
$archiveHash = Get-Sha256 -Path $archivePath
$sourceManifestHash = Get-Sha256 -Path $sourceHashPath
Write-Utf8Lf `
    -Path $archiveHashPath `
    -Content "$archiveHash  $($archiveItem.Name)`n"

$headExists = $true
& git -C $rebuild rev-parse --verify HEAD 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $headExists = $false }
$name = & git config --get user.name
$nameExit = $LASTEXITCODE
$email = & git config --get user.email
$emailExit = $LASTEXITCODE
$backend = Get-Content `
    -LiteralPath (Join-Path $rebuild 'Data\BuildBaseline\p0-10-validation.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$ue = Get-Content `
    -LiteralPath (Join-Path $rebuild 'Data\BuildBaseline\p0-10a-ue-validation.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json

$manifest = [pscustomobject][ordered]@{
    schema_version = 1
    backup_name = $backupName
    created_local = (Get-Date).ToString('o')
    created_utc = [DateTimeOffset]::UtcNow.ToString('o')
    workspace_root = $workspace
    archive = [pscustomobject][ordered]@{
        file = $archiveItem.Name
        bytes = [int64]$archiveItem.Length
        sha256 = $archiveHash
        format = 'zip'
    }
    contents = [pscustomobject][ordered]@{
        file_count = $hashRecords.Count
        files_sha256_file = Split-Path -Leaf $sourceHashPath
        files_sha256 = $sourceManifestHash
        includes_git_metadata = $true
        includes_root_plans = $true
    }
    repository = [pscustomobject][ordered]@{
        root = $rebuild
        branch = & git -C $rebuild branch --show-current
        head_exists = $headExists
        remotes = @(& git -C $rebuild remote)
        user_name_configured = $nameExit -eq 0 -and
            -not [string]::IsNullOrWhiteSpace(($name -join ''))
        user_email_configured = $emailExit -eq 0 -and
            -not [string]::IsNullOrWhiteSpace(($email -join ''))
    }
    validation = [pscustomobject][ordered]@{
        backend = $backend.result
        backend_build = [bool]$backend.build.passed
        ue = $ue.result
        ue_editor_build = [bool]$ue.editor_build.passed
        ue_automation = [bool]$ue.automation.passed
        ue_module_loaded = [bool]$ue.automation.module_loaded
        ue_asset_count = [int]$ue.project.cooked_asset_count
    }
    excluded = @(
        'UE Binaries/Intermediate/Saved/DerivedDataCache/.vs',
        'generated solutions',
        'CMake build and machine caches',
        'raw manifests with local absolute paths',
        'bulk extracted/exported/generated assets',
        'Data/Backups output directory'
    )
    verification = [pscustomobject][ordered]@{
        archive_entries_read = $true
        verified_file_count = $hashRecords.Count
        hash_mismatch_count = 0
    }
}
$manifestJson = $manifest | ConvertTo-Json -Depth 8
Write-Utf8Lf -Path $manifestPath -Content ($manifestJson + "`n")

[pscustomobject][ordered]@{
    archive = $archivePath
    archive_bytes = [int64]$archiveItem.Length
    archive_sha256 = $archiveHash
    included_files = $hashRecords.Count
    verification = 'PASS'
    manifest = $manifestPath
    files_sha256 = $sourceHashPath
    archive_sha256_file = $archiveHashPath
}
