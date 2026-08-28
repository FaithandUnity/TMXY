[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$BuilderImage = 'mmorpg-source-builder:local',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-17'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-17 temporary root escaped Rebuild.'
}
$runRoot = Join-Path $localRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length + 1)).Replace('\', '/')
}

function Copy-Generated([string]$Source, [string]$Target) {
    $directory = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
}

try {
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $pythonPath = Join-Path $root 'Tools\TMXY.ProtocolGen\protocol_gen.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\protocol-codegen-policy-v1.json'
    $contractPath = Join-Path $root 'Contracts\data-schema\core-data-model-v1.schema.json'
    $registryPath = Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
    $auditPath = Join-Path $root 'Data\Inventory\p2-11-id-limit-audit.json'
    foreach ($required in @($pythonPath, $policyPath, $contractPath, $registryPath, $auditPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing input: $required" }
    }

    $schemaName = 'core-data-model-v1.json'
    $backendName = 'core_data_types.generated.hpp'
    $ueName = 'TMXYCoreDataTypes.generated.hpp'
    $arguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m',
        $BuilderImage, 'python3', '/workspace/Tools/TMXY.ProtocolGen/protocol_gen.py',
        '--registry', '/workspace/Data/Schemas/core-table-registry-v1.json',
        '--audit', '/workspace/Data/Inventory/p2-11-id-limit-audit.json',
        '--policy', '/workspace/Contracts/data-schema/protocol-codegen-policy-v1.json',
        '--schema-output', "/output/$schemaName",
        '--backend-output', "/output/$backendName",
        '--ue-output', "/output/$ueName"
    )
    $summaryText = & $docker @arguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-17 isolated generator failed.' }
    $summary = $summaryText | ConvertFrom-Json
    $selfText = & $docker run --rm --network none --read-only --cap-drop ALL `
        --security-opt no-new-privileges `
        --mount "type=bind,src=$root,dst=/workspace,readonly" `
        $BuilderImage python3 /workspace/Tools/TMXY.ProtocolGen/protocol_gen.py --self-test
    if ($LASTEXITCODE -ne 0) { throw 'P2-17 generator self-test failed.' }
    $self = $selfText | ConvertFrom-Json

    $targets = [ordered]@{
        schema = Join-Path $root "Contracts\data-schema\$schemaName"
        backend = Join-Path $root "Contracts\generated\cpp\tmxy\contracts\data\$backendName"
        ue = Join-Path $root "Contracts\generated\ue\$ueName"
    }
    $generated = [ordered]@{
        schema = Join-Path $runRoot $schemaName
        backend = Join-Path $runRoot $backendName
        ue = Join-Path $runRoot $ueName
    }
    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf)) {
                throw "Tracked P2-17 output is missing: $($targets[$name])"
            }
            if ((Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked P2-17 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Generated $generated[$name] $targets[$name] }
    }

    $evidencePath = Join-Path $root 'Data\Inventory\p2-17-protocol-codegen.json'
    $outputRecords = [ordered]@{}
    foreach ($name in $targets.Keys) {
        $item = Get-Item -LiteralPath $targets[$name]
        $outputRecords[$name] = [pscustomobject][ordered]@{
            path = Get-Relative $targets[$name]
            bytes = [int64]$item.Length
            lines = @(Get-Content -LiteralPath $targets[$name]).Count
            sha256 = Get-Sha256 $targets[$name]
        }
    }
    $report = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
        task_id = 'P2-17'
        result = 'PASS'
        task_status = 'COMPLETE'
        completion_criteria_satisfied = $true
        inputs = [pscustomobject][ordered]@{
            core_table_registry_path = Get-Relative $registryPath
            core_table_registry_sha256 = Get-Sha256 $registryPath
            id_limit_audit_path = Get-Relative $auditPath
            id_limit_audit_sha256 = Get-Sha256 $auditPath
            policy_sha256 = Get-Sha256 $policyPath
            contract_sha256 = Get-Sha256 $contractPath
        }
        summary = [pscustomobject][ordered]@{
            models = [int]$summary.models
            source_fields = [int]$summary.source_fields
            identity_components = [int]$summary.identity_components
            nullable_fields = [int]$summary.nullable_fields
            targets = [int]$summary.targets
            numeric_identity_storage = 'uint64'
            narrowing = 'forbidden'
        }
        outputs = $outputRecords
        target_contracts = [pscustomobject][ordered]@{
            backend = 'portable-cpp20-compiled-by-backend-cmake'
            ue = 'unreal-engine-5.8-cpp20-compiled-by-tmxy-core'
            same_schema_sha256 = $outputRecords.schema.sha256
        }
        implementation = [pscustomobject][ordered]@{
            generator = Get-Relative $pythonPath
            generator_sha256 = Get-Sha256 $pythonPath
            wrapper = 'Tools/TMXY.ProtocolGen/New-ProtocolTypes.ps1'
            wrapper_sha256 = Get-Sha256 $MyInvocation.MyCommand.Path
            self_test_assertions = [int]$self.assertions
        }
        reproduction = [pscustomobject][ordered]@{
            builder_image = $BuilderImage
            builder_user = 'tmxy'
            repository_mount = 'read-only'
            network = 'none'
            check_mode = [bool]$Check
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-18')
            detail = 'Aggregate parse, integrity, reference, conversion, and capacity evidence into the content health report.'
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-17 evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        if ($frozen.result -ne 'PASS' -or -not $frozen.completion_criteria_satisfied -or
            $frozen.outputs.schema.sha256 -ne $report.outputs.schema.sha256 -or
            $frozen.outputs.backend.sha256 -ne $report.outputs.backend.sha256 -or
            $frozen.outputs.ue.sha256 -ne $report.outputs.ue.sha256) {
            throw 'Tracked P2-17 evidence differs from deterministic regeneration.'
        }
    }
    else {
        $json = ($report | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n")
        [IO.File]::WriteAllText($evidencePath, $json + "`n", [Text.UTF8Encoding]::new($false))
    }
    $report | ConvertTo-Json -Depth 20
}
finally {
    $resolvedRun = [IO.Path]::GetFullPath($runRoot)
    if ($resolvedRun.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedRun -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRun -Recurse -Force
    }
}
