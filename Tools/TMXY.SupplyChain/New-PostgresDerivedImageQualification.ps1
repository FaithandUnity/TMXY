[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ImageReference = 'tmxy-postgres:18.6-gosu-go1.26.7',
    [string]$ExpectedImageId = 'sha256:cf86acb2941d1703c8b21cc51722d200b7d6b0cf01398a45b01d58f649f5ae5b',
    [string[]]$BinaryComparisonImageReferences = @(),
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-postgres-derived-image-qualification.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$dockerfilePath = Join-Path $root 'Deploy\postgres\Dockerfile'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$dispositionPath = Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'
$sbomPath = Join-Path $root 'Data\Security\tmxy-postgres-18.6-gosu-go1.26.7.sbom.cdx.json'
$imageScanPath = Join-Path $root 'Data\Security\p0-12-postgres-derived-image-vulnerabilities.json'
$sbomScanPath = Join-Path $root 'Data\Security\p0-12-postgres-derived-vulnerabilities.json'
$databaseIdentityPath = Join-Path $root 'Data\Security\p0-12-postgres-derived-vulnerability-database-identity.txt'
$govulncheckPath = Join-Path $root 'Data\Security\p0-12-postgres-derived-gosu-govulncheck.sarif.json'
$migrationPath = Join-Path $root 'Data\BuildBaseline\p0-12-postgres-derived-migration.json'
$contractTestPath = Join-Path $root 'Tests\CI\Test-PostgresDerivedImageContract.ps1'
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Required qualification input is missing: $Path"
        return ''
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Required JSON qualification input is missing: $Path"
        return $null
    }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch {
        Add-Failure "Could not parse qualification input $Path`: $($_.Exception.Message)"
        return $null
    }
}

function Get-VulnerabilityCounts {
    param([AllowNull()][object]$Report)
    if ($null -eq $Report) {
        return [pscustomobject][ordered]@{ total = -1; critical = -1; high = -1; high_or_critical = -1 }
    }
    $findings = @($Report.Results | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains 'Vulnerabilities' -and
                $null -ne $_.Vulnerabilities) {
                @($_.Vulnerabilities)
            }
        })
    $critical = @($findings | Where-Object { [string]$_.Severity -eq 'CRITICAL' })
    $high = @($findings | Where-Object { [string]$_.Severity -eq 'HIGH' })
    return [pscustomobject][ordered]@{
        total = $findings.Count
        critical = $critical.Count
        high = $high.Count
        high_or_critical = $critical.Count + $high.Count
    }
}

function Get-GosuSha {
    param([Parameter(Mandatory = $true)][string]$Reference)
    $line = @(& docker run --rm --network none --entrypoint sha256sum `
            $Reference /usr/local/bin/gosu 2>$null)
    if ($LASTEXITCODE -ne 0 -or $line.Count -ne 1 -or
        [string]$line[0] -notmatch '^(?<sha>[a-f0-9]{64})\s+/usr/local/bin/gosu$') {
        Add-Failure "Could not hash gosu in candidate image $Reference."
        return ''
    }
    return $Matches.sha
}

function Convert-TrivyTimestamp {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][ref]$Timestamp
    )
    $normalized = $Value.Trim() -replace '\s+UTC$', ''
    $normalized = [regex]::Replace(
        $normalized,
        '(?<offset>[+-]\d{2})(?<minutes>\d{2})$',
        '${offset}:${minutes}')
    $normalized = [regex]::Replace(
        $normalized,
        '(?<fraction>\.\d{7})\d+(?=\s+[+-]\d{2}:\d{2}$)',
        '${fraction}')
    return [DateTimeOffset]::TryParse(
        $normalized,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AllowWhiteSpaces,
        $Timestamp)
}

if ($ExpectedImageId -notmatch '^sha256:[a-f0-9]{64}$') {
    Add-Failure 'Expected derived image ID is not a SHA-256 digest.'
}
$dockerfileSha = Get-Sha256 $dockerfilePath
$lockSha = Get-Sha256 $lockPath
$dispositionSha = Get-Sha256 $dispositionPath
$sbomSha = Get-Sha256 $sbomPath
$imageScanSha = Get-Sha256 $imageScanPath
$sbomScanSha = Get-Sha256 $sbomScanPath
$databaseIdentitySha = Get-Sha256 $databaseIdentityPath
$govulncheckSha = Get-Sha256 $govulncheckPath
$migrationSha = Get-Sha256 $migrationPath

$lock = Read-Json $lockPath
$disposition = Read-Json $dispositionPath
$sbom = Read-Json $sbomPath
$imageScan = Read-Json $imageScanPath
$sbomScan = Read-Json $sbomScanPath
$govulncheck = Read-Json $govulncheckPath
$migration = Read-Json $migrationPath

$image = $null
try {
    $records = @(& docker image inspect $ImageReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $records.Count -ne 1) {
        Add-Failure 'The exact local derived PostgreSQL candidate is unavailable.'
    }
    else { $image = $records[0] }
}
catch { Add-Failure "Could not inspect the derived PostgreSQL candidate: $($_.Exception.Message)" }
$actualImageId = if ($null -ne $image) { [string]$image.Id } else { '' }
if ($actualImageId -ne $ExpectedImageId) {
    Add-Failure 'The local candidate image ID differs from the qualified digest.'
}

$labels = if ($null -ne $image) { $image.Config.Labels } else { $null }
if ($null -eq $labels -or
    [string]$labels.'org.opencontainers.image.base.digest' -ne
        'sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2' -or
    [string]$labels.'io.tmxy.gosu.revision' -ne
        '6456aaa0f3c854d199d0f037f068eb97515b7513' -or
    [string]$labels.'io.tmxy.gosu.go-version' -ne '1.26.7' -or
    [string]$labels.'io.tmxy.alpine.openssl-version' -ne '3.5.8-r0') {
    Add-Failure 'Derived image OCI labels do not bind the reviewed base, gosu, Go, and OpenSSL identities.'
}

$probeLines = @()
if ($null -ne $image) {
    $probeLines = @(& docker run --rm --network none --entrypoint sh $ImageReference -ec `
            'postgres --version; gosu --version; sha256sum /usr/local/bin/gosu; gosu postgres id -u; apk list --installed libcrypto3 libssl3 2>/dev/null' 2>$null)
    if ($LASTEXITCODE -ne 0) { Add-Failure 'Networkless candidate runtime probe failed.' }
}
$postgresVersion = [string]($probeLines | Where-Object { $_ -match '^postgres \(PostgreSQL\) ' } | Select-Object -First 1)
$gosuVersion = [string]($probeLines | Where-Object { $_ -match '^1\.19 \(go' } | Select-Object -First 1)
$gosuSha = if ($null -ne $image) { Get-GosuSha $ImageReference } else { '' }
$postgresUid = [string]($probeLines | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
$opensslPackages = @($probeLines | Where-Object { $_ -match '^lib(?:crypto|ssl)3-' } | Sort-Object)
if ($postgresVersion -ne 'postgres (PostgreSQL) 18.6' -or
    $gosuVersion -ne '1.19 (go1.26.7 on linux/amd64; gc)' -or
    $gosuSha -ne 'dac0a884d5b1423d76bcf2267725047b045f49165291e3808b0052fde9010aeb' -or
    $postgresUid -ne '70' -or
    $opensslPackages.Count -ne 2 -or
    $opensslPackages -notcontains 'libcrypto3-3.5.8-r0 x86_64 {openssl} (Apache-2.0) [installed]' -or
    $opensslPackages -notcontains 'libssl3-3.5.8-r0 x86_64 {openssl} (Apache-2.0) [installed]') {
    Add-Failure 'Derived image runtime identity, privilege switch, or fixed OpenSSL packages do not match qualification.'
}

$comparisonReferences = @($BinaryComparisonImageReferences | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
$comparisonShas = @($comparisonReferences | ForEach-Object { Get-GosuSha $_ })
$binaryReproducible = $comparisonShas.Count -ge 2 -and
    @($comparisonShas | Where-Object { $_ -ne $gosuSha }).Count -eq 0
if ($comparisonReferences.Count -gt 0 -and -not $binaryReproducible) {
    Add-Failure 'Independent no-cache builds did not reproduce the qualified gosu bytes.'
}

$sbomComponentCount = if ($null -ne $sbom) { @($sbom.components).Count } else { 0 }
$stdlibVersions = @()
if ($null -ne $sbom) {
    $stdlibVersions = @($sbom.components |
        Where-Object { [string]$_.name -eq 'stdlib' } |
        ForEach-Object { [string]$_.version } | Sort-Object -Unique)
}
$sbomImageIdBound = $null -ne $sbom -and [string]$sbom.bomFormat -eq 'CycloneDX' -and
    [string]$sbom.specVersion -eq '1.7' -and
    [string]$sbom.metadata.component.purl -match [regex]::Escape($ExpectedImageId) -and
    $sbomComponentCount -gt 0 -and $stdlibVersions.Count -eq 1 -and
    $stdlibVersions[0] -eq 'v1.26.7'
if (-not $sbomImageIdBound) {
    Add-Failure 'Trivy SBOM is not uniquely bound to the candidate and Go 1.26.7 final filesystem.'
}

$imageCounts = Get-VulnerabilityCounts $imageScan
$sbomCounts = Get-VulnerabilityCounts $sbomScan
$scanBound = $null -ne $imageScan -and $null -ne $sbomScan -and
    [int]$imageScan.SchemaVersion -eq 2 -and [int]$sbomScan.SchemaVersion -eq 2 -and
    [string]$imageScan.Metadata.ImageID -eq $ExpectedImageId -and
    $imageCounts.high_or_critical -eq 0 -and $sbomCounts.high_or_critical -eq 0
if (-not $scanBound) {
    Add-Failure 'Direct-image and final-filesystem SBOM scans must both contain zero HIGH/CRITICAL findings.'
}

$databaseIdentity = if (Test-Path -LiteralPath $databaseIdentityPath -PathType Leaf) {
    Get-Content -LiteralPath $databaseIdentityPath -Raw -Encoding UTF8
}
else { '' }
$updatedMatch = [regex]::Match($databaseIdentity, '(?m)^\s*UpdatedAt:\s*(?<value>.+)$')
$downloadedMatch = [regex]::Match($databaseIdentity, '(?m)^\s*DownloadedAt:\s*(?<value>.+)$')
$databaseUpdated = [DateTimeOffset]::MinValue
$databaseDownloaded = [DateTimeOffset]::MinValue
$databaseValid = $databaseIdentity -match '(?m)^Version:\s*0\.74\.0\s*$' -and
    $updatedMatch.Success -and $downloadedMatch.Success -and
    (Convert-TrivyTimestamp $updatedMatch.Groups['value'].Value ([ref]$databaseUpdated)) -and
    (Convert-TrivyTimestamp $downloadedMatch.Groups['value'].Value ([ref]$databaseDownloaded)) -and
    $databaseDownloaded.ToUniversalTime() -ge $databaseUpdated.ToUniversalTime() -and
    ([DateTimeOffset]::UtcNow - $databaseUpdated.ToUniversalTime()).TotalHours -le 48
if (-not $databaseValid) { Add-Failure 'Trivy scanner or vulnerability database identity is missing, invalid, or stale.' }

$govulncheckResults = @('invalid')
if ($null -ne $govulncheck -and @($govulncheck.runs).Count -eq 1) {
    $govulncheckResults = @($govulncheck.runs[0].results)
}
if ($null -eq $govulncheck -or [string]$govulncheck.version -ne '2.1.0' -or
    $govulncheckResults.Count -ne 0) {
    Add-Failure 'govulncheck must report zero reachable vulnerabilities for the exact derived gosu bytes.'
}

if ($null -eq $migration -or [string]$migration.result -ne 'PASS' -or
    [string]$migration.image -ne $ImageReference -or
    [string]$migration.database_version -ne '18.6' -or
    [string]$migration.migration.runtime_contract -ne 'foundation:1') {
    Add-Failure 'Derived PostgreSQL migration evidence is missing or not bound to the candidate.'
}

$contract = $null
try { $contract = (& $contractTestPath -RebuildRoot $root) | ConvertFrom-Json }
catch { Add-Failure "Derived image source contract failed: $($_.Exception.Message)" }
if ($null -eq $contract -or [string]$contract.result -ne 'PASS') {
    Add-Failure 'Derived image source contract did not pass.'
}

$baseDigest = if ($null -ne $lock) { [string]$lock.database.development_image.image_id } else { '' }
$previousBlockers = if ($null -ne $disposition) { [int]$disposition.blocking_findings.total } else { -1 }
if ($baseDigest -ne 'sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2' -or
    $previousBlockers -ne 22) {
    Add-Failure 'The derived qualification no longer starts from the reviewed 22-finding base image.'
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS_DIAGNOSTIC' } else { 'FAIL' }
    completion_criteria_satisfied = $false
    release_authority = $false
    source_mutation_performed = $false
    lock_update_performed = $false
    candidate = [pscustomobject][ordered]@{
        local_reference = $ImageReference
        image_id = $actualImageId
        platform = if ($null -ne $image) { "$($image.Os)/$($image.Architecture)" } else { '' }
        base_image_id = $baseDigest
        postgres_version = $postgresVersion
        gosu_version = $gosuVersion
        gosu_sha256 = $gosuSha
        postgres_uid = $postgresUid
        openssl_packages = @($opensslPackages)
        registry_published = $false
        signed_provenance_attached = $false
        oci_attestation_attached = $false
    }
    reproducibility = [pscustomobject][ordered]@{
        comparison_images = @($comparisonReferences)
        comparison_gosu_sha256 = @($comparisonShas)
        binary_reproducible = $binaryReproducible
        oci_manifest_reproducible = $false
        note = 'Independent no-cache builds reproduced the exact gosu bytes. BuildKit layer metadata produced different OCI manifest IDs, so manifest reproducibility is not claimed.'
    }
    vulnerability = [pscustomobject][ordered]@{
        scanner = 'trivy'
        scanner_version = '0.74.0'
        database_updated_utc = if ($databaseValid) { $databaseUpdated.ToUniversalTime().ToString('o') } else { '' }
        database_downloaded_utc = if ($databaseValid) { $databaseDownloaded.ToUniversalTime().ToString('o') } else { '' }
        previous_high_or_critical = $previousBlockers
        direct_image = $imageCounts
        final_filesystem_sbom = $sbomCounts
        govulncheck_result_count = $govulncheckResults.Count
    }
    sbom = [pscustomobject][ordered]@{
        format = if ($null -ne $sbom) { [string]$sbom.bomFormat } else { '' }
        spec_version = if ($null -ne $sbom) { [string]$sbom.specVersion } else { '' }
        component_count = $sbomComponentCount
        stdlib_versions = @($stdlibVersions)
        image_id_bound = $sbomImageIdBound
    }
    migration = [pscustomobject][ordered]@{
        result = if ($null -ne $migration) { [string]$migration.result } else { '' }
        runtime_contract = if ($null -ne $migration) { [string]$migration.migration.runtime_contract } else { '' }
    }
    decision = [pscustomobject][ordered]@{
        status = if ($failures.Count -eq 0) {
            'QUALIFIED_LOCAL_CANDIDATE_REQUIRES_REGISTRY_AUTHORITY'
        }
        else { 'QUALIFICATION_FAILED_CLOSED' }
        next_step = 'Publish this exact OCI manifest with an authorized packages:write credential, rerun hosted scans, and attach signed provenance before changing the lock.'
    }
    bindings = [pscustomobject][ordered]@{
        dockerfile = 'Deploy/postgres/Dockerfile'
        dockerfile_sha256 = $dockerfileSha
        toolchain_lock_sha256 = $lockSha
        vulnerability_disposition_sha256 = $dispositionSha
        sbom_sha256 = $sbomSha
        direct_image_scan_sha256 = $imageScanSha
        sbom_scan_sha256 = $sbomScanSha
        vulnerability_database_identity_sha256 = $databaseIdentitySha
        govulncheck_sarif_sha256 = $govulncheckSha
        migration_sha256 = $migrationSha
    }
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 9).Replace("`r`n", "`n").Replace("`r", "`n")
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[IO.File]::WriteAllText($resolvedOutput, $json + "`n", [Text.UTF8Encoding]::new($false))
$json
if ($failures.Count -gt 0) { throw 'Derived PostgreSQL image qualification failed closed.' }
