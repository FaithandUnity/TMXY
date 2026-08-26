[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClangFormatPath = '',
    [string]$ClangTidyPath = '',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p0-12-static-analysis.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')

function Resolve-ToolPath {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RequestedPath,
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$VisualStudioFallback
    )
    if ($RequestedPath) { return (Resolve-Path -LiteralPath $RequestedPath).Path }
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    if (Test-Path -LiteralPath $VisualStudioFallback -PathType Leaf) { return $VisualStudioFallback }
    throw "$CommandName is unavailable."
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        output = ($stdout + $stderr).Trim()
    }
}

function Get-OutputEvidence {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Output)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Output)
    $sha = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [pscustomobject][ordered]@{
        line_count = @($Output -split "`n").Count
        sha256 = [System.Convert]::ToHexString($sha).ToLowerInvariant()
    }
}

$llvmBin = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\Llvm\x64\bin'
$formatTool = Resolve-ToolPath -RequestedPath $ClangFormatPath -CommandName 'clang-format' `
    -VisualStudioFallback (Join-Path $llvmBin 'clang-format.exe')
$tidyTool = Resolve-ToolPath -RequestedPath $ClangTidyPath -CommandName 'clang-tidy' `
    -VisualStudioFallback (Join-Path $llvmBin 'clang-tidy.exe')

$backendRoot = Join-Path $root 'Backend'
$allSourceFiles = @(Get-ChildItem -LiteralPath $backendRoot -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @('.cpp', '.h', '.hpp') })
$translationUnits = @($allSourceFiles | Where-Object { $_.Extension -eq '.cpp' })
$formatArguments = @('--dry-run', '--Werror') + @($allSourceFiles.FullName)
$format = Invoke-NativeProcess -FilePath $formatTool -ArgumentList $formatArguments -WorkingDirectory $root

$tidyArguments = @("--config-file=$(Join-Path $root '.clang-tidy')") +
    @($translationUnits.FullName) + @('--', '-std=c++20', "-I$(Join-Path $backendRoot 'modules\foundation\include')")
$tidy = Invoke-NativeProcess -FilePath $tidyTool -ArgumentList $tidyArguments -WorkingDirectory $root
$tidyVersion = Invoke-NativeProcess -FilePath $tidyTool -ArgumentList @('--version') -WorkingDirectory $root

$passed = $format.exit_code -eq 0 -and $tidy.exit_code -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS_DIAGNOSTIC' } else { 'FAIL' }
    authoritative_release_analysis = $false
    authority_note = 'Host clang-tidy proves rule cleanliness; the locked Linux Clang 21 builder remains authoritative.'
    clang_tidy_version = ($tidyVersion.output -replace '\s+', ' ').Trim()
    format = [pscustomobject][ordered]@{
        passed = $format.exit_code -eq 0
        checked_files = $allSourceFiles.Count
        evidence = Get-OutputEvidence -Output $format.output
    }
    tidy = [pscustomobject][ordered]@{
        passed = $tidy.exit_code -eq 0
        checked_translation_units = $translationUnits.Count
        evidence = Get-OutputEvidence -Output $tidy.output
    }
}
$json = ($report | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
$fullOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.File]::WriteAllText($fullOutputPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'Backend static analysis failed.' }
