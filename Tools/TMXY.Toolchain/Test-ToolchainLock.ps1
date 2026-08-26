[CmdletBinding()]
param(
    [string]$LockPath = 'E:\QQXYCodeDev\Rebuild\Data\Toolchain\toolchain.lock.json',
    [string]$EnvironmentPath = 'E:\QQXYCodeDev\Rebuild\Data\Toolchain\host-environment.json',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Toolchain\validation.json',
    [switch]$RunPostgresSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail,
        [ValidateSet('required', 'pending')][string]$Kind = 'required'
    )
    $checks.Add([pscustomobject][ordered]@{
        name = $Name
        kind = $Kind
        passed = $Passed
        detail = $Detail
    })
}

foreach ($path in @($LockPath, $EnvironmentPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

$lock = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$environment = Get-Content -LiteralPath $EnvironmentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$lockDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($LockPath))
$dataDirectory = Split-Path -Parent $lockDirectory
$rebuildRoot = Split-Path -Parent $dataDirectory

Add-Check -Name 'lock schema' -Passed ([int]$lock.schema_version -eq 1) -Detail "schema_version=$($lock.schema_version)"
Add-Check -Name 'environment schema' -Passed ([int]$environment.schema_version -eq 1) -Detail "schema_version=$($environment.schema_version)"
Add-Check -Name 'Linux Docker engine' -Passed ([bool]$environment.readiness.linux_container_engine) -Detail "$($environment.docker.server_os)/$($environment.docker.server_architecture), Docker $($environment.docker.server_version)"
Add-Check -Name 'UE and Visual Studio' -Passed ([bool]$environment.readiness.client_toolchain) -Detail "UE $($environment.client_toolchain.unreal_engine.major).$($environment.client_toolchain.unreal_engine.minor).$($environment.client_toolchain.unreal_engine.patch), $($environment.client_toolchain.visual_studio[0].display_name)"

$actualUnrealVersion = "$($environment.client_toolchain.unreal_engine.major).$($environment.client_toolchain.unreal_engine.minor).$($environment.client_toolchain.unreal_engine.patch)"
Add-Check -Name 'UE lock match' -Passed ($actualUnrealVersion -eq [string]$lock.client_toolchain.unreal_engine.version) -Detail "actual=$actualUnrealVersion expected=$($lock.client_toolchain.unreal_engine.version)"
Add-Check -Name 'UE changelist lock match' -Passed ([int64]$environment.client_toolchain.unreal_engine.changelist -eq [int64]$lock.client_toolchain.unreal_engine.changelist) -Detail "actual=$($environment.client_toolchain.unreal_engine.changelist) expected=$($lock.client_toolchain.unreal_engine.changelist)"
Add-Check -Name 'PostgreSQL image present' -Passed ([bool]$environment.readiness.postgresql_18_6_image_present) -Detail "reference=$($lock.database.development_image.reference)"

$expectedDigest = [string]$lock.database.development_image.digest_reference
$actualDigests = @($environment.database_image.repo_digests)
Add-Check -Name 'PostgreSQL image digest' -Passed ($actualDigests -contains $expectedDigest) -Detail "actual=$($actualDigests -join ',') expected=$expectedDigest"
Add-Check -Name 'P0 toolchain lock state' -Passed ([string]$lock.lock_state -eq 'locked') -Detail "lock_state=$($lock.lock_state)"

$builderDigestFrozen = -not [string]::IsNullOrWhiteSpace([string]$lock.backend_toolchain.base_image.manifest_digest) -and
    -not [string]::IsNullOrWhiteSpace([string]$lock.backend_toolchain.container_image_digest)
Add-Check -Name 'backend builder immutable digest' -Passed $builderDigestFrozen -Detail 'Base manifest and built image digests must both be populated before P0-08 can close.' -Kind 'pending'
Add-Check -Name 'exact Clang package revision' -Passed (-not [string]::IsNullOrWhiteSpace([string]$lock.backend_toolchain.compiler.exact_package_revision)) -Detail 'Resolved inside the final builder image.' -Kind 'pending'
$qualificationPath = Join-Path $rebuildRoot ([string]$lock.backend_toolchain.qualification.report)
$qualificationPassed = $false
$qualificationDetail = "report=$qualificationPath"
if (Test-Path -LiteralPath $qualificationPath -PathType Leaf) {
    $qualification = Get-Content -LiteralPath $qualificationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $qualificationHash = (Get-FileHash -LiteralPath $qualificationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $qualificationPassed = [string]$qualification.result -eq 'PASS' -and
        $qualificationHash -eq [string]$lock.backend_toolchain.qualification.report_sha256 -and
        [string]$qualification.primary_image.image_id -eq [string]$lock.backend_toolchain.container_image_digest -and
        [string]$qualification.clean_image.image_id -eq [string]$lock.backend_toolchain.qualification.clean_builder_image_digest -and
        [string]$qualification.inputs.dockerfile_sha256 -eq [string]$lock.backend_toolchain.qualification.dockerfile_sha256 -and
        [string]$qualification.inputs.backend_source.sha256 -eq [string]$lock.backend_toolchain.qualification.backend_source_sha256 -and
        [string]$qualification.official_base.index_digest -eq [string]$lock.backend_toolchain.base_image.manifest_digest -and
        [string]$qualification.primary_image.llvm_packages[0] -match [regex]::Escape(
            [string]$lock.backend_toolchain.compiler.exact_package_revision)
    $qualificationDetail += " hash=$qualificationHash result=$($qualification.result)"
}
Add-Check -Name 'backend builder qualification evidence' -Passed $qualificationPassed -Detail $qualificationDetail

$dockerfilePath = Join-Path $rebuildRoot 'Deploy\toolchain\Dockerfile'
$dockerfileHash = if (Test-Path -LiteralPath $dockerfilePath -PathType Leaf) {
    (Get-FileHash -LiteralPath $dockerfilePath -Algorithm SHA256).Hash.ToLowerInvariant()
} else { '' }
Add-Check -Name 'backend builder Dockerfile binding' -Passed (
    $dockerfileHash -eq [string]$lock.backend_toolchain.qualification.dockerfile_sha256
) -Detail "actual=$dockerfileHash expected=$($lock.backend_toolchain.qualification.dockerfile_sha256)"

$sbomPath = Join-Path $rebuildRoot ([string]$lock.backend_toolchain.qualification.sbom)
$sbomHash = if (Test-Path -LiteralPath $sbomPath -PathType Leaf) {
    (Get-FileHash -LiteralPath $sbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
} else { '' }
Add-Check -Name 'backend builder SBOM binding' -Passed (
    $sbomHash -eq [string]$lock.backend_toolchain.qualification.sbom_sha256
) -Detail "actual=$sbomHash expected=$($lock.backend_toolchain.qualification.sbom_sha256)"

$builderInspectOutput = & docker image inspect ([string]$lock.backend_toolchain.container_image_reference) 2>$null
$builderImageId = ''
if ($LASTEXITCODE -eq 0) {
    $builderInspect = @(($builderInspectOutput -join "`n") | ConvertFrom-Json)
    if ($builderInspect.Count -eq 1) { $builderImageId = [string]$builderInspect[0].Id }
}
Add-Check -Name 'qualified backend builder image present' -Passed (
    $builderImageId -eq [string]$lock.backend_toolchain.container_image_digest
) -Detail "actual=$builderImageId expected=$($lock.backend_toolchain.container_image_digest)"
$msvcStatus = [string]$lock.client_toolchain.msvc_qualification.status
$msvcQualificationPassed = $msvcStatus -eq 'preferred_and_qualified'
$msvcDetail = "status=$msvcStatus installed=$($lock.client_toolchain.msvc_qualification.reported_toolchain_version) preferred=$($lock.client_toolchain.msvc_qualification.ue_5_8_latest_preferred_version)"
if ($msvcStatus -eq 'waiver_active_time_bounded') {
    $waiverReportPath = Join-Path $rebuildRoot ([string]$lock.client_toolchain.msvc_qualification.waiver.report)
    if (Test-Path -LiteralPath $waiverReportPath -PathType Leaf) {
        $waiverReport = Get-Content -LiteralPath $waiverReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $waiverHash = (Get-FileHash -LiteralPath $waiverReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $waiverExpiry = [DateTimeOffset]::Parse([string]$waiverReport.waiver.expires_local)
        $msvcQualificationPassed = [string]$waiverReport.result -eq 'PASS' -and
            [string]$waiverReport.waiver.status -eq 'active' -and
            $waiverExpiry -gt [DateTimeOffset]::Now -and
            $waiverHash -eq [string]$lock.client_toolchain.msvc_qualification.waiver.report_sha256
        $msvcDetail += " waiver_expires=$($waiverExpiry.ToString('o')) report_hash_match=$($waiverHash -eq [string]$lock.client_toolchain.msvc_qualification.waiver.report_sha256)"
    }
}
Add-Check -Name 'UE MSVC qualification' -Passed $msvcQualificationPassed -Detail $msvcDetail -Kind 'pending'

$smokeVersion = $null
if ($RunPostgresSmoke) {
    $containerName = "tmxy-p0-08-postgres-$([Guid]::NewGuid().ToString('N').Substring(0, 12))"
    try {
        $containerId = & docker run --rm -d --name $containerName --network none -e POSTGRES_HOST_AUTH_METHOD=trust --tmpfs /var/lib/postgresql $expectedDigest
        if ($LASTEXITCODE -ne 0) { throw 'Unable to start PostgreSQL smoke-test container.' }

        $ready = $false
        foreach ($attempt in 1..30) {
            & docker exec $containerName pg_isready -U postgres -d postgres *> $null
            if ($LASTEXITCODE -eq 0) {
                $ready = $true
                break
            }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) { throw 'PostgreSQL did not become ready within 30 seconds.' }

        $smokeVersion = (& docker exec $containerName psql -U postgres -d postgres -Atc 'show server_version;').Trim()
        if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL version query failed.' }
        Add-Check -Name 'PostgreSQL runtime smoke test' -Passed ($smokeVersion -eq [string]$lock.database.qualified_minor) -Detail "server_version=$smokeVersion"
    }
    finally {
        & docker rm -f $containerName *> $null
    }
}

$requiredFailures = @($checks | Where-Object { $_.kind -eq 'required' -and -not $_.passed })
$pendingFailures = @($checks | Where-Object { $_.kind -eq 'pending' -and -not $_.passed })
$result = if ($requiredFailures.Count -gt 0) {
    'FAIL'
}
elseif ($pendingFailures.Count -gt 0) {
    'PASS_WITH_PENDING_FREEZE_ITEMS'
}
else {
    'PASS'
}

$report = [pscustomobject][ordered]@{
    result = $result
    required_failure_count = $requiredFailures.Count
    pending_freeze_count = $pendingFailures.Count
    postgres_smoke_version = $smokeVersion
    lock_sha256 = (Get-FileHash -LiteralPath $LockPath -Algorithm SHA256).Hash.ToLowerInvariant()
    environment_sha256 = (Get-FileHash -LiteralPath $EnvironmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    checks = @($checks)
}
$json = ($report | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n")
$outputDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false)
)
$json

if ($requiredFailures.Count -gt 0) {
    throw "Toolchain validation failed with $($requiredFailures.Count) required check(s)."
}
