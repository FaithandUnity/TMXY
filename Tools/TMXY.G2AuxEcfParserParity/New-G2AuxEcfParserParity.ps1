[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacySourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$legacyRoot = [IO.Path]::GetFullPath($LegacySourceRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A10'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.10 temporary root escaped Rebuild.'
}
$runRoot = Join-Path $localRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Copy-Output([string]$Source, [string]$Target) {
    $directory = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
}

try {
    $lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') `
        -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    $builder = [string]$lock.backend_toolchain.container_image_reference
    $builderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builder 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $builderId -or [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.10 requires the qualified non-root Clang 21 builder image.'
    }
    $targets = [ordered]@{
        detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-aux-ecf-parser-parity.jsonl'
        json = Join-Path $root 'Data\Reports\p2-20a-aux-ecf-parser-parity-report.json'
        markdown = Join-Path $root 'Data\Reports\p2-20a-aux-ecf-parser-parity-report.md'
        evidence = Join-Path $root 'Data\Inventory\p2-20a-aux-ecf-parser-parity.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $targets.Keys) {
        $generated[$name] = Join-Path $runRoot ([IO.Path]::GetFileName($targets[$name]))
    }
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $arguments = @('run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$legacyRoot,dst=/legacy,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=32m', $builder, 'python3',
        '/workspace/Tools/TMXY.G2AuxEcfParserParity/g2_aux_ecf_parser_parity.py',
        '--root', '/workspace', '--legacy-source-root', '/legacy',
        '--detail-output', "/output/$([IO.Path]::GetFileName($generated.detail))",
        '--json-output', "/output/$([IO.Path]::GetFileName($generated.json))",
        '--markdown-output', "/output/$([IO.Path]::GetFileName($generated.markdown))",
        '--evidence-output', "/output/$([IO.Path]::GetFileName($generated.evidence))")
    $text = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.10 generation failed.' }
    $summary = $text | ConvertFrom-Json -Depth 50
    if ($summary.result -ne 'BLOCKED' -or $summary.review_execution_result -ne 'PASS' -or
        [int]$summary.a3_actual_parity_instances -ne 51 -or
        [int]$summary.a3_actual_difference_instances -ne 13 -or
        [int]$summary.correct_plain_filter_parity_instances -ne 63 -or
        [int]$summary.legacy_pair_records_absent_from_a3 -ne 4 -or
        [bool]$summary.legacy_runtime_executed -or
        [bool]$summary.runtime_binary_parity_claimed) {
        throw 'P2-20A.10 summary drifted.'
    }
    foreach ($name in $targets.Keys) {
        if ($Check) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -cne (Get-Sha256 $generated[$name])) {
                throw "P2-20A.10 output differs: $name"
            }
        }
        else { Copy-Output $generated[$name] $targets[$name] }
    }
    $summary | ConvertTo-Json -Depth 50 -Compress
}
finally {
    $resolved = [IO.Path]::GetFullPath($runRoot)
    if ($resolved.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolved -PathType Container)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
