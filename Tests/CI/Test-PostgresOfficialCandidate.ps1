[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$toolPath = Join-Path $root 'Tools\TMXY.SupplyChain\Test-PostgresOfficialCandidate.ps1'
$dispositionPath = Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$composePath = Join-Path $root 'Deploy\compose\compose.yaml'
$preflightPath = Join-Path $root 'Data\Security\p0-12-postgres-refresh-preflight.json'
$boundPaths = @($dispositionPath, $lockPath, $composePath, $preflightPath)
$failures = [Collections.Generic.List[string]]::new()

function Assert-CandidateTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { $failures.Add($Message) }
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    $json = ($Value | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
    throw "PostgreSQL official candidate evaluation tool is missing: $toolPath"
}
$beforeHashes = @($boundPaths | ForEach-Object {
        (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
    })
$disposition = Get-Content -LiteralPath $dispositionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$lockedReference = [string]$lock.database.development_image.digest_reference
$lockedDigest = [string]$disposition.component.locked_index_digest
$candidateDigest = 'sha256:' + ('f' * 64)
$candidateReference = "postgres@$candidateDigest"
$candidateTag = '18.6-alpine3.23'
$gosuSha = '1' * 64
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'tmxy-postgres-candidate-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $observation = [pscustomobject][ordered]@{
        name = $candidateTag
        digest = $candidateDigest
        last_updated = '2026-08-27T01:00:00Z'
        images = @([pscustomobject][ordered]@{
                architecture = 'amd64'
                os = 'linux'
                digest = 'sha256:' + ('e' * 64)
            })
    }
    $lockedProbe = [pscustomobject][ordered]@{
        image_reference = $lockedReference
        image_id = $lockedDigest
        platform = 'linux/amd64'
        base_distribution = 'alpine'
        base_version = '3.24.1'
        postgres_version = '18.6'
        gosu_version = '1.19'
        gosu_build = 'go1.24.6 on linux/amd64; gc'
        gosu_sha256 = $gosuSha
    }
    $identicalProbe = [pscustomobject][ordered]@{
        image_reference = $candidateReference
        image_id = $candidateDigest
        platform = 'linux/amd64'
        base_distribution = 'alpine'
        base_version = '3.23.5'
        postgres_version = '18.6'
        gosu_version = '1.19'
        gosu_build = 'go1.24.6 on linux/amd64; gc'
        gosu_sha256 = $gosuSha
    }
    Write-JsonFixture -Path (Join-Path $testRoot 'observation.json') -Value $observation
    Write-JsonFixture -Path (Join-Path $testRoot 'locked.json') -Value $lockedProbe
    Write-JsonFixture -Path (Join-Path $testRoot 'identical.json') -Value $identicalProbe

    $identicalOutput = Join-Path $testRoot 'identical-output.json'
    $identical = (& $toolPath -RebuildRoot $root -CandidateTag $candidateTag `
            -CandidateReference $candidateReference `
            -CandidateObservationPath (Join-Path $testRoot 'observation.json') `
            -LockedProbePath (Join-Path $testRoot 'locked.json') `
            -CandidateProbePath (Join-Path $testRoot 'identical.json') `
            -OutputPath $identicalOutput) | ConvertFrom-Json
    Assert-CandidateTest ([string]$identical.result -eq 'PASS_DIAGNOSTIC' -and
        [string]$identical.decision.status -eq 'REJECTED_IDENTICAL_BLOCKING_COMPONENT') `
        'An official candidate with identical gosu bytes must be rejected.'
    Assert-CandidateTest ([bool]$identical.security_inference.candidate_inherits_recorded_blocker -and
        [int]$identical.security_inference.inherited_high_or_critical -eq
            [int]$disposition.blocking_findings.total -and
        -not [bool]$identical.security_inference.candidate_scan_claimed) `
        'Identical bytes must inherit the recorded blocker without claiming a new scan.'
    Assert-CandidateTest (-not [bool]$identical.release_authority -and
        -not [bool]$identical.decision.lock_update_performed -and
        -not [bool]$identical.decision.automatic_lock_update_allowed) `
        'Candidate evaluation must never mutate the lock or grant authority.'

    $changedProbe = $identicalProbe.PSObject.Copy()
    $changedProbe.gosu_build = 'go1.25.1 on linux/amd64; gc'
    $changedProbe.gosu_sha256 = '2' * 64
    Write-JsonFixture -Path (Join-Path $testRoot 'changed.json') -Value $changedProbe
    $changed = (& $toolPath -RebuildRoot $root -CandidateTag $candidateTag `
            -CandidateReference $candidateReference `
            -CandidateObservationPath (Join-Path $testRoot 'observation.json') `
            -LockedProbePath (Join-Path $testRoot 'locked.json') `
            -CandidateProbePath (Join-Path $testRoot 'changed.json') `
            -OutputPath (Join-Path $testRoot 'changed-output.json')) | ConvertFrom-Json
    Assert-CandidateTest ([string]$changed.decision.status -eq
        'CANDIDATE_REQUIRES_HOSTED_QUALIFICATION' -and
        -not [bool]$changed.security_inference.candidate_inherits_recorded_blocker) `
        'Changed gosu bytes must require hosted qualification rather than automatic acceptance.'

    $invalidProbe = $identicalProbe.PSObject.Copy()
    $invalidProbe.gosu_sha256 = 'not-a-sha'
    Write-JsonFixture -Path (Join-Path $testRoot 'invalid.json') -Value $invalidProbe
    $invalidOutput = Join-Path $testRoot 'invalid-output.json'
    $invalidRejected = $false
    try {
        $null = & $toolPath -RebuildRoot $root -CandidateTag $candidateTag `
            -CandidateReference $candidateReference `
            -CandidateObservationPath (Join-Path $testRoot 'observation.json') `
            -LockedProbePath (Join-Path $testRoot 'locked.json') `
            -CandidateProbePath (Join-Path $testRoot 'invalid.json') `
            -OutputPath $invalidOutput 2>$null
    }
    catch { $invalidRejected = $true }
    $invalid = Get-Content -LiteralPath $invalidOutput -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-CandidateTest ($invalidRejected -and [string]$invalid.result -eq 'FAIL' -and
        [string]$invalid.decision.status -eq 'EVALUATION_FAILED_CLOSED') `
        'Malformed candidate probe evidence must fail closed with a machine-readable report.'

    $afterHashes = @($boundPaths | ForEach-Object {
            (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    Assert-CandidateTest (($beforeHashes -join ',') -eq ($afterHashes -join ',')) `
        'Candidate regression tests must not modify bound disposition, lock, compose, or preflight files.'
}
catch { $failures.Add("PostgreSQL official candidate regression failed: $($_.Exception.Message)") }
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
if ($failures.Count -gt 0) { throw 'PostgreSQL official candidate regression failed.' }
