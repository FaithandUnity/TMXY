[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$contractPath = Join-Path $root 'Data\Governance\p0-hosted-ci-contract.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$postgresSbomPath = Join-Path $root 'Data\Security\postgres-18.6.sbom.cdx.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { $failures.Add($Message) }
}

$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$postgresSbomSha = (Get-FileHash -LiteralPath $postgresSbomPath -Algorithm SHA256).Hash.ToLowerInvariant()

Assert-Contract ([int]$contract.schema_version -eq 1) 'CI authority contract schema must be 1.'
Assert-Contract ([string]$contract.state -eq 'prepared_pending_authorization') `
    'Local contract must remain pending until a hosted provider is authorized.'
Assert-Contract (-not [bool]$contract.provider_binding.selected) `
    'A hosted provider must not be selected without explicit authorization.'
Assert-Contract ($null -eq $contract.provider_binding.provider -and $null -eq $contract.provider_binding.repository) `
    'Provider and repository must remain null before authorization.'
Assert-Contract ([string]$contract.protected_branch.name -eq 'main') 'Protected branch must be main.'
Assert-Contract (-not [bool]$contract.protected_branch.allow_direct_push) 'Direct push must be forbidden.'
Assert-Contract (-not [bool]$contract.protected_branch.allow_force_push) 'Force push must be forbidden.'
Assert-Contract (-not [bool]$contract.protected_branch.allow_administrator_bypass) `
    'Administrator bypass must be forbidden.'
Assert-Contract ([int]$contract.protected_branch.required_approvals -ge 1) `
    'At least one independent approval is required.'
Assert-Contract ([int]$contract.protected_branch.sensitive_change_required_approvals -ge 2) `
    'Sensitive changes require at least two approvals.'

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

Assert-Contract (
    [string]$contract.build_authority.backend_builder_digest -eq
    [string]$lock.backend_toolchain.container_image_digest) 'Backend builder digest does not match the lock.'
Assert-Contract (
    [string]$contract.supply_chain.backend_builder_sbom_sha256 -eq
    [string]$lock.backend_toolchain.qualification.sbom_sha256) 'Builder SBOM hash does not match the lock.'
Assert-Contract (
    [string]$contract.supply_chain.postgres_sbom_sha256 -eq $postgresSbomSha) `
    'PostgreSQL SBOM hash does not match the local evidence.'
Assert-Contract ([bool]$contract.supply_chain.authenticated_or_approved_offline_vulnerability_policy_required) `
    'Hosted vulnerability policy must be required.'
Assert-Contract ([bool]$contract.supply_chain.license_policy_required) `
    'Hosted license policy must be required.'
Assert-Contract ([bool]$contract.supply_chain.signed_provenance_required) `
    'Signed provenance must be required.'
Assert-Contract (-not [bool]$contract.authority_evidence.local_diagnostic_report_is_authority) `
    'Local diagnostic evidence must never be release authority.'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    state = [string]$contract.state
    required_check_count = $actualChecks.Count
    provider_selected = [bool]$contract.provider_binding.selected
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 5).Replace("`r`n", "`n").Replace("`r", "`n")
$json
if ($failures.Count -gt 0) { throw 'Hosted CI authority contract validation failed.' }
