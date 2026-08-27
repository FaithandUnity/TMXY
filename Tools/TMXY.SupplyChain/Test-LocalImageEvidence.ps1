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
$postgresDispositionPath = Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'
$postgresRefreshPath = Join-Path $root 'Data\Security\p0-12-postgres-refresh-preflight.json'
$postgresCandidatePath = Join-Path $root 'Data\Security\p0-12-postgres-official-candidate-evaluation.json'
$postgresReachabilityPath = Join-Path $root 'Data\Security\p0-12-postgres-gosu-reachability-review.json'
$postgresReachabilitySarifPath = Join-Path $root 'Data\Security\p0-12-postgres-gosu-govulncheck.sarif.json'
$postgresReachabilityOsvPath = Join-Path $root 'Data\Security\p0-12-postgres-gosu-GO-2026-4970.osv.json'
$postgresWaiverRequestPath = Join-Path $root 'Data\Security\p0-12-postgres-gosu-waiver-request.json'
$postgresWaiverDecisionPath = Join-Path $root 'Data\Security\p0-12-postgres-gosu-waiver-decision.json'
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
$postgresDisposition = Get-Content -LiteralPath $postgresDispositionPath -Raw | ConvertFrom-Json
$postgresDispositionBound = [string]$postgresDisposition.result -eq 'BLOCKED' -and
    -not [bool]$postgresDisposition.release_authority -and
    [string]$postgresDisposition.policy_effect -eq 'blocking' -and
    [string]$postgresDisposition.component.locked_index_digest -eq $expectedImageId -and
    [int]$postgresDisposition.blocking_findings.total -gt 0 -and
    [string]$postgresDisposition.review.reachability_review -eq 'completed_no_symbol_reachability' -and
    [string]$postgresDisposition.review.reachability_policy_effect -eq 'risk_reduced_but_still_blocking' -and
    [string]$postgresDisposition.review.waiver_state -eq 'none'
$hostedDatabaseUpdatedUtc = ([DateTimeOffset]$postgresDisposition.hosted_scan.database_updated_utc).ToUniversalTime().ToString('o')
$postgresRefresh = Get-Content -LiteralPath $postgresRefreshPath -Raw | ConvertFrom-Json
$postgresRefreshSha = (Get-FileHash -LiteralPath $postgresRefreshPath -Algorithm SHA256).Hash.ToLowerInvariant()
$dispositionSha = (Get-FileHash -LiteralPath $postgresDispositionPath -Algorithm SHA256).Hash.ToLowerInvariant()
$lockSha = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant()
$composePath = Join-Path $root 'Deploy\compose\compose.yaml'
$composeSha = (Get-FileHash -LiteralPath $composePath -Algorithm SHA256).Hash.ToLowerInvariant()
$refreshStatus = [string]$postgresRefresh.decision.status
$refreshDigestChanged = [bool]$postgresRefresh.observation.tag_manifest_changed
$postgresRefreshBound = [string]$postgresRefresh.result -eq 'PASS_DIAGNOSTIC' -and
    -not [bool]$postgresRefresh.release_authority -and
    -not [bool]$postgresRefresh.decision.lock_update_performed -and
    -not [bool]$postgresRefresh.decision.automatic_lock_update_allowed -and
    [string]$postgresRefresh.component.locked_index_digest -eq $expectedImageId -and
    [string]$postgresRefresh.bindings.vulnerability_disposition_sha256 -eq $dispositionSha -and
    [string]$postgresRefresh.bindings.toolchain_lock_sha256 -eq $lockSha -and
    [string]$postgresRefresh.bindings.compose_sha256 -eq $composeSha -and
    (($refreshStatus -eq 'NO_REFRESH_AVAILABLE' -and -not $refreshDigestChanged -and
        [string]$postgresRefresh.observation.observed_index_digest -eq $expectedImageId) -or
    ($refreshStatus -eq 'CANDIDATE_AVAILABLE_REQUIRES_FULL_QUALIFICATION' -and
        $refreshDigestChanged -and
        [string]$postgresRefresh.observation.observed_index_digest -match '^sha256:[a-f0-9]{64}$'))
$postgresCandidate = Get-Content -LiteralPath $postgresCandidatePath -Raw | ConvertFrom-Json
$postgresCandidateSha = (Get-FileHash -LiteralPath $postgresCandidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
$postgresCandidateBound = [string]$postgresCandidate.result -eq 'PASS_DIAGNOSTIC' -and
    -not [bool]$postgresCandidate.release_authority -and
    -not [bool]$postgresCandidate.candidate_pull_performed -and
    -not [bool]$postgresCandidate.source_mutation_performed -and
    [string]$postgresCandidate.decision.status -eq 'REJECTED_IDENTICAL_BLOCKING_COMPONENT' -and
    -not [bool]$postgresCandidate.decision.lock_update_performed -and
    -not [bool]$postgresCandidate.decision.automatic_lock_update_allowed -and
    [bool]$postgresCandidate.comparison.same_gosu_binary_sha256 -and
    [bool]$postgresCandidate.security_inference.candidate_inherits_recorded_blocker -and
    -not [bool]$postgresCandidate.security_inference.candidate_scan_claimed -and
    [int]$postgresCandidate.security_inference.inherited_high_or_critical -eq
        [int]$postgresDisposition.blocking_findings.total -and
    [string]$postgresCandidate.locked_probe.image_id -eq $expectedImageId -and
    [string]$postgresCandidate.bindings.vulnerability_disposition_sha256 -eq $dispositionSha -and
    [string]$postgresCandidate.bindings.toolchain_lock_sha256 -eq $lockSha -and
    [string]$postgresCandidate.bindings.compose_sha256 -eq $composeSha -and
    [string]$postgresCandidate.bindings.refresh_preflight_sha256 -eq $postgresRefreshSha
$postgresReachability = Get-Content -LiteralPath $postgresReachabilityPath -Raw | ConvertFrom-Json
$postgresReachabilitySha = (Get-FileHash -LiteralPath $postgresReachabilityPath -Algorithm SHA256).Hash.ToLowerInvariant()
$postgresReachabilitySarifSha = (Get-FileHash -LiteralPath $postgresReachabilitySarifPath -Algorithm SHA256).Hash.ToLowerInvariant()
$postgresReachabilityOsvSha = (Get-FileHash -LiteralPath $postgresReachabilityOsvPath -Algorithm SHA256).Hash.ToLowerInvariant()
$mappedReachabilityIds = @($postgresReachability.mapped_blocking_findings.findings |
    ForEach-Object { [string]$_.cve } | Sort-Object)
$expectedReachabilityIds = @($postgresDisposition.blocking_findings.vulnerability_ids |
    ForEach-Object { [string]$_ } | Sort-Object)
$postgresReachabilityBound = [string]$postgresReachability.result -eq 'PASS_DIAGNOSTIC' -and
    -not [bool]$postgresReachability.release_authority -and
    [string]$postgresReachability.review.status -eq
        'REVIEW_COMPLETE_NO_SYMBOL_REACHABILITY_STILL_BLOCKING' -and
    [bool]$postgresReachability.review.policy_blocking -and
    [string]$postgresReachability.review.risk_assessment -eq 'reduced_reachability_not_zero_risk' -and
    [string]$postgresReachability.review.waiver_state -eq 'none' -and
    -not [bool]$postgresReachability.review.owner_approval -and
    -not [bool]$postgresReachability.review.automatic_policy_exception -and
    -not [bool]$postgresReachability.review.lock_update_performed -and
    [string]$postgresReachability.binary.binary_sha256 -eq
        [string]$postgresCandidate.locked_probe.gosu_sha256 -and
    [string]$postgresReachability.scanner.name -eq 'govulncheck' -and
    [string]$postgresReachability.scanner.version -eq 'v1.7.0' -and
    [string]$postgresReachability.scanner.scan_level -eq 'symbol' -and
    [string]$postgresReachability.scanner.scan_mode -eq 'binary' -and
    [string]$postgresReachability.scanner.sarif_sha256 -eq $postgresReachabilitySarifSha -and
    [string]$postgresReachability.official_osv.sha256 -eq $postgresReachabilityOsvSha -and
    [string]$postgresReachability.official_osv.id -eq 'GO-2026-4970' -and
    [string]$postgresReachability.official_osv.alias -eq 'CVE-2026-39822' -and
    (@($postgresReachability.official_osv.affected_packages) -join ',') -eq 'os' -and
    @($postgresReachability.official_osv.vulnerable_symbols).Count -eq 12 -and
    [int]$postgresReachability.mapped_blocking_findings.expected -eq
        [int]$postgresDisposition.blocking_findings.total -and
    [int]$postgresReachability.mapped_blocking_findings.mapped -eq
        [int]$postgresDisposition.blocking_findings.total -and
    [int]$postgresReachability.mapped_blocking_findings.symbol_reachable -eq 0 -and
    [int]$postgresReachability.mapped_blocking_findings.package_only -eq 1 -and
    [int]$postgresReachability.mapped_blocking_findings.module_only -eq 21 -and
    ($mappedReachabilityIds -join ',') -eq ($expectedReachabilityIds -join ',') -and
    -not [bool]$postgresReachability.threat_model.network_listener -and
    -not [bool]$postgresReachability.threat_model.untrusted_network_parser -and
    [bool]$postgresReachability.threat_model.os_package_imported -and
    -not [bool]$postgresReachability.threat_model.vulnerable_os_symbols_reported_reachable -and
    [string]$postgresReachability.bindings.vulnerability_disposition_sha256 -eq $dispositionSha -and
    [string]$postgresReachability.bindings.official_candidate_sha256 -eq $postgresCandidateSha -and
    [string]$postgresReachability.bindings.toolchain_lock_sha256 -eq $lockSha -and
    [string]$postgresReachability.bindings.compose_sha256 -eq $composeSha
$postgresWaiverRequest = Get-Content -LiteralPath $postgresWaiverRequestPath -Raw | ConvertFrom-Json
$postgresWaiverRequestSha = (Get-FileHash -LiteralPath $postgresWaiverRequestPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
$postgresWaiverDecision = Get-Content -LiteralPath $postgresWaiverDecisionPath -Raw | ConvertFrom-Json
$postgresWaiverDecisionSha = (Get-FileHash -LiteralPath $postgresWaiverDecisionPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
$postgresWaiverBound = [string]$postgresWaiverRequest.waiver_id -eq 'WVR-0002' -and
    [string]$postgresWaiverRequest.status -eq 'draft_not_approved' -and
    [string]$postgresWaiverRequest.policy_effect -eq 'none_still_blocking' -and
    -not [bool]$postgresWaiverRequest.approval.owner_approval -and
    [string]$postgresWaiverRequest.approval.owner_authorization_mode -eq
        'owner_as_pr_author_or_current_head_reviewer' -and
    [int]$postgresWaiverRequest.approval.pull_request_number -eq 0 -and
    @($postgresWaiverRequest.approval.approved_review_ids).Count -eq 0 -and
    [int]$postgresWaiverRequest.duration.maximum_days -eq 30 -and
    $null -eq $postgresWaiverRequest.duration.effective_utc -and
    $null -eq $postgresWaiverRequest.duration.expires_utc -and
    -not [bool]$postgresWaiverRequest.activation.requested -and
    -not [bool]$postgresWaiverRequest.activation.effective -and
    -not [bool]$postgresWaiverRequest.activation.automatic_activation_allowed -and
    -not [bool]$postgresWaiverRequest.activation.offline_fixture_can_activate -and
    -not [bool]$postgresWaiverRequest.activation.release_authority -and
    [string]$postgresWaiverRequest.component.image_digest -eq $expectedImageId -and
    [string]$postgresWaiverRequest.component.binary_sha256 -eq
        [string]$postgresCandidate.locked_probe.gosu_sha256 -and
    [int]$postgresWaiverRequest.finding_scope.count -eq
        [int]$postgresDisposition.blocking_findings.total -and
    [string]$postgresWaiverDecision.result -eq 'PASS_DIAGNOSTIC' -and
    [string]$postgresWaiverDecision.decision -eq
        'DRAFT_READY_FOR_OWNER_DECISION_NOT_EFFECTIVE' -and
    [string]$postgresWaiverDecision.evaluation_mode -eq 'local_draft' -and
    [string]$postgresWaiverDecision.request_status -eq 'draft_not_approved' -and
    [string]$postgresWaiverDecision.request_sha256 -eq $postgresWaiverRequestSha -and
    -not [bool]$postgresWaiverDecision.waiver_effective -and
    [bool]$postgresWaiverDecision.policy_blocking -and
    -not [bool]$postgresWaiverDecision.component_policy_exception -and
    -not [bool]$postgresWaiverDecision.automatic_activation -and
    -not [bool]$postgresWaiverDecision.release_authority -and
    [int]$postgresWaiverDecision.approval.verified_approval_count -eq 0 -and
    -not [bool]$postgresWaiverDecision.approval.owner_authorization_verified -and
    [string]$postgresWaiverDecision.approval.owner_authorization_mode -eq 'unverified' -and
    [string]$postgresWaiverDecision.bindings.vulnerability_disposition_sha256 -eq $dispositionSha -and
    [string]$postgresWaiverDecision.bindings.reachability_review_sha256 -eq
        $postgresReachabilitySha -and
    [string]$postgresWaiverDecision.bindings.official_candidate_sha256 -eq
        $postgresCandidateSha -and
    [string]$postgresWaiverDecision.bindings.toolchain_lock_sha256 -eq $lockSha -and
    [string]$postgresWaiverDecision.bindings.compose_sha256 -eq $composeSha

$scoutVersionOutput = (docker scout version 2>$null) -join "`n"
$scoutVersion = if ($scoutVersionOutput -match 'version:\s*([^\s]+)') { $Matches[1] } else { 'unknown' }
$passed = $imageVerified -and $postgresSbomVerified -and $builderImageVerified -and
    $builderSbomVerified -and [string]$licensePolicy.result -eq 'PASS_DIAGNOSTIC' -and
    $postgresDispositionBound -and $postgresRefreshBound -and $postgresCandidateBound -and
    $postgresReachabilityBound -and $postgresWaiverBound
$report = [pscustomobject][ordered]@{
    schema_version = 9
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
        vulnerability_status = 'hosted_postgres_blocked_pending_remediation_or_approved_waiver'
        hosted_scanner = [string]$postgresDisposition.hosted_scan.scanner
        hosted_scanner_version = [string]$postgresDisposition.hosted_scan.scanner_version
        hosted_database_updated_utc = $hostedDatabaseUpdatedUtc
        postgres_high_or_critical = [int]$postgresDisposition.blocking_findings.total
        disposition = 'Data/Security/p0-12-postgres-vulnerability-disposition.json'
        disposition_bound = $postgresDispositionBound
        note = 'Hosted Trivy evidence is authoritative for the recorded PostgreSQL blocker; unauthenticated local Docker Scout remains supplementary only.'
    }
    postgres_refresh_preflight = [pscustomobject][ordered]@{
        file = 'Data/Security/p0-12-postgres-refresh-preflight.json'
        sha256 = $postgresRefreshSha
        result = [string]$postgresRefresh.result
        status = $refreshStatus
        tag_manifest_changed = $refreshDigestChanged
        observed_index_digest = [string]$postgresRefresh.observation.observed_index_digest
        lock_update_performed = [bool]$postgresRefresh.decision.lock_update_performed
        release_authority = [bool]$postgresRefresh.release_authority
        bindings_verified = $postgresRefreshBound
    }
    postgres_official_candidate = [pscustomobject][ordered]@{
        file = 'Data/Security/p0-12-postgres-official-candidate-evaluation.json'
        sha256 = $postgresCandidateSha
        result = [string]$postgresCandidate.result
        tag = [string]$postgresCandidate.official_candidate.tag
        candidate_index_digest = [string]$postgresCandidate.official_candidate.observed_index_digest
        decision = [string]$postgresCandidate.decision.status
        same_gosu_binary_sha256 = [bool]$postgresCandidate.comparison.same_gosu_binary_sha256
        inherited_high_or_critical = [int]$postgresCandidate.security_inference.inherited_high_or_critical
        candidate_scan_claimed = [bool]$postgresCandidate.security_inference.candidate_scan_claimed
        lock_update_performed = [bool]$postgresCandidate.decision.lock_update_performed
        release_authority = [bool]$postgresCandidate.release_authority
        bindings_verified = $postgresCandidateBound
    }
    postgres_gosu_reachability = [pscustomobject][ordered]@{
        file = 'Data/Security/p0-12-postgres-gosu-reachability-review.json'
        sha256 = $postgresReachabilitySha
        result = [string]$postgresReachability.result
        status = [string]$postgresReachability.review.status
        risk_assessment = [string]$postgresReachability.review.risk_assessment
        mapped_blocking_findings = [int]$postgresReachability.mapped_blocking_findings.mapped
        symbol_reachable = [int]$postgresReachability.mapped_blocking_findings.symbol_reachable
        package_only = [int]$postgresReachability.mapped_blocking_findings.package_only
        module_only = [int]$postgresReachability.mapped_blocking_findings.module_only
        sarif_sha256 = $postgresReachabilitySarifSha
        official_osv_sha256 = $postgresReachabilityOsvSha
        policy_blocking = [bool]$postgresReachability.review.policy_blocking
        waiver_state = [string]$postgresReachability.review.waiver_state
        owner_approval = [bool]$postgresReachability.review.owner_approval
        release_authority = [bool]$postgresReachability.release_authority
        bindings_verified = $postgresReachabilityBound
    }
    postgres_gosu_waiver_decision = [pscustomobject][ordered]@{
        request_file = 'Data/Security/p0-12-postgres-gosu-waiver-request.json'
        request_sha256 = $postgresWaiverRequestSha
        decision_file = 'Data/Security/p0-12-postgres-gosu-waiver-decision.json'
        decision_sha256 = $postgresWaiverDecisionSha
        waiver_id = [string]$postgresWaiverDecision.waiver_id
        request_status = [string]$postgresWaiverDecision.request_status
        decision = [string]$postgresWaiverDecision.decision
        waiver_effective = [bool]$postgresWaiverDecision.waiver_effective
        policy_blocking = [bool]$postgresWaiverDecision.policy_blocking
        verified_approval_count = [int]$postgresWaiverDecision.approval.verified_approval_count
        maximum_days = [int]$postgresWaiverDecision.duration.maximum_days
        release_authority = [bool]$postgresWaiverDecision.release_authority
        bindings_verified = $postgresWaiverBound
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
        'Remediate the 22 hosted PostgreSQL HIGH/CRITICAL findings or explicitly approve WVR-0002 with current-HEAD reviews and a maximum-30-day interval; the checked-in draft is not effective',
        'The newer official 18.6-alpine3.23 variant was rejected because its affected gosu binary is byte-identical to the locked image',
        'Exact locked builder manifest verified in GHCR',
        'Provision the labeled ephemeral UE 5.8 hosted runner',
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
