[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p0-readiness.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Evidence,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RequiredAction
    )
    $checks.Add([pscustomobject][ordered]@{
        id = $Id
        passed = $Passed
        evidence = $Evidence.Replace('\', '/')
        required_action = $RequiredAction
    })
}

$ue = Get-Content -LiteralPath (Join-Path $root 'Data\BuildBaseline\p0-10a-ue-validation.json') -Raw |
    ConvertFrom-Json
$quality = Get-Content -LiteralPath (Join-Path $root 'Data\BuildBaseline\p0-12-local-quality-gates.json') -Raw |
    ConvertFrom-Json
$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') -Raw |
    ConvertFrom-Json
$secret = Get-Content -LiteralPath (Join-Path $root 'Data\Security\p0-14-secret-scan.json') -Raw |
    ConvertFrom-Json
$golden = Get-Content -LiteralPath (Join-Path $root 'Data\GoldenSamples\p0-golden-samples.json') -Raw |
    ConvertFrom-Json
$hostingStatus = Get-Content -LiteralPath (
    Join-Path $root 'Data\Governance\p0-github-hosting-status.json') -Raw | ConvertFrom-Json

Add-Check -Id 'rights_and_read_only' -Passed (
    (Test-Path -LiteralPath (Join-Path $root 'Docs\Governance\COPYRIGHT-BASELINE.md')) -and
    (Test-Path -LiteralPath (Join-Path $root 'README.md'))) `
    -Evidence 'Docs/Governance/COPYRIGHT-BASELINE.md; README.md' -RequiredAction ''
Add-Check -Id 'input_manifests' -Passed (
    Test-Path -LiteralPath (Join-Path $root 'Data\RawManifests\BASELINE.md')) `
    -Evidence 'Data/RawManifests/BASELINE.md' -RequiredAction ''
Add-Check -Id 'architecture_and_standard' -Passed (
    (Test-Path -LiteralPath (Join-Path $root 'Docs\Architecture\TARGET-ARCHITECTURE.md')) -and
    (Test-Path -LiteralPath (Join-Path $root 'Docs\Standards\ENGINEERING-STANDARD.md'))) `
    -Evidence 'Docs/Architecture/TARGET-ARCHITECTURE.md; Docs/Standards/ENGINEERING-STANDARD.md' `
    -RequiredAction ''
Add-Check -Id 'ue_baseline' -Passed ([string]$ue.result -eq 'PASS') `
    -Evidence 'Data/BuildBaseline/p0-10a-ue-validation.json' -RequiredAction ''
Add-Check -Id 'golden_samples' -Passed (
    [int]$golden.summary.sample_count -eq 42 -and [string]$golden.copy_policy -eq 'reference_only') `
    -Evidence 'Data/GoldenSamples/p0-golden-samples.json' -RequiredAction ''
Add-Check -Id 'platform_budget' -Passed (
    Test-Path -LiteralPath (Join-Path $root 'Data\Performance\p0-platform-budget.json')) `
    -Evidence 'Data/Performance/p0-platform-budget.json' -RequiredAction ''
Add-Check -Id 'local_repository' -Passed (
    (Test-Path -LiteralPath (Join-Path $root '.git')) -and
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $root) '.git'))) `
    -Evidence '.git; Docs/Governance/VERSION-CONTROL-POLICY.md' -RequiredAction ''
Add-Check -Id 'toolchain_release_authority' -Passed ([string]$lock.lock_state -eq 'locked') `
    -Evidence 'Data/Toolchain/toolchain.lock.json; Data/Toolchain/backend-toolchain-qualification.json; Data/Security/tmxy-backend-builder.sbom.cdx.json; Data/BuildBaseline/p0-08-ue-packaging-waiver.json' `
    -RequiredAction ''
Add-Check -Id 'hosted_ci_authority' -Passed ([bool]$quality.authoritative_release_gate) `
    -Evidence 'Data/Governance/p0-hosted-ci-contract.json; Data/Governance/p0-github-hosting-status.json; Data/BuildBaseline/p0-12-local-quality-gates.json' `
    -RequiredAction ('GitHub is bound but release authority is blocked: ' +
        (@($hostingStatus.blockers) -join ', ') + '.')
$secretProviderPath = Join-Path $root 'Data\Security\secret-provider-binding.json'
$secretProviderPassed = $false
if (Test-Path -LiteralPath $secretProviderPath -PathType Leaf) {
    $secretProvider = Get-Content -LiteralPath $secretProviderPath -Raw | ConvertFrom-Json
    $secretProviderPassed = [string]$secretProvider.result -eq 'PASS' -and
        [bool]$secretProvider.rotation_drill.drill_secret_absent_after_test
}
Add-Check -Id 'secret_store_binding' -Passed (
    [string]$secret.result -eq 'PASS' -and $secretProviderPassed) `
    -Evidence 'Data/Security/p0-14-secret-scan.json; Deploy/secret-contract/secret-contract.json' `
    -RequiredAction 'Bind the proven contract to the selected hosted CI/production Secret Store.'
$resourcingPath = Join-Path $root 'Data\Governance\p1-resourcing.json'
$resourcingPassed = $false
if (Test-Path -LiteralPath $resourcingPath -PathType Leaf) {
    $resourcing = Get-Content -LiteralPath $resourcingPath -Raw | ConvertFrom-Json
    $resourcingPassed = [string]$resourcing.status -eq 'frozen_execution_charter' -and
        @($resourcing.workstreams | ForEach-Object { @($_.tasks) }).Count -eq 28
}
Add-Check -Id 'p1_resourcing' -Passed $resourcingPassed `
    -Evidence 'Data/Governance/p1-resourcing.json' `
    -RequiredAction 'Approve the frozen P1 execution charter during P0-16 review.'

$failed = @($checks | Where-Object { -not $_.passed })
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failed.Count -eq 0) { 'READY_FOR_G0_REVIEW' } else { 'NOT_READY' }
    p0_completed_items = 17
    p0_total_items = 19
    passed_check_count = $checks.Count - $failed.Count
    total_check_count = $checks.Count
    checks = @($checks)
    blockers = @($failed | ForEach-Object { $_.required_action })
    review_policy = 'P0-16 and G0 cannot pass while any check is false.'
}
$json = ($report | ConvertTo-Json -Depth 7).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
