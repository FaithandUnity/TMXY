[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-19'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-19 temporary root escaped Rebuild.'
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
    $moduleRoot = Join-Path $root 'Tools\TMXY.ResourceBudget'
    $pythonPath = Join-Path $moduleRoot 'resource_budget.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\resource-budget-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\resource-budget-report-v1.schema.json'
    $pilotPath = Join-Path $root 'Data\Performance\p2-19-conversion-pilot.json'
    $p215Path = Join-Path $root 'Data\Inventory\p2-15-conversion-routing.json'
    $p218Path = Join-Path $root 'Data\Inventory\p2-18-content-health.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($pythonPath, $policyPath, $schemaPath, $pilotPath,
            $p215Path, $p218Path, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-19 input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-19 requires the qualified non-root Clang 21 builder image.'
    }

    $jsonName = 'p2-19-resource-budget-report.json'
    $markdownName = 'p2-19-resource-budget-report.md'
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
        $builderReference, 'python3', '/workspace/Tools/TMXY.ResourceBudget/resource_budget.py',
        '--root', '/workspace',
        '--policy', '/workspace/Contracts/data-schema/resource-budget-policy-v1.json',
        '--pilot', '/workspace/Data/Performance/p2-19-conversion-pilot.json',
        '--json-output', "/output/$jsonName",
        '--markdown-output', "/output/$markdownName"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-19 isolated report generation failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfText = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$root,dst=/workspace,readonly" `
        $builderReference python3 /workspace/Tools/TMXY.ResourceBudget/resource_budget.py --self-test
    if ($LASTEXITCODE -ne 0) { throw 'P2-19 generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json -Depth 100
    if ($summary.result -ne 'PASS_WITH_OPEN_MEASUREMENT_GAPS' -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -lt 8) {
        throw 'P2-19 generator summary or self-test failed.'
    }

    $targets = [ordered]@{ json = $trackedJson; markdown = $trackedMarkdown }
    $generated = [ordered]@{ json = $generatedJson; markdown = $generatedMarkdown }
    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked P2-19 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    $report = Get-Content -LiteralPath $trackedJson -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100
    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    $evidencePath = Join-Path $root 'Data\Inventory\p2-19-resource-budget.json'
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
        task_id = 'P2-19'
        result = 'PASS'
        task_status = 'COMPLETE'
        completion_criteria_satisfied = $true
        input = [pscustomobject][ordered]@{
            source_build = [string]$report.source_build
            bindings = $report.input_bindings
            basis_kinds = @($report.basis_catalog.PSObject.Properties.Name | Sort-Object -Unique)
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
            budget_status = [string]$report.budget_status
            human_budget = $report.human_budget
            machine_budget = $report.machine_budget
            storage_budget = $report.storage_budget
            program_forecast = $report.program_forecast
            team_plan = $report.team_plan
            risk_items = @($report.risk_register).Count
            missing_measurements = @($report.missing_measurements).Count
            decisions = $report.decisions
        }
        contracts = [pscustomobject][ordered]@{
            policy = Get-Relative $policyPath
            policy_sha256 = Get-Sha256 $policyPath
            schema = Get-Relative $schemaPath
            schema_sha256 = Get-Sha256 $schemaPath
            pilot = Get-Relative $pilotPath
            pilot_sha256 = Get-Sha256 $pilotPath
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceSha
            generator = Get-Relative $pythonPath
            generator_sha256 = Get-Sha256 $pythonPath
            wrapper = Get-Relative $MyInvocation.MyCommand.Path
            wrapper_sha256 = Get-Sha256 $MyInvocation.MyCommand.Path
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
            check_mode = $false
            repository_mount = 'read-only'
            network = 'none'
            builder_reference = $builderReference
            builder_id = $expectedBuilderId
            builder_user = 'tmxy'
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-20')
            detail = 'Execute the fail-closed G2 review; open measurements remain explicit and do not grant schedule, price, playable, gate, or release authority.'
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-19 evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        $evidence.captured_utc = [string]$frozen.captured_utc
        $frozenCanonical = $frozen | ConvertTo-Json -Depth 100 -Compress
        $generatedCanonical = $evidence | ConvertTo-Json -Depth 100 -Compress
        if ($frozenCanonical -cne $generatedCanonical) {
            throw 'Tracked P2-19 evidence differs from deterministic full-object regeneration.'
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
