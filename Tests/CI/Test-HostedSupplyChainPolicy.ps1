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

$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$postgresSbom = Get-Content -LiteralPath $postgresSbomPath -Raw -Encoding UTF8 | ConvertFrom-Json
$builderSbom = Get-Content -LiteralPath $builderSbomPath -Raw -Encoding UTF8 | ConvertFrom-Json
$postgresSha = (Get-FileHash -LiteralPath $postgresSbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
$builderSha = (Get-FileHash -LiteralPath $builderSbomPath -Algorithm SHA256).Hash.ToLowerInvariant()

if ($postgresSha -ne [string]$contract.supply_chain.postgres_sbom_sha256) {
    Add-SupplyFailure 'PostgreSQL SBOM hash differs from the hosted contract.'
}
if ($builderSha -ne [string]$contract.supply_chain.backend_builder_sbom_sha256 -or
    $builderSha -ne [string]$lock.backend_toolchain.qualification.sbom_sha256) {
    Add-SupplyFailure 'Builder SBOM hash differs from the lock or hosted contract.'
}
$postgresComponents = @($postgresSbom.components).Count
$builderComponents = @($builderSbom.components).Count
$postgresLicensed = Get-LicenseEvidenceCount -Sbom $postgresSbom
$builderLicensed = Get-LicenseEvidenceCount -Sbom $builderSbom
$postgresBlocking = 0
$builderBlocking = 0
$databaseIdentitySha = ''

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
        postgres_components_with_license_evidence = $postgresLicensed
        builder_components = $builderComponents
        builder_components_with_license_evidence = $builderLicensed
    }
    blocking_vulnerabilities = [pscustomobject][ordered]@{
        postgres_high_or_critical = $postgresBlocking
        builder_high_or_critical = $builderBlocking
    }
    vulnerability_database_identity_sha256 = $databaseIdentitySha
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 6
if (-not $passed) { throw 'Hosted supply-chain policy failed.' }
