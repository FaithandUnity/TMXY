[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$BuilderImage = 'mmorpg-source-builder:local',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p0-10-validation.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$dockerPath = (Get-Command 'docker.exe' -ErrorAction Stop).Source

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [hashtable]$Environment = @{}
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
    foreach ($key in $Environment.Keys) { $startInfo.Environment[$key] = [string]$Environment[$key] }

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

$layoutScript = Join-Path $root 'Tests\Contract\Test-RepositoryLayout.ps1'
$layout = (& $layoutScript -RebuildRoot $root) | ConvertFrom-Json

$composePath = Join-Path $root 'Deploy\compose\compose.yaml'
$compose = Invoke-NativeProcess -FilePath $dockerPath -ArgumentList @(
    'compose', '-f', $composePath, 'config', '--quiet'
) -Environment @{ TMXY_POSTGRES_PASSWORD_FILE = 'E:\outside-workspace\validation-secret-file' }

$imageInspectResult = Invoke-NativeProcess -FilePath $dockerPath -ArgumentList @(
    'image', 'inspect', $BuilderImage
)
$imageRecord = $null
if ($imageInspectResult.exit_code -eq 0) {
    $imageRecords = @($imageInspectResult.stdout | ConvertFrom-Json)
    if ($imageRecords.Count -gt 0) { $imageRecord = $imageRecords[0] }
}

$buildCommands = @'
set -e
cmake -S /workspace/Backend --list-presets
cmake -S /workspace/Backend -B /tmp/tmxy-build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=g++ -DTMXY_WARNINGS_AS_ERRORS=ON
cmake --build /tmp/tmxy-build --parallel
ctest --test-dir /tmp/tmxy-build --output-on-failure
/tmp/tmxy-build/apps/gateway/tmxy-gateway
'@
$build = Invoke-NativeProcess -FilePath $dockerPath -ArgumentList @(
    'run', '--rm', '--network', 'none',
    '--mount', "type=bind,src=$root,dst=/workspace,readonly",
    $BuilderImage, 'bash', '-lc', $buildCommands
)

$passed = [string]$layout.result -eq 'PASS' -and
    $compose.exit_code -eq 0 -and
    $null -ne $imageRecord -and
    $build.exit_code -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS_DIAGNOSTIC' } else { 'FAIL' }
    authoritative_release_build = $false
    authority_note = 'This proves portable C++20/CMake structure with the cached GCC image. Clang 21 remains the release authority.'
    repository_layout = $layout
    compose = [pscustomobject][ordered]@{
        passed = $compose.exit_code -eq 0
        exit_code = $compose.exit_code
        error = $compose.stderr
    }
    builder = if ($null -eq $imageRecord) {
        [pscustomobject][ordered]@{
            reference = $BuilderImage
            inspect_error = $imageInspectResult.stderr
        }
    }
    else {
        [pscustomobject][ordered]@{
            reference = $BuilderImage
            id = [string]$imageRecord.Id
            repo_digests = @($imageRecord.RepoDigests)
            os = [string]$imageRecord.Os
            architecture = [string]$imageRecord.Architecture
            source_mount = 'read-only'
            network = 'none'
        }
    }
    build = [pscustomobject][ordered]@{
        passed = $build.exit_code -eq 0
        exit_code = $build.exit_code
        stdout = $build.stdout
        stderr = $build.stderr
    }
}

$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
$fullOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $fullOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText($fullOutputPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json

if (-not $passed) {
    throw 'Backend baseline validation failed. See the generated report for details.'
}
