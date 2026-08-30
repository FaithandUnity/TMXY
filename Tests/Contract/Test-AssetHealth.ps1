[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\asset-health-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\asset-health-v1.schema.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-14-asset-health.json'
$reportPath = Join-Path $root 'Data\Exports\P2-14\p2-14-asset-health.jsonl'
$generatorPath = Join-Path $root 'Tools\TMXY.AssetHealth\New-AssetHealthReport.ps1'
$pythonPath = Join-Path $root 'Tools\TMXY.AssetHealth\asset_health.py'
$queryPath = Join-Path $root 'Tools\TMXY.AssetHealth\Find-AssetHealth.ps1'
$fixturePath = Join-Path $root 'Tests\Fixtures\AssetHealth\smoke-health.jsonl'
$assetEvidencePath = Join-Path $root 'Data\Inventory\p2-12-full-asset-inventory.json'
$closureEvidencePath = Join-Path $root 'Data\Inventory\p2-13-reference-closure.json'
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

foreach ($path in @($policyPath, $schemaPath, $evidencePath, $generatorPath,
        $pythonPath, $queryPath, $fixturePath, $assetEvidencePath, $closureEvidencePath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject][ordered]@{
        schema_version = 1; task_id = 'P2-14'; result = 'FAIL'
        completion_criteria_satisfied = $false; assertions = $assertions
    } | ConvertTo-Json -Depth 10
    exit 1
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$assetEvidence = Get-Content -LiteralPath $assetEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$closureEvidence = Get-Content -LiteralPath $closureEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
$python = Get-Content -LiteralPath $pythonPath -Raw -Encoding UTF8

Add-Assertion 'Evidence completes P2-14' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-Assertion 'Schema is closed draft 2020-12 evidence' (
    $schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and
    $schema.properties.task_id.const -eq 'P2-14')
Add-Assertion 'Policy separates proof candidates and deletion authority' (
    $policy.source_build -eq 'qy-3.0.0.413' -and
    @($policy.reference_states).Count -eq 4 -and
    $policy.orphan_policy.root_unreachable_is_review_only -and
    $policy.orphan_policy.unlinked_does_not_mean_unused -and
    -not $policy.orphan_policy.all_assets_delete_eligible -and
    $policy.completion_policy.forbids_automatic_deletion_or_repair -and
    $policy.completion_policy.forbids_semantic_equivalence_claim_without_normalized_payload_digest)
Add-Assertion 'Evidence binds exact completed upstream artifacts' (
    $evidence.input.asset_catalog_sha256 -eq $assetEvidence.catalog.sha256 -and
    $evidence.input.reference_closure_sha256 -eq $closureEvidence.graph.sha256)
Add-Assertion 'Ignored health report is deterministic and complete' (
    $evidence.report.path -eq 'Data/Exports/P2-14/p2-14-asset-health.jsonl' -and
    -not $evidence.report.tracked -and $evidence.report.lines -eq 42356 -and
    $evidence.report.bytes -eq 23686877 -and
    $evidence.report.sha256 -eq '9a0db19c7809da06e7225ec900864f0854c8b61af224366aac746be312880b9f' -and
    $evidence.report.records.asset_health -eq 40090 -and
    $evidence.report.records.exact_duplicate_group -eq 1743 -and
    $evidence.report.records.structural_review_group -eq 523)
if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    Add-Assertion 'Local health report hash size and line count match evidence' (
        (Get-Sha256 $reportPath) -eq $evidence.report.sha256 -and
        (Get-Item -LiteralPath $reportPath).Length -eq $evidence.report.bytes -and
        (Get-LineCount $reportPath) -eq $evidence.report.lines)
}
Add-Assertion 'All assets have one explicit reference state' (
    $evidence.summary.assets.files -eq 40090 -and
    $evidence.summary.assets.bytes -eq 8882019027 -and
    $evidence.summary.assets.reference_states.root_reachable -eq 14058 -and
    $evidence.summary.assets.reference_states.linked_outside_declared_roots -eq 24119 -and
    $evidence.summary.assets.reference_states.unlinked_identity_rule_no_match -eq 1008 -and
    $evidence.summary.assets.reference_states.unlinked_no_identity_rule -eq 905)
Add-Assertion 'Declared roots and graph reachability are frozen' (
    $evidence.summary.assets.root_count -eq 24465 -and
    $evidence.summary.assets.root_reachable_graph_nodes -eq 60512 -and
    @($evidence.summary.assets.by_family.PSObject.Properties).Count -eq 8)
Add-Assertion 'Exact duplicate accounting is complete' (
    $evidence.summary.duplicates.exact_groups -eq 1743 -and
    $evidence.summary.duplicates.exact_files -eq 9102 -and
    $evidence.summary.duplicates.redundant_files -eq 7359 -and
    $evidence.summary.duplicates.redundant_bytes -eq 1286887829 -and
    $evidence.summary.duplicates.cross_family_exact_groups -eq 0)
Add-Assertion 'Structural candidates are not semantic duplicate claims' (
    $evidence.summary.duplicates.structural_review_groups -eq 523 -and
    $evidence.summary.duplicates.structural_review_files -eq 33629 -and
    $evidence.summary.duplicates.semantic_equivalence_proven_groups -eq 0 -and
    $evidence.summary.semantic_equivalence_claims_without_digest -eq 0)
$expectedFamilyDuplicates = [ordered]@{
    anim = @(155, 471, 316, 203970664, 47, 268)
    mp3 = @(3, 6, 3, 5726390, 0, 0)
    qtx = @(1326, 2880, 1554, 242876664, 272, 23905)
    skem = @(76, 154, 78, 39406874, 41, 132)
    sm = @(64, 162, 98, 17505262, 98, 252)
    ter = @(81, 5325, 5244, 773494744, 9, 8876)
    wav = @(24, 55, 31, 3822950, 44, 162)
    zif = @(14, 49, 35, 84281, 12, 34)
}
$familyDuplicatePassed = $true
foreach ($property in $expectedFamilyDuplicates.GetEnumerator()) {
    $actual = $evidence.summary.duplicates.by_family.($property.Key)
    $expected = $property.Value
    $familyDuplicatePassed = $familyDuplicatePassed -and
        $actual.exact_groups -eq $expected[0] -and $actual.exact_files -eq $expected[1] -and
        $actual.redundant_files_within_family -eq $expected[2] -and
        $actual.redundant_bytes_within_family -eq $expected[3] -and
        $actual.structural_review_groups -eq $expected[4] -and
        $actual.structural_review_files -eq $expected[5]
}
Add-Assertion 'Every asset family has frozen duplicate and review counts' $familyDuplicatePassed
Add-Assertion 'No asset is authorized for deletion or repair' (
    $evidence.summary.deletion_recommendations -eq 0 -and
    $evidence.disclosure.automatic_deletions_performed -eq 0 -and
    -not $evidence.disclosure.payload_bytes_copied)
Add-Assertion 'Tracked evidence preserves the public repository boundary' (
    -not $evidence.disclosure.tracked_evidence_contains_asset_paths -and
    -not $evidence.disclosure.tracked_evidence_contains_per_asset_hashes -and
    -not $evidence.disclosure.full_report_committed_to_git)
Add-Assertion 'Policy and schema hashes are bound by evidence' (
    $evidence.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath))
Add-Assertion 'Implementation uses exact hashes graph reachability and isolation' (
    $python -match 'source_sha256' -and $python -match 'reachable_from' -and
    $python -match 'semantic_equivalence_proven' -and
    $generator -match "'--network', 'none'" -and $generator -match "'--read-only'" -and
    $generator -match "'--cap-drop', 'ALL'" -and
    $evidence.reproduction.builder_user -eq 'tmxy')

$stateQueries = @('root_reachable', 'linked_outside_declared_roots',
    'unlinked_identity_rule_no_match', 'unlinked_no_identity_rule' | ForEach-Object {
        & $queryPath -ReportPath $fixturePath -ReferenceState $_ -MaximumExamples 5 |
            ConvertFrom-Json
    })
$exactQuery = & $queryPath -ReportPath $fixturePath `
    -GroupId ('a' * 64) -MaximumExamples 5 | ConvertFrom-Json
$structuralQuery = & $queryPath -ReportPath $fixturePath `
    -GroupId ('d' * 64) -MaximumExamples 5 | ConvertFrom-Json
Add-Assertion 'All review states and both group modes are queryable without payloads' (
    $stateQueries.Count -eq 4 -and
    @($stateQueries | Where-Object { $_.result -ne 'PASS' -or $_.matches -lt 1 -or
            $_.query.raw_payloads_emitted -or $_.query.source_hashes_emitted }).Count -eq 0 -and
    $exactQuery.matches -eq 2 -and $exactQuery.query.group_kind -eq 'exact_duplicate_group' -and
    $structuralQuery.matches -eq 2 -and
    $structuralQuery.query.group_kind -eq 'structural_review_group' -and
    @($exactQuery.examples + $structuralQuery.examples |
        Where-Object delete_eligible).Count -eq 0)

$localCheck = $null
if ($VerifyDerivedSources) {
    $localCheck = & $generatorPath -RebuildRoot $root -Check | ConvertFrom-Json
    Add-Assertion 'Full deterministic asset health regeneration passes' (
        $localCheck.result -eq 'PASS' -and $localCheck.completion_criteria_satisfied -and
        $localCheck.report.sha256 -eq $evidence.report.sha256 -and
        $localCheck.summary.deletion_recommendations -eq 0)
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-14'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    verify_derived_sources = [bool]$VerifyDerivedSources
    report = $evidence.report
    summary = $evidence.summary
    local_check = $localCheck
    assertions = $assertions
} | ConvertTo-Json -Depth 20
if ($failed.Count -gt 0) { exit 1 }
