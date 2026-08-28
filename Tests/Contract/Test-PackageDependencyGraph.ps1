[CmdletBinding()]
param([string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$reportPath = Join-Path $root 'Data\Inventory\p2-03-package-dependency-graph.json'
$generatorPath = Join-Path $root 'Tools\TMXY.DependencyGraph\New-FullPackageDependencyGraph.ps1'
$pythonPath = Join-Path $root 'Tools\TMXY.DependencyGraph\package_dependency_graph.py'
$queryPath = Join-Path $root 'Tools\TMXY.DependencyGraph\Find-PackageDependency.ps1'
$fixturePath = Join-Path $root 'Tests\Fixtures\DependencyGraph\query-graph.jsonl'
$p202Path = Join-Path $root 'Data\Inventory\p2-02-package-boundary-completeness.json'
foreach ($path in @($reportPath, $generatorPath, $pythonPath, $queryPath, $fixturePath, $p202Path)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P2-03 contract input is missing: $path"
    }
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [System.Array]::Clear($bytes, 0, $bytes.Length) }
}

$generatorText = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
foreach ($fragment in @(
        "'--network', 'none'", "'--read-only'", "'--cap-drop', 'ALL'",
        "'no-new-privileges:true'", 'client_mount = ''read-only''',
        "full_graph_committed_to_git = `$false", "heuristic_string_edges = 0")) {
    if (-not $generatorText.Contains($fragment, [System.StringComparison]::Ordinal)) {
        throw "P2-03 generator contract is missing: $fragment"
    }
}
$pythonText = Get-Content -LiteralPath $pythonPath -Raw -Encoding UTF8
foreach ($fragment in @(
        'EXACT_OBJECT_REFERENCES', 'ARRAY_OBJECT_REFERENCES',
        'SUFFIX_OBJECT_REFERENCES', 'LOGICAL_REFERENCES',
        'object_names_emitted', 'hashlib.sha256', 'parse_envelope')) {
    if (-not $pythonText.Contains($fragment, [System.StringComparison]::Ordinal)) {
        throw "P2-03 graph implementation contract is missing: $fragment"
    }
}

$materialQuery = (& $queryPath -GraphPath $fixturePath -LogicalName 'sample.material' `
        -MaximumExamples 2) | ConvertFrom-Json
$textureQuery = (& $queryPath -GraphPath $fixturePath -NameHex `
        '73616d706c652e74657874757265' -MaximumExamples 2) | ConvertFrom-Json
$meshQuery = (& $queryPath -GraphPath $fixturePath -NodeId `
        'e1e5cdbf9ca7c6a066ea23951a7322fdd71cb8add4ea0990092189bce4b528fa' `
        -MaximumExamples 2) | ConvertFrom-Json

$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'Tools\TMXY.DependencyGraph') `
        -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.py') } |
        Sort-Object FullName)
$sourceLines = foreach ($file in $sourceFiles) {
    $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    "$relative|$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($sourceLines -join "`n") + "`n")
$p202Sha = (Get-FileHash -LiteralPath $p202Path -Algorithm SHA256).Hash.ToLowerInvariant()
$legacyHashes = @($report.legacy_registration_evidence_sha256.psobject.Properties |
    ForEach-Object { [string]$_.Value })
$classProperties = @($report.graph.classes.psobject.Properties)
$categoryProperties = @($report.graph.categories.psobject.Properties)
$kindProperties = @($report.graph.edge_kinds.psobject.Properties)
$expectedKindCounts = @{
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
$kindMatch = $kindProperties.Count -eq $expectedKindCounts.Count
foreach ($entry in $expectedKindCounts.GetEnumerator()) {
    if ([int]$report.graph.edge_kinds.($entry.Key) -ne $entry.Value) { $kindMatch = $false }
}
$classTotal = [int](($classProperties.Value | Measure-Object -Sum).Sum)
$categoryTotal = [int](($categoryProperties.Value | Measure-Object -Sum).Sum)

$passed = [string]$report.result -eq 'PASS' -and [string]$report.task -eq 'P2-03' -and
    [string]$report.task_status -eq 'COMPLETE' -and
    [bool]$report.completion_criteria_satisfied -and
    [string]$report.input.p2_02_evidence_sha256 -eq $p202Sha -and
    [int]$report.input.package_files -eq 167 -and [int]$report.input.integrity_failures -eq 0 -and
    [int]$report.graph.nodes -eq 121715 -and [int]$report.graph.edges -eq 147349 -and
    [int64]$report.graph.properties -eq 1639860 -and
    [int64]$report.graph.bytes -eq 106382503 -and [int]$report.graph.lines -eq 269064 -and
    [string]$report.graph.sha256 -eq '7a2fc8751bda61306c7abb6a4796ddc7eb90e921aaf758e68c22a68e8e466c57' -and
    [int]$report.graph.unique_logical_names -eq 92641 -and
    [int]$report.graph.duplicate_logical_names -eq 13177 -and
    [int]$report.graph.maximum_logical_name_multiplicity -eq 6 -and
    [int]$report.graph.unique_ascii_lower_logical_names -eq 92485 -and
    [int]$report.graph.duplicate_ascii_lower_logical_names -eq 13258 -and
    [int]$report.graph.maximum_ascii_lower_logical_name_multiplicity -eq 12 -and
    $classProperties.Count -eq 19 -and $classTotal -eq 121715 -and
    $categoryProperties.Count -eq 8 -and $categoryTotal -eq 121715 -and
    $kindMatch -and
    [int]$report.graph.resolution.unique -eq 94882 -and
    [int]$report.graph.resolution.ambiguous -eq 21146 -and
    [int]$report.graph.resolution.unresolved -eq 1076 -and
    [int]$report.graph.resolution.logical -eq 30245 -and
    [int]$report.coverage.object_envelopes -eq 121715 -and
    [int]$report.coverage.envelope_failures -eq 0 -and
    [int]$report.coverage.reference_values -eq 147349 -and
    [int]$report.coverage.reference_value_failures -eq 0 -and
    [int]$report.coverage.heuristic_string_edges -eq 0 -and
    [int]$report.query_contract.probe_matched_nodes -eq 1 -and
    [int]$report.query_contract.probe_outgoing -gt 0 -and
    [int]$report.implementation.source_file_count -eq $sourceFiles.Count -and
    [string]$report.implementation.source_sha256 -eq $sourceSha -and
    [int]$report.implementation.self_test_assertions -eq 9 -and
    @($report.implementation.name_hash_modes).Count -eq 2 -and
    [int]$report.implementation.ctest_count -eq 7 -and
    $legacyHashes.Count -eq 7 -and
    @($legacyHashes | Where-Object { $_ -notmatch '^[a-f0-9]{64}$' }).Count -eq 0 -and
    -not [bool]$report.disclosure.object_names_emitted -and
    [string]$report.disclosure.logical_names_stored_as -eq 'sha256' -and
    [bool]$report.disclosure.ascii_case_insensitive_lookup_preserved -and
    -not [bool]$report.disclosure.object_bodies_copied -and
    -not [bool]$report.disclosure.full_graph_committed_to_git -and
    -not [bool]$report.graph.git_tracked -and
    [int]$materialQuery.matched_nodes -eq 1 -and
    [int]$materialQuery.incoming.count -eq 1 -and
    [int]$materialQuery.outgoing.count -eq 1 -and
    [int]$textureQuery.matched_nodes -eq 1 -and
    [int]$textureQuery.incoming.count -eq 1 -and
    [int]$textureQuery.outgoing.count -eq 0 -and
    [int]$meshQuery.matched_nodes -eq 1 -and
    [int]$meshQuery.outgoing.count -eq 1 -and
    -not [bool]$materialQuery.query.raw_name_emitted -and
    -not [bool]$textureQuery.query.raw_name_emitted -and
    -not [bool]$meshQuery.query.raw_name_emitted

$reportSha = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash.ToLowerInvariant()
$result = [pscustomobject][ordered]@{
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P2-03'
    completion_criteria_satisfied = $passed
    assertions = 60
    nodes = [int]$report.graph.nodes
    edges = [int]$report.graph.edges
    unique_resolved_edges = [int]$report.graph.resolution.unique
    explicit_ambiguous_edges = [int]$report.graph.resolution.ambiguous
    explicit_unresolved_edges = [int]$report.graph.resolution.unresolved
    query_modes_verified = 3
    report_sha256 = $reportSha
    raw_names_committed = $false
    legacy_payloads_copied = $false
}
$result | ConvertTo-Json -Depth 4
if (-not $passed) { throw 'P2-03 Package dependency graph contract failed.' }
