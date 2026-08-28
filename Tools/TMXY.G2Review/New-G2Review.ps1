[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20 temporary root escaped Rebuild.'
}
$runRoot = Join-Path $localRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length + 1)).Replace('\', '/')
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Get-TextSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Copy-Output([string]$Source, [string]$Target) {
    $directory = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
}

try {
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2Review'
    $generatorPath = Join-Path $moduleRoot 'g2_review.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-review-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-review-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generatorPath, $policyPath, $schemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20 input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20 requires the qualified non-root Clang 21 builder image.'
    }

    $jsonName = 'p2-20-g2-review-report.json'
    $markdownName = 'p2-20-g2-review-report.md'
    $generatedJson = Join-Path $runRoot $jsonName
    $generatedMarkdown = Join-Path $runRoot $markdownName
    $trackedJson = Join-Path $root "Data\Reports\$jsonName"
    $trackedMarkdown = Join-Path $root "Data\Reports\$markdownName"
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $arguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=32m',
        $builderReference, 'python3', '/workspace/Tools/TMXY.G2Review/g2_review.py',
        '--root', '/workspace',
        '--policy', '/workspace/Contracts/data-schema/g2-review-policy-v1.json',
        '--schema', '/workspace/Contracts/data-schema/g2-review-v1.schema.json',
        '--json-output', "/output/$jsonName",
        '--markdown-output', "/output/$markdownName"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20 isolated report generation failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfText = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$root,dst=/workspace,readonly" `
        $builderReference python3 /workspace/Tools/TMXY.G2Review/g2_review.py --self-test
    if ($LASTEXITCODE -ne 0) { throw 'P2-20 generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json -Depth 100
    if ($summary.result -ne 'BLOCKED' -or $summary.review_execution_result -ne 'PASS' -or
        [int]$summary.satisfied -ne 7 -or [int]$summary.blocked -ne 2 -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -lt 8) {
        throw 'P2-20 generator summary or self-test failed.'
    }
    $valid = Get-Content -LiteralPath $generatedJson -Raw -Encoding UTF8 |
        Test-Json -SchemaFile $schemaPath
    if (-not $valid) { throw 'P2-20 generated report failed its closed JSON Schema.' }

    $targets = [ordered]@{ json = $trackedJson; markdown = $trackedMarkdown }
    $generated = [ordered]@{ json = $generatedJson; markdown = $generatedMarkdown }
    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked P2-20 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    $report = Get-Content -LiteralPath $trackedJson -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    $evidencePath = Join-Path $root 'Data\Inventory\p2-20-g2-review.json'
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [string]$report.captured_utc
        task_id = 'P2-20'
        result = 'BLOCKED'
        review_execution_result = 'PASS'
        task_status = 'BLOCKED'
        completion_criteria_satisfied = $false
        gate = 'G2'
        gate_decision = 'BLOCKED'
        g2_approved = $false
        p3_authorized = $false
        input = [pscustomobject][ordered]@{
            source_build = [string]$report.source_build
            bindings = $report.input_bindings
        }
        report = [pscustomobject][ordered]@{
            json = [pscustomobject][ordered]@{
                path = Get-Relative $trackedJson
                tracked = $true
                bytes = [int64](Get-Item -LiteralPath $trackedJson).Length
                lines = Get-LineCount $trackedJson
                sha256 = Get-Sha256 $trackedJson
            }
            markdown = [pscustomobject][ordered]@{
                path = Get-Relative $trackedMarkdown
                tracked = $true
                bytes = [int64](Get-Item -LiteralPath $trackedMarkdown).Length
                lines = Get-LineCount $trackedMarkdown
                sha256 = Get-Sha256 $trackedMarkdown
            }
        }
        summary = $report.summary
        blockers = $report.blockers
        budget_interpretation = $report.budget_interpretation
        authority_boundaries = $report.authority_boundaries
        security = $report.security
        contracts = [pscustomobject][ordered]@{
            policy = Get-Relative $policyPath
            policy_sha256 = Get-Sha256 $policyPath
            schema = Get-Relative $schemaPath
            schema_sha256 = Get-Sha256 $schemaPath
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceSha
            generator = Get-Relative $generatorPath
            generator_sha256 = Get-Sha256 $generatorPath
            wrapper = Get-Relative $MyInvocation.MyCommand.Path
            wrapper_sha256 = Get-Sha256 $MyInvocation.MyCommand.Path
            self_test_assertions = [int]$selfTest.assertions
        }
        disclosure = $report.disclosure
        reproduction = [pscustomobject][ordered]@{
            check_mode = $false
            repository_mount = 'read-only'
            network = 'none'
            capabilities = 'none'
            no_new_privileges = $true
            builder_reference = $builderReference
            builder_id = $expectedBuilderId
            builder_user = 'tmxy'
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-20-remediation')
            detail = 'Close G2-06 resource-reference proof and G2-07 migration decisions, then rerun the fail-closed G2 review. P3 remains unauthorized.'
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-20 evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        $frozenCanonical = $frozen | ConvertTo-Json -Depth 100 -Compress
        $generatedCanonical = $evidence | ConvertTo-Json -Depth 100 -Compress
        if ($frozenCanonical -cne $generatedCanonical) {
            throw 'Tracked P2-20 evidence differs from deterministic full-object regeneration.'
        }
    }
    else {
        $json = ($evidence | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n")
        [IO.File]::WriteAllText($evidencePath, $json + "`n", [Text.UTF8Encoding]::new($false))
    }
    $evidence | ConvertTo-Json -Depth 100
}
finally {
    $resolvedRun = [IO.Path]::GetFullPath($runRoot)
    if ($resolvedRun.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedRun -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRun -Recurse -Force
    }
}
