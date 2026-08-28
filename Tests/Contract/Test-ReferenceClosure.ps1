[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\reference-closure-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\reference-closure-v1.schema.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-13-reference-closure.json'
$graphPath = Join-Path $root 'Data\Exports\P2-13\p2-13-reference-closure.jsonl'
$generatorPath = Join-Path $root 'Tools\TMXY.ReferenceClosure\New-ReferenceClosure.ps1'
$pythonPath = Join-Path $root 'Tools\TMXY.ReferenceClosure\reference_closure.py'
$corePythonPath = Join-Path $root 'Tools\TMXY.ReferenceClosure\reference_closure_core.py'
$queryPath = Join-Path $root 'Tools\TMXY.ReferenceClosure\Find-ReferenceClosure.ps1'
$fixturePath = Join-Path $root 'Tests\Fixtures\ReferenceClosure\smoke-closure.jsonl'
$packageEvidencePath = Join-Path $root 'Data\Inventory\p2-03-package-dependency-graph.json'
$coreEvidencePath = Join-Path $root 'Data\Inventory\p2-07-core-table-schema.json'
$assetEvidencePath = Join-Path $root 'Data\Inventory\p2-12-full-asset-inventory.json'
$assertions = [Collections.Generic.List[object]]::new()

function Add-Assertion([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
            detail = $Detail
        })
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

foreach ($path in @($policyPath, $schemaPath, $evidencePath, $generatorPath, $pythonPath, $corePythonPath,
        $queryPath, $fixturePath, $packageEvidencePath, $coreEvidencePath, $assetEvidencePath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject][ordered]@{
        schema_version = 1; task_id = 'P2-13'; result = 'FAIL'
        completion_criteria_satisfied = $false; assertions = $assertions
    } | ConvertTo-Json -Depth 10
    exit 1
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$packageEvidence = Get-Content -LiteralPath $packageEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$coreEvidence = Get-Content -LiteralPath $coreEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$assetEvidence = Get-Content -LiteralPath $assetEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
$python = Get-Content -LiteralPath $pythonPath -Raw -Encoding UTF8
$corePython = Get-Content -LiteralPath $corePythonPath -Raw -Encoding UTF8

Add-Assertion 'Evidence completes P2-13' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-Assertion 'Schema is closed draft 2020-12 evidence' (
    $schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and
    $schema.properties.task_id.const -eq 'P2-13')
Add-Assertion 'Policy freezes roots references and non-heuristic completion' (
    $policy.source_build -eq 'qy-3.0.0.413' -and
    @($policy.root_sets.PSObject.Properties).Count -eq 3 -and
    @($policy.table_object_references).Count -eq 16 -and
    @($policy.table_scoped_references).Count -eq 3 -and
    @($policy.asset_link_rules).Count -eq 6 -and
    $policy.completion_policy.requires_zero_core_dangling_references -and
    $policy.completion_policy.forbids_heuristic_target_selection)
Add-Assertion 'Evidence binds exact completed upstream artifacts' (
    $evidence.input.package_graph_sha256 -eq $packageEvidence.graph.sha256 -and
    $evidence.input.core_registry_sha256 -eq $coreEvidence.output.registry_sha256 -and
    $evidence.input.asset_catalog_sha256 -eq $assetEvidence.catalog.sha256)
Add-Assertion 'Ignored closure graph is deterministic and complete' (
    $evidence.graph.path -eq 'Data/Exports/P2-13/p2-13-reference-closure.jsonl' -and
    -not $evidence.graph.tracked -and $evidence.graph.lines -eq 683355 -and
    $evidence.graph.bytes -eq 205392166 -and
    $evidence.graph.sha256 -eq '6d895d722d8a547c8c1c560a8c68750ae98b83b458e27836befac18cf496c9ed')
if (Test-Path -LiteralPath $graphPath -PathType Leaf) {
    Add-Assertion 'Local closure graph hash size and line count match evidence' (
        (Get-Sha256 $graphPath) -eq $evidence.graph.sha256 -and
        (Get-Item -LiteralPath $graphPath).Length -eq $evidence.graph.bytes -and
        (Get-LineCount $graphPath) -eq $evidence.graph.lines)
}
Add-Assertion 'Character scene and skill roots are explicit' (
    $evidence.roots.character -eq 1096 -and $evidence.roots.scene -eq 142 -and
    $evidence.roots.skill -eq 23227)
Add-Assertion 'All canonical core table rows are present' (
    $evidence.table_closure.table_count -eq 12 -and
    $evidence.table_closure.physical_rows -eq 87844 -and
    $evidence.table_closure.canonical_rows -eq 87044 -and
    $evidence.table_closure.normalized_hashes_verified -eq 12)
Add-Assertion 'All authoritative foreign keys close with zero dangling rows' (
    $evidence.table_closure.foreign_keys.rules -eq 14 -and
    $evidence.table_closure.foreign_keys.physical_active_references -eq 55361 -and
    $evidence.table_closure.foreign_keys.physical_inactive_references -eq 129154 -and
    $evidence.table_closure.foreign_keys.canonical_edges -eq 54561 -and
    $evidence.table_closure.foreign_keys.dangling -eq 0 -and
    $evidence.health.core_dangling_references -eq 0)
Add-Assertion 'Nullable object references are fully and honestly classified' (
    $evidence.table_closure.object_references.rules -eq 16 -and
    $evidence.table_closure.object_references.physical_nonempty_references -eq 113484 -and
    $evidence.table_closure.object_references.canonical_edges -eq 113484 -and
    $evidence.table_closure.object_references.resolution.unique -eq 101378 -and
    $evidence.table_closure.object_references.resolution.ambiguous -eq 6945 -and
    $evidence.table_closure.object_references.resolution.unresolved -eq 5161)
Add-Assertion 'Legacy runtime assertion risk is retained rather than guessed' (
    $evidence.health.legacy_runtime_assert_rows -eq 5993 -and
    $evidence.health.legacy_runtime_assert_missing_values -eq 29 -and
    $evidence.health.legacy_runtime_assert_unresolved_values -eq 0)
Add-Assertion 'Scoped animation and bone tokens remain scoped terminals' (
    $evidence.table_closure.object_references.scoped_rules -eq 3 -and
    $evidence.table_closure.object_references.scoped_edges -eq 631)
Add-Assertion 'All Package nodes and evidence-backed edges are preserved' (
    $evidence.package_closure.nodes -eq 121715 -and
    $evidence.package_closure.edges -eq 147349 -and
    $evidence.package_closure.resolution.unique -eq 94882 -and
    $evidence.package_closure.resolution.ambiguous -eq 21146 -and
    $evidence.package_closure.resolution.unresolved -eq 1076 -and
    $evidence.package_closure.resolution.'scoped-terminal' -eq 30245 -and
    $evidence.package_closure.recorded_resolution_mismatches -eq 0)
Add-Assertion 'All eight asset families are present with explicit link state' (
    $evidence.asset_closure.files -eq 40090 -and
    $evidence.asset_closure.link_edges -eq 61511 -and
    $evidence.asset_closure.catalog_candidate_mismatches -eq 0 -and
    @($evidence.asset_closure.families.PSObject.Properties).Count -eq 8 -and
    $evidence.asset_closure.families.qtx.files -eq 24798 -and
    $evidence.asset_closure.families.ter.files -eq 8876 -and
    $evidence.asset_closure.families.zif.unlinked -eq 841)
Add-Assertion 'No heuristic selection or raw protected values are emitted' (
    $evidence.health.heuristic_target_selections -eq 0 -and
    -not $evidence.disclosure.raw_table_values_emitted -and
    -not $evidence.disclosure.raw_primary_keys_emitted -and
    -not $evidence.disclosure.raw_package_object_names_emitted -and
    -not $evidence.disclosure.graph_committed_to_git -and
    -not $evidence.disclosure.payload_bytes_copied)
Add-Assertion 'Policy and schema hashes are bound by evidence' (
    $evidence.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath))
Add-Assertion 'Implementation uses hashed identities and isolated generation' (
    $python -match 'candidate_ascii_lower_hashes' -and $python -match 'stable_id' -and
    $corePython -match 'def candidate_ascii_lower_hashes' -and
    $corePython -match 'def stable_id' -and
    $python -match 'heuristic_target_selections' -and
    $generator -match "'--network', 'none'" -and $generator -match "'--read-only'" -and
    $generator -match "'--cap-drop', 'ALL'" -and
    $evidence.reproduction.builder_user -eq 'tmxy')
Add-Assertion 'Legacy consumer evidence is hash-only and complete' (
    @($evidence.implementation.legacy_consumer_evidence_sha256.PSObject.Properties).Count -eq 6 -and
    @($evidence.implementation.legacy_consumer_evidence_sha256.PSObject.Properties |
        Where-Object { [string]$_.Value -notmatch '^[0-9a-f]{64}$' }).Count -eq 0)

$queries = @('character', 'scene', 'skill' | ForEach-Object {
        & $queryPath -GraphPath $fixturePath -RootKind $_ -MaximumDepth 3 -MaximumExamples 2 |
            ConvertFrom-Json
    })
Add-Assertion 'Character scene and skill query modes traverse without raw values' (
    $queries.Count -eq 3 -and @($queries | Where-Object result -ne 'PASS').Count -eq 0 -and
    @($queries | Where-Object { $_.traversal.visited_nodes -lt 2 }).Count -eq 0 -and
    @($queries | Where-Object { $_.query.raw_values_emitted -or
            $_.query.raw_primary_keys_emitted -or $_.query.raw_package_names_emitted }).Count -eq 0)

$localCheck = $null
if ($VerifyDerivedSources) {
    $localCheck = & $generatorPath -RebuildRoot $root -Check | ConvertFrom-Json
    Add-Assertion 'Full deterministic closure regeneration passes' (
        $localCheck.result -eq 'PASS' -and $localCheck.completion_criteria_satisfied -and
        $localCheck.graph.sha256 -eq $evidence.graph.sha256 -and
        $localCheck.health.core_dangling_references -eq 0)
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-13'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    verify_derived_sources = [bool]$VerifyDerivedSources
    graph = $evidence.graph
    health = $evidence.health
    local_check = $localCheck
    assertions = $assertions
} | ConvertTo-Json -Depth 20
if ($failed.Count -gt 0) { exit 1 }
