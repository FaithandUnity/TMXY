[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$BuilderImage = 'tmxy-backend-builder:p0-08',
    [string]$PostgresImage = 'postgres:18.6-alpine',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-license-evidence.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$qualificationPath = Join-Path $root 'Data\Toolchain\backend-toolchain-qualification.json'
$builderSbomPath = Join-Path $root 'Data\Security\tmxy-backend-builder.sbom.cdx.json'
$postgresSbomPath = Join-Path $root 'Data\Security\postgres-18.6.sbom.cdx.json'

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
    return ([Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Get-MissingLicenseComponents {
    param([Parameter(Mandatory = $true)][object]$Sbom)
    return @($Sbom.components | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'licenses') -or
        $null -eq $_.licenses -or @($_.licenses).Count -eq 0
    } | Sort-Object purl)
}

function Get-ImageId {
    param([Parameter(Mandatory = $true)][string]$Image)
    $value = & docker image inspect --format '{{.Id}}' $Image 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect ${Image}: $value" }
    return ([string]$value).Trim()
}

function Get-ImageFileHashes {
    param(
        [Parameter(Mandatory = $true)][string]$Image,
        [Parameter(Mandatory = $true)][string[]]$Paths
    )
    $uniquePaths = @($Paths | Sort-Object -Unique)
    $script = "set -eu`n"
    foreach ($path in $uniquePaths) {
        if ($path -notmatch '^/[A-Za-z0-9._/+:-]+$') {
            throw "Unsafe evidence path rejected: $path"
        }
        $script += "test -f '$path'`nsha256sum '$path'`n"
    }
    $output = & docker run --rm --network none --read-only --cap-drop ALL `
        --entrypoint sh $Image -ec $script 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to hash license evidence in ${Image}: $($output -join "`n")"
    }
    $hashes = @{}
    foreach ($line in @($output)) {
        $match = [regex]::Match([string]$line, '^(?<sha>[a-f0-9]{64})\s+(?<path>/\S+)$')
        if ($match.Success) {
            $hashes[$match.Groups['path'].Value] = $match.Groups['sha'].Value
        }
    }
    foreach ($path in $uniquePaths) {
        if (-not $hashes.ContainsKey($path)) {
            throw "Image evidence hash is missing for ${Image}: $path"
        }
    }
    return $hashes
}

$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$qualification = Get-Content -LiteralPath $qualificationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$builderSbom = Get-Content -LiteralPath $builderSbomPath -Raw -Encoding UTF8 | ConvertFrom-Json
$postgresSbom = Get-Content -LiteralPath $postgresSbomPath -Raw -Encoding UTF8 | ConvertFrom-Json
$builderId = Get-ImageId -Image $BuilderImage
$postgresId = Get-ImageId -Image $PostgresImage
if ($builderId -ne [string]$lock.backend_toolchain.container_image_digest) {
    throw 'Builder image does not match the toolchain lock.'
}
if ($postgresId -ne [string]$lock.database.development_image.image_id) {
    throw 'PostgreSQL image does not match the toolchain lock.'
}

$builderFallbackPaths = @{
    'bash' = '/usr/share/doc/bash/copyright'
    'curl' = '/usr/share/doc/curl/copyright'
    'gzip' = '/usr/share/doc/gzip/copyright'
    'libgc' = '/usr/share/doc/libgc1/copyright'
    'libsemanage' = '/usr/share/doc/libsemanage2/copyright'
    'libssh2' = '/usr/share/doc/libssh2-1/copyright'
    'openssl' = '/usr/share/doc/openssl/copyright'
    'python' = '/usr/share/doc/python3.11/copyright'
    'util-linux' = '/usr/share/doc/util-linux/copyright'
    'xz' = '/usr/share/doc/xz-utils/copyright'
}
$pythonLicenses = @{
    'autocommand' = 'LGPL-3.0-only'
    'backports-tarfile' = 'MIT'
    'colorama' = 'BSD-3-Clause'
    'distro' = 'Apache-2.0'
    'jaraco-text' = 'MIT'
    'jinja2' = 'BSD-3-Clause'
    'python-dateutil' = 'Apache-2.0 OR BSD-3-Clause'
}
$builderMissing = Get-MissingLicenseComponents -Sbom $builderSbom
$builderPaths = [System.Collections.Generic.List[string]]::new()
$builderDraft = foreach ($component in $builderMissing) {
    $name = [string]$component.name
    $nestedPath = @(if ($component.PSObject.Properties.Name -contains 'components') {
        $component.components | Where-Object {
            [string]$_.name -match '(?i)(copyright|license|metadata)'
        } | Select-Object -First 1 -ExpandProperty name
    }
    else { @() })
    $path = if ($nestedPath.Count -gt 0) {
        [string]$nestedPath[0]
    }
    elseif ($builderFallbackPaths.ContainsKey($name)) {
        [string]$builderFallbackPaths[$name]
    }
    elseif ([string]$component.purl -like 'pkg:deb/*') {
        "/usr/share/doc/${name}/copyright"
    }
    else {
        throw "No builder license evidence path is mapped for $($component.purl)."
    }
    $builderPaths.Add($path)
    [pscustomobject]@{ component = $component; path = $path }
}
$builderHashes = Get-ImageFileHashes -Image $BuilderImage -Paths $builderPaths.ToArray()
$builderEntries = @($builderDraft | ForEach-Object {
    $component = $_.component
    [pscustomobject][ordered]@{
        bom_ref = [string]$component.'bom-ref'
        purl = [string]$component.purl
        name = [string]$component.name
        version = [string]$component.version
        evidence_kind = if ([string]$component.purl -like 'pkg:pypi/*') {
            'installed-package-metadata'
        } else { 'installed-copyright-file' }
        evidence_source = [string]$_.path
        evidence_sha256 = [string]$builderHashes[[string]$_.path]
        declared_license = if ($pythonLicenses.ContainsKey([string]$component.name)) {
            [string]$pythonLicenses[[string]$component.name]
        } else { 'SEE-INSTALLED-COPYRIGHT' }
        review_state = 'verified-source-evidence'
    }
})

$apkDatabasePath = '/lib/apk/db/installed'
$postgresHashes = Get-ImageFileHashes -Image $PostgresImage -Paths @($apkDatabasePath)
$upstream = @{
    'gosu' = [pscustomobject]@{
        url = 'https://raw.githubusercontent.com/tianon/gosu/1.19/LICENSE'
        sha256 = 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30'
        license = 'Apache-2.0'
    }
    'postgresql' = [pscustomobject]@{
        url = 'https://raw.githubusercontent.com/postgres/postgres/REL_18_6/COPYRIGHT'
        sha256 = '3d6af92ff8a4c2cdf69afb1cf44edea727922f5cd0cf8b5f72b11cdecac8fdfd'
        license = 'PostgreSQL'
    }
    'stdlib' = [pscustomobject]@{
        url = 'https://raw.githubusercontent.com/golang/go/go1.24.6/LICENSE'
        sha256 = '911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad'
        license = 'BSD-3-Clause'
    }
    'sys' = [pscustomobject]@{
        url = 'https://raw.githubusercontent.com/golang/sys/v0.1.0/LICENSE'
        sha256 = '2d36597f7117c38b006835ae7f537487207d8ec407aa9d9980794b2030cbc067'
        license = 'BSD-3-Clause'
    }
    'user' = [pscustomobject]@{
        url = 'https://raw.githubusercontent.com/moby/sys/user/v0.1.0/LICENSE'
        sha256 = 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30'
        license = 'Apache-2.0'
    }
}
$postgresEntries = @()
foreach ($component in (Get-MissingLicenseComponents -Sbom $postgresSbom)) {
    $name = [string]$component.name
    if ($name -in @('.postgresql-rundeps', 'tzdata')) {
        $postgresEntries += [pscustomobject][ordered]@{
            bom_ref = [string]$component.'bom-ref'
            purl = [string]$component.purl
            name = $name
            version = [string]$component.version
            evidence_kind = 'installed-package-metadata'
            evidence_source = $apkDatabasePath
            evidence_sha256 = [string]$postgresHashes[$apkDatabasePath]
            declared_license = if ($name -eq 'tzdata') { 'LicenseRef-Public-Domain' } else { 'NONE' }
            review_state = 'verified-source-evidence'
        }
        continue
    }
    if (-not $upstream.ContainsKey($name)) {
        throw "No PostgreSQL license evidence source is mapped for $($component.purl)."
    }
    $source = $upstream[$name]
    $response = Invoke-WebRequest -Uri $source.url -UseBasicParsing
    $actualSha = Get-TextSha256 -Text ([string]$response.Content)
    if ($actualSha -ne [string]$source.sha256) {
        throw "Upstream license hash changed for $name."
    }
    $postgresEntries += [pscustomobject][ordered]@{
        bom_ref = [string]$component.'bom-ref'
        purl = [string]$component.purl
        name = $name
        version = [string]$component.version
        evidence_kind = 'version-pinned-upstream-license'
        evidence_source = [string]$source.url
        evidence_sha256 = $actualSha
        declared_license = [string]$source.license
        review_state = 'verified-source-evidence'
    }
}

$builderLicensed = @($builderSbom.components).Count - $builderMissing.Count
$postgresMissing = Get-MissingLicenseComponents -Sbom $postgresSbom
$postgresLicensed = @($postgresSbom.components).Count - $postgresMissing.Count
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = ([DateTimeOffset]$qualification.captured_utc).ToUniversalTime().ToString('o')
    result = 'PASS'
    release_authority = $false
    policy = 'Every SBOM component carries embedded license data or exact supplemental source evidence.'
    images = @(
        [pscustomobject][ordered]@{
            role = 'postgres-runtime'
            image_digest = $postgresId
            sbom_path = 'Data/Security/postgres-18.6.sbom.cdx.json'
            sbom_sha256 = Get-Sha256 -Path $postgresSbomPath
            component_count = @($postgresSbom.components).Count
            embedded_license_count = $postgresLicensed
            supplemental_evidence_count = $postgresEntries.Count
            evidence_entries = @($postgresEntries | Sort-Object purl)
        },
        [pscustomobject][ordered]@{
            role = 'backend-builder'
            image_digest = $builderId
            sbom_path = 'Data/Security/tmxy-backend-builder.sbom.cdx.json'
            sbom_sha256 = Get-Sha256 -Path $builderSbomPath
            component_count = @($builderSbom.components).Count
            embedded_license_count = $builderLicensed
            supplemental_evidence_count = $builderEntries.Count
            evidence_entries = @($builderEntries | Sort-Object purl)
        }
    )
}
$directory = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
[IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json,
    [Text.UTF8Encoding]::new($false))
$json
