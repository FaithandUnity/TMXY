[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$toolPath = Join-Path $root 'Tools\TMXY.SupplyChain\Test-PostgresRefreshPreflight.ps1'
$boundPaths = @(
    (Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'),
    (Join-Path $root 'Data\Toolchain\toolchain.lock.json'),
    (Join-Path $root 'Deploy\compose\compose.yaml')
)
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-PreflightTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { $failures.Add($Message) }
}

if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
    throw "PostgreSQL refresh preflight tool is missing: $toolPath"
}
$beforeHashes = @($boundPaths | ForEach-Object {
        (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
    })
$disposition = Get-Content -LiteralPath $boundPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
$tag = ([string]$disposition.component.image_reference).Substring('postgres:'.Length)
$lockedDigest = [string]$disposition.component.locked_index_digest
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'tmxy-postgres-refresh-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $commonImage = [pscustomobject][ordered]@{
        architecture = 'amd64'
        os = 'linux'
        digest = ('sha256:' + ('a' * 64))
    }
    $fixtures = @{
        current = [pscustomobject][ordered]@{
            name = $tag
            digest = $lockedDigest
            last_updated = '2026-08-27T00:00:00Z'
            images = @($commonImage)
        }
        candidate = [pscustomobject][ordered]@{
            name = $tag
            digest = ('sha256:' + ('f' * 64))
            last_updated = '2026-08-28T00:00:00Z'
            images = @($commonImage)
        }
        invalid = [pscustomobject][ordered]@{
            name = $tag
            digest = 'latest'
            last_updated = 'not-a-timestamp'
            images = @()
        }
    }
    foreach ($entry in $fixtures.GetEnumerator()) {
        $path = Join-Path $testRoot "$($entry.Key).json"
        $text = ($entry.Value | ConvertTo-Json -Depth 5).Replace("`r`n", "`n") + "`n"
        [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    }

    $currentOutput = Join-Path $testRoot 'current-output.json'
    $current = (& $toolPath -RebuildRoot $root `
            -ObservationPath (Join-Path $testRoot 'current.json') `
            -OutputPath $currentOutput) | ConvertFrom-Json
    Assert-PreflightTest ([string]$current.result -eq 'PASS_DIAGNOSTIC') `
        'Unchanged official tag fixture must pass diagnostically.'
    Assert-PreflightTest (-not [bool]$current.observation.tag_manifest_changed -and
        [string]$current.decision.status -eq 'NO_REFRESH_AVAILABLE') `
        'Unchanged official tag fixture must preserve the current lock.'
    Assert-PreflightTest (-not [bool]$current.release_authority -and
        -not [bool]$current.decision.lock_update_performed -and
        -not [bool]$current.decision.automatic_lock_update_allowed) `
        'Preflight must never grant authority or update the lock.'

    $candidateOutput = Join-Path $testRoot 'candidate-output.json'
    $candidate = (& $toolPath -RebuildRoot $root `
            -ObservationPath (Join-Path $testRoot 'candidate.json') `
            -OutputPath $candidateOutput) | ConvertFrom-Json
    Assert-PreflightTest ([string]$candidate.result -eq 'PASS_DIAGNOSTIC' -and
        [bool]$candidate.observation.tag_manifest_changed) `
        'Changed official tag fixture must be recognized as a candidate.'
    Assert-PreflightTest (
        [string]$candidate.decision.status -eq
            'CANDIDATE_AVAILABLE_REQUIRES_FULL_QUALIFICATION' -and
        -not [bool]$candidate.decision.lock_update_performed) `
        'Changed tag fixture must require qualification without mutating the lock.'

    $invalidOutput = Join-Path $testRoot 'invalid-output.json'
    $invalidRejected = $false
    try {
        $null = & $toolPath -RebuildRoot $root `
            -ObservationPath (Join-Path $testRoot 'invalid.json') `
            -OutputPath $invalidOutput 2>$null
    }
    catch { $invalidRejected = $true }
    $invalid = Get-Content -LiteralPath $invalidOutput -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-PreflightTest ($invalidRejected -and [string]$invalid.result -eq 'FAIL' -and
        [string]$invalid.decision.status -eq 'OBSERVATION_FAILED_CLOSED') `
        'Malformed upstream data must produce machine-readable fail-closed evidence.'

    $afterHashes = @($boundPaths | ForEach-Object {
            (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    Assert-PreflightTest (($beforeHashes -join ',') -eq ($afterHashes -join ',')) `
        'Preflight regression tests must not modify the disposition, toolchain lock, or compose file.'
}
catch {
    $failures.Add("PostgreSQL refresh preflight regression failed: $($_.Exception.Message)")
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    fixture_count = 3
    source_mutation_performed = $false
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 5
if ($failures.Count -gt 0) { throw 'PostgreSQL refresh preflight regression failed.' }
