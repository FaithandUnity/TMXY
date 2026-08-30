[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'Finalize')]
    [string]$Mode = 'Prepare',
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A8'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.8 temporary root escaped Rebuild.'
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
    $generator = Join-Path $root 'Tools\TMXY.G2AssetBindingRecovery\g2_asset_binding_recovery.py'
    $basePlanContract = Join-Path $root `
        'Contracts\data-schema\g2-asset-binding-recovery-base-plan-v1.tsv'
    if (-not (Test-Path -LiteralPath $basePlanContract -PathType Leaf)) {
        throw 'P2-20A.8 frozen base-plan contract is missing.'
    }
    $lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') `
        -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    $builder = [string]$lock.backend_toolchain.container_image_reference
    $builderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builder 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $builderId -or [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.8 requires the qualified non-root Clang 21 builder image.'
    }
    $targets = [ordered]@{
        attempt = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery-eligible-attempts.tsv'
        effective = Join-Path $root 'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
        prepare = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery-prepare.json'
        success = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery-successes.tsv'
        detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-recovery.jsonl'
        json = Join-Path $root 'Data\Reports\p2-20a-asset-binding-recovery-report.json'
        markdown = Join-Path $root 'Data\Reports\p2-20a-asset-binding-recovery-report.md'
        evidence = Join-Path $root 'Data\Inventory\p2-20a-asset-binding-recovery.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $targets.Keys) {
        $generated[$name] = Join-Path $runRoot ([IO.Path]::GetFileName($targets[$name]))
    }
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $isolation = @('run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=32m', $builder)

    if ($Mode -eq 'Prepare') {
        $arguments = $isolation + @('python3',
            '/workspace/Tools/TMXY.G2AssetBindingRecovery/g2_asset_binding_recovery.py',
            'prepare', '--root', '/workspace', '--attempt-tsv',
            "/output/$([IO.Path]::GetFileName($generated.attempt))", '--base-plan-contract',
            '/workspace/Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv',
            '--prepare-manifest',
            "/output/$([IO.Path]::GetFileName($generated.prepare))")
        $text = & $docker @arguments
        if ($LASTEXITCODE -ne 0) { throw 'P2-20A.8 preparation failed.' }
        $summary = $text | ConvertFrom-Json -Depth 20
        if ($summary.result -ne 'PASS' -or $summary.meaning -ne 'UPPER_BOUND_ATTEMPT_ONLY' -or
            [int]$summary.targets -ne 17 -or [int]$summary.candidate_edges -ne 21 -or
            $summary.attempt_matches_base_plan_contract -ne $true -or
            [string]$summary.base_plan_contract_sha256 -cne (Get-Sha256 $basePlanContract)) {
            throw 'P2-20A.8 eligible-attempt upper bound drifted.'
        }
        foreach ($name in @('attempt', 'prepare')) {
            if ($Check) {
                if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                    (Get-Sha256 $targets[$name]) -cne (Get-Sha256 $generated[$name])) {
                    throw "P2-20A.8 prepare output differs: $name"
                }
            }
            else { Copy-Output $generated[$name] $targets[$name] }
        }
        $summary | ConvertTo-Json -Depth 20
        return
    }

    if (-not (Test-Path -LiteralPath $targets.attempt -PathType Leaf) -or
        -not (Test-Path -LiteralPath $targets.effective -PathType Leaf)) {
        throw 'Run P2-20A.8 Prepare and P2-20A.13 before Finalize.'
    }
    $a4Detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-descriptor-diagnostics.jsonl'
    $captured = @()
    if ($Check) {
        if (-not (Test-Path -LiteralPath $targets.json -PathType Leaf)) {
            throw 'P2-20A.8 report is absent in check mode.'
        }
        $existing = Get-Content -LiteralPath $targets.json -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        $captured = @('--captured-utc', [string]$existing.captured_utc)
    }
    $arguments = $isolation + @('python3',
        '/workspace/Tools/TMXY.G2AssetBindingRecovery/g2_asset_binding_recovery.py',
        'finalize', '--root', '/workspace',
        '--attempt-tsv', '/workspace/Data/Exports/P2-20/p2-20a-asset-binding-recovery-eligible-attempts.tsv',
        '--base-plan-contract', '/workspace/Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv',
        '--effective-plan-tsv', '/workspace/Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv',
        '--a4-effective-detail', '/workspace/Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl',
        '--success-tsv', "/output/$([IO.Path]::GetFileName($generated.success))",
        '--detail-output', "/output/$([IO.Path]::GetFileName($generated.detail))",
        '--json-output', "/output/$([IO.Path]::GetFileName($generated.json))",
        '--markdown-output', "/output/$([IO.Path]::GetFileName($generated.markdown))",
        '--evidence-output', "/output/$([IO.Path]::GetFileName($generated.evidence))") + $captured
    $text = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.8 finalization failed.' }
    $summary = $text | ConvertFrom-Json -Depth 100
    if ($summary.result -ne 'PASS' -or $summary.task_status -ne 'BLOCKED' -or
        [int]$summary.attempted.candidate_edges -ne 21 -or
        [int]$summary.successful.targets -ne 13 -or
        [int]$summary.successful.candidate_edges -ne 15 -or
        [int]$summary.effective_resolution.unresolved.targets -ne 6 -or
        [int]$summary.effective_resolution.unresolved.candidate_edges -ne 9) {
        throw 'P2-20A.8 cross-proof summary drifted.'
    }
    foreach ($name in @('success', 'detail', 'json', 'markdown', 'evidence')) {
        if ($Check) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -cne (Get-Sha256 $generated[$name])) {
                throw "P2-20A.8 finalize output differs: $name"
            }
        }
        else { Copy-Output $generated[$name] $targets[$name] }
    }
    $summary | ConvertTo-Json -Depth 100
}
finally {
    $resolved = [IO.Path]::GetFullPath($runRoot)
    if ($resolved.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolved -PathType Container)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
