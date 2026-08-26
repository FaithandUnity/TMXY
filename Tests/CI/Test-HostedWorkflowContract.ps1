[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$mergePath = Join-Path $root '.github/workflows/p0-required-checks.yml'
$releasePath = Join-Path $root '.github/workflows/p0-release-provenance.yml'
$codeOwnersPath = Join-Path $root '.github/CODEOWNERS'
$actionlintPath = Join-Path $root '.github/actionlint.yaml'
$contractPath = Join-Path $root 'Data/Governance/p0-hosted-ci-contract.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-HostedContract {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { $failures.Add($Message) }
}

foreach ($path in @($mergePath, $releasePath, $codeOwnersPath, $actionlintPath, $contractPath)) {
    Assert-HostedContract (Test-Path -LiteralPath $path -PathType Leaf) "Required hosted CI file is missing: $path"
}

$merge = if (Test-Path -LiteralPath $mergePath) {
    Get-Content -LiteralPath $mergePath -Raw -Encoding UTF8
}
else { '' }
$release = if (Test-Path -LiteralPath $releasePath) {
    Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8
}
else { '' }
$codeOwners = if (Test-Path -LiteralPath $codeOwnersPath) {
    Get-Content -LiteralPath $codeOwnersPath -Raw -Encoding UTF8
}
else { '' }
$actionlint = if (Test-Path -LiteralPath $actionlintPath) {
    Get-Content -LiteralPath $actionlintPath -Raw -Encoding UTF8
}
else { '' }
$contract = if (Test-Path -LiteralPath $contractPath) {
    Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else { $null }

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
foreach ($check in $requiredChecks) {
    $count = [regex]::Matches($merge, "(?m)^\s+name:\s+$([regex]::Escape($check))\s*$").Count
    Assert-HostedContract ($count -eq 1) "Hosted merge workflow must map exactly one job to $check."
}

Assert-HostedContract ($merge -match '(?m)^\s{2}pull_request:\s*$') `
    'Required-check workflow must run for pull requests.'
Assert-HostedContract ($merge -match '(?m)^\s{2}push:\s*$') `
    'Required-check workflow must run after protected main updates.'
Assert-HostedContract ($merge -notmatch '(?m)^\s*pull_request_target:\s*$') `
    'Untrusted changes must not run through pull_request_target.'
Assert-HostedContract ($merge -match '(?m)^permissions:\s*\n\s{2}contents:\s*read\s*$') `
    'Merge workflow must default to read-only contents permission.'
Assert-HostedContract ($merge -notmatch '(?m)^\s+(?:id-token|attestations|packages):\s*write\s*$') `
    'Merge workflow must not receive release write permissions.'
Assert-HostedContract ($merge -notmatch '\$\{\{\s*secrets\.') `
    'Merge workflow must not inject configured repository secrets.'
Assert-HostedContract ($merge -notmatch 'actions/cache@') `
    'Unified cache actions can write from untrusted runs; use explicit restore/save actions.'
Assert-HostedContract ($merge -match 'actions/cache/restore@0400d5f644dc74513175e3cd8d07132dd4860809') `
    'Backend cache restore must be pinned to the reviewed action revision.'
Assert-HostedContract ($merge -match 'actions/cache/save@0400d5f644dc74513175e3cd8d07132dd4860809') `
    'Backend cache save must be a separate protected-main-only step.'
Assert-HostedContract ($merge -match "steps\.cache_authority\.outputs\.protected == 'true'") `
    'Shared cache writes must require an API-confirmed protected main branch.'
Assert-HostedContract ($merge -match '--network none --read-only --cap-drop ALL') `
    'Locked backend jobs must build with no network, read-only root, and no capabilities.'
Assert-HostedContract ($merge -match 'tmxy-ue58' -and $merge -match 'tmxy-ephemeral') `
    'UE authority must require an ephemeral UE 5.8 self-hosted runner.'
Assert-HostedContract ($merge -match 'retention-days:\s*90') `
    'Current hosted diagnostic retention must remain explicit until 365-day authority storage is available.'
Assert-HostedContract ($merge -match 'aquasecurity/setup-trivy@e6c2c5e321ed9123bda567646e2f96565e34abe1' -and
    $merge -match 'version:\s*v0\.74\.0') `
    'Hosted vulnerability scanning must use the reviewed setup action and available Trivy release.'

$builderDigest = if ($null -ne $contract) {
    [string]$contract.build_authority.backend_builder_digest
}
else { '' }
Assert-HostedContract ($builderDigest -match '^sha256:[a-f0-9]{64}$') `
    'Hosted contract must carry a valid locked backend builder digest.'
Assert-HostedContract ($merge.Contains($builderDigest) -and $release.Contains($builderDigest)) `
    'Both hosted workflows must bind the exact backend builder digest.'

Assert-HostedContract ($release -match '(?m)^\s{2}workflow_dispatch:\s*$') `
    'Release provenance must require an explicit protected dispatch.'
Assert-HostedContract ($release -notmatch '(?m)^\s{2}(?:pull_request|push):\s*$') `
    'Release provenance must not run from untrusted changes or an ordinary push.'
$identityPermissionName = 'id-' + 'token'
Assert-HostedContract ($release -match "(?m)^\s{2}$($identityPermissionName):\s*write\s*`$" -and
    $release -match '(?m)^\s{2}attestations:\s*write\s*$' -and
    $release -match '(?m)^\s{2}packages:\s*write\s*$') `
    'Release provenance must carry only the required signing and registry permissions.'
Assert-HostedContract ($release -match "test .*\.protected.* = true") `
    'Release workflow must fail closed unless GitHub reports main as protected.'
Assert-HostedContract ($release -match 'environment:\s*p0-release') `
    'Release provenance must bind the protected p0-release environment.'
Assert-HostedContract ($release -match 'actions/attest-build-provenance@e8998f949152b193b063cb0ec769d69d929409be') `
    'Release provenance action must be pinned to the reviewed revision.'
Assert-HostedContract ($release -match 'push-to-registry:\s*true') `
    'The locked OCI manifest must receive a registry attestation.'
Assert-HostedContract ($codeOwners -match '(?m)^\*\s+@FaithandUnity\s*$') `
    'CODEOWNERS must define the current repository owner.'
Assert-HostedContract ($actionlint -match '(?m)^\s+-\s+tmxy-ue58\s*$' -and
    $actionlint -match '(?m)^\s+-\s+tmxy-ephemeral\s*$') `
    'Actionlint must recognize both custom ephemeral UE runner labels.'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    required_check_count = $requiredChecks.Count
    merge_workflow = '.github/workflows/p0-required-checks.yml'
    release_workflow = '.github/workflows/p0-release-provenance.yml'
    untrusted_secret_injection = $false
    untrusted_shared_cache_write = $false
    ue_runner = 'self-hosted/Windows/X64/tmxy-ue58/tmxy-ephemeral'
    diagnostic_retention_days = 90
    authority_retention_requirement_satisfied = $false
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
$json
if ($failures.Count -gt 0) { throw 'Hosted workflow contract validation failed.' }
