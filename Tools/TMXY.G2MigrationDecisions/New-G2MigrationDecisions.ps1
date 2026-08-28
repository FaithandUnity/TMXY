[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$DevDocRoot = 'E:\QQXYCodeDev\DevDoc',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$devDoc = [IO.Path]::GetFullPath($DevDocRoot).TrimEnd([char[]]'\/')
$authorizedLegacy = [IO.Path]::GetFullPath((Join-Path (Split-Path $root -Parent) 'DevDoc')).TrimEnd([char[]]'\/')
if (-not $devDoc.Equals($authorizedLegacy, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20B requires the authorized read-only DevDoc root.'
}
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20B'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20B temporary root escaped Rebuild.'
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
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2MigrationDecisions'
    $generatorPath = Join-Path $moduleRoot 'migration_decisions.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-policy-v2.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-registry-v2.schema.json'
    $authoritySchemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-authority-v2.schema.json'
    $packetSchemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-review-packets-v2.schema.json'
    $authorityPath = Join-Path $root 'Data\Governance\p2-g2-migration-decision-authority-v2.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($devDoc, $generatorPath, $policyPath, $schemaPath,
            $authoritySchemaPath, $packetSchemaPath, $authorityPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing P2-20B input: $required" }
    }
    if (-not (Get-Content -LiteralPath $authorityPath -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $authoritySchemaPath)) {
        throw 'P2-20B authority ledger failed its closed JSON Schema.'
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20B requires the qualified non-root Clang 21 builder image.'
    }

    $registryName = 'p2-g2-migration-decisions.json'
    $packetName = 'p2-g2-migration-review-packets.json'
    $markdownName = 'p2-20b-migration-decisions-report.md'
    $generatedRegistry = Join-Path $runRoot $registryName
    $generatedPackets = Join-Path $runRoot $packetName
    $generatedMarkdown = Join-Path $runRoot $markdownName
    $trackedRegistry = Join-Path $root "Data\Governance\$registryName"
    $trackedPackets = Join-Path $root "Data\Governance\$packetName"
    $trackedMarkdown = Join-Path $root "Data\Reports\$markdownName"
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $arguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$devDoc,dst=/legacy-root,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=32m',
        $builderReference, 'python3', '/workspace/Tools/TMXY.G2MigrationDecisions/migration_decisions.py',
        '--root', '/workspace', '--legacy-root', '/legacy-root',
        '--policy', '/workspace/Contracts/data-schema/g2-migration-decision-policy-v2.json',
        '--schema', '/workspace/Contracts/data-schema/g2-migration-decision-registry-v2.schema.json',
        '--registry-output', "/output/$registryName", '--packet-output', "/output/$packetName",
        '--markdown-output', "/output/$markdownName"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20B isolated generation failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfText = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$root,dst=/workspace,readonly" `
        $builderReference python3 /workspace/Tools/TMXY.G2MigrationDecisions/migration_decisions.py --self-test
    if ($LASTEXITCODE -ne 0) { throw 'P2-20B generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json -Depth 100
    if ($summary.generation_result -ne 'PASS' -or $summary.result -ne 'BLOCKED' -or
        [int]$summary.enumerated_units -ne 1359 -or [int]$summary.pending -ne 1359 -or
        $summary.g2_07_satisfied -ne $false -or [int]$summary.review_packets -ne 39 -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -lt 23 -or
        @($selfTest.workflow_negative_cases.PSObject.Properties |
            Where-Object Value -ne $true).Count -ne 0) {
        throw 'P2-20B generation or self-test summary failed.'
    }
    if (-not (Get-Content -LiteralPath $generatedRegistry -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)) {
        throw 'P2-20B registry failed its closed JSON Schema.'
    }
    if (-not (Get-Content -LiteralPath $generatedPackets -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $packetSchemaPath)) {
        throw 'P2-20B review packets failed their closed JSON Schema.'
    }

    $targets = [ordered]@{ registry = $trackedRegistry; packets = $trackedPackets; markdown = $trackedMarkdown }
    $generated = [ordered]@{ registry = $generatedRegistry; packets = $generatedPackets; markdown = $generatedMarkdown }
    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked P2-20B output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    $registry = Get-Content -LiteralPath $trackedRegistry -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $evidencePath = Join-Path $root 'Data\Inventory\p2-20b-migration-decisions.json'
    $evidence = [pscustomobject][ordered]@{
        schema_version = 2
        workflow_version = 2
        captured_utc = [string]$registry.captured_utc
        task_id = 'P2-20B'
        result = 'BLOCKED'
        generation_result = 'PASS'
        task_status = 'BLOCKED'
        completion_criteria_satisfied = $false
        gate_criterion = 'G2-07'
        g2_07_satisfied = $false
        input = $registry.input_bindings
        registry = [pscustomobject][ordered]@{
            path = Get-Relative $trackedRegistry
            tracked = $true
            bytes = [int64](Get-Item -LiteralPath $trackedRegistry).Length
            lines = Get-LineCount $trackedRegistry
            sha256 = Get-Sha256 $trackedRegistry
        }
        review_packets = [pscustomobject][ordered]@{
            path = Get-Relative $trackedPackets
            tracked = $true
            bytes = [int64](Get-Item -LiteralPath $trackedPackets).Length
            lines = Get-LineCount $trackedPackets
            sha256 = Get-Sha256 $trackedPackets
            packet_count = [int]$registry.review_packets.packet_count
            member_count = [int]$registry.review_packets.member_count
            aggregate_membership_sha256 = [string]$registry.review_packets.aggregate_membership_sha256
            counts_as_decision = $false
        }
        report = [pscustomobject][ordered]@{
            path = Get-Relative $trackedMarkdown
            tracked = $true
            bytes = [int64](Get-Item -LiteralPath $trackedMarkdown).Length
            lines = Get-LineCount $trackedMarkdown
            sha256 = Get-Sha256 $trackedMarkdown
        }
        summary = $registry.summary
        completeness = $registry.completeness
        hard_invariants = $registry.hard_invariants
        authority_boundaries = $registry.authority_boundaries
        contracts = [pscustomobject][ordered]@{
            policy = Get-Relative $policyPath
            policy_sha256 = Get-Sha256 $policyPath
            schema = Get-Relative $schemaPath
            schema_sha256 = Get-Sha256 $schemaPath
            authority_schema = Get-Relative $authoritySchemaPath
            authority_schema_sha256 = Get-Sha256 $authoritySchemaPath
            review_packet_schema = Get-Relative $packetSchemaPath
            review_packet_schema_sha256 = Get-Sha256 $packetSchemaPath
            authority_ledger = Get-Relative $authorityPath
            authority_ledger_sha256 = Get-Sha256 $authorityPath
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = Get-TextSha256 (($sourceLines -join "`n") + "`n")
            generator = Get-Relative $generatorPath
            generator_sha256 = Get-Sha256 $generatorPath
            wrapper = Get-Relative $MyInvocation.MyCommand.Path
            wrapper_sha256 = Get-Sha256 $MyInvocation.MyCommand.Path
            self_test_assertions = [int]$selfTest.assertions
            workflow_negative_cases = $selfTest.workflow_negative_cases
        }
        disclosure = $registry.disclosure
        reproduction = [pscustomobject][ordered]@{
            repository_mount = 'read-only'
            legacy_mount = 'read-only-authorized-input'
            network = 'none'
            capabilities = 'none'
            no_new_privileges = $true
            builder_reference = $builderReference
            builder_id = $expectedBuilderId
            builder_user = 'tmxy'
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-20B-owner-decisions', 'P2-20B-approved-verification', 'P2-20-g2-rerun')
            detail = 'Review 39 anonymous packets while preserving all 1359 members; import only real owner decisions and independently verified digest-bound authority. Machine suggestions and packet grouping do not close G2-07.'
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-20B evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        if (($frozen | ConvertTo-Json -Depth 100 -Compress) -cne
            ($evidence | ConvertTo-Json -Depth 100 -Compress)) {
            throw 'Tracked P2-20B evidence differs from deterministic full-object regeneration.'
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
