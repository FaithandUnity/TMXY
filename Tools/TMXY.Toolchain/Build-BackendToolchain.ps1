[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [ValidateSet('BuildAndQualify', 'QualifyExisting')]
    [string]$Mode = 'BuildAndQualify',
    [string]$PrimaryImage = 'tmxy-backend-builder:p0-08',
    [string]$CleanImage = 'tmxy-backend-builder:p0-08-clean',
    [string]$ExistingCleanBuilder = 'tmxy-p0-08-clean',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Toolchain\backend-toolchain-qualification.json',
    [string]$SbomPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\tmxy-backend-builder.sbom.cdx.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$dockerfile = Join-Path $root 'Deploy\toolchain\Dockerfile'
$requirements = Join-Path $root 'Deploy\toolchain\conan-requirements.txt'
$backend = Join-Path $root 'Backend'
$baseReportPath = Join-Path $root 'Data\Toolchain\debian-bookworm-slim-import.json'
$expectedBaseDigest = 'sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171'
$expectedClangRevision = '1:21.1.8~++20251221032947+2078da43e25a-1~exp1~20251221153113.67'

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

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(
        $Text.Replace("`r`n", "`n").Replace("`r", "`n"))
    return ([Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Invoke-DockerText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $lines = & docker @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = (@($lines) | ForEach-Object { $_.ToString() }) -join "`n"
    if ($exitCode -ne 0) {
        throw "docker $($Arguments[0]) failed with exit code ${exitCode}: $text"
    }
    return $text.TrimEnd()
}

function Get-BackendSourceFingerprint {
    $files = @(Get-ChildItem -LiteralPath $backend -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]out[\\/]'
    } | Sort-Object FullName)
    $lines = foreach ($file in $files) {
        $relative = $file.FullName.Substring($backend.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    $manifest = ($lines -join "`n") + "`n"
    return [pscustomobject][ordered]@{
        file_count = $files.Count
        sha256 = Get-TextSha256 -Text $manifest
    }
}

function Get-ImageEvidence {
    param([Parameter(Mandatory = $true)][string]$Image)
    $inspect = @(Invoke-DockerText -Arguments @('image', 'inspect', $Image) |
        ConvertFrom-Json)[0]
    $toolsScript = @'
set -eu
clang++-21 --version
clang-tidy-21 --version
clang-format-21 --version
ld.lld-21 --version
cmake --version
ninja --version
conan --version
'@
    $packageScript = 'dpkg-query -W -f=''${binary:Package}=${Version}\n'' | LC_ALL=C sort'
    $pipScript = '/opt/conan/bin/pip freeze --all | LC_ALL=C sort'
    $tools = Invoke-DockerText -Arguments @('run', '--rm', '--network', 'none', $Image,
        'sh', '-ec', $toolsScript)
    $packages = Invoke-DockerText -Arguments @('run', '--rm', '--network', 'none', $Image,
        'sh', '-ec', $packageScript)
    $pythonPackages = Invoke-DockerText -Arguments @('run', '--rm', '--network', 'none',
        $Image, 'sh', '-ec', $pipScript)
    $llvmPackages = @($packages -split "`n" | Where-Object {
        $_ -match '^(?:clang|clang-format|clang-tidy|lld)-21='
    })
    $requiredLlvm = @('clang-21', 'clang-format-21', 'clang-tidy-21', 'lld-21')
    $llvmLocked = $true
    foreach ($name in $requiredLlvm) {
        if ($llvmPackages -notcontains "${name}=${expectedClangRevision}") {
            $llvmLocked = $false
        }
    }
    return [pscustomobject][ordered]@{
        reference = $Image
        image_id = [string]$inspect.Id
        repo_digests = @($inspect.RepoDigests)
        created_utc = [string]$inspect.Created
        os = [string]$inspect.Os
        architecture = [string]$inspect.Architecture
        size_bytes = [int64]$inspect.Size
        user = [string]$inspect.Config.User
        base_digest_label = [string]$inspect.Config.Labels.'org.opencontainers.image.base.digest'
        rootfs_layers = @($inspect.RootFS.Layers)
        tool_versions = $tools
        tool_versions_sha256 = Get-TextSha256 -Text ($tools + "`n")
        installed_package_count = @($packages -split "`n").Count
        installed_packages_sha256 = Get-TextSha256 -Text ($packages + "`n")
        llvm_packages = $llvmPackages
        llvm_revision_locked = $llvmLocked
        python_packages_sha256 = Get-TextSha256 -Text ($pythonPackages + "`n")
    }
}

function Invoke-BackendQualification {
    param([Parameter(Mandatory = $true)][string]$Image)
    $mount = "type=bind,src=$backend,dst=/source,readonly"
    $script = @'
set -eu
cp -a /source/. /tmp/backend
cd /tmp/backend
cmake --preset ci-linux-clang
cmake --build --preset ci-linux-clang
ctest --preset ci-linux-clang
printf '\nTMXY_ARTIFACTS_BEGIN\n'
sha256sum \
  out/build/ci-linux-clang/apps/gateway/tmxy-gateway \
  out/build/ci-linux-clang/modules/foundation/libtmxy_foundation.a \
  out/build/ci-linux-clang/modules/foundation/tests/tmxy_foundation_build_info_test \
  out/build/ci-linux-clang/modules/foundation/tests/tmxy_foundation_redaction_test \
  | LC_ALL=C sort
'@
    $output = Invoke-DockerText -Arguments @('run', '--rm', '--network', 'none',
        '--mount', $mount, $Image, 'sh', '-ec', $script)
    $parts = $output -split 'TMXY_ARTIFACTS_BEGIN', 2
    if ($parts.Count -ne 2) { throw "Artifact sentinel is missing for $Image." }
    $buildLog = $parts[0].Trim()
    $artifacts = $parts[1].Trim()
    $artifactLines = @($artifacts -split "`n" | Where-Object { $_ -match '^[a-f0-9]{64}\s+' })
    $passed = $buildLog -match '100% tests passed(?:, 0 tests failed)? out of 2' -and
        $artifactLines.Count -eq 4
    return [pscustomobject][ordered]@{
        passed = $passed
        network = 'none'
        source_mount = 'read-only'
        configure_preset = 'ci-linux-clang'
        ctest_count = 2
        build_log_sha256 = Get-TextSha256 -Text ($buildLog + "`n")
        artifact_manifest_sha256 = Get-TextSha256 -Text ($artifacts + "`n")
        artifacts = $artifactLines
    }
}

function Build-PrimaryImage {
    Invoke-DockerText -Arguments @('build', '--pull=false', '--no-cache',
        '--platform', 'linux/amd64', '--provenance=false', '--tag', $PrimaryImage,
        '--file', $dockerfile, (Split-Path -Parent $dockerfile)) | Out-Null
}

function Build-CleanImage {
    param(
        [Parameter(Mandatory = $true)][string]$Builder,
        [Parameter(Mandatory = $true)][string]$LayoutPath
    )
    Invoke-DockerText -Arguments @('buildx', 'create', '--name', $Builder,
        '--driver', 'docker-container', '--driver-opt', 'network=host') | Out-Null
    Invoke-DockerText -Arguments @('buildx', 'inspect', '--bootstrap', $Builder) | Out-Null
    $layoutUri = 'oci-layout://' + $LayoutPath.Replace('\', '/') + '@' + $expectedBaseDigest
    Invoke-DockerText -Arguments @('buildx', 'build', '--builder', $Builder,
        '--no-cache', '--platform', 'linux/amd64', '--provenance=false', '--load',
        '--build-arg', 'TMXY_BASE_IMAGE=tmxy_official_debian', '--build-context',
        "tmxy_official_debian=$layoutUri", '--tag', $CleanImage, '--file', $dockerfile,
        (Split-Path -Parent $dockerfile)) | Out-Null
}

foreach ($path in @($dockerfile, $requirements, $backend, $baseReportPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required input is missing: $path" }
}
$baseReport = Get-Content -LiteralPath $baseReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$baseReport.result -ne 'PASS' -or
    [string]$baseReport.official_index.digest -ne $expectedBaseDigest) {
    throw 'The verified official Debian OCI acquisition report does not match the lock.'
}
$archivePath = Join-Path $root ([string]$baseReport.archive.cache_path).Replace('/', '\')
$layoutPath = Join-Path (Split-Path -Parent $archivePath) 'layout'

$builderName = $ExistingCleanBuilder
$createdEphemeralBuilder = $false
if ($Mode -eq 'BuildAndQualify') {
    Build-PrimaryImage
    $builderName = 'tmxy-p0-08-clean-' + [System.Diagnostics.Process]::GetCurrentProcess().Id
    $createdEphemeralBuilder = $true
    try {
        Build-CleanImage -Builder $builderName -LayoutPath $layoutPath
    }
    catch {
        throw
    }
}

$primary = Get-ImageEvidence -Image $PrimaryImage
$clean = Get-ImageEvidence -Image $CleanImage
$primaryQualification = Invoke-BackendQualification -Image $PrimaryImage
$cleanQualification = Invoke-BackendQualification -Image $CleanImage
$historyLines = Invoke-DockerText -Arguments @('buildx', 'history', 'ls', '--builder',
    $builderName, '--format', 'json')
$history = @($historyLines -split "`n" | Where-Object { $_.Trim() } |
    ForEach-Object { $_ | ConvertFrom-Json })
$completedHistory = @($history | Where-Object { [string]$_.status -eq 'Completed' } |
    Sort-Object completed_at -Descending)[0]

$scoutOutput = & docker scout sbom --format cyclonedx --output $SbomPath $PrimaryImage 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Docker Scout SBOM generation failed: $($scoutOutput -join "`n")"
}
$sbom = Get-Content -LiteralPath $SbomPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sbomHash = (Get-FileHash -LiteralPath $SbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
$source = Get-BackendSourceFingerprint
$dockerfileHash = (Get-FileHash -LiteralPath $dockerfile -Algorithm SHA256).Hash.ToLowerInvariant()
$requirementsHash = (Get-FileHash -LiteralPath $requirements -Algorithm SHA256).Hash.ToLowerInvariant()
$baseReportHash = (Get-FileHash -LiteralPath $baseReportPath -Algorithm SHA256).Hash.ToLowerInvariant()

$comparison = [pscustomobject][ordered]@{
    base_layer_equal = [string]$primary.rootfs_layers[0] -eq [string]$clean.rootfs_layers[0]
    tool_versions_equal = $primary.tool_versions_sha256 -eq $clean.tool_versions_sha256
    installed_packages_equal = $primary.installed_packages_sha256 -eq $clean.installed_packages_sha256
    python_packages_equal = $primary.python_packages_sha256 -eq $clean.python_packages_sha256
    backend_artifacts_equal = $primaryQualification.artifact_manifest_sha256 -eq
        $cleanQualification.artifact_manifest_sha256
    note = 'Image manifests may differ because build metadata timestamps are not release inputs; locked inventories, tools, source-bound artifacts, and the official base layer must match.'
}
$passed = $primary.os -eq 'linux' -and $primary.architecture -eq 'amd64' -and
    $clean.os -eq 'linux' -and $clean.architecture -eq 'amd64' -and
    $primary.user -eq 'tmxy' -and $clean.user -eq 'tmxy' -and
    $primary.base_digest_label -eq $expectedBaseDigest -and
    $clean.base_digest_label -eq $expectedBaseDigest -and
    $primary.llvm_revision_locked -and $clean.llvm_revision_locked -and
    $primary.tool_versions -match 'cmake version 4\.4\.2' -and
    $primary.tool_versions -match '1\.11\.1' -and
    $primary.tool_versions -match 'Conan version 2\.31\.2' -and
    $primaryQualification.passed -and $cleanQualification.passed -and
    $comparison.base_layer_equal -and $comparison.tool_versions_equal -and
    $comparison.installed_packages_equal -and $comparison.python_packages_equal -and
    $comparison.backend_artifacts_equal -and [string]$completedHistory.status -eq 'Completed' -and
    [int]$completedHistory.completed_steps -eq [int]$completedHistory.total_steps -and
    [string]$sbom.bomFormat -eq 'CycloneDX' -and @($sbom.components).Count -gt 0

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    mode = $Mode
    target = 'linux/amd64'
    official_base = [pscustomobject][ordered]@{
        index_digest = $expectedBaseDigest
        platform_manifest_digest = [string]$baseReport.platform_manifest.digest
        acquisition_report_sha256 = $baseReportHash
        tls_verified = [bool]$baseReport.tls.verified
        clean_builder_input = 'verified local OCI layout'
    }
    inputs = [pscustomobject][ordered]@{
        dockerfile_sha256 = $dockerfileHash
        conan_requirements_sha256 = $requirementsHash
        backend_source = $source
    }
    primary_image = $primary
    clean_image = $clean
    primary_qualification = $primaryQualification
    clean_qualification = $cleanQualification
    clean_builder = [pscustomobject][ordered]@{
        name = $builderName
        driver = 'docker-container'
        no_cache_policy = $true
        base_context_cached_only = ([int]$completedHistory.cached_steps -eq 1)
        completed_steps = [int]$completedHistory.completed_steps
        total_steps = [int]$completedHistory.total_steps
        history_ref = [string]$completedHistory.ref
        status = [string]$completedHistory.status
        ephemeral = $createdEphemeralBuilder
    }
    comparison = $comparison
    sbom = [pscustomobject][ordered]@{
        path = $SbomPath.Substring($root.Length + 1).Replace('\', '/')
        format = [string]$sbom.bomFormat
        spec_version = [string]$sbom.specVersion
        component_count = @($sbom.components).Count
        sha256 = $sbomHash
    }
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
Write-Utf8Lf -Path $OutputPath -Content ($json + "`n")
$json
if (-not $passed) { throw 'Backend toolchain qualification failed.' }
