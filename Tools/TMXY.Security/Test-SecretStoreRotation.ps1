[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\secret-provider-binding.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$dockerPath = (Get-Command 'docker.exe' -ErrorAction Stop).Source
$pwshPath = (Get-Command 'pwsh.exe' -ErrorAction Stop).Source
$drillId = "tmxy/p0-14/rotation-$([Guid]::NewGuid().ToString('N'))"
$created = $false
$revoked = $false

function New-SyntheticSecret {
    $bytes = [byte[]]::new(48)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [System.Convert]::ToBase64String($bytes)
}

function Invoke-DockerPass {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [AllowEmptyString()][string]$StandardInput = '',
        [hashtable]$Environment = @{}
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $dockerPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $true
    foreach ($key in $Environment.Keys) { $startInfo.Environment[$key] = [string]$Environment[$key] }
    foreach ($argument in @('pass') + $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($StandardInput) { $process.StandardInput.Write($StandardInput) }
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdout.TrimEnd("`r", "`n")
        stderr_kind = if ($stderr) { 'present' } else { 'none' }
    }
}

function Get-ResolvedSecretFingerprint {
    param([Parameter(Mandatory = $true)][string]$Reference)
    $fingerprintCommand = @'
$value = [Environment]::GetEnvironmentVariable('TMXY_P0_SECRET')
$bytes = [Text.Encoding]::UTF8.GetBytes($value)
$hash = [Security.Cryptography.SHA256]::HashData($bytes)
[Convert]::ToHexString($hash).ToLowerInvariant()
'@
    return Invoke-DockerPass -Arguments @(
        'run', '--', $pwshPath, '-NoLogo', '-NoProfile', '-Command', $fingerprintCommand) `
        -Environment @{ TMXY_P0_SECRET = $Reference }
}

function Get-SecretFingerprint {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

$first = New-SyntheticSecret
$second = New-SyntheticSecret
$setPassed = $false
$readPassed = $false
$rotationPassed = $false
$revocationPassed = $false
try {
    $set = Invoke-DockerPass -Arguments @(
        'set', $drillId, '--metadata', 'owner=platform_security',
        '--metadata', 'purpose=p0-14-rotation-drill') -StandardInput $first
    $setPassed = $set.exit_code -eq 0
    if (-not $setPassed) { throw 'Docker Pass could not create the synthetic drill Secret.' }
    $created = $true

    $read = Get-ResolvedSecretFingerprint -Reference "se://$drillId"
    $readPassed = $read.exit_code -eq 0 -and $read.stdout -eq (Get-SecretFingerprint -Value $first)
    if (-not $readPassed) { throw 'Docker Pass read-back verification failed.' }

    $rotate = Invoke-DockerPass -Arguments @('set', $drillId, '--force') -StandardInput $second
    $rotatedRead = Get-ResolvedSecretFingerprint -Reference "se://$drillId"
    $rotationPassed = $rotate.exit_code -eq 0 -and $rotatedRead.exit_code -eq 0 -and
        $rotatedRead.stdout -ne (Get-SecretFingerprint -Value $first) -and
        $rotatedRead.stdout -eq (Get-SecretFingerprint -Value $second)
    if (-not $rotationPassed) { throw 'Docker Pass rotation verification failed.' }

    $remove = Invoke-DockerPass -Arguments @('rm', $drillId)
    $created = $false
    $removedRead = Get-ResolvedSecretFingerprint -Reference "se://$drillId"
    $revocationPassed = $remove.exit_code -eq 0 -and $removedRead.exit_code -ne 0
    $revoked = $revocationPassed
    if (-not $revocationPassed) { throw 'Docker Pass revocation verification failed.' }
}
finally {
    if ($created) {
        $cleanup = Invoke-DockerPass -Arguments @('rm', $drillId)
        $revoked = $cleanup.exit_code -eq 0
    }
    $first = $null
    $second = $null
}

$version = Invoke-DockerPass -Arguments @('version')
$providerVersion = if ($version.stdout -match 'Version:\s*([^\s]+)') { $Matches[1] } else { 'unknown' }
$passed = $setPassed -and $readPassed -and $rotationPassed -and $revocationPassed -and $revoked
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    provider = [pscustomobject][ordered]@{
        name = 'Docker Pass local keychain'
        version = $providerVersion
        storage = 'operating_system_keychain'
        remote_login_required = $false
    }
    application_contract = [pscustomobject][ordered]@{
        secret_id = 'tmxy.postgres.superuser_password'
        provider_reference = 'se://tmxy/development/postgres/password'
        container_target = '/run/secrets/tmxy_postgres_password'
        values_committed_to_repository = $false
    }
    rotation_drill = [pscustomobject][ordered]@{
        synthetic_non_reusable_value = $true
        create_passed = $setPassed
        read_passed = $readPassed
        rotate_passed = $rotationPassed
        revoke_passed = $revocationPassed
        drill_secret_absent_after_test = $revoked
        value_disclosed_in_report = $false
    }
}
$json = ($report | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'Secret Store rotation drill failed.' }
