[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [Parameter(Mandatory = $true)][string]$CandidateTag,
    [Parameter(Mandatory = $true)][string]$CandidateReference,
    [string]$CandidateObservationPath = '',
    [string]$LockedProbePath = '',
    [string]$CandidateProbePath = '',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-postgres-official-candidate-evaluation.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$dispositionPath = Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$composePath = Join-Path $root 'Deploy\compose\compose.yaml'
$preflightPath = Join-Path $root 'Data\Security\p0-12-postgres-refresh-preflight.json'
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Required binding file is missing: $Path"
        return ''
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-ProbeFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Role
    )
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Role probe fixture does not exist: $resolved"
    }
    return Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-LocalImageProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Reference,
        [Parameter(Mandatory = $true)][string]$ExpectedDigest,
        [Parameter(Mandatory = $true)][string]$Role
    )
    $inspectText = (& docker image inspect $Reference --format '{{json .}}' 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($inspectText)) {
        throw "$Role image is not present locally at the immutable reference: $Reference"
    }
    $inspect = $inspectText | ConvertFrom-Json
    if ([string]$inspect.Id -ne $ExpectedDigest) {
        throw "$Role local image ID does not match the expected immutable digest."
    }
    if ([string]$inspect.Os -ne 'linux' -or [string]$inspect.Architecture -ne 'amd64') {
        throw "$Role image must be linux/amd64."
    }

    $script = @'
set -eu
cat /etc/alpine-release
postgres --version
gosu --version
sha256sum /usr/local/bin/gosu
'@
    $lines = @(& docker run --rm --entrypoint /bin/sh $Reference -c $script 2>&1)
    if ($LASTEXITCODE -ne 0 -or $lines.Count -ne 4) {
        throw "$Role isolated component probe failed or returned an unexpected shape."
    }
    $postgresMatch = [regex]::Match([string]$lines[1], 'PostgreSQL\)\s*(?<version>[0-9]+(?:\.[0-9]+)*)$')
    $gosuMatch = [regex]::Match([string]$lines[2], '^(?<version>\S+)\s+\((?<build>.+)\)$')
    $shaMatch = [regex]::Match([string]$lines[3], '^(?<sha>[a-f0-9]{64})\s+/usr/local/bin/gosu$')
    if (-not $postgresMatch.Success -or -not $gosuMatch.Success -or -not $shaMatch.Success) {
        throw "$Role isolated component probe output could not be parsed."
    }
    return [pscustomobject][ordered]@{
        image_reference = $Reference
        image_id = [string]$inspect.Id
        platform = 'linux/amd64'
        base_distribution = 'alpine'
        base_version = [string]$lines[0]
        postgres_version = $postgresMatch.Groups['version'].Value
        gosu_version = $gosuMatch.Groups['version'].Value
        gosu_build = $gosuMatch.Groups['build'].Value
        gosu_sha256 = $shaMatch.Groups['sha'].Value
    }
}

function Test-Probe {
    param(
        [Parameter(Mandatory = $true)][object]$Probe,
        [Parameter(Mandatory = $true)][string]$ExpectedReference,
        [Parameter(Mandatory = $true)][string]$ExpectedDigest,
        [Parameter(Mandatory = $true)][string]$Role
    )
    if ([string]$Probe.image_reference -ne $ExpectedReference) {
        Add-Failure "$Role probe reference does not match the requested immutable reference."
    }
    if ([string]$Probe.image_id -ne $ExpectedDigest) {
        Add-Failure "$Role probe image ID does not match the requested immutable digest."
    }
    if ([string]$Probe.platform -ne 'linux/amd64' -or
        [string]$Probe.base_distribution -ne 'alpine') {
        Add-Failure "$Role probe does not describe the required linux/amd64 Alpine image."
    }
    if ([string]$Probe.base_version -notmatch '^[0-9]+\.[0-9]+(?:\.[0-9]+)?$') {
        Add-Failure "$Role probe Alpine version is invalid."
    }
    if ([string]$Probe.postgres_version -notmatch '^[0-9]+(?:\.[0-9]+)+$') {
        Add-Failure "$Role probe PostgreSQL version is invalid."
    }
    if ([string]$Probe.gosu_version -notmatch '^[0-9]+(?:\.[0-9]+)+$' -or
        [string]$Probe.gosu_build -notmatch '^go[0-9]+(?:\.[0-9]+)+ on linux/amd64; .+$' -or
        [string]$Probe.gosu_sha256 -notmatch '^[a-f0-9]{64}$') {
        Add-Failure "$Role probe gosu identity is invalid."
    }
}

$bindingPaths = [ordered]@{
    vulnerability_disposition = $dispositionPath
    toolchain_lock = $lockPath
    compose = $composePath
    refresh_preflight = $preflightPath
}
$bindingHashes = [ordered]@{}
foreach ($entry in $bindingPaths.GetEnumerator()) {
    $bindingHashes[$entry.Key] = Get-Sha256 -Path $entry.Value
}

$disposition = $null
$lock = $null
$compose = ''
try {
    $disposition = Get-Content -LiteralPath $dispositionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $compose = Get-Content -LiteralPath $composePath -Raw -Encoding UTF8
}
catch { Add-Failure "Could not parse a required binding file: $($_.Exception.Message)" }

$lockedReference = ''
$lockedDigest = ''
$blockingCount = 0
$blockingIds = @()
if ($null -ne $disposition -and $null -ne $lock) {
    $lockedReference = [string]$lock.database.development_image.digest_reference
    $lockedDigest = [string]$disposition.component.locked_index_digest
    $blockingCount = [int]$disposition.blocking_findings.total
    $blockingIds = @($disposition.blocking_findings.vulnerability_ids | ForEach-Object { [string]$_ })
    if ([string]$disposition.component.embedding_binary -ne 'gosu' -or
        [string]$disposition.component.affected_package -ne 'stdlib' -or $blockingCount -le 0) {
        Add-Failure 'The bound disposition does not identify an unresolved gosu Go stdlib blocker.'
    }
    if ([string]$lock.database.development_image.image_id -ne $lockedDigest -or
        -not $lockedReference.EndsWith("@$lockedDigest", [StringComparison]::Ordinal)) {
        Add-Failure 'The toolchain lock and vulnerability disposition use different PostgreSQL digests.'
    }
    if (-not $compose.Contains("postgres@$lockedDigest")) {
        Add-Failure 'Compose is not bound to the locked PostgreSQL digest.'
    }
}

if ($CandidateTag -notmatch '^[0-9]+(?:\.[0-9]+)*-alpine(?:[0-9]+\.[0-9]+)?$') {
    Add-Failure 'Candidate tag is not an allowed official PostgreSQL Alpine tag.'
}
$candidateDigest = ''
if ($CandidateReference -match '^postgres@(?<digest>sha256:[a-f0-9]{64})$') {
    $candidateDigest = $Matches.digest
}
else { Add-Failure 'Candidate reference must be an immutable official postgres digest reference.' }
if (-not [string]::IsNullOrWhiteSpace($candidateDigest) -and $candidateDigest -eq $lockedDigest) {
    Add-Failure 'Candidate digest must differ from the currently locked digest.'
}

$source = "https://hub.docker.com/v2/repositories/library/postgres/tags/$CandidateTag"
$observationMode = if ([string]::IsNullOrWhiteSpace($CandidateObservationPath)) {
    'read_only_https_and_local_docker'
}
else { 'local_fixture' }
$observation = $null
try {
    if ($observationMode -eq 'local_fixture') {
        $observation = Get-Content -LiteralPath ([IO.Path]::GetFullPath($CandidateObservationPath)) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    elseif ($failures.Count -eq 0) {
        $observation = Invoke-RestMethod -Uri $source -Method Get -TimeoutSec 30 `
            -Headers @{ Accept = 'application/json'; 'User-Agent' = 'TMXY-P0-12-Candidate-Evaluation/1' }
    }
}
catch { Add-Failure "Official candidate observation failed: $($_.Exception.Message)" }

$observedDigest = ''
$linuxAmd64Digest = ''
$tagLastPushedUtc = ''
if ($null -ne $observation) {
    if ([string](Get-PropertyValue -Object $observation -Name 'name') -ne $CandidateTag) {
        Add-Failure 'Official candidate response tag does not match the requested tag.'
    }
    $observedDigest = [string](Get-PropertyValue -Object $observation -Name 'digest')
    if ($observedDigest -ne $candidateDigest) {
        Add-Failure 'Official candidate index digest does not match the requested immutable reference.'
    }
    $lastUpdated = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            [string](Get-PropertyValue -Object $observation -Name 'last_updated'),
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$lastUpdated)) {
        Add-Failure 'Official candidate response last_updated timestamp is invalid.'
    }
    else { $tagLastPushedUtc = $lastUpdated.ToUniversalTime().ToString('o') }
    $images = @((Get-PropertyValue -Object $observation -Name 'images') | Where-Object {
            [string](Get-PropertyValue -Object $_ -Name 'os') -eq 'linux' -and
            [string](Get-PropertyValue -Object $_ -Name 'architecture') -eq 'amd64'
        })
    if ($images.Count -ne 1 -or [string]$images[0].digest -notmatch '^sha256:[a-f0-9]{64}$') {
        Add-Failure 'Official candidate response must contain exactly one valid linux/amd64 manifest.'
    }
    else { $linuxAmd64Digest = [string]$images[0].digest }
}

$fixturePair = -not [string]::IsNullOrWhiteSpace($LockedProbePath) -and
    -not [string]::IsNullOrWhiteSpace($CandidateProbePath)
if ($fixturePair -ne ($observationMode -eq 'local_fixture')) {
    Add-Failure 'Observation and both probe fixtures must be supplied together, or all omitted for a live local evaluation.'
}
$lockedProbe = $null
$candidateProbe = $null
try {
    if ($fixturePair) {
        $lockedProbe = Read-ProbeFixture -Path $LockedProbePath -Role 'Locked'
        $candidateProbe = Read-ProbeFixture -Path $CandidateProbePath -Role 'Candidate'
    }
    elseif ($failures.Count -eq 0) {
        $lockedProbe = Get-LocalImageProbe -Reference $lockedReference `
            -ExpectedDigest $lockedDigest -Role 'Locked'
        $candidateProbe = Get-LocalImageProbe -Reference $CandidateReference `
            -ExpectedDigest $candidateDigest -Role 'Candidate'
    }
}
catch { Add-Failure "Candidate component probe failed: $($_.Exception.Message)" }

if ($null -ne $lockedProbe) {
    Test-Probe -Probe $lockedProbe -ExpectedReference $lockedReference `
        -ExpectedDigest $lockedDigest -Role 'Locked'
}
if ($null -ne $candidateProbe) {
    Test-Probe -Probe $candidateProbe -ExpectedReference $CandidateReference `
        -ExpectedDigest $candidateDigest -Role 'Candidate'
}

$sameGosuBinary = $failures.Count -eq 0 -and
    [string]$lockedProbe.gosu_sha256 -eq [string]$candidateProbe.gosu_sha256
$decision = if ($failures.Count -gt 0) {
    'EVALUATION_FAILED_CLOSED'
}
elseif ($sameGosuBinary) {
    'REJECTED_IDENTICAL_BLOCKING_COMPONENT'
}
else { 'CANDIDATE_REQUIRES_HOSTED_QUALIFICATION' }

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS_DIAGNOSTIC' } else { 'FAIL' }
    release_authority = $false
    evaluation_mode = $observationMode
    candidate_pull_performed = $false
    source_mutation_performed = $false
    official_candidate = [pscustomobject][ordered]@{
        source = $source
        tag = $CandidateTag
        reference = $CandidateReference
        observed_index_digest = $observedDigest
        linux_amd64_manifest_digest = $linuxAmd64Digest
        tag_last_pushed_utc = $tagLastPushedUtc
    }
    locked_probe = $lockedProbe
    candidate_probe = $candidateProbe
    comparison = [pscustomobject][ordered]@{
        same_postgres_version = $failures.Count -eq 0 -and
            [string]$lockedProbe.postgres_version -eq [string]$candidateProbe.postgres_version
        same_gosu_version = $failures.Count -eq 0 -and
            [string]$lockedProbe.gosu_version -eq [string]$candidateProbe.gosu_version
        same_gosu_build = $failures.Count -eq 0 -and
            [string]$lockedProbe.gosu_build -eq [string]$candidateProbe.gosu_build
        same_gosu_binary_sha256 = $sameGosuBinary
    }
    security_inference = [pscustomobject][ordered]@{
        type = 'exact_affected_binary_identity'
        candidate_inherits_recorded_blocker = $sameGosuBinary
        inherited_high_or_critical = if ($sameGosuBinary) { $blockingCount } else { 0 }
        inherited_vulnerability_ids = if ($sameGosuBinary) { $blockingIds } else { @() }
        candidate_scan_claimed = $false
        note = 'An identical gosu SHA-256 proves byte identity with the component carrying the recorded hosted Go stdlib findings; this is not represented as a new vulnerability scan.'
    }
    decision = [pscustomobject][ordered]@{
        status = $decision
        lock_update_performed = $false
        automatic_lock_update_allowed = $false
        next_step = if ($sameGosuBinary) {
            'Reject this candidate and retain the current lock; wait for an official image whose gosu bytes or build change, then run full hosted qualification.'
        }
        else {
            'Generate SBOM and hosted vulnerability evidence, run migration and full gates, and request review before any lock change.'
        }
    }
    bindings = [pscustomobject][ordered]@{
        vulnerability_disposition = 'Data/Security/p0-12-postgres-vulnerability-disposition.json'
        vulnerability_disposition_sha256 = $bindingHashes.vulnerability_disposition
        toolchain_lock = 'Data/Toolchain/toolchain.lock.json'
        toolchain_lock_sha256 = $bindingHashes.toolchain_lock
        compose = 'Deploy/compose/compose.yaml'
        compose_sha256 = $bindingHashes.compose
        refresh_preflight = 'Data/Security/p0-12-postgres-refresh-preflight.json'
        refresh_preflight_sha256 = $bindingHashes.refresh_preflight
    }
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n")
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    [IO.File]::WriteAllText($resolvedOutput, $json + "`n", [Text.UTF8Encoding]::new($false))
}
$json
if ($failures.Count -gt 0) { throw 'PostgreSQL official candidate evaluation failed closed.' }
