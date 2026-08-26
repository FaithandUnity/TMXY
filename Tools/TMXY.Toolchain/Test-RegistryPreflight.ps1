[CmdletBinding()]
param(
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Toolchain\registry-preflight.json',
    [int]$TimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$registryHost = 'registry-1.docker.io'
$registryUrl = "https://$registryHost/v2/"

function Invoke-CurlProbe {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('4', '6')][string]$AddressFamily,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][int]$Timeout
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command 'curl.exe' -ErrorAction Stop).Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @("-$AddressFamily", '--silent', '--show-error', '--head', '--max-time', [string]$Timeout, $Url)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $response = ($stdout + $stderr).Trim()
    return [pscustomobject][ordered]@{
        address_family = "IPv$AddressFamily"
        passed = $process.ExitCode -eq 0 -and $stdout -match 'HTTP/\S+\s+401'
        exit_code = $process.ExitCode
        response_kind = if ($response -match 'timed out') { 'timeout' } elseif ($process.ExitCode -eq 0) { 'http_response' } else { 'connection_error' }
        tls_verification = 'enabled'
    }
}

$dnsRecords = @(Resolve-DnsName -Name $registryHost -Type A_AAAA -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress } | ForEach-Object { [string]$_.IPAddress })
$ipv4 = Invoke-CurlProbe -AddressFamily '4' -Url $registryUrl -Timeout $TimeoutSeconds
$ipv6 = Invoke-CurlProbe -AddressFamily '6' -Url $registryUrl -Timeout $TimeoutSeconds
$reachable = $ipv4.passed -or $ipv6.passed
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($reachable) { 'PASS' } else { 'BLOCKED_NETWORK' }
    registry = $registryHost
    endpoint = $registryUrl
    resolved_addresses = $dnsRecords
    probes = @($ipv4, $ipv6)
    security = [pscustomobject][ordered]@{
        tls_verification_disabled = $false
        alternate_registry_used = $false
        unknown_image_used = $false
    }
    impact = if ($reachable) { 'Registry metadata can be resolved.' } else {
        'Official Debian manifest digest and Clang 21 builder digest cannot be frozen from this host.'
    }
}
$json = ($report | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
