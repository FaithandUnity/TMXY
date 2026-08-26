[CmdletBinding()]
param(
    [string]$RegistryHost = 'registry-1.docker.io',
    [string]$BaseImage = 'debian:bookworm-slim',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Toolchain\registry-diagnostics.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )
    $output = @(& $FilePath @ArgumentList 2>&1)
    return [pscustomobject][ordered]@{
        exit_code = $LASTEXITCODE
        output = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    }
}

function Get-DnsRecords {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('A', 'AAAA')][string]$Type
    )
    try {
        return @(
            Resolve-DnsName $Name -Type $Type -DnsOnly -QuickTimeout -ErrorAction Stop |
                Where-Object { [string]$_.Type -eq $Type } |
                ForEach-Object {
                    [pscustomobject][ordered]@{
                        name = [string]$_.Name
                        type = [string]$_.Type
                        address = [string]$_.IPAddress
                        ttl = [int]$_.TTL
                    }
                }
        )
    }
    catch {
        return @([pscustomobject][ordered]@{
            name = $Name
            type = $Type
            address = $null
            ttl = $null
            error = $_.Exception.Message
        })
    }
}

function Test-HttpsFamily {
    param(
        [Parameter(Mandatory = $true)][string]$CurlPath,
        [Parameter(Mandatory = $true)][ValidateSet('4', '6')][string]$Family,
        [Parameter(Mandatory = $true)][string]$Uri
    )
    $result = Invoke-NativeCapture -FilePath $CurlPath -ArgumentList @(
        "-$Family", '-sS', '-o', 'NUL',
        '-w', 'http=%{http_code};remote=%{remote_ip};error=%{errormsg}',
        '--connect-timeout', '10', $Uri
    )
    $status = $null
    $remote = $null
    if ($result.output -match 'http=(?<status>[0-9]{3});remote=(?<remote>[^;]*);') {
        $status = $Matches.status
        $remote = $Matches.remote
    }
    return [pscustomobject][ordered]@{
        family = "IPv$Family"
        exit_code = $result.exit_code
        http_status = $status
        remote_address = $remote
        reachable = $result.exit_code -eq 0 -and $status -in @('200', '401')
        output = $result.output
    }
}

$curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$docker = Get-Command 'docker.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$registryUri = "https://$RegistryHost/v2/"
$httpsChecks = @()
if ($null -ne $curl) {
    $httpsChecks = @(
        Test-HttpsFamily -CurlPath $curl.Source -Family '4' -Uri $registryUri
        Test-HttpsFamily -CurlPath $curl.Source -Family '6' -Uri $registryUri
    )
}

$imageInspect = $null
if ($null -ne $docker) {
    $inspectResult = Invoke-NativeCapture -FilePath $docker.Source -ArgumentList @('buildx', 'imagetools', 'inspect', $BaseImage)
    $digest = $null
    if ($inspectResult.output -match '(?m)^Digest:\s*(?<digest>sha256:[a-f0-9]{64})\s*$') {
        $digest = $Matches.digest
    }
    $imageInspect = [pscustomobject][ordered]@{
        image = $BaseImage
        exit_code = $inspectResult.exit_code
        manifest_digest = $digest
        succeeded = $inspectResult.exit_code -eq 0 -and $null -ne $digest
        output = $inspectResult.output
    }
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    registry_host = $RegistryHost
    dns = [pscustomobject][ordered]@{
        a = @(Get-DnsRecords -Name $RegistryHost -Type 'A')
        aaaa = @(Get-DnsRecords -Name $RegistryHost -Type 'AAAA')
    }
    https = $httpsChecks
    base_image_inspect = $imageInspect
    registry_reachable = @($httpsChecks | Where-Object reachable).Count -gt 0
    base_image_digest_resolved = $null -ne $imageInspect -and [bool]$imageInspect.succeeded
    remediation_rule = 'Fix the controlled DNS/proxy path or import an audited OCI archive. Never disable TLS or substitute an untrusted mirror.'
}

$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
$fullOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $fullOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText($fullOutputPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$report
