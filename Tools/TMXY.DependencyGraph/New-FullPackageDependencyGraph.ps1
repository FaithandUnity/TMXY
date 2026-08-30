[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$GraphPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-03\p2-03-package-dependency-graph.jsonl',
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-03-package-dependency-graph.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$graph = [System.IO.Path]::GetFullPath($GraphPath)
$report = [System.IO.Path]::GetFullPath($ReportPath)
$exportRoot = [System.IO.Path]::GetFullPath((Join-Path $root 'Data\Exports\P2-03')).TrimEnd([char[]]'\/')
$inventoryRoot = [System.IO.Path]::GetFullPath((Join-Path $root 'Data\Inventory')).TrimEnd([char[]]'\/')
if (-not $graph.StartsWith(
        $exportRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase) -or
    -not $report.StartsWith(
        $inventoryRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-03 outputs escaped their scoped Rebuild directories.'
}

$packagesRoot = Join-Path $client 'Packages'
$manifestPath = Join-Path $root 'Data\RawManifests\client-3.0.0.413.files.jsonl'
$p202Path = Join-Path $root 'Data\Inventory\p2-02-package-boundary-completeness.json'
$pythonPath = Join-Path $root 'Tools\TMXY.DependencyGraph\package_dependency_graph.py'
$queryPath = Join-Path $root 'Tools\TMXY.DependencyGraph\Find-PackageDependency.ps1'
$moduleRoot = Join-Path $root 'Tools\TMXY.DependencyGraph'
foreach ($path in @($packagesRoot, $manifestPath, $p202Path, $pythonPath, $queryPath, $moduleRoot)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-03 input is missing: $path" }
}
[System.IO.Directory]::CreateDirectory($exportRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($inventoryRoot) | Out-Null

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [System.Array]::Clear($bytes, 0, $bytes.Length) }
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdoutTask.GetAwaiter().GetResult()
        stderr = $stderrTask.GetAwaiter().GetResult()
    }
}

$manifestEntries = [System.Collections.Generic.List[object]]::new()
foreach ($line in [System.IO.File]::ReadLines($manifestPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $entry = $line | ConvertFrom-Json
    $relative = [string]$entry.path
    if ($relative.StartsWith('Packages/', [System.StringComparison]::Ordinal)) {
        if ($relative.Contains("`t") -or $relative.Contains("`r") -or $relative.Contains("`n")) {
            throw 'P2-03 refuses Package paths containing control separators.'
        }
        $manifestEntries.Add([pscustomobject][ordered]@{
            path = $relative
            size = [int64]$entry.size
            sha256 = [string]$entry.sha256
        })
    }
}
$manifestEntries = @($manifestEntries | Sort-Object path)
if ($manifestEntries.Count -ne 167 -or
    @($manifestEntries.path | Sort-Object -Unique).Count -ne 167) {
    throw 'P2-03 requires the frozen set of 167 unique Package files.'
}

$integrityFailures = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $manifestEntries) {
    $path = Join-Path $client $entry.path.Replace(
        '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $integrityFailures.Add("missing:$($entry.path)")
        continue
    }
    $item = Get-Item -LiteralPath $path
    $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne $entry.size -or $sha -ne $entry.sha256) {
        $integrityFailures.Add("integrity:$($entry.path)")
    }
}
if ($integrityFailures.Count -gt 0) {
    throw "P2-03 frozen Package inputs changed: $($integrityFailures -join ', ')"
}

$p202 = Get-Content -LiteralPath $p202Path -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$p202.result -ne 'PASS' -or [string]$p202.task -ne 'P2-02' -or
    -not [bool]$p202.completion_criteria_satisfied -or
    [int]$p202.summary.complete_packages -ne 163) {
    throw 'P2-03 requires completed P2-02 boundary evidence.'
}

$legacyEvidence = @(
    'ClientCode/QRender/Src/QRenderTypes.cpp',
    'ClientCode/QRender/Src/QSkelMesh.cpp',
    'ClientCode/QRender/Src/QEmitter.cpp',
    'ClientCode/QRender/Src/QParticle.cpp',
    'ClientCode/QRender/Src/QAnimNotify.cpp',
    'ClientCode/QRender/Src/QProjector.cpp',
    'ClientCode/Game/Src/QUnitAction.cpp'
)
$legacyHashes = [ordered]@{}
foreach ($relative in $legacyEvidence) {
    $path = Join-Path (Split-Path -Parent $root) $relative.Replace(
        '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P2-03 legacy registration evidence is missing: $relative"
    }
    $legacyHashes[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
$sourceLines = foreach ($file in $sourceFiles) {
    $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$relative|$sha"
}
$sourceSha = Get-TextSha256 -Value (($sourceLines -join "`n") + "`n")

$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$imageRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$imagePresent = $LASTEXITCODE -eq 0 -and $imageRecords.Count -gt 0
$actualBuilderId = if ($imagePresent) { [string]$imageRecords[0].Id } else { '' }
$builderUser = if ($imagePresent) { [string]$imageRecords[0].Config.User } else { '' }
if (-not $imagePresent -or $actualBuilderId -ne $expectedBuilderId -or
    $builderUser -ne 'tmxy') {
    throw 'P2-03 requires the qualified non-root Clang 21 builder image.'
}

$temporaryName = '.p2-03-' + [Guid]::NewGuid().ToString('N') + '.jsonl'
$temporaryGraph = Join-Path $exportRoot $temporaryName
$containerGraph = "/output/$temporaryName"
$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools
cp /workspace/.clang-format /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /workspace/Tools/TMXY.FormatCore /workspace/Tools/TMXY.Package /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
find TMXY.FormatCore TMXY.Package -type f \( -name '*.cpp' -o -name '*.hpp' \) -print0 | xargs -0 clang-format-21 --dry-run --Werror --style=file
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TRANSFORM=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang
find TMXY.FormatCore TMXY.Package -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --preset ci-linux-clang
self_test=$(python3 /workspace/Tools/TMXY.DependencyGraph/package_dependency_graph.py --self-test)
printf 'SELFTEST\t%s\n' "$self_test"
exporter=./out/build/ci-linux-clang/TMXY.Package/tmxy_package_tree_export
summary=$(
  while IFS= read -r -d '' file; do
    "$exporter" "$file" "${file#/legacy/}" 2>/dev/null || true
  done < <(find /legacy/Packages -type f -print0 | sort -z) |
    python3 /workspace/Tools/TMXY.DependencyGraph/package_dependency_graph.py \
      --legacy-root /legacy --output "$TMXY_GRAPH_OUTPUT"
)
printf 'GRAPH\t%s\n' "$summary"
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--env', "TMXY_GRAPH_OUTPUT=$containerGraph",
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$client,target=/legacy,readonly",
    '--mount', "type=bind,source=$exportRoot,target=/output",
    $builderReference, 'bash', '-c', $containerScript
)
try {
    $execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments `
        -WorkingDirectory $root
    if ($execution.exit_code -ne 0) {
        throw "P2-03 locked graph generation failed: $($execution.stderr.Trim())"
    }
    $selfTestLine = @($execution.stdout -split "`n" |
        Where-Object { $_.StartsWith("SELFTEST`t", [System.StringComparison]::Ordinal) })
    $graphLine = @($execution.stdout -split "`n" |
        Where-Object { $_.StartsWith("GRAPH`t", [System.StringComparison]::Ordinal) })
    if ($selfTestLine.Count -ne 1 -or $graphLine.Count -ne 1) {
        throw 'P2-03 did not emit one self-test and one graph summary.'
    }
    $selfTest = $selfTestLine[0].Substring(9) | ConvertFrom-Json
    $summary = $graphLine[0].Substring(6) | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $temporaryGraph -PathType Leaf)) {
        throw 'P2-03 graph output was not created.'
    }
    $actualGraphSha = (Get-FileHash -LiteralPath $temporaryGraph -Algorithm SHA256).Hash.ToLowerInvariant()
    $actualGraphBytes = (Get-Item -LiteralPath $temporaryGraph).Length
    if ($actualGraphSha -ne [string]$summary.sha256 -or
        $actualGraphBytes -ne [int64]$summary.bytes) {
        throw 'P2-03 graph file does not match its in-container digest.'
    }
    Move-Item -LiteralPath $temporaryGraph -Destination $graph -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryGraph -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryGraph -Force
    }
}

$probe = (& $queryPath -GraphPath $graph -NodeId ([string]$summary.query_probe_node_id) `
        -MaximumExamples 2) | ConvertFrom-Json
$expectedKinds = [ordered]@{
    animation = 9944
    'animation-name' = 1619
    'bone-name' = 476
    'logical-name' = 28150
    material = 20905
    mesh = 17419
    notify = 894
    particle = 7155
    scene = 82
    sound = 893
    texture = 59812
}
$kindMatch = $true
foreach ($entry in $expectedKinds.GetEnumerator()) {
    if ([int]$summary.edge_kinds.($entry.Key) -ne $entry.Value) { $kindMatch = $false }
}
$completed = [string]$selfTest.result -eq 'PASS' -and [int]$selfTest.assertions -eq 9 -and
    [int]$summary.nodes -eq 121715 -and [int]$summary.edges -eq 147349 -and
    [int]$summary.envelope_failures -eq 0 -and
    [int]$summary.reference_value_failures -eq 0 -and
    [int]$summary.unique_logical_names -eq 92641 -and
    [int]$summary.duplicate_logical_names -eq 13177 -and
    [int]$summary.maximum_logical_name_multiplicity -eq 6 -and
    [int]$summary.unique_ascii_lower_logical_names -eq 92485 -and
    [int]$summary.duplicate_ascii_lower_logical_names -eq 13258 -and
    [int]$summary.maximum_ascii_lower_logical_name_multiplicity -eq 12 -and
    [int]$summary.edge_resolution.unique -eq 94882 -and
    [int]$summary.edge_resolution.ambiguous -eq 21146 -and
    [int]$summary.edge_resolution.unresolved -eq 1076 -and
    [int]$summary.edge_resolution.logical -eq 30245 -and $kindMatch -and
    [int]$probe.matched_nodes -eq 1 -and [int]$probe.outgoing.count -gt 0 -and
    -not [bool]$summary.object_names_emitted -and
    [bool]$summary.class_names_emitted -and
    -not [bool]$summary.object_bodies_copied -and $integrityFailures.Count -eq 0

$result = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($completed) { 'PASS' } else { 'FAIL' }
    task = 'P2-03'
    task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
    completion_criteria_satisfied = $completed
    input = [pscustomobject][ordered]@{
        client_version = '3.0.0.413'
        manifest = 'Data/RawManifests/client-3.0.0.413.files.jsonl'
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        p2_02_evidence = 'Data/Inventory/p2-02-package-boundary-completeness.json'
        p2_02_evidence_sha256 = (Get-FileHash -LiteralPath $p202Path -Algorithm SHA256).Hash.ToLowerInvariant()
        package_files = $manifestEntries.Count
        integrity_failures = $integrityFailures.Count
        copy_policy = 'reference_only'
    }
    graph = [pscustomobject][ordered]@{
        local_path = 'Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl'
        git_tracked = $false
        regeneration_required_for_query = $true
        bytes = [int64]$summary.bytes
        lines = [int]$summary.lines
        sha256 = [string]$summary.sha256
        nodes = [int]$summary.nodes
        edges = [int]$summary.edges
        properties = [int64]$summary.properties
        unique_logical_names = [int]$summary.unique_logical_names
        duplicate_logical_names = [int]$summary.duplicate_logical_names
        maximum_logical_name_multiplicity = [int]$summary.maximum_logical_name_multiplicity
        unique_ascii_lower_logical_names = [int]$summary.unique_ascii_lower_logical_names
        duplicate_ascii_lower_logical_names = [int]$summary.duplicate_ascii_lower_logical_names
        maximum_ascii_lower_logical_name_multiplicity = [int]$summary.maximum_ascii_lower_logical_name_multiplicity
        classes = $summary.classes
        categories = $summary.categories
        edge_kinds = $summary.edge_kinds
        resolution = $summary.edge_resolution
    }
    coverage = [pscustomobject][ordered]@{
        object_envelopes = [int]$summary.nodes
        envelope_failures = [int]$summary.envelope_failures
        reference_values = [int]$summary.edges
        reference_value_failures = [int]$summary.reference_value_failures
        evidence_backed_rule_families = 11
        heuristic_string_edges = 0
    }
    query_contract = [pscustomobject][ordered]@{
        tool = 'Tools/TMXY.DependencyGraph/Find-PackageDependency.ps1'
        accepts = @('UTF-8 logical name', 'opaque name hex', 'node SHA-256 ID')
        probe_node_id = [string]$summary.query_probe_node_id
        probe_matched_nodes = [int]$probe.matched_nodes
        probe_incoming = [int]$probe.incoming.count
        probe_outgoing = [int]$probe.outgoing.count
        raw_name_emitted = $false
    }
    implementation = [pscustomobject][ordered]@{
        source_file_count = $sourceFiles.Count
        source_sha256 = $sourceSha
        self_test_assertions = [int]$selfTest.assertions
        name_hash_modes = @('exact-bytes-sha256', 'ascii-lower-bytes-sha256')
        ctest_count = 7
    }
    legacy_registration_evidence_sha256 = $legacyHashes
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        client_mount = 'read-only'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_storage = 'ephemeral_tmpfs'
        output_mount = 'scoped Data/Exports/P2-03 only'
    }
    disclosure = [pscustomobject][ordered]@{
        object_names_emitted = $false
        logical_names_stored_as = 'sha256'
        ascii_case_insensitive_lookup_preserved = $true
        class_names_emitted = $true
        object_bodies_copied = $false
        full_graph_committed_to_git = $false
    }
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        stdout_sha256 = Get-TextSha256 -Value $execution.stdout
        stderr_sha256 = Get-TextSha256 -Value $execution.stderr
    }
    next_scope = [pscustomobject][ordered]@{
        tasks = @('P2-04', 'P2-11', 'P2-18')
        detail = 'Use explicit unresolved and ambiguous edges as owned work queues; never select a target silently.'
    }
}
$json = ($result | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($report, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json
if (-not $completed) { throw 'P2-03 Package dependency graph did not meet completion criteria.' }
