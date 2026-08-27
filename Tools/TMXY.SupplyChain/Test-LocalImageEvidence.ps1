[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-supply-chain-status.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$postgresSbomPath = Join-Path $root 'Data\Security\postgres-18.6.sbom.cdx.json'
$builderSbomPath = Join-Path $root 'Data\Security\tmxy-backend-builder.sbom.cdx.json'
$hostingStatusPath = Join-Path $root 'Data\Governance\p0-github-hosting-status.json'
$licenseEvidencePath = Join-Path $root 'Data\Security\p0-12-license-evidence.json'
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$expectedReference = [string]$lock.database.development_image.digest_reference

$imageRecords = @(docker image inspect $expectedReference 2>$null | ConvertFrom-Json)
$imagePresent = $LASTEXITCODE -eq 0 -and $imageRecords.Count -gt 0
$actualImageId = if ($imagePresent) { [string]$imageRecords[0].Id } else { '' }
$expectedImageId = [string]$lock.database.development_image.image_id
$imageVerified = $imagePresent -and $actualImageId -eq $expectedImageId

$postgresSbom = Get-Content -LiteralPath $postgresSbomPath -Raw | ConvertFrom-Json
$postgresSbomSha = (Get-FileHash -LiteralPath $postgresSbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
$postgresComponentCount = @($postgresSbom.components).Count
$postgresLicensedComponentCount = @($postgresSbom.components | Where-Object {
        $_.PSObject.Properties.Name -contains 'licenses' -and $null -ne $_.licenses
    }).Count
$postgresSbomVerified = [string]$postgresSbom.bomFormat -eq 'CycloneDX' -and
    [string]$postgresSbom.specVersion -eq '1.5' -and $postgresComponentCount -gt 0

$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$builderRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$builderPresent = $LASTEXITCODE -eq 0 -and $builderRecords.Count -gt 0
$actualBuilderId = if ($builderPresent) { [string]$builderRecords[0].Id } else { '' }
$builderImageVerified = $builderPresent -and $actualBuilderId -eq $expectedBuilderId
$builderSbom = Get-Content -LiteralPath $builderSbomPath -Raw | ConvertFrom-Json
$builderSbomSha = (Get-FileHash -LiteralPath $builderSbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
$builderComponentCount = @($builderSbom.components).Count
$builderLicensedComponentCount = @($builderSbom.components | Where-Object {
        $_.PSObject.Properties.Name -contains 'licenses' -and $null -ne $_.licenses
    }).Count
$builderSbomVerified = [string]$builderSbom.bomFormat -eq 'CycloneDX' -and
    [string]$builderSbom.specVersion -eq '1.5' -and
    $builderSbomSha -eq [string]$lock.backend_toolchain.qualification.sbom_sha256 -and
    $builderComponentCount -eq [int]$lock.backend_toolchain.qualification.sbom_component_count
$hostingStatus = Get-Content -LiteralPath $hostingStatusPath -Raw | ConvertFrom-Json
$licensePolicy = (& (Join-Path $root 'Tests\CI\Test-HostedSupplyChainPolicy.ps1') `
        -RebuildRoot $root -Mode ContractOnly) | ConvertFrom-Json
$licenseEvidenceSha = (Get-FileHash -LiteralPath $licenseEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()

$scoutVersionOutput = (docker scout version 2>$null) -join "`n"
$scoutVersion = if ($scoutVersionOutput -match 'version:\s*([^\s]+)') { $Matches[1] } else { 'unknown' }
$passed = $imageVerified -and $postgresSbomVerified -and $builderImageVerified -and
    $builderSbomVerified -and [string]$licensePolicy.result -eq 'PASS_DIAGNOSTIC'
$report = [pscustomobject][ordered]@{
    schema_version = 4
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS_WITH_PENDING_AUTHORITY' } else { 'FAIL' }
    release_authority = $false
    image = [pscustomobject][ordered]@{
        reference = $expectedReference
        expected_id = $expectedImageId
        actual_id = $actualImageId
        locally_verified = $imageVerified
    }
    sbom = [pscustomobject][ordered]@{
        file = 'Data/Security/postgres-18.6.sbom.cdx.json'
        sha256 = $postgresSbomSha
        format = [string]$postgresSbom.bomFormat
        spec_version = [string]$postgresSbom.specVersion
        component_count = $postgresComponentCount
        components_with_embedded_license_evidence = $postgresLicensedComponentCount
        components_with_license_evidence = [int]$licensePolicy.sbom.postgres_components_with_license_evidence
        locally_verified = $postgresSbomVerified
    }
    backend_builder = [pscustomobject][ordered]@{
        image = [pscustomobject][ordered]@{
            reference = $builderReference
            expected_id = $expectedBuilderId
            actual_id = $actualBuilderId
            locally_verified = $builderImageVerified
        }
        sbom = [pscustomobject][ordered]@{
            file = 'Data/Security/tmxy-backend-builder.sbom.cdx.json'
            sha256 = $builderSbomSha
            format = [string]$builderSbom.bomFormat
            spec_version = [string]$builderSbom.specVersion
            component_count = $builderComponentCount
            components_with_embedded_license_evidence = $builderLicensedComponentCount
            components_with_license_evidence = [int]$licensePolicy.sbom.builder_components_with_license_evidence
            locally_verified = $builderSbomVerified
        }
    }
    license_evidence = [pscustomobject][ordered]@{
        file = 'Data/Security/p0-12-license-evidence.json'
        sha256 = $licenseEvidenceSha
        result = [string]$licensePolicy.result
        component_complete = (
            [int]$licensePolicy.sbom.postgres_components_with_license_evidence -eq $postgresComponentCount -and
            [int]$licensePolicy.sbom.builder_components_with_license_evidence -eq $builderComponentCount)
        release_authority = $false
    }
    scanner = [pscustomobject][ordered]@{
        docker_scout_version = $scoutVersion
        vulnerability_status = 'pending_authenticated_database_access'
        note = 'Docker Scout CVE analysis requested authentication; no login or credential mutation was performed.'
    }
    hosted_ci = [pscustomobject][ordered]@{
        provider = [string]$hostingStatus.provider.name
        repository = [string]$hostingStatus.provider.repository
        workflow_source_prepared = [bool]$hostingStatus.local_workflow_binding.required_checks_workflow_present
        protected_branch = [bool]$hostingStatus.branch_authority.protected
        release_authority = [bool]$hostingStatus.release_authority
        blocker_count = [int]$hostingStatus.blocker_count
        evidence = 'Data/Governance/p0-github-hosting-status.json'
    }
    pending = @(
        'Protected GitHub main and provider-generated results for all eight stable checks',
        'Authenticated or approved hosted vulnerability database evidence for both locked SBOMs',
        'Exact locked builder manifest verified in GHCR',
        'Signed release provenance, OCI attestation, and 365-day immutable retention'
    )
    deferred_to_p4 = @(
        'Create application Conan profile lockfiles when the first external C++ dependency is introduced'
    )
}
$json = ($report | ConvertTo-Json -Depth 7).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'Local image supply-chain evidence validation failed.' }
