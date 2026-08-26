[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Toolchain\debian-bookworm-slim-import.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$helperImage = 'mmorpg-source-builder@sha256:a075a9492afd87a416267fc70689d898cdad7048ca6e55fdf73258e7d30fd68d'
$fetchScript = Join-Path $root 'Tools\TMXY.Toolchain\fetch_official_oci.py'
$cacheRoot = Join-Path $root ('Data\Toolchain\OciCache\debian-bookworm-slim-' +
    [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmssfff'))

function Write-Utf8Lf {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $directory = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        [System.IO.Path]::GetFullPath($Path),
        $Content.Replace("`r`n", "`n").Replace("`r", "`n"),
        [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $fetchScript -PathType Leaf)) {
    throw "Required OCI fetch tool is missing: $fetchScript"
}

$dohOutput = docker run --rm $helperImage curl --fail --silent --show-error --max-time 15 `
    'https://dns.google/resolve?name=registry-1.docker.io&type=A'
if ($LASTEXITCODE -ne 0) { throw 'Trusted DoH resolution failed.' }
$doh = ($dohOutput -join "`n") | ConvertFrom-Json
$addresses = @($doh.Answer | Where-Object { [int]$_.type -eq 1 } | ForEach-Object { [string]$_.data })
if ($addresses.Count -eq 0) { throw 'Trusted DoH returned no IPv4 Registry addresses.' }

$selectedAddress = $null
foreach ($address in $addresses) {
    $probe = docker run --rm $helperImage curl --silent --show-error --max-time 8 `
        --resolve "registry-1.docker.io:443:$address" -o /dev/null `
        -w 'status=%{http_code};verify=%{ssl_verify_result}' 'https://registry-1.docker.io/v2/' 2>&1
    $probeText = $probe -join "`n"
    if ($LASTEXITCODE -eq 0 -and $probeText -match 'status=401;verify=0') {
        $selectedAddress = $address
        break
    }
}
if ([string]::IsNullOrWhiteSpace($selectedAddress)) {
    throw 'No trusted DoH Registry address passed official-hostname TLS verification.'
}

New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
$fetchMount = "type=bind,src=$fetchScript,dst=/tool/fetch_official_oci.py,readonly"
$outputMount = "type=bind,src=$cacheRoot,dst=/out"
$fetchOutput = docker run --rm --mount $fetchMount --mount $outputMount $helperImage `
    python3 /tool/fetch_official_oci.py --registry-address $selectedAddress `
    --tag bookworm-slim --output /out
if ($LASTEXITCODE -ne 0) { throw 'Verified OCI fetch failed.' }
$fetch = ($fetchOutput -join "`n") | ConvertFrom-Json

$archivePath = Join-Path $cacheRoot ([string]$fetch.archive.file)
$loadOutput = docker load --input $archivePath 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Docker could not load the verified OCI archive.' }
$imageInspect = $null
foreach ($attempt in 1..20) {
    $inspectOutput = docker image inspect 'debian:bookworm-slim' 2>$null
    if ($LASTEXITCODE -eq 0) {
        $imageInspect = ($inspectOutput -join "`n") | ConvertFrom-Json
        break
    }
    Start-Sleep -Milliseconds 250
}
if ($null -eq $imageInspect -or @($imageInspect).Count -ne 1) {
    throw 'The imported Debian tag is unavailable after docker load.'
}
$image = @($imageInspect)[0]
$expectedImageId = [string]$fetch.official_index.digest
$expectedRepoDigest = 'debian@' + [string]$fetch.official_index.digest
$passed = [string]$image.Id -eq $expectedImageId -and
    @($image.RepoDigests) -contains $expectedRepoDigest -and
    [string]$fetch.platform_manifest.os -eq 'linux' -and
    [string]$fetch.platform_manifest.architecture -eq 'amd64' -and
    [string]$image.Os -eq 'linux' -and [string]$image.Architecture -eq 'amd64' -and
    [bool]$fetch.tls_verified

$loadText = $loadOutput -join "`n"
$loadHash = 'sha256:' + ([Convert]::ToHexString(
    [System.Security.Cryptography.SHA256]::HashData(
        [System.Text.Encoding]::UTF8.GetBytes($loadText)))).ToLowerInvariant()
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    acquisition = [pscustomobject][ordered]@{
        source = 'official Docker Registry'
        trusted_dns = 'Google DNS-over-HTTPS'
        dynamic_address_selection = $true
        selected_address_persisted = $false
        tls_verification_disabled = $false
        system_dns_modified = $false
        hosts_file_modified = $false
        alternate_registry_used = $false
        bearer_token_persisted = $false
    }
    official_index = $fetch.official_index
    platform_manifest = $fetch.platform_manifest
    config = $fetch.config
    layers = @($fetch.layers)
    tls = [pscustomobject][ordered]@{
        verified = [bool]$fetch.tls_verified
        certificate_sha256 = [string]$fetch.registry_certificate_sha256
        same_certificate_for_manifest = [bool]$fetch.manifest_certificate_same
    }
    archive = [pscustomobject][ordered]@{
        cache_path = $archivePath.Substring($root.Length + 1).Replace('\', '/')
        bytes = [int64]$fetch.archive.size
        sha256 = [string]$fetch.archive.sha256
    }
    imported_image = [pscustomobject][ordered]@{
        tag = 'debian:bookworm-slim'
        image_id = [string]$image.Id
        expected_image_id = $expectedImageId
        os = [string]$image.Os
        architecture = [string]$image.Architecture
        repo_digests = @($image.RepoDigests)
    }
    docker_load_output_sha256 = $loadHash
}
$json = ($report | ConvertTo-Json -Depth 9).Replace("`r`n", "`n").Replace("`r", "`n")
Write-Utf8Lf -Path $OutputPath -Content ($json + "`n")
$json
if (-not $passed) { throw 'Official Debian OCI import validation failed.' }
