[CmdletBinding()]
param([string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$scanner = Join-Path $root 'Tools\TMXY.Security\Test-RepositorySecrets.ps1'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

$requiredFiles = @(
    'Deploy/secret-contract/secret-contract.json',
    'Data/Security/secret-provider-binding.json',
    'Docs/Security/SECRET-MANAGEMENT.md',
    'Backend/modules/foundation/include/tmxy/foundation/redaction.hpp',
    'Backend/modules/foundation/src/redaction.cpp'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "Secret policy file is missing: $relativePath"
    }
}

$scan = (& $scanner -ScanRoot $root) | ConvertFrom-Json
if ([string]$scan.result -ne 'PASS' -or [int]$scan.finding_count -ne 0) {
    Add-Failure -Message 'Repository and reachable-history Secret scan did not pass.'
}
if ([string]$scan.disclosure_policy -ne 'fingerprints_only') {
    Add-Failure -Message 'Scanner disclosure policy must be fingerprints_only.'
}

$contractPath = Join-Path $root 'Deploy\secret-contract\secret-contract.json'
if (Test-Path -LiteralPath $contractPath -PathType Leaf) {
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    $postgresSecret = @($contract.secrets | Where-Object { $_.id -eq 'tmxy.postgres.superuser_password' })
    if ($postgresSecret.Count -ne 1 -or
        [string]$postgresSecret[0].container_target -ne '/run/secrets/tmxy_postgres_password') {
        Add-Failure -Message 'PostgreSQL Secret mount contract is missing or invalid.'
    }
}

$bindingPath = Join-Path $root 'Data\Security\secret-provider-binding.json'
if (Test-Path -LiteralPath $bindingPath -PathType Leaf) {
    $binding = Get-Content -LiteralPath $bindingPath -Raw | ConvertFrom-Json
    if ([string]$binding.result -ne 'PASS' -or
        [string]$binding.provider.storage -ne 'operating_system_keychain' -or
        -not [bool]$binding.rotation_drill.rotate_passed -or
        -not [bool]$binding.rotation_drill.revoke_passed -or
        -not [bool]$binding.rotation_drill.drill_secret_absent_after_test -or
        [bool]$binding.rotation_drill.value_disclosed_in_report) {
        Add-Failure -Message 'Secret Store binding or rotation evidence is invalid.'
    }
}

$localTestRoot = Join-Path $root 'Data\Local\SecretScannerTests'
$temporaryRoot = Join-Path $localTestRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    $syntheticValue = 'A1b2C3d4' * 5
    $fixturePath = Join-Path $temporaryRoot 'fixture.txt'
    [System.IO.File]::WriteAllText(
        $fixturePath,
        "password = $syntheticValue`n",
        [System.Text.UTF8Encoding]::new($false))
    $fixtureJson = & $scanner -ScanRoot $temporaryRoot -SkipGitHistory -NoThrow
    $fixture = $fixtureJson | ConvertFrom-Json
    if ([string]$fixture.result -ne 'FAIL' -or [int]$fixture.finding_count -lt 1) {
        Add-Failure -Message 'Scanner did not reject a synthetic literal credential.'
    }
    if ($fixtureJson -match [regex]::Escape($syntheticValue)) {
        Add-Failure -Message 'Scanner report disclosed the synthetic credential value.'
    }
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $expectedPrefix = [System.IO.Path]::GetFullPath($localTestRoot).TrimEnd([char[]]'\/') +
        [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTemporaryRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Secret scanner test cleanup escaped its local test root.'
    }
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
}

$report = [pscustomobject][ordered]@{
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    repository_files_scanned = [int]$scan.working_tree_files_scanned
    history_mode = [string]$scan.history_mode
    history_blobs_scanned = [int]$scan.history_blobs_scanned
    scanner_self_test = 'PASS'
    secret_store_rotation = 'PASS'
    finding_count = [int]$scan.finding_count
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 4
if ($failures.Count -gt 0) {
    throw "Secret policy validation failed with $($failures.Count) error(s)."
}
