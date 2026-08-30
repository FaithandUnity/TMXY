[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientLegacySourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [string]$ServerLegacySourceRoot = 'E:\QQXYCodeDev\ServerCode',
    [switch]$VerifyDerivedSources,
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $VerifyDerivedSources) {
    throw 'P2-20A.11 requires -VerifyDerivedSources.'
}

$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$clientRoot = [IO.Path]::GetFullPath($ClientLegacySourceRoot).TrimEnd([char[]]'\/')
$serverRoot = [IO.Path]::GetFullPath($ServerLegacySourceRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A11'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.11 temporary root escaped Rebuild.'
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
        throw 'P2-20A.11 requires the qualified non-root Clang 21 builder image.'
    }
    $targets = [ordered]@{
        detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-aux-malformed-xml-diagnostics.jsonl'
        json = Join-Path $root 'Data\Reports\p2-20a-aux-malformed-xml-diagnostics-report.json'
        markdown = Join-Path $root 'Data\Reports\p2-20a-aux-malformed-xml-diagnostics-report.md'
        evidence = Join-Path $root 'Data\Inventory\p2-20a-aux-malformed-xml-diagnostics.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $targets.Keys) {
        $generated[$name] = Join-Path $runRoot ([IO.Path]::GetFileName($targets[$name]))
    }
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $arguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$clientRoot,dst=/legacy-client,readonly",
        '--mount', "type=bind,src=$serverRoot,dst=/legacy-server,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/work",
        '--tmpfs', '/tmp:rw,nosuid,nodev,noexec,size=32m',
        $builder, 'python3',
        '/workspace/Tools/TMXY.G2AuxMalformedXmlDiagnostics/g2_aux_malformed_xml_diagnostics.py',
        '--root', '/workspace', '--client-source-root', '/legacy-client',
        '--server-source-root', '/legacy-server', '--work-root', '/work',
        '--builder-image-reference', $builder, '--builder-image-digest', $builderId,
        '--network-mode', 'none', '--repository-mount-mode', 'read-only',
        '--client-legacy-mount-mode', 'read-only',
        '--server-legacy-mount-mode', 'read-only', '--builder-user', 'tmxy',
        '--capabilities', 'none', '--no-new-privileges', 'true',
        '--detail-output', "/work/$([IO.Path]::GetFileName($generated.detail))",
        '--json-output', "/work/$([IO.Path]::GetFileName($generated.json))",
        '--markdown-output', "/work/$([IO.Path]::GetFileName($generated.markdown))",
        '--evidence-output', "/work/$([IO.Path]::GetFileName($generated.evidence))",
        '--verify-derived-sources'
    )
    $text = & $docker @arguments
    if ($LASTEXITCODE -ne 0) {
        throw 'P2-20A.11 generation or source-derived verification failed.'
    }
    $summary = $text | ConvertFrom-Json -Depth 50
    if ($summary.result -ne 'BLOCKED' -or $summary.review_execution_result -ne 'PASS' -or
        [int]$summary.instances -ne 6 -or [int]$summary.strict_rejections -ne 6 -or
        [int]$summary.elementtree_rejections -ne 6 -or
        [int]$summary.tinyxml_api_successes -ne 6 -or
        [int]$summary.tinyxml_full_consumption -ne 5 -or
        [int]$summary.tinyxml_silent_partial -ne 1 -or
        [bool]$summary.legacy_runtime_executed -or
        [bool]$summary.runtime_binary_parity_claimed) {
        throw 'P2-20A.11 summary drifted.'
    }
    foreach ($name in $targets.Keys) {
        if ($Check) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -cne (Get-Sha256 $generated[$name])) {
                throw "P2-20A.11 output differs: $name"
            }
        }
        else {
            Copy-Output $generated[$name] $targets[$name]
        }
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
