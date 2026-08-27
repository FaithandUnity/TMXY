[CmdletBinding()]
param(
    [string]$ScanRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ReportPath = '',
    [switch]$SkipGitHistory,
    [switch]$NoThrow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($ScanRoot).TrimEnd([char[]]'\/')
$findings = [System.Collections.Generic.List[object]]::new()
$scannedWorkingFiles = 0
$scannedHistoryBlobs = 0

function Get-Fingerprint {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($sha).ToLowerInvariant().Substring(0, 16)
}

function Get-ShannonEntropy {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value.Length -eq 0) { return 0.0 }
    $counts = @{}
    foreach ($character in $Value.ToCharArray()) {
        $counts[$character] = 1 + [int]($counts[$character] ?? 0)
    }
    $entropy = 0.0
    foreach ($count in $counts.Values) {
        $probability = [double]$count / [double]$Value.Length
        $entropy -= $probability * [Math]::Log($probability, 2)
    }
    return $entropy
}

function Test-AllowlistedValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    $normalized = $Value.Trim('"', "'", ' ').ToLowerInvariant()
    if ($normalized -match '^(?:true|false|null|none|redacted|masked|unset)$') { return $true }
    if ($normalized -match '(?:example|placeholder|dummy|not-a-secret|validation-only|changeme)') { return $true }
    if ($normalized -match '^\$|^<.*>$|^\{\{.*\}\}$') { return $true }
    return $false
}

function Add-Finding {
    param(
        [Parameter(Mandatory = $true)][string]$Rule,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$Line,
        [Parameter(Mandatory = $true)][string]$Origin,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $findings.Add([pscustomobject][ordered]@{
        rule = $Rule
        path = $Path.Replace('\', '/')
        line = $Line
        origin = $Origin
        fingerprint = Get-Fingerprint -Value $Value
    })
}

function Test-ContentForSecrets {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Origin
    )

    $knownPatterns = [ordered]@{
        private_key = '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
        aws_access_key = '(?<![A-Z0-9])AKIA[A-Z0-9]{16}(?![A-Z0-9])'
        github_token = '(?<![A-Za-z0-9])gh[pousr]_[A-Za-z0-9]{36,}(?![A-Za-z0-9])'
        slack_token = '(?<![A-Za-z0-9])xox[baprs]-[A-Za-z0-9-]{20,}(?![A-Za-z0-9])'
        jwt = '(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
        credential_url = '(?i)[a-z][a-z0-9+.-]*://[^:/\s]+:[^@/\s]{4,}@'
    }
    $lines = $Content -split "`n"
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        foreach ($entry in $knownPatterns.GetEnumerator()) {
            foreach ($match in [regex]::Matches($line, $entry.Value)) {
                Add-Finding -Rule $entry.Key -Path $Path -Line ($index + 1) -Origin $Origin -Value $match.Value
            }
        }

        $assignmentPattern = '(?i)(?<![$A-Za-z0-9_])(?:password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|securitytoken|client[_-]?secret|authorization|cookie)\b\s*[:=]\s*["'']?([^"''\s,;}{]{8,})'
        foreach ($match in [regex]::Matches($line, $assignmentPattern)) {
            $value = $match.Groups[1].Value
            $isScannerRuleDeclaration = $Path -eq 'Tools/TMXY.Security/Test-RepositorySecrets.ps1' -and
                $line -match '^\s*private_key\s*='
            if (-not $isScannerRuleDeclaration -and -not (Test-AllowlistedValue -Value $value)) {
                Add-Finding -Rule 'literal_assignment' -Path $Path -Line ($index + 1) -Origin $Origin -Value $value
            }
        }

        $entropyPattern = '(?<![A-Za-z0-9])([A-Za-z0-9+/_=-]{32,})(?![A-Za-z0-9])'
        foreach ($match in [regex]::Matches($line, $entropyPattern)) {
            $value = $match.Groups[1].Value
            $isDigest = $value -match '^[a-fA-F0-9]{40,128}$' -or
                $value -match '(?i)^(?:[a-z0-9_.-]*(?:commit|revision|sha256))=[a-f0-9]{40,128}$'
            $isPathContext = $line -match '(?i)"(?:path|file|directory|source|target|cache_path|log_path|generated_log|archive|[a-z0-9_-]+_(?:path|source))"\s*:' -or
                $line -match '^\s*["''][^"'']*[\/][^"'']*["'']\s*,?\s*$' -or
                $line -match '(?i)^\s*(?:path|source|[a-z][a-z0-9_]*(?:path|source))\s*=\s*["''][^"'']*[\/][^"'']*["'']\s*$'
            $isSbomComponentPathName = $Path -match '(?i)\.sbom\.cdx\.json$' -and
                $line -match '^\s*"name"\s*:\s*"[^"\r\n]*[\/][^"\r\n]*"\s*,?\s*$'
            $hasClasses = $value -cmatch '[A-Z]' -and $value -cmatch '[a-z]' -and $value -match '[0-9]'
            if (-not $isDigest -and -not $isPathContext -and -not $isSbomComponentPathName -and $hasClasses -and
                (Get-ShannonEntropy -Value $value) -ge 4.5 -and
                -not (Test-AllowlistedValue -Value $value)) {
                Add-Finding -Rule 'high_entropy_token' -Path $Path -Line ($index + 1) -Origin $Origin -Value $value
            }
        }
    }
}

function Test-TextCandidate {
    param([Parameter(Mandatory = $true)][string]$Path)
    $name = [System.IO.Path]::GetFileName($Path)
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    return $extension -in @(
        '.c', '.cc', '.cmake', '.cpp', '.cs', '.h', '.hpp', '.ini', '.json',
        '.jsonl', '.md', '.proto', '.ps1', '.sql', '.txt', '.uplugin', '.uproject', '.yaml', '.yml') -or
        $name -in @('CMakeLists.txt', '.clang-format', '.clang-tidy', '.editorconfig', '.gitattributes', '.gitignore')
}

function Get-WorkingFiles {
    param([Parameter(Mandatory = $true)][string]$Root)
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
        $files = @(& git -C $Root ls-files --cached --others --exclude-standard)
        if ($LASTEXITCODE -ne 0) { throw 'Git could not enumerate repository candidate files.' }
        return @($files | ForEach-Object { Join-Path $Root $_ })
    }
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object { $_.FullName })
}

foreach ($file in @(Get-WorkingFiles -Root $root)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or -not (Test-TextCandidate -Path $file)) { continue }
    $relative = [System.IO.Path]::GetRelativePath($root, $file).Replace('\', '/')
    $content = Get-Content -LiteralPath $file -Raw
    Test-ContentForSecrets -Content $content -Path $relative -Origin 'working_tree'
    $scannedWorkingFiles++
}

$historyMode = 'skipped'
if (-not $SkipGitHistory -and (Test-Path -LiteralPath (Join-Path $root '.git'))) {
    $commits = @(& git -C $root rev-list --all)
    if ($LASTEXITCODE -ne 0) { throw 'Git history enumeration failed.' }
    $historyMode = if ($commits.Count -eq 0) { 'no_commits' } else { 'all_reachable_blobs' }
    $seenBlobs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($commit in $commits) {
        $entries = @(& git -C $root ls-tree -r --format='%(objectname) %(path)' $commit)
        foreach ($entry in $entries) {
            if ($entry -notmatch '^([a-f0-9]{40,64}) (.+)$') { continue }
            $blob = $Matches[1]
            $path = $Matches[2]
            if (-not $seenBlobs.Add($blob) -or -not (Test-TextCandidate -Path $path)) { continue }
            $size = [int64](& git -C $root cat-file -s $blob)
            if ($LASTEXITCODE -ne 0 -or $size -gt 2MB) { continue }
            $content = (& git -C $root cat-file blob $blob) -join "`n"
            Test-ContentForSecrets -Content $content -Path $path -Origin "history:$($blob.Substring(0, 12))"
            $scannedHistoryBlobs++
        }
    }
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($findings.Count -eq 0) { 'PASS' } else { 'FAIL' }
    scan_root_kind = if (Test-Path -LiteralPath (Join-Path $root '.git')) { 'git_repository' } else { 'directory' }
    working_tree_files_scanned = $scannedWorkingFiles
    history_mode = $historyMode
    history_blobs_scanned = $scannedHistoryBlobs
    finding_count = $findings.Count
    findings = @($findings)
    disclosure_policy = 'fingerprints_only'
}
$json = ($report | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
if ($ReportPath) {
    $fullReportPath = [System.IO.Path]::GetFullPath($ReportPath)
    $reportDirectory = Split-Path -Parent $fullReportPath
    if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($fullReportPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}
$json
if ($findings.Count -gt 0 -and -not $NoThrow) {
    throw "Secret scan failed with $($findings.Count) redacted finding(s)."
}
