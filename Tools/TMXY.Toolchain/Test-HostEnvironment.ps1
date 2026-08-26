[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Toolchain\host-environment.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $Encoding
    $startInfo.StandardErrorEncoding = $Encoding
    foreach ($argument in $ArgumentList) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdout.Trim()
        stderr = $stderr.Trim()
    }
}

function Get-OptionalFeatureState {
    param([Parameter(Mandatory = $true)][string]$Name)
    try {
        return [string](Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop).State
    }
    catch {
        return "Unknown: $($_.Exception.Message)"
    }
}

function Get-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) { return $null }
    return $command.Source
}

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$expectedOutputRoot = Join-Path $workspace 'Rebuild'
$normalizedOutput = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $normalizedOutput.StartsWith($expectedOutputRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must stay under the Rebuild directory: $normalizedOutput"
}

$wslPath = Get-CommandPath -Name 'wsl.exe'
$wslVersion = $null
$wslRaw = $null
if ($null -ne $wslPath) {
    $wslResult = Invoke-NativeProcess -FilePath $wslPath -ArgumentList @('--version') -Encoding ([System.Text.Encoding]::Unicode)
    $wslRaw = $wslResult.stdout
    if ($wslResult.exit_code -eq 0 -and $wslRaw -match '(?m)^WSL[^0-9]*(?<version>[0-9]+(?:\.[0-9]+){3})') {
        $wslVersion = $Matches.version
    }
}

$dockerPath = Get-CommandPath -Name 'docker.exe'
$dockerVersion = $null
$dockerInfo = $null
$composeVersion = $null
$buildxVersion = $null
$dockerError = $null
if ($null -ne $dockerPath) {
    $versionResult = Invoke-NativeProcess -FilePath $dockerPath -ArgumentList @('version', '--format', '{{json .}}')
    if ($versionResult.exit_code -eq 0) {
        $dockerVersion = $versionResult.stdout | ConvertFrom-Json
        $infoResult = Invoke-NativeProcess -FilePath $dockerPath -ArgumentList @('info', '--format', '{{json .}}')
        if ($infoResult.exit_code -eq 0) {
            $dockerInfo = $infoResult.stdout | ConvertFrom-Json
        }
        else {
            $dockerError = $infoResult.stderr
        }

        $composeResult = Invoke-NativeProcess -FilePath $dockerPath -ArgumentList @('compose', 'version', '--short')
        if ($composeResult.exit_code -eq 0) { $composeVersion = $composeResult.stdout.TrimStart('v') }

        $buildxResult = Invoke-NativeProcess -FilePath $dockerPath -ArgumentList @('buildx', 'version')
        if ($buildxResult.exit_code -eq 0 -and $buildxResult.stdout -match 'v(?<version>[0-9]+(?:\.[0-9]+){2}(?:-[^\s]+)?)') {
            $buildxVersion = $Matches.version
        }
    }
    else {
        $dockerError = $versionResult.stderr
    }
}

$inventoryEnvironmentPath = Join-Path $workspace 'Rebuild\Data\BuildInventory\toolchain-environment.json'
$clientEnvironment = $null
if (Test-Path -LiteralPath $inventoryEnvironmentPath -PathType Leaf) {
    $clientEnvironment = Get-Content -LiteralPath $inventoryEnvironmentPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$postgresImage = $null
if ($null -ne $dockerVersion) {
    $inspectResult = Invoke-NativeProcess -FilePath $dockerPath -ArgumentList @('image', 'inspect', 'postgres:18.6-alpine')
    if ($inspectResult.exit_code -eq 0) {
        $imageRecords = @($inspectResult.stdout | ConvertFrom-Json)
        if ($imageRecords.Count -gt 0) {
            $image = $imageRecords[0]
            $postgresImage = [pscustomobject][ordered]@{
                reference = 'postgres:18.6-alpine'
                id = [string]$image.Id
                repo_digests = @($image.RepoDigests)
                os = [string]$image.Os
                architecture = [string]$image.Architecture
                created_utc = [string]$image.Created
            }
        }
    }
}

$hypervisorPresent = $null
try {
    $hypervisorPresent = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).HypervisorPresent
}
catch {
    $hypervisorPresent = $null
}

$dockerLinuxReady = $null -ne $dockerVersion -and
    $null -ne $dockerInfo -and
    [string]$dockerVersion.Server.Os -eq 'linux' -and
    [string]$dockerVersion.Server.Arch -eq 'amd64'
$clientReady = $null -ne $clientEnvironment -and
    $null -ne $clientEnvironment.unreal_engine -and
    @($clientEnvironment.visual_studio).Count -gt 0

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    workspace_root = $workspace
    host = [pscustomobject][ordered]@{
        computer_name = $env:COMPUTERNAME
        os_version = [Environment]::OSVersion.VersionString
        powershell_version = $PSVersionTable.PSVersion.ToString()
        hypervisor_present = $hypervisorPresent
        windows_optional_features = [pscustomobject][ordered]@{
            microsoft_windows_subsystem_linux = Get-OptionalFeatureState -Name 'Microsoft-Windows-Subsystem-Linux'
            virtual_machine_platform = Get-OptionalFeatureState -Name 'VirtualMachinePlatform'
        }
    }
    wsl = [pscustomobject][ordered]@{
        executable = $wslPath
        version = $wslVersion
        installed = $null -ne $wslPath
        independent_linux_distribution_required = $false
    }
    docker = if ($null -eq $dockerVersion) {
        [pscustomobject][ordered]@{ executable = $dockerPath; available = $false; error = $dockerError }
    }
    else {
        [pscustomobject][ordered]@{
            executable = $dockerPath
            available = $true
            context = [string]$dockerVersion.Client.Context
            client_version = [string]$dockerVersion.Client.Version
            server_version = [string]$dockerVersion.Server.Version
            desktop_platform = [string]$dockerVersion.Server.Platform.Name
            server_os = [string]$dockerVersion.Server.Os
            server_architecture = [string]$dockerVersion.Server.Arch
            kernel = [string]$dockerVersion.Server.KernelVersion
            compose_version = $composeVersion
            buildx_version = $buildxVersion
            cpus = if ($null -ne $dockerInfo) { [int]$dockerInfo.NCPU } else { $null }
            memory_bytes = if ($null -ne $dockerInfo) { [long]$dockerInfo.MemTotal } else { $null }
            proxy_configured = if ($null -ne $dockerInfo) { -not [string]::IsNullOrWhiteSpace([string]$dockerInfo.HttpsProxy) } else { $null }
            error = $dockerError
        }
    }
    client_toolchain = $clientEnvironment
    database_image = $postgresImage
    commands = [pscustomobject][ordered]@{
        docker = $dockerPath
        cmake = Get-CommandPath -Name 'cmake.exe'
        ninja = Get-CommandPath -Name 'ninja.exe'
        clang = Get-CommandPath -Name 'clang.exe'
        conan = Get-CommandPath -Name 'conan.exe'
        protoc = Get-CommandPath -Name 'protoc.exe'
        psql = Get-CommandPath -Name 'psql.exe'
    }
    readiness = [pscustomobject][ordered]@{
        client_toolchain = $clientReady
        linux_container_engine = $dockerLinuxReady
        postgresql_18_6_image_present = $null -ne $postgresImage
        backend_builder_image_frozen = $false
        p0_08_complete = $false
    }
}

$outputDirectory = Split-Path -Parent $normalizedOutput
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$json = ($report | ConvertTo-Json -Depth 16).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($normalizedOutput, $json + "`n", $utf8NoBom)
$report
