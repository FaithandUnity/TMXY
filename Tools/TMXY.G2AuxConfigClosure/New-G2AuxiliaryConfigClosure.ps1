[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A3'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.3 temporary root escaped Rebuild.'
}
$runRoot = Join-Path $localRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length + 1)).Replace('\', '/')
}

function Get-TextSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
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
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2AuxConfigClosure'
    $generatorPath = Join-Path $moduleRoot 'g2_aux_config.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-auxiliary-config-reference-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-auxiliary-config-reference-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generatorPath, $policyPath, $schemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20A.3 input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.3 requires the qualified non-root Clang 21 builder image.'
    }

    $names = [ordered]@{
        detail = 'p2-20a-aux-config-reference-candidates.jsonl'
        json = 'p2-20a-aux-config-reference-report.json'
        markdown = 'p2-20a-aux-config-reference-report.md'
        governance = 'p2-g2-aux-config-reference.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $names.Keys) { $generated[$name] = Join-Path $runRoot $names[$name] }
    $targets = [ordered]@{
        detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-aux-config-reference-candidates.jsonl'
        json = Join-Path $root 'Data\Reports\p2-20a-aux-config-reference-report.json'
        markdown = Join-Path $root 'Data\Reports\p2-20a-aux-config-reference-report.md'
        governance = Join-Path $root 'Data\Governance\p2-g2-aux-config-reference.json'
    }

    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $arguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=32m',
        $builderReference, 'python3',
        '/workspace/Tools/TMXY.G2AuxConfigClosure/g2_aux_config.py',
        '--root', '/workspace',
        '--policy', '/workspace/Contracts/data-schema/g2-auxiliary-config-reference-policy-v1.json',
        '--schema', '/workspace/Contracts/data-schema/g2-auxiliary-config-reference-v1.schema.json',
        '--detail-output', "/output/$($names.detail)",
        '--json-output', "/output/$($names.json)",
        '--markdown-output', "/output/$($names.markdown)",
        '--governance-output', "/output/$($names.governance)"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.3 isolated generation failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfText = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$root,dst=/workspace,readonly" `
        $builderReference python3 `
        /workspace/Tools/TMXY.G2AuxConfigClosure/g2_aux_config.py `
        --root /workspace --self-test
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.3 generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json -Depth 100
    if ($summary.result -ne 'BLOCKED' -or
        $summary.review_execution_result -ne 'PASS' -or
        $summary.task_status -ne 'BLOCKED' -or
        $summary.completion_criteria_satisfied -ne $false -or
        $summary.scope_complete -ne $false -or
        [int]$summary.file_instances -ne 212 -or
        [int]$summary.detail_records -ne 3907 -or
        [int]$summary.nonempty_scalar_positions -ne 39498 -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -lt 22) {
        throw 'P2-20A.3 summary or self-test failed.'
    }
    if (-not (Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)) {
        throw 'P2-20A.3 generated report failed its closed JSON Schema.'
    }

    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked or local P2-20A.3 output differs from deterministic regeneration: $name"
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
        [int]$report.measured_lexical_candidates.file_instances -ne 212 -or
        [int]$report.measured_lexical_candidates.nonempty_scalar_positions -ne 39498 -or
        [int]$report.adapter_state_summary.approved_roots -ne 0) {
        throw 'P2-20A.3 fail-closed report binding failed.'
    }

    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    $evidencePath = Join-Path $root 'Data\Inventory\p2-20a-aux-config-reference-evidence.json'
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_revision = 'P2-20A.3'
        captured_utc = [string]$report.captured_utc
        task_id = 'P2-20A'
        criterion_id = 'G2-06'
        result = 'BLOCKED'
        review_execution_result = 'PASS'
        task_status = 'BLOCKED'
        completion_criteria_satisfied = $false
        scope_complete = $false
        g2_06_satisfied = $false
        p3_authorized = $false
        input_bindings = $report.input_bindings
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
            anonymous_candidate_export = [pscustomobject][ordered]@{
                path = Get-Relative $targets.detail
                tracked = $false
                bytes = [int64](Get-Item $targets.detail).Length
                lines = Get-LineCount $targets.detail
                sha256 = Get-Sha256 $targets.detail
            }
        }
        measured_lexical_candidates = $report.measured_lexical_candidates
        adapter_state_summary = $report.adapter_state_summary
        semantic_resolution = $report.semantic_resolution
        config_closure = $report.config_closure
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
            tasks = @('P2-20A.4', 'P2-20')
            detail = 'Approve explicit semantic or no-reference dispositions for every file instance, safely cover malformed XML, build approved roots and config closure, then rerun G2. P3 remains unauthorized.'
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-20A.3 evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        if (($frozen | ConvertTo-Json -Depth 100 -Compress) -cne
            ($evidence | ConvertTo-Json -Depth 100 -Compress)) {
            throw 'Tracked P2-20A.3 evidence differs from deterministic regeneration.'
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
