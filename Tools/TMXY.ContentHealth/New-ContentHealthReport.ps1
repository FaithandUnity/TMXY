[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-18'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-18 temporary root escaped Rebuild.'
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
    $moduleRoot = Join-Path $root 'Tools\TMXY.ContentHealth'
    $pythonPath = Join-Path $moduleRoot 'content_health.py'
    $queryPath = Join-Path $moduleRoot 'Find-ContentHealth.ps1'
    $policyPath = Join-Path $root 'Contracts\data-schema\content-health-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\content-health-report-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    $requiredEvidence = @(1..17 | ForEach-Object {
            Join-Path $root ('Data\Inventory\p2-{0:D2}-' -f $_)
        })
    foreach ($required in @($pythonPath, $queryPath, $policyPath, $schemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing P2-18 input: $required" }
    }
    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($policy.required_tasks).Count -ne 17) { throw 'P2-18 policy must require P2-01 through P2-17.' }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-18 requires the qualified non-root Clang 21 builder image.'
    }

    $jsonName = 'p2-18-content-health-report.json'
    $markdownName = 'p2-18-content-health-report.md'
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
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m',
        $builderReference, 'python3', '/workspace/Tools/TMXY.ContentHealth/content_health.py',
        '--root', '/workspace',
        '--policy', '/workspace/Contracts/data-schema/content-health-policy-v1.json',
        '--json-output', "/output/$jsonName",
        '--markdown-output', "/output/$markdownName"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-18 isolated report generation failed.' }
    $summary = $summaryText | ConvertFrom-Json
    $selfText = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$root,dst=/workspace,readonly" `
        $builderReference python3 /workspace/Tools/TMXY.ContentHealth/content_health.py --self-test
    if ($LASTEXITCODE -ne 0) { throw 'P2-18 generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json
    if ($summary.result -ne 'PASS_WITH_OPEN_CONTENT_RISKS' -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -ne 6) {
        throw 'P2-18 generator summary or self-test failed.'
    }

    $targets = [ordered]@{ json = $trackedJson; markdown = $trackedMarkdown }
    $generated = [ordered]@{ json = $generatedJson; markdown = $generatedMarkdown }
    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked P2-18 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    $report = Get-Content -LiteralPath $trackedJson -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    $evidencePath = Join-Path $root 'Data\Inventory\p2-18-content-health.json'
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
        task_id = 'P2-18'
        result = 'PASS'
        task_status = 'COMPLETE'
        completion_criteria_satisfied = $true
        input = [pscustomobject][ordered]@{
            source_build = 'qy-3.0.0.413'
            completed_tasks = [int]$report.scope.completed_tasks
            binding_sha256 = [string]$report.scope.input_binding_sha256
            inputs = $report.scope.inputs
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
        summary = [pscustomobject][ordered]@{
            report_result = [string]$report.result
            executive = $report.executive_summary
            risk_summary = $report.risk_summary
            parsing = $report.dimensions.parsing
            damage = $report.dimensions.damage
            unknown_or_opaque = $report.dimensions.unknown_or_opaque
            references = $report.dimensions.references
            conversion = $report.dimensions.conversion
            effort = $report.dimensions.effort
            capacity = $report.dimensions.capacity
            decisions = $report.decisions
        }
        contracts = [pscustomobject][ordered]@{
            policy = Get-Relative $policyPath
            policy_sha256 = Get-Sha256 $policyPath
            schema = Get-Relative $schemaPath
            schema_sha256 = Get-Sha256 $schemaPath
            rate_unit = 'parts-per-million'
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceSha
            generator = Get-Relative $pythonPath
            generator_sha256 = Get-Sha256 $pythonPath
            wrapper = Get-Relative $MyInvocation.MyCommand.Path
            wrapper_sha256 = Get-Sha256 $MyInvocation.MyCommand.Path
            query = Get-Relative $queryPath
            query_sha256 = Get-Sha256 $queryPath
            self_test_assertions = [int]$selfTest.assertions
        }
        disclosure = [pscustomobject][ordered]@{
            private_source_paths = $false
            exact_primary_keys = $false
            exact_observed_extrema = $false
            raw_table_rows = $false
            decoded_confidential_payloads = $false
            legacy_source_lines = $false
        }
        reproduction = [pscustomobject][ordered]@{
            check_mode = [bool]$Check
            repository_mount = 'read-only'
            network = 'none'
            builder_reference = $builderReference
            builder_id = $expectedBuilderId
            builder_user = 'tmxy'
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-19', 'P2-20')
            detail = 'Re-estimate budget from measured inventory facts, then execute the G2 review without claiming playable or release readiness.'
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-18 evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        $matches = $frozen.result -eq 'PASS' -and $frozen.completion_criteria_satisfied -and
            $frozen.input.binding_sha256 -eq $evidence.input.binding_sha256 -and
            $frozen.report.json.sha256 -eq $evidence.report.json.sha256 -and
            $frozen.report.markdown.sha256 -eq $evidence.report.markdown.sha256 -and
            $frozen.contracts.policy_sha256 -eq $evidence.contracts.policy_sha256 -and
            $frozen.contracts.schema_sha256 -eq $evidence.contracts.schema_sha256 -and
            $frozen.implementation.source_sha256 -eq $evidence.implementation.source_sha256
        if (-not $matches) { throw 'Tracked P2-18 evidence differs from deterministic regeneration.' }
        $evidence.captured_utc = [string]$frozen.captured_utc
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
