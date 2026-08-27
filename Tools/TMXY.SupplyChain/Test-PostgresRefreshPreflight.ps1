[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ObservationPath = '',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-postgres-refresh-preflight.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$dispositionPath = Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$composePath = Join-Path $root 'Deploy\compose\compose.yaml'
$failures = [System.Collections.Generic.List[string]]::new()

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

$dispositionSha = Get-Sha256 -Path $dispositionPath
$lockSha = Get-Sha256 -Path $lockPath
$composeSha = Get-Sha256 -Path $composePath
$disposition = $null
$lock = $null
$compose = ''
try {
    if (-not [string]::IsNullOrWhiteSpace($dispositionSha)) {
        $disposition = Get-Content -LiteralPath $dispositionPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    if (-not [string]::IsNullOrWhiteSpace($lockSha)) {
        $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    if (-not [string]::IsNullOrWhiteSpace($composeSha)) {
        $compose = Get-Content -LiteralPath $composePath -Raw -Encoding UTF8
    }
}
catch {
    Add-Failure "Could not parse a required binding file: $($_.Exception.Message)"
}

$tag = ''
$lockedDigest = ''
$source = ''
$lockedReference = ''
if ($null -ne $disposition) {
    $imageReference = [string]$disposition.component.image_reference
    if ($imageReference -notmatch '^postgres:(?<tag>[0-9]+(?:\.[0-9]+)*-alpine)$') {
        Add-Failure 'PostgreSQL disposition image reference is not an allowed official alpine tag.'
    }
    else { $tag = $Matches.tag }
    $lockedDigest = [string]$disposition.component.locked_index_digest
    $source = [string]$disposition.upstream_tag_observation.source
}
if ($null -ne $lock) {
    $lockedReference = [string]$lock.database.development_image.digest_reference
    $lockImageId = [string]$lock.database.development_image.image_id
    if ($lockImageId -ne $lockedDigest) {
        Add-Failure 'PostgreSQL disposition and toolchain lock use different image digests.'
    }
    if (-not $lockedReference.EndsWith("@$lockedDigest", [StringComparison]::Ordinal)) {
        Add-Failure 'Toolchain PostgreSQL reference is not bound to the disposition digest.'
    }
}
if ($lockedDigest -notmatch '^sha256:[a-f0-9]{64}$') {
    Add-Failure 'Locked PostgreSQL index digest is invalid.'
}
if (-not [string]::IsNullOrWhiteSpace($compose) -and
    -not $compose.Contains("postgres@$lockedDigest")) {
    Add-Failure 'Compose PostgreSQL reference is not bound to the disposition digest.'
}

$expectedSource = if ([string]::IsNullOrWhiteSpace($tag)) {
    ''
}
else {
    "https://hub.docker.com/v2/repositories/library/postgres/tags/$tag"
}
$sourceUri = $null
if ($source -ne $expectedSource) {
    Add-Failure 'PostgreSQL refresh source is not the exact approved Docker Hub tag endpoint.'
}
elseif (-not [Uri]::TryCreate($source, [UriKind]::Absolute, [ref]$sourceUri) -or
    $sourceUri.Scheme -ne 'https' -or $sourceUri.Host -ne 'hub.docker.com') {
    Add-Failure 'PostgreSQL refresh source must use the approved Docker Hub HTTPS host.'
}

$observation = $null
$observationMode = if ([string]::IsNullOrWhiteSpace($ObservationPath)) {
    'read_only_https'
}
else { 'local_fixture' }
try {
    if ($observationMode -eq 'local_fixture') {
        $fixture = [System.IO.Path]::GetFullPath($ObservationPath)
        if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
            throw "Observation fixture does not exist: $fixture"
        }
        $observation = Get-Content -LiteralPath $fixture -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    elseif ($failures.Count -eq 0) {
        $observation = Invoke-RestMethod -Uri $sourceUri -Method Get -TimeoutSec 30 `
            -Headers @{ Accept = 'application/json'; 'User-Agent' = 'TMXY-P0-12-ReadOnly-Preflight/1' }
    }
}
catch {
    Add-Failure "Docker Hub tag observation failed: $($_.Exception.Message)"
}

$observedTag = ''
$observedDigest = ''
$tagLastPushedUtc = ''
$linuxAmd64Digest = ''
if ($null -ne $observation) {
    $observedTag = [string](Get-PropertyValue -Object $observation -Name 'name')
    $observedDigest = [string](Get-PropertyValue -Object $observation -Name 'digest')
    $lastUpdated = Get-PropertyValue -Object $observation -Name 'last_updated'
    if ($observedTag -ne $tag) {
        Add-Failure 'Docker Hub response tag does not match the locked PostgreSQL tag.'
    }
    if ($observedDigest -notmatch '^sha256:[a-f0-9]{64}$') {
        Add-Failure 'Docker Hub response does not contain a valid index digest.'
    }
    $lastUpdatedValue = [DateTimeOffset]::MinValue
    $lastUpdatedValid = if ($lastUpdated -is [DateTimeOffset]) {
        $lastUpdatedValue = $lastUpdated
        $true
    }
    elseif ($lastUpdated -is [DateTime]) {
        $lastUpdatedValue = [DateTimeOffset]::new($lastUpdated)
        $true
    }
    else {
        [DateTimeOffset]::TryParse(
            [string]$lastUpdated,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$lastUpdatedValue)
    }
    if (-not $lastUpdatedValid) {
        Add-Failure 'Docker Hub response does not contain a valid last_updated timestamp.'
    }
    else { $tagLastPushedUtc = $lastUpdatedValue.ToUniversalTime().ToString('o') }

    $imagesValue = Get-PropertyValue -Object $observation -Name 'images'
    $images = if ($null -eq $imagesValue) { @() } else { @($imagesValue) }
    $amd64Images = @($images | Where-Object {
            [string](Get-PropertyValue -Object $_ -Name 'os') -eq 'linux' -and
            [string](Get-PropertyValue -Object $_ -Name 'architecture') -eq 'amd64'
        })
    if ($amd64Images.Count -ne 1) {
        Add-Failure 'Docker Hub response must contain exactly one linux/amd64 manifest.'
    }
    else {
        $linuxAmd64Digest = [string](Get-PropertyValue -Object $amd64Images[0] -Name 'digest')
        if ($linuxAmd64Digest -notmatch '^sha256:[a-f0-9]{64}$') {
            Add-Failure 'Docker Hub linux/amd64 manifest digest is invalid.'
        }
    }
}

$tagManifestChanged = $failures.Count -eq 0 -and $observedDigest -ne $lockedDigest
$decision = if ($failures.Count -gt 0) {
    'OBSERVATION_FAILED_CLOSED'
}
elseif ($tagManifestChanged) {
    'CANDIDATE_AVAILABLE_REQUIRES_FULL_QUALIFICATION'
}
else { 'NO_REFRESH_AVAILABLE' }
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS_DIAGNOSTIC' } else { 'FAIL' }
    release_authority = $false
    network_mode = $observationMode
    component = [pscustomobject][ordered]@{
        role = 'postgres-runtime'
        tag = $tag
        locked_reference = $lockedReference
        locked_index_digest = $lockedDigest
    }
    observation = [pscustomobject][ordered]@{
        source = $source
        observed_tag = $observedTag
        observed_index_digest = $observedDigest
        linux_amd64_manifest_digest = $linuxAmd64Digest
        tag_last_pushed_utc = $tagLastPushedUtc
        tag_manifest_changed = $tagManifestChanged
    }
    decision = [pscustomobject][ordered]@{
        status = $decision
        lock_update_performed = $false
        automatic_lock_update_allowed = $false
        next_step = if ($tagManifestChanged) {
            'Pull the candidate by digest, generate a new SBOM, run hosted vulnerability policy and migration tests, then request review before changing the lock.'
        }
        else {
            'Keep the current digest locked and repeat this read-only observation when upstream publishes a new manifest.'
        }
    }
    bindings = [pscustomobject][ordered]@{
        vulnerability_disposition = 'Data/Security/p0-12-postgres-vulnerability-disposition.json'
        vulnerability_disposition_sha256 = $dispositionSha
        toolchain_lock = 'Data/Toolchain/toolchain.lock.json'
        toolchain_lock_sha256 = $lockSha
        compose = 'Deploy/compose/compose.yaml'
        compose_sha256 = $composeSha
    }
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 7).Replace("`r`n", "`n").Replace("`r", "`n")
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $resolvedOutput,
        $json + "`n",
        [System.Text.UTF8Encoding]::new($false))
}
$json
if ($failures.Count -gt 0) { throw 'PostgreSQL refresh preflight failed closed.' }
