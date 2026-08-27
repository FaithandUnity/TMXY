[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [ValidateSet('ContractOnly', 'MergeGate', 'HostedAuthority')][string]$Mode = 'ContractOnly',
    [string]$PostgresVulnerabilityReport = '',
    [string]$BuilderVulnerabilityReport = '',
    [string]$VulnerabilityDatabaseIdentity = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$contractPath = Join-Path $root 'Data/Governance/p0-hosted-ci-contract.json'
$lockPath = Join-Path $root 'Data/Toolchain/toolchain.lock.json'
$postgresSbomPath = Join-Path $root 'Data/Security/postgres-18.6.sbom.cdx.json'
$builderSbomPath = Join-Path $root 'Data/Security/tmxy-backend-builder.sbom.cdx.json'
$licenseEvidencePath = Join-Path $root 'Data/Security/p0-12-license-evidence.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-SupplyFailure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-LicenseEvidenceCount {
    param([Parameter(Mandatory = $true)][object]$Sbom)
    return @($Sbom.components | Where-Object {
        $_.PSObject.Properties.Name -contains 'licenses' -and
        $null -ne $_.licenses -and @($_.licenses).Count -gt 0
    }).Count
}

function Get-ValidatedLicenseEvidenceCount {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][object]$Sbom,
        [Parameter(Mandatory = $true)][string]$SbomSha256,
        [Parameter(Mandatory = $true)][string]$ImageDigest,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    $embedded = Get-LicenseEvidenceCount -Sbom $Sbom
    $missing = @($Sbom.components | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'licenses') -or
        $null -eq $_.licenses -or @($_.licenses).Count -eq 0
    })
    $imageEntries = @($Manifest.images | Where-Object { [string]$_.role -eq $Role })
    if ($imageEntries.Count -ne 1) {
        Add-SupplyFailure "License evidence must contain exactly one image entry for $Role."
        return $embedded
    }
    $image = $imageEntries[0]
    if ([string]$image.sbom_sha256 -ne $SbomSha256 -or
        [string]$image.image_digest -ne $ImageDigest -or
        [int]$image.component_count -ne @($Sbom.components).Count -or
        [int]$image.embedded_license_count -ne $embedded) {
        Add-SupplyFailure "License evidence binding differs from the locked $Role image or SBOM."
    }
    $entries = @($image.evidence_entries)
    if ([int]$image.supplemental_evidence_count -ne $entries.Count -or
        $entries.Count -ne $missing.Count) {
        Add-SupplyFailure "Supplemental license evidence count is incomplete for $Role."
    }
    $allowedKinds = @(
        'installed-copyright-file',
        'installed-package-metadata',
        'version-pinned-upstream-license'
    )
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        $bomRef = [string]$entry.bom_ref
        $component = @($missing | Where-Object { [string]$_.'bom-ref' -eq $bomRef })
        if (-not $seen.Add($bomRef)) {
            Add-SupplyFailure "Duplicate supplemental license evidence exists for ${Role}: $bomRef"
        }
        if ($component.Count -ne 1 -or [string]$component[0].purl -ne [string]$entry.purl) {
            Add-SupplyFailure "Supplemental license evidence does not match a missing component for ${Role}: $bomRef"
        }
        if ([string]$entry.evidence_kind -notin $allowedKinds -or
            [string]::IsNullOrWhiteSpace([string]$entry.evidence_source) -or
            [string]$entry.evidence_sha256 -notmatch '^[a-f0-9]{64}$' -or
            [string]::IsNullOrWhiteSpace([string]$entry.declared_license) -or
            [string]$entry.review_state -ne 'verified-source-evidence') {
            Add-SupplyFailure "Supplemental license evidence is incomplete for ${Role}: $bomRef"
        }
    }
    foreach ($component in $missing) {
        if (-not $seen.Contains([string]$component.'bom-ref')) {
            Add-SupplyFailure "Missing supplemental license evidence for ${Role}: $($component.purl)"
        }
    }
    return $embedded + $seen.Count
}

function Get-BlockingVulnerabilityCount {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-SupplyFailure "Vulnerability report is missing: $Path"
        return 0
    }
    $report = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($report.Results | ForEach-Object { @($_.Vulnerabilities) } | Where-Object {
        [string]$_.Severity -in @('HIGH', 'CRITICAL')
    }).Count
}

function ConvertFrom-TrivyTimestamp {
    param([Parameter(Mandatory = $true)][string]$Value)
    $candidate = $Value.Trim()
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse(
            $candidate,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }

    $match = [regex]::Match(
        $candidate,
        '^(?<date>\d{4}-\d{2}-\d{2}) (?<time>\d{2}:\d{2}:\d{2})(?<fraction>\.\d+)? (?<sign>[+-])(?<hours>\d{2})(?<minutes>\d{2})(?: UTC)?$')
    if (-not $match.Success) { return $null }
    $fraction = $match.Groups['fraction'].Value
    if ($fraction.Length -gt 8) { $fraction = $fraction.Substring(0, 8) }
    $normalized = '{0} {1}{2} {3}{4}:{5}' -f @(
        $match.Groups['date'].Value,
        $match.Groups['time'].Value,
        $fraction,
        $match.Groups['sign'].Value,
        $match.Groups['hours'].Value,
        $match.Groups['minutes'].Value
    )
    $formats = if ([string]::IsNullOrEmpty($fraction)) {
        @('yyyy-MM-dd HH:mm:ss zzz')
    }
    else {
        @('yyyy-MM-dd HH:mm:ss.FFFFFFF zzz')
    }
    if (-not [DateTimeOffset]::TryParseExact(
            $normalized,
            $formats,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$parsed)) {
        return $null
    }
    return $parsed.ToUniversalTime()
}

$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$postgresSbom = Get-Content -LiteralPath $postgresSbomPath -Raw -Encoding UTF8 | ConvertFrom-Json
$builderSbom = Get-Content -LiteralPath $builderSbomPath -Raw -Encoding UTF8 | ConvertFrom-Json
$licenseEvidence = if (Test-Path -LiteralPath $licenseEvidencePath -PathType Leaf) {
    Get-Content -LiteralPath $licenseEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    Add-SupplyFailure 'Supplemental license evidence manifest is missing.'
    [pscustomobject]@{ schema_version = 0; result = 'MISSING'; images = @() }
}
$postgresSha = (Get-FileHash -LiteralPath $postgresSbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
$builderSha = (Get-FileHash -LiteralPath $builderSbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
$licenseEvidenceSha = if (Test-Path -LiteralPath $licenseEvidencePath -PathType Leaf) {
    (Get-FileHash -LiteralPath $licenseEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
}
else { '' }

if ($postgresSha -ne [string]$contract.supply_chain.postgres_sbom_sha256) {
    Add-SupplyFailure 'PostgreSQL SBOM hash differs from the hosted contract.'
}
if ($builderSha -ne [string]$contract.supply_chain.backend_builder_sbom_sha256 -or
    $builderSha -ne [string]$lock.backend_toolchain.qualification.sbom_sha256) {
    Add-SupplyFailure 'Builder SBOM hash differs from the lock or hosted contract.'
}
if ([string]$contract.supply_chain.license_evidence_path -ne
        'Data/Security/p0-12-license-evidence.json' -or
    $licenseEvidenceSha -ne [string]$contract.supply_chain.license_evidence_sha256) {
    Add-SupplyFailure 'Supplemental license evidence differs from the hosted contract.'
}
$postgresComponents = @($postgresSbom.components).Count
$builderComponents = @($builderSbom.components).Count
$postgresEmbeddedLicensed = Get-LicenseEvidenceCount -Sbom $postgresSbom
$builderEmbeddedLicensed = Get-LicenseEvidenceCount -Sbom $builderSbom
if ([int]$licenseEvidence.schema_version -ne 1 -or [string]$licenseEvidence.result -ne 'PASS' -or
    [bool]$licenseEvidence.release_authority) {
    Add-SupplyFailure 'Supplemental license evidence manifest is not a non-authoritative PASS evidence set.'
}
$postgresLicensed = Get-ValidatedLicenseEvidenceCount -Role 'postgres-runtime' `
    -Sbom $postgresSbom -SbomSha256 $postgresSha `
    -ImageDigest ([string]$lock.database.development_image.image_id) -Manifest $licenseEvidence
$builderLicensed = Get-ValidatedLicenseEvidenceCount -Role 'backend-builder' `
    -Sbom $builderSbom -SbomSha256 $builderSha `
    -ImageDigest ([string]$lock.backend_toolchain.container_image_digest) -Manifest $licenseEvidence
$postgresBlocking = 0
$builderBlocking = 0
$databaseIdentitySha = ''
$databaseUpdatedAt = ''
$databaseDownloadedAt = ''
$databaseAgeHours = $null

if ($Mode -ne 'ContractOnly') {
    $postgresBlocking = Get-BlockingVulnerabilityCount -Path $PostgresVulnerabilityReport
    $builderBlocking = Get-BlockingVulnerabilityCount -Path $BuilderVulnerabilityReport
    if (-not (Test-Path -LiteralPath $VulnerabilityDatabaseIdentity -PathType Leaf)) {
        Add-SupplyFailure 'Vulnerability database identity evidence is missing.'
    }
    else {
        $identityItem = Get-Item -LiteralPath $VulnerabilityDatabaseIdentity
        if ($identityItem.Length -eq 0) { Add-SupplyFailure 'Vulnerability database identity evidence is empty.' }
        $databaseIdentitySha = (Get-FileHash -LiteralPath $identityItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $identity = Get-Content -LiteralPath $identityItem.FullName -Raw -Encoding UTF8
        $expectedScannerVersion = [regex]::Escape([string]$contract.supply_chain.vulnerability_scanner_version)
        if ($identity -notmatch "(?m)^Version:\s*${expectedScannerVersion}\s*$") {
            Add-SupplyFailure 'Vulnerability scanner identity does not match the hosted contract.'
        }
        $updatedMatch = [regex]::Match($identity, '(?m)^\s*UpdatedAt:\s*(?<value>.+?)\s*$')
        $downloadedMatch = [regex]::Match($identity, '(?m)^\s*DownloadedAt:\s*(?<value>.+?)\s*$')
        if ($identity -notmatch '(?m)^Vulnerability DB:\s*$' -or
            -not $updatedMatch.Success -or -not $downloadedMatch.Success) {
            Add-SupplyFailure 'Vulnerability database version, UpdatedAt, or DownloadedAt identity is missing.'
        }
        else {
            $updated = ConvertFrom-TrivyTimestamp -Value $updatedMatch.Groups['value'].Value
            $downloaded = ConvertFrom-TrivyTimestamp -Value $downloadedMatch.Groups['value'].Value
            if ($null -eq $updated -or $null -eq $downloaded) {
                Add-SupplyFailure 'Vulnerability database UpdatedAt or DownloadedAt identity is invalid.'
            }
            else {
                $databaseUpdatedAt = $updated.ToString('o')
                $databaseDownloadedAt = $downloaded.ToString('o')
                $databaseAgeHours = ([DateTimeOffset]::UtcNow - $updated).TotalHours
                $maxAgeHours = [int]$contract.supply_chain.vulnerability_database_max_age_hours
                if ($databaseAgeHours -lt -1 -or $databaseAgeHours -gt $maxAgeHours) {
                    Add-SupplyFailure "Vulnerability database age is outside the ${maxAgeHours}-hour policy."
                }
            }
        }
    }
    if ($postgresBlocking -gt 0 -or $builderBlocking -gt 0) {
        Add-SupplyFailure 'HIGH or CRITICAL vulnerabilities require remediation or an approved time-bounded waiver.'
    }
    if ($postgresLicensed -ne $postgresComponents -or $builderLicensed -ne $builderComponents) {
        Add-SupplyFailure 'Every component requires license evidence or an approved component-specific waiver.'
    }
}

$passed = $failures.Count -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { if ($Mode -eq 'ContractOnly') { 'PASS_DIAGNOSTIC' } else { 'PASS' } } else { 'FAIL' }
    mode = $Mode
    release_authority = $Mode -eq 'HostedAuthority' -and $passed
    sbom = [pscustomobject][ordered]@{
        postgres_components = $postgresComponents
        postgres_components_with_embedded_license_evidence = $postgresEmbeddedLicensed
        postgres_components_with_license_evidence = $postgresLicensed
        builder_components = $builderComponents
        builder_components_with_embedded_license_evidence = $builderEmbeddedLicensed
        builder_components_with_license_evidence = $builderLicensed
    }
    blocking_vulnerabilities = [pscustomobject][ordered]@{
        postgres_high_or_critical = $postgresBlocking
        builder_high_or_critical = $builderBlocking
    }
    vulnerability_database_identity_sha256 = $databaseIdentitySha
    vulnerability_database_updated_utc = $databaseUpdatedAt
    vulnerability_database_downloaded_utc = $databaseDownloadedAt
    vulnerability_database_age_hours = $databaseAgeHours
    license_evidence_sha256 = $licenseEvidenceSha
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 6
if (-not $passed) { throw 'Hosted supply-chain policy failed.' }
