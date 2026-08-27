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
$summaryGeneratorPath = Join-Path $root 'Tools/TMXY.SupplyChain/New-HostedVulnerabilitySummary.ps1'
$supplyChainPolicyPath = Join-Path $root 'Tests/CI/Test-HostedSupplyChainPolicy.ps1'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-HostedContract {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { $failures.Add($Message) }
}

foreach ($path in @(
        $mergePath,
        $releasePath,
        $codeOwnersPath,
        $actionlintPath,
        $contractPath,
        $summaryGeneratorPath,
        $supplyChainPolicyPath)) {
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
Assert-HostedContract ($merge -match '(?m)^\s{2}packages:\s*read\s*$') `
    'Merge workflow requires read-only access to verify the locked GHCR manifest.'
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
Assert-HostedContract ($merge -match "github\.event_name == 'pull_request' && always\(\)" -and
    $merge -match 'retention-days:\s*7') `
    'Pull-request vulnerability diagnostics must be retained briefly even when policy fails closed.'
Assert-HostedContract ($merge -match 'aquasecurity/setup-trivy@e6c2c5e321ed9123bda567646e2f96565e34abe1' -and
    $merge -match 'version:\s*v0\.74\.0') `
    'Hosted vulnerability scanning must use the reviewed setup action and available Trivy release.'
Assert-HostedContract ($merge -match 'trivy --version --cache-dir "\$\{cache_dir\}"') `
    'Hosted vulnerability identity must bind the database cache used by both scans.'
Assert-HostedContract ($merge -match 'New-HostedVulnerabilitySummary\.ps1' -and
    ([regex]::Matches($merge, 'hosted-vulnerability-summary\.json').Count -ge 3)) `
    'Hosted scans must create and retain a sanitized run-bound vulnerability summary.'
Assert-HostedContract ($merge -match "-SourceRevision '\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'" -and
    $merge -match "-WorkflowRevision '\$\{\{ github\.sha \}\}'") `
    'Hosted vulnerability summaries must distinguish the reviewed source revision from the workflow merge revision.'

if (Test-Path -LiteralPath $summaryGeneratorPath -PathType Leaf) {
    $summaryTestRoot = Join-Path ([IO.Path]::GetTempPath()) ("tmxy-hosted-summary-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $summaryTestRoot | Out-Null
        $syntheticReport = [pscustomobject][ordered]@{
            SchemaVersion = 2
            ArtifactName = 'synthetic-test-sbom'
            ArtifactType = 'cyclonedx'
            CreatedAt = '2026-08-27T03:33:39Z'
            Results = @([pscustomobject][ordered]@{
                Target = 'Python'
                Class = 'lang-pkgs'
                Type = 'python-pkg'
            })
        }
        $reportJson = ($syntheticReport | ConvertTo-Json -Depth 4) + "`n"
        $postgresTestPath = Join-Path $summaryTestRoot 'postgres.json'
        $builderTestPath = Join-Path $summaryTestRoot 'builder.json'
        $identityTestPath = Join-Path $summaryTestRoot 'identity.txt'
        $summaryTestPath = Join-Path $summaryTestRoot 'summary.json'
        [IO.File]::WriteAllText($postgresTestPath, $reportJson, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($builderTestPath, $reportJson, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($identityTestPath, @'
Version: 0.74.0
Vulnerability DB:
  Version: 2
  UpdatedAt: 2026-08-27 02:16:59.49157034 +0000 UTC
  NextUpdate: 2026-08-28 02:16:59.491570069 +0000 UTC
  DownloadedAt: 2026-08-27 03:33:39.075679278 +0000 UTC
'@, [Text.UTF8Encoding]::new($false))
        & $summaryGeneratorPath `
            -PostgresVulnerabilityReport $postgresTestPath `
            -BuilderVulnerabilityReport $builderTestPath `
            -VulnerabilityDatabaseIdentity $identityTestPath `
            -OutputPath $summaryTestPath `
            -Repository 'FaithandUnity/TMXY' `
            -RunId '1' `
            -RunAttempt '1' `
            -SourceRevision ('a' * 40) `
            -WorkflowRevision ('b' * 40) `
            -EventName 'pull_request' | Out-Null
        $summaryTest = Get-Content -LiteralPath $summaryTestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $updatedTestUtc = ([DateTimeOffset]$summaryTest.vulnerability_database.updated_utc).ToUniversalTime().ToString('o')
        $downloadedTestUtc = ([DateTimeOffset]$summaryTest.vulnerability_database.downloaded_utc).ToUniversalTime().ToString('o')
        Assert-HostedContract ($updatedTestUtc -eq '2026-08-27T02:16:59.4915703+00:00' -and
            $downloadedTestUtc -eq '2026-08-27T03:33:39.0756792+00:00') `
            'Hosted vulnerability summary must parse Trivy Go timestamps without losing UTC identity.'
        Assert-HostedContract ([string]$summaryTest.provider.source_revision -eq ('a' * 40) -and
            [string]$summaryTest.provider.workflow_revision -eq ('b' * 40)) `
            'Hosted vulnerability summary must preserve distinct source and workflow revisions.'
        Assert-HostedContract (@($summaryTest.reports).Count -eq 2 -and
            @($summaryTest.reports | Where-Object { [int]$_.finding_count -ne 0 }).Count -eq 0 -and
            [int]$summaryTest.total_high_or_critical -eq 0) `
            'Hosted vulnerability summary must accept Trivy result entries that omit Vulnerabilities when no findings exist.'
        $currentGoTimestamp = [DateTimeOffset]::UtcNow.ToString(
            'yyyy-MM-dd HH:mm:ss.fffffff',
            [Globalization.CultureInfo]::InvariantCulture) + '00 +0000 UTC'
        [IO.File]::WriteAllText($identityTestPath, @"
Version: 0.74.0
Vulnerability DB:
  Version: 2
  UpdatedAt: $currentGoTimestamp
  NextUpdate: $currentGoTimestamp
  DownloadedAt: $currentGoTimestamp
"@, [Text.UTF8Encoding]::new($false))
        $policyTest = & $supplyChainPolicyPath `
            -RebuildRoot $root `
            -Mode MergeGate `
            -PostgresVulnerabilityReport $postgresTestPath `
            -BuilderVulnerabilityReport $builderTestPath `
            -VulnerabilityDatabaseIdentity $identityTestPath | ConvertFrom-Json
        Assert-HostedContract ([string]$policyTest.result -eq 'PASS' -and
            [int]$policyTest.blocking_vulnerabilities.postgres_high_or_critical -eq 0 -and
            [int]$policyTest.blocking_vulnerabilities.builder_high_or_critical -eq 0) `
            'Hosted supply-chain policy must accept Trivy result entries that omit Vulnerabilities when no findings exist.'
    }
    catch {
        $failures.Add("Hosted vulnerability summary regression test failed: $($_.Exception.Message)")
    }
    finally {
        if (Test-Path -LiteralPath $summaryTestRoot -PathType Container) {
            Remove-Item -LiteralPath $summaryTestRoot -Recurse -Force
        }
    }
}

$builderDigest = if ($null -ne $contract) {
    [string]$contract.build_authority.backend_builder_digest
}
else { '' }
Assert-HostedContract ($builderDigest -match '^sha256:[a-f0-9]{64}$') `
    'Hosted contract must carry a valid locked backend builder digest.'
Assert-HostedContract ([string]$contract.supply_chain.vulnerability_scanner -eq 'trivy' -and
    [string]$contract.supply_chain.vulnerability_scanner_version -eq '0.74.0' -and
    [int]$contract.supply_chain.vulnerability_database_max_age_hours -eq 48) `
    'Hosted contract must bind the scanner version and maximum vulnerability database age.'
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
