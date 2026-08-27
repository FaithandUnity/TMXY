[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$contractPath = Join-Path $root 'Data\Governance\p0-hosted-ci-contract.json'
$hostingStatusPath = Join-Path $root 'Data\Governance\p0-github-hosting-status.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$postgresSbomPath = Join-Path $root 'Data\Security\postgres-18.6.sbom.cdx.json'
$licenseEvidencePath = Join-Path $root 'Data\Security\p0-12-license-evidence.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { $failures.Add($Message) }
}

$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$hostingStatus = Get-Content -LiteralPath $hostingStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$postgresSbomSha = (Get-FileHash -LiteralPath $postgresSbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
$licenseEvidenceSha = (Get-FileHash -LiteralPath $licenseEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()

Assert-Contract ([int]$contract.schema_version -eq 2) 'CI authority contract schema must be 2.'
Assert-Contract ([string]$contract.state -eq 'github_workflows_prepared_pending_external_authority') `
    'The GitHub binding must remain pending until protected hosted authority exists.'
Assert-Contract ([bool]$contract.provider_binding.selected) `
    'The authorized GitHub provider binding must be selected.'
Assert-Contract ([string]$contract.provider_binding.provider -eq 'github' -and
    [string]$contract.provider_binding.repository -eq 'FaithandUnity/TMXY') `
    'Provider binding must identify the authorized GitHub repository.'
Assert-Contract ([string]$contract.provider_binding.remote_name -eq 'origin' -and
    [string]$contract.provider_binding.remote_url -eq 'https://github.com/FaithandUnity/TMXY.git') `
    'Provider binding must use the reviewed origin URL.'
Assert-Contract ([string]$contract.protected_branch.name -eq 'main') 'Protected branch must be main.'
Assert-Contract (-not [bool]$contract.protected_branch.allow_direct_push) 'Direct push must be forbidden.'
Assert-Contract (-not [bool]$contract.protected_branch.allow_force_push) 'Force push must be forbidden.'
Assert-Contract (-not [bool]$contract.protected_branch.allow_deletion) 'Branch deletion must be forbidden.'
Assert-Contract (-not [bool]$contract.protected_branch.allow_administrator_bypass) `
    'Administrator bypass must be forbidden.'
Assert-Contract ([int]$contract.protected_branch.required_approvals -ge 1) `
    'At least one independent approval is required.'
Assert-Contract ([int]$contract.protected_branch.sensitive_change_required_approvals -ge 2) `
    'Sensitive changes require at least two approvals.'
Assert-Contract ([bool]$contract.protected_branch.dismiss_stale_approvals) `
    'New commits must dismiss stale approvals.'
Assert-Contract ([bool]$contract.protected_branch.require_code_owner_review) `
    'Code owner review must be required.'

$requiredChecks = @(
    'policy/repository',
    'security/secrets',
    'backend/clang21',
    'backend/static-analysis',
    'backend/postgres-migration',
    'client/ue58-build-automation',
    'supply-chain/policy',
    'release/provenance'
)
$actualChecks = @($contract.required_checks)
Assert-Contract ($actualChecks.Count -eq $requiredChecks.Count) 'Required hosted check count changed.'
foreach ($check in $requiredChecks) {
    Assert-Contract ($actualChecks -contains $check) "Required hosted check is missing: $check"
}

Assert-Contract (-not [bool]$contract.trust_boundary.untrusted_change_receives_secrets) `
    'Untrusted changes must not receive secrets.'
Assert-Contract (-not [bool]$contract.trust_boundary.untrusted_change_writes_shared_cache) `
    'Untrusted changes must not write shared caches.'
Assert-Contract (-not [bool]$contract.trust_boundary.untrusted_change_publishes_release_artifacts) `
    'Untrusted changes must not publish release artifacts.'
Assert-Contract (-not [bool]$contract.cache_contract.cache_hit_bypasses_verification) `
    'Cache hits must not bypass verification.'
Assert-Contract (-not [bool]$contract.cache_contract.secret_material_allowed) `
    'Secret material must not enter CI caches.'
Assert-Contract (-not [bool]$contract.workflow_binding.untrusted_workflow_has_release_permissions) `
    'Untrusted workflows must not receive release permissions.'
Assert-Contract ([bool]$contract.workflow_binding.shared_cache_write_requires_protected_main) `
    'Shared cache writes must require protected main authority.'
Assert-Contract (@($contract.workflow_binding.ue_runner_labels) -contains 'tmxy-ephemeral') `
    'UE authority must run on an ephemeral self-hosted runner.'

Assert-Contract (
    [string]$contract.build_authority.backend_builder_digest -eq
    [string]$lock.backend_toolchain.container_image_digest) 'Backend builder digest does not match the lock.'
Assert-Contract (
    [string]$contract.supply_chain.backend_builder_sbom_sha256 -eq
    [string]$lock.backend_toolchain.qualification.sbom_sha256) 'Builder SBOM hash does not match the lock.'
Assert-Contract (
    [string]$contract.supply_chain.postgres_sbom_sha256 -eq $postgresSbomSha) `
    'PostgreSQL SBOM hash does not match the local evidence.'
Assert-Contract (
    [string]$contract.supply_chain.license_evidence_path -eq
        'Data/Security/p0-12-license-evidence.json' -and
    [string]$contract.supply_chain.license_evidence_sha256 -eq $licenseEvidenceSha) `
    'Supplemental license evidence does not match the hosted contract.'
Assert-Contract ([bool]$contract.supply_chain.authenticated_or_approved_offline_vulnerability_policy_required) `
    'Hosted vulnerability policy must be required.'
Assert-Contract ([bool]$contract.supply_chain.license_policy_required) `
    'Hosted license policy must be required.'
Assert-Contract ([bool]$contract.supply_chain.signed_provenance_required) `
    'Signed provenance must be required.'
Assert-Contract (-not [bool]$contract.authority_evidence.local_diagnostic_report_is_authority) `
    'Local diagnostic evidence must never be release authority.'
Assert-Contract ([int]$contract.authority_evidence.minimum_retention_days -eq 365) `
    'Hosted authority evidence retention must remain 365 days.'
Assert-Contract ([int]$hostingStatus.schema_version -eq 1 -and
    [string]$hostingStatus.provider.repository -eq 'FaithandUnity/TMXY') `
    'GitHub hosting observation must identify the bound repository.'
Assert-Contract (-not [bool]$hostingStatus.completion_criteria_satisfied -and
    -not [bool]$hostingStatus.release_authority) `
    'Current hosting observation must not claim release authority.'
Assert-Contract (-not [bool]$hostingStatus.branch_authority.protected -and
    -not [bool]$hostingStatus.branch_authority.required_checks_enforced) `
    'Current evidence must accurately retain the unprotected main blocker.'
Assert-Contract ([int]$hostingStatus.runners.matching_ephemeral_ue58_count -eq 0) `
    'Current evidence must retain the missing UE 5.8 ephemeral runner blocker.'

$workflowContract = (& (Join-Path $root 'Tests\CI\Test-HostedWorkflowContract.ps1') `
        -RebuildRoot $root) | ConvertFrom-Json
Assert-Contract ([string]$workflowContract.result -eq 'PASS') `
    'Hosted workflow source contract did not pass.'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    state = [string]$contract.state
    required_check_count = $actualChecks.Count
    provider_selected = [bool]$contract.provider_binding.selected
    provider = [string]$contract.provider_binding.provider
    repository = [string]$contract.provider_binding.repository
    hosted_release_authority = [bool]$hostingStatus.release_authority
    hosted_blocker_count = [int]$hostingStatus.blocker_count
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 5).Replace("`r`n", "`n").Replace("`r", "`n")
$json
if ($failures.Count -gt 0) { throw 'Hosted CI authority contract validation failed.' }
