[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacySourceRoot = 'E:\QQXYCodeDev',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$legacyRoot = [IO.Path]::GetFullPath($LegacySourceRoot).TrimEnd([char[]]'\/')
$legacyConsumerRoot = [IO.Path]::GetFullPath((Join-Path $legacyRoot 'ClientCode'))
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A5'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.5 temporary root escaped Rebuild.'
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
    foreach ($directory in @($root, $legacyConsumerRoot)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Required directory is missing: $directory"
        }
    }
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2AuxSemanticDiagnostics'
    $generatorPath = Join-Path $moduleRoot 'g2_aux_semantic_diagnostics.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-aux-semantic-diagnostics-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-aux-semantic-diagnostics-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generatorPath, $policyPath, $schemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20A.5 input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.5 requires the qualified non-root Clang 21 builder image.'
    }

    $names = [ordered]@{
        json = 'p2-20a-aux-semantic-diagnostics-report.json'
        markdown = 'p2-20a-aux-semantic-diagnostics-report.md'
        evidence = 'p2-20a-aux-semantic-diagnostics.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $names.Keys) { $generated[$name] = Join-Path $runRoot $names[$name] }
    $targets = [ordered]@{
        json = Join-Path $root 'Data\Reports\p2-20a-aux-semantic-diagnostics-report.json'
        markdown = Join-Path $root 'Data\Reports\p2-20a-aux-semantic-diagnostics-report.md'
        evidence = Join-Path $root 'Data\Inventory\p2-20a-aux-semantic-diagnostics.json'
    }

    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $base = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$legacyConsumerRoot,dst=/legacy/source,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m', $builderReference
    )
    $arguments = $base + @(
        'python3', '/workspace/Tools/TMXY.G2AuxSemanticDiagnostics/g2_aux_semantic_diagnostics.py',
        '--root', '/workspace', '--legacy-source-root', '/legacy/source',
        '--json-output', "/output/$($names.json)",
        '--markdown-output', "/output/$($names.markdown)",
        '--evidence-output', "/output/$($names.evidence)"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.5 isolated generation failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfArguments = $base + @(
        'python3', '/workspace/Tools/TMXY.G2AuxSemanticDiagnostics/g2_aux_semantic_diagnostics.py',
        '--self-test'
    )
    $selfText = & $docker @selfArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.5 generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json -Depth 100
    if ($summary.result -ne 'BLOCKED' -or $summary.review_execution_result -ne 'PASS' -or
        [int]$summary.file_instances -ne 212 -or
        [int]$summary.unique_semantic_references -ne 3180 -or
        [int]$summary.ambiguous_object_references -ne 211 -or
        [int]$summary.unresolved_resources -ne 1 -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -lt 10 -or
        @($selfTest.negative_cases.PSObject.Properties | Where-Object Value -ne $true).Count -ne 0) {
        throw 'P2-20A.5 deterministic summary or negative self-test failed.'
    }
    if (-not (Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)) {
        throw 'P2-20A.5 report failed its closed JSON Schema.'
    }

    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "P2-20A.5 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    $report = Get-Content -LiteralPath $targets.json -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    if ($report.scope_complete -ne $false -or $report.g2_06_satisfied -ne $false -or
        $report.p3_authorized -ne $false -or
        [int]$report.g2_projection.satisfied -ne 7 -or
        [int]$report.g2_projection.blocked -ne 2) {
        throw 'P2-20A.5 fail-closed G2 projection drifted.'
    }
    [pscustomobject][ordered]@{
        result = 'PASS_DIAGNOSTIC'
        task_status = 'BLOCKED'
        file_instances = 212
        unique_semantic_references = 3180
        ambiguous_object_references = 211
        unresolved_resources = 1
        report_sha256 = Get-Sha256 $targets.json
        evidence_sha256 = Get-Sha256 $targets.evidence
    } | ConvertTo-Json -Depth 10
}
finally {
    $resolvedRun = [IO.Path]::GetFullPath($runRoot)
    if ($resolvedRun.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedRun -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRun -Recurse -Force
    }
}
