[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$GraphPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-13\p2-13-reference-closure.jsonl',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-13-reference-closure.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$graph = [IO.Path]::GetFullPath($GraphPath)
$output = [IO.Path]::GetFullPath($OutputPath)
$exportRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Exports\P2-13')).TrimEnd([char[]]'\/')
$inventoryRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Inventory')).TrimEnd([char[]]'\/')
if (-not $graph.StartsWith($exportRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not $output.StartsWith($inventoryRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-13 outputs escaped their scoped Rebuild directories.'
}

$moduleRoot = Join-Path $root 'Tools\TMXY.ReferenceClosure'
$pythonPath = Join-Path $moduleRoot 'reference_closure.py'
$queryPath = Join-Path $moduleRoot 'Find-ReferenceClosure.ps1'
$policyPath = Join-Path $root 'Contracts\data-schema\reference-closure-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\reference-closure-v1.schema.json'
$packageGraphPath = Join-Path $root 'Data\Exports\P2-03\p2-03-package-dependency-graph.jsonl'
$packageEvidencePath = Join-Path $root 'Data\Inventory\p2-03-package-dependency-graph.json'
$assetCatalogPath = Join-Path $root 'Data\Exports\P2-12\p2-12-full-asset-inventory.jsonl'
$assetEvidencePath = Join-Path $root 'Data\Inventory\p2-12-full-asset-inventory.json'
$tableRoot = Join-Path $root 'Data\Exports\P2-06\tables'
$coreRegistryPath = Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
$coreEvidencePath = Join-Path $root 'Data\Inventory\p2-07-core-table-schema.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
foreach ($path in @($moduleRoot, $pythonPath, $queryPath, $policyPath, $schemaPath,
        $packageGraphPath, $packageEvidencePath, $assetCatalogPath, $assetEvidencePath,
        $tableRoot, $coreRegistryPath, $coreEvidencePath, $lockPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-13 input is missing: $path" }
}
[IO.Directory]::CreateDirectory($exportRoot) | Out-Null

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdout.GetAwaiter().GetResult()
        stderr = $stderr.GetAwaiter().GetResult()
    }
}

$packageEvidence = Get-Content -LiteralPath $packageEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$assetEvidence = Get-Content -LiteralPath $assetEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$coreEvidence = Get-Content -LiteralPath $coreEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($packageEvidence.result -ne 'PASS' -or -not $packageEvidence.completion_criteria_satisfied -or
    $assetEvidence.result -ne 'PASS' -or -not $assetEvidence.completion_criteria_satisfied -or
    $coreEvidence.result -ne 'PASS' -or -not $coreEvidence.completion_criteria_satisfied) {
    throw 'P2-13 requires completed P2-03, P2-07, and P2-12 evidence.'
}
if ((Get-FileSha256 $packageGraphPath) -ne [string]$packageEvidence.graph.sha256 -or
    (Get-FileSha256 $assetCatalogPath) -ne [string]$assetEvidence.catalog.sha256 -or
    (Get-FileSha256 $coreRegistryPath) -ne [string]$coreEvidence.output.registry_sha256) {
    throw 'P2-13 derived input hash binding failed.'
}

$legacyFiles = @(
    'ClientCode/Base/Src/QDataTable.cpp',
    'ClientCode/Game/Src/QCLItem.cpp',
    'ClientCode/Game/Src/QCLSkill.cpp',
    'ClientCode/Game/Src/QCLState.cpp',
    'ClientCode/Game/Src/QNetUnit.cpp',
    'ClientCode/Game/Src/QUnit.cpp'
)
$workspace = Split-Path -Parent $root
$legacyHashes = [ordered]@{}
foreach ($relative in $legacyFiles) {
    $path = Join-Path $workspace $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P2-13 legacy consumer evidence is missing: $relative"
    }
    $legacyHashes[$relative] = Get-FileSha256 $path
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
$sourceLines = @($sourceFiles | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
        "$relative|$(Get-FileSha256 $_.FullName)"
    })
$sourceHash = Get-TextSha256 -Value (($sourceLines -join "`n") + "`n")

$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
    [string]$image[0].Id -ne $expectedBuilderId -or [string]$image[0].Config.User -ne 'tmxy') {
    throw 'P2-13 requires the qualified non-root Clang 21 builder image.'
}

$temporaryName = '.p2-13-' + [Guid]::NewGuid().ToString('N') + '.jsonl'
$temporaryGraph = Join-Path $exportRoot $temporaryName
$containerOutput = "/output/$temporaryName"
$containerScript = @'
set -euo pipefail
self_test=$(python3 /workspace/Tools/TMXY.ReferenceClosure/reference_closure.py --self-test)
printf 'SELFTEST\t%s\n' "$self_test"
summary=$(python3 /workspace/Tools/TMXY.ReferenceClosure/reference_closure.py \
  --package-graph /workspace/Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl \
  --asset-catalog /workspace/Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl \
  --table-root /workspace/Data/Exports/P2-06/tables \
  --registry /workspace/Data/Schemas/core-table-registry-v1.json \
  --policy /workspace/Contracts/data-schema/reference-closure-policy-v1.json \
  --output "$TMXY_CLOSURE_OUTPUT")
printf 'SUMMARY\t%s\n' "$summary"
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--env', "TMXY_CLOSURE_OUTPUT=$containerOutput",
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$exportRoot,target=/output",
    $builderReference, 'bash', '-c', $containerScript
)
try {
    $execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
    if ($execution.exit_code -ne 0) {
        throw "P2-13 closure generation failed: $($execution.stderr.Trim())"
    }
    $selfTestLines = @($execution.stdout -split "`n" |
        Where-Object { $_.StartsWith("SELFTEST`t", [StringComparison]::Ordinal) })
    $summaryLines = @($execution.stdout -split "`n" |
        Where-Object { $_.StartsWith("SUMMARY`t", [StringComparison]::Ordinal) })
    if ($selfTestLines.Count -ne 1 -or $summaryLines.Count -ne 1) {
        throw 'P2-13 generator did not emit one self-test and one summary.'
    }
    $selfTest = $selfTestLines[0].Substring(9) | ConvertFrom-Json
    $summary = $summaryLines[0].Substring(8) | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $temporaryGraph -PathType Leaf) -or
        (Get-FileSha256 $temporaryGraph) -ne [string]$summary.graph.sha256 -or
        (Get-Item -LiteralPath $temporaryGraph).Length -ne [int64]$summary.graph.bytes) {
        throw 'P2-13 graph does not match the isolated generator summary.'
    }

    $completed = $selfTest.result -eq 'PASS' -and [int]$selfTest.assertions -eq 9 -and
        $summary.result -eq 'PASS' -and
        [int]$summary.packages.nodes -eq [int]$packageEvidence.graph.nodes -and
        [int]$summary.packages.edges -eq [int]$packageEvidence.graph.edges -and
        [int]$summary.packages.recorded_resolution_mismatches -eq 0 -and
        [int]$summary.tables.table_count -eq [int]$coreEvidence.summary.tables -and
        [int]$summary.tables.physical_rows -eq [int]$coreEvidence.summary.physical_rows -and
        [int]$summary.tables.canonical_rows -eq [int]$coreEvidence.summary.canonical_rows -and
        [int]$summary.tables.foreign_keys.rules -eq [int]$coreEvidence.summary.foreign_keys -and
        [int]$summary.tables.foreign_keys.physical_active_references -eq
            [int]$coreEvidence.summary.active_reference_rows -and
        [int]$summary.tables.foreign_keys.physical_inactive_references -eq
            [int]$coreEvidence.summary.inactive_reference_rows -and
        [int]$summary.tables.foreign_keys.dangling -eq 0 -and
        [int]$summary.assets.files -eq [int]$assetEvidence.summary.files -and
        [int]$summary.assets.catalog_candidate_mismatches -eq 0 -and
        [int]$summary.roots.character -gt 0 -and [int]$summary.roots.scene -gt 0 -and
        [int]$summary.roots.skill -gt 0 -and
        -not [bool]$summary.raw_table_values_emitted -and
        -not [bool]$summary.raw_primary_keys_emitted -and
        -not [bool]$summary.raw_package_object_names_emitted -and
        [int]$summary.heuristic_target_selections -eq 0

    if ($Check) {
        if (-not (Test-Path -LiteralPath $graph -PathType Leaf) -or
            (Get-FileSha256 $graph) -ne [string]$summary.graph.sha256) {
            throw 'P2-13 closure graph differs from the frozen generated graph.'
        }
    }
    else { Move-Item -LiteralPath $temporaryGraph -Destination $graph -Force }

    $captured = [DateTimeOffset]::UtcNow.ToString('o')
    if ($Check -and (Test-Path -LiteralPath $output -PathType Leaf)) {
        $captured = [string](Get-Content -LiteralPath $output -Raw -Encoding UTF8 |
            ConvertFrom-Json -DateKind String).captured_utc
    }
    $report = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = $captured
        task_id = 'P2-13'
        result = if ($completed) { 'PASS' } else { 'FAIL' }
        task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
        completion_criteria_satisfied = $completed
        input = [pscustomobject][ordered]@{
            source_build = 'qy-3.0.0.413'
            package_graph_sha256 = [string]$packageEvidence.graph.sha256
            core_registry_sha256 = [string]$coreEvidence.output.registry_sha256
            asset_catalog_sha256 = [string]$assetEvidence.catalog.sha256
            copy_policy = 'reference_only'
        }
        graph = [pscustomobject][ordered]@{
            path = 'Data/Exports/P2-13/p2-13-reference-closure.jsonl'
            tracked = $false
            lines = [int]$summary.graph.lines
            bytes = [int64]$summary.graph.bytes
            sha256 = [string]$summary.graph.sha256
            records = $summary.graph.records
        }
        roots = $summary.roots
        table_closure = $summary.tables
        package_closure = $summary.packages
        asset_closure = $summary.assets
        health = [pscustomobject][ordered]@{
            core_dangling_references = [int]$summary.tables.foreign_keys.dangling
            nullable_object_unresolved = [int]$summary.tables.object_references.resolution.unresolved
            nullable_object_ambiguous = [int]$summary.tables.object_references.resolution.ambiguous
            legacy_runtime_assert_rows = [int]$summary.tables.object_references.runtime_assert_rows
            legacy_runtime_assert_missing_values = [int]$summary.tables.object_references.runtime_assert_missing_values
            legacy_runtime_assert_unresolved_values = [int]$summary.tables.object_references.runtime_assert_unresolved_values
            package_unresolved_edges = [int]$summary.packages.resolution.unresolved
            package_ambiguous_edges = [int]$summary.packages.resolution.ambiguous
            heuristic_target_selections = 0
        }
        contracts = [pscustomobject][ordered]@{
            policy = 'Contracts/data-schema/reference-closure-policy-v1.json'
            policy_sha256 = Get-FileSha256 $policyPath
            schema = 'Contracts/data-schema/reference-closure-v1.schema.json'
            schema_sha256 = Get-FileSha256 $schemaPath
            core_dangling_definition = 'declared authoritative P2-07 foreign-key rows only'
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceHash
            self_test_assertions = [int]$selfTest.assertions
            legacy_consumer_evidence_sha256 = $legacyHashes
            package_name_lookup = 'ascii-case-insensitive-hash'
        }
        disclosure = [pscustomobject][ordered]@{
            raw_table_values_emitted = $false
            raw_primary_keys_emitted = $false
            raw_package_object_names_emitted = $false
            asset_paths_only_in_ignored_graph = $true
            graph_committed_to_git = $false
            payload_bytes_copied = $false
        }
        reproduction = [pscustomobject][ordered]@{
            generator = 'Tools/TMXY.ReferenceClosure/New-ReferenceClosure.ps1'
            query = 'Tools/TMXY.ReferenceClosure/Find-ReferenceClosure.ps1'
            check_mode = '-Check'
            source_mount = 'read-only'
            network = 'none'
            builder_id = [string]$image[0].Id
            builder_user = [string]$image[0].Config.User
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-14', 'P2-15', 'P2-16', 'P2-18')
            detail = 'Use explicit linked, ambiguous, unresolved, and unlinked sets; do not delete assets during P2-14.'
        }
    }
    $json = ($report | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
    if ($Check) {
        if (-not (Test-Path -LiteralPath $output -PathType Leaf) -or
            [IO.File]::ReadAllText($output, [Text.Encoding]::UTF8) -cne $json) {
            throw 'P2-13 evidence differs from the regenerated report.'
        }
    }
    else {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
        [IO.File]::WriteAllText($output, $json, [Text.UTF8Encoding]::new($false))
    }
    $json
    if (-not $completed) { throw 'P2-13 closure did not meet completion criteria.' }
}
finally {
    if (Test-Path -LiteralPath $temporaryGraph -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryGraph -Force
    }
}
