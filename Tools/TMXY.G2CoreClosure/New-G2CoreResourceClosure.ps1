[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A temporary root escaped Rebuild.'
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
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2CoreClosure'
    $generatorPath = Join-Path $moduleRoot 'g2_core_closure.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-core-resource-closure-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-core-resource-closure-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generatorPath, $policyPath, $schemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20A input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A requires the qualified non-root Clang 21 builder image.'
    }

    $names = [ordered]@{
        detail = 'p2-20a-core-resource-closure.jsonl'
        workset = 'p2-20a-conditional-required-workset.jsonl'
        json = 'p2-20a-core-resource-closure-report.json'
        markdown = 'p2-20a-core-resource-closure-report.md'
        governance = 'p2-g2-core-resource-closure.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $names.Keys) { $generated[$name] = Join-Path $runRoot $names[$name] }
    $targets = [ordered]@{
        detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-core-resource-closure.jsonl'
        workset = Join-Path $root 'Data\Exports\P2-20\p2-20a-conditional-required-workset.jsonl'
        json = Join-Path $root 'Data\Reports\p2-20a-core-resource-closure-report.json'
        markdown = Join-Path $root 'Data\Reports\p2-20a-core-resource-closure-report.md'
        governance = Join-Path $root 'Data\Governance\p2-g2-core-resource-closure.json'
    }
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $arguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=32m',
        $builderReference, 'python3', '/workspace/Tools/TMXY.G2CoreClosure/g2_core_closure.py',
        '--root', '/workspace',
        '--policy', '/workspace/Contracts/data-schema/g2-core-resource-closure-policy-v1.json',
        '--schema', '/workspace/Contracts/data-schema/g2-core-resource-closure-v1.schema.json',
        '--detail-output', "/output/$($names.detail)",
        '--table-root', '/workspace/Data/Exports/P2-06/tables',
        '--workset-output', "/output/$($names.workset)",
        '--json-output', "/output/$($names.json)",
        '--markdown-output', "/output/$($names.markdown)",
        '--governance-output', "/output/$($names.governance)"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A isolated generation failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfText = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$root,dst=/workspace,readonly" `
        $builderReference python3 /workspace/Tools/TMXY.G2CoreClosure/g2_core_closure.py --self-test
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json -Depth 100
    if ($summary.result -ne 'BLOCKED' -or $summary.review_execution_result -ne 'PASS' -or
        $summary.task_status -ne 'BLOCKED' -or $summary.completion_criteria_satisfied -ne $false -or
        $summary.scope_complete -ne $false -or [int]$summary.logical_gap_count -le 0 -or
        [int]$summary.conditional_required_missing -le 0 -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -lt 11) {
        throw 'P2-20A generator summary or self-test failed.'
    }
    $valid = Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
        Test-Json -SchemaFile $schemaPath
    if (-not $valid) { throw 'P2-20A generated report failed its closed JSON Schema.' }

    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked or local P2-20A output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    $report = Get-Content -LiteralPath $targets.json -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    if ($report.evidence_revision -ne 'P2-20A.1' -or
        $report.closure.conditional_required.member_set_exported -ne $true -or
        [int]$report.closure.conditional_required.member_set_count -ne
            (Get-LineCount $targets.workset) -or
        [string]$report.closure.conditional_required.member_set_sha256 -cne
            (Get-Sha256 $targets.workset)) {
        throw 'P2-20A.1 conditional-required workset binding failed.'
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    $evidencePath = Join-Path $root 'Data\Inventory\p2-20a-core-resource-closure.json'
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_revision = 'P2-20A.1'
        captured_utc = [string]$report.captured_utc
        task_id = 'P2-20A'
        criterion_id = 'G2-06'
        result = 'BLOCKED'
        review_execution_result = 'PASS'
        task_status = 'BLOCKED'
        completion_criteria_satisfied = $false
        input = [pscustomobject][ordered]@{
            source_build = [string]$report.source_build
            bindings = $report.input_bindings
        }
        outputs = [pscustomobject][ordered]@{
            report_json = [pscustomobject][ordered]@{
                path = Get-Relative $targets.json
                tracked = $true
                bytes = [int64](Get-Item $targets.json).Length
                lines = Get-LineCount $targets.json
                sha256 = Get-Sha256 $targets.json
            }
            report_markdown = [pscustomobject][ordered]@{
                path = Get-Relative $targets.markdown
                tracked = $true
                bytes = [int64](Get-Item $targets.markdown).Length
                lines = Get-LineCount $targets.markdown
                sha256 = Get-Sha256 $targets.markdown
            }
            governance = [pscustomobject][ordered]@{
                path = Get-Relative $targets.governance
                tracked = $true
                bytes = [int64](Get-Item $targets.governance).Length
                lines = Get-LineCount $targets.governance
                sha256 = Get-Sha256 $targets.governance
            }
            detail_export = [pscustomobject][ordered]@{
                path = Get-Relative $targets.detail
                tracked = $false
                bytes = [int64](Get-Item $targets.detail).Length
                lines = Get-LineCount $targets.detail
                sha256 = Get-Sha256 $targets.detail
            }
            conditional_required_workset = [pscustomobject][ordered]@{
                tracked = $false
                count = [int]$report.closure.conditional_required.member_set_count
                sha256 = Get-Sha256 $targets.workset
            }
        }
        scope_definition = $report.scope_definition
        closure = $report.closure
        decision = $report.decision
        blockers = $report.blockers
        authority_boundaries = $report.authority_boundaries
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
            tasks = @('P2-20A-remediation', 'P2-20')
            detail = 'Close configuration scope, asset-binding resolution, conditional-required missing values, logical queues, and reachable structural gaps; then regenerate P2-13/P2-18 and rerun G2. P3 remains unauthorized.'
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-20A evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        if (($frozen | ConvertTo-Json -Depth 100 -Compress) -cne
            ($evidence | ConvertTo-Json -Depth 100 -Compress)) {
            throw 'Tracked P2-20A evidence differs from deterministic regeneration.'
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
