[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\conversion-cache-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\conversion-cache-v1.schema.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-16-conversion-cache.json'
$reportPath = Join-Path $root 'Data\Exports\P2-16\p2-16-conversion-cache-plan.jsonl'
$generatorPath = Join-Path $root 'Tools\TMXY.ConversionCache\New-ConversionCachePlan.ps1'
$pythonPath = Join-Path $root 'Tools\TMXY.ConversionCache\conversion_cache.py'
$queryPath = Join-Path $root 'Tools\TMXY.ConversionCache\Find-ConversionCachePlan.ps1'
$verifierPath = Join-Path $root 'Tools\TMXY.ConversionCache\Test-ConversionCacheEntry.ps1'
$fixtureRoot = Join-Path $root 'Tests\Fixtures\ConversionCache'
$planFixture = Join-Path $fixtureRoot 'smoke-plan.jsonl'
$manifestFixture = Join-Path $fixtureRoot 'smoke-manifest.jsonl'
$corruptFixture = Join-Path $fixtureRoot 'corrupt-manifest.jsonl'
$artifactRoot = Join-Path $fixtureRoot 'artifacts'
$assetEvidencePath = Join-Path $root 'Data\Inventory\p2-12-full-asset-inventory.json'
$routingEvidencePath = Join-Path $root 'Data\Inventory\p2-15-conversion-routing.json'
$assertions = [Collections.Generic.List[object]]::new()

function Add-Assertion([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $assertions.Add([pscustomobject][ordered]@{name=$Name;result=if($Passed){'PASS'}else{'FAIL'};detail=$Detail})
}
function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-LineCount([string]$Path) {
    $count=0; foreach($line in [IO.File]::ReadLines($Path)){++$count}; $count
}

foreach ($path in @($policyPath,$schemaPath,$evidencePath,$generatorPath,$pythonPath,$queryPath,
        $verifierPath,$planFixture,$manifestFixture,$corruptFixture,$assetEvidencePath,$routingEvidencePath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" (Test-Path $path -PathType Leaf)
}
Add-Assertion 'Required fixture artifact root exists' (Test-Path $artifactRoot -PathType Container)
if (@($assertions|Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject]@{schema_version=1;task_id='P2-16';result='FAIL';completion_criteria_satisfied=$false;assertions=$assertions}|ConvertTo-Json -Depth 10
    exit 1
}

$policy=Get-Content $policyPath -Raw|ConvertFrom-Json
$schema=Get-Content $schemaPath -Raw|ConvertFrom-Json
$evidence=Get-Content $evidencePath -Raw|ConvertFrom-Json
$assetEvidence=Get-Content $assetEvidencePath -Raw|ConvertFrom-Json
$routingEvidence=Get-Content $routingEvidencePath -Raw|ConvertFrom-Json
$python=Get-Content $pythonPath -Raw
$generator=Get-Content $generatorPath -Raw

Add-Assertion 'Evidence completes P2-16' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-Assertion 'Schema is closed draft 2020-12 evidence' ($schema.'$schema' -eq
    'https://json-schema.org/draft/2020-12/schema' -and $schema.type -eq 'object' -and
    $schema.additionalProperties -eq $false -and $schema.properties.task_id.const -eq 'P2-16')
Add-Assertion 'Policy defines complete immutable content key material' (
    $policy.key_namespace -eq 'tmxy.conversion.cache-key.v1' -and
    $policy.hash_algorithm -eq 'sha256' -and @($policy.key_components).Count -eq 11 -and
    @($policy.converter_tool_evidence.PSObject.Properties).Count -eq 8 -and
    @($policy.external_descriptor_families).Count -eq 5 -and
    -not (@($policy.key_components) -contains 'mtime') -and
    -not (@($policy.key_components) -contains 'absolute_path'))
Add-Assertion 'Manual and untrusted cache operations fail closed' (
    @($policy.manual_routes_require_intervention_digest).Count -eq 2 -and
    $policy.completion_policy.forbids_manual_cache_key_without_intervention_digest -and
    $policy.completion_policy.forbids_cache_hit_without_output_sha256_verification -and
    $policy.storage_policy.cache_manifest_is_untrusted_until_artifact_hash_verification -and
    $policy.storage_policy.shared_cache_writes_require_trusted_pipeline)
Add-Assertion 'Evidence binds P2-12 and P2-15 exact reports' (
    $evidence.input.asset_catalog_sha256 -eq $assetEvidence.catalog.sha256 -and
    $evidence.input.conversion_routing_sha256 -eq $routingEvidence.report.sha256 -and
    $evidence.input.routing_policy_sha256 -eq $routingEvidence.contracts.policy_sha256)
Add-Assertion 'Ignored plan is deterministic and complete' (
    $evidence.report.path -eq 'Data/Exports/P2-16/p2-16-conversion-cache-plan.jsonl' -and
    -not $evidence.report.tracked -and $evidence.report.lines -eq 40090 -and
    $evidence.report.bytes -eq 28389045 -and
    $evidence.report.sha256 -eq 'eb7991ca638edbb0029fb20b34b2f794380d6ff202413734e7abd46e78ff4afb')
if (Test-Path $reportPath -PathType Leaf) {
    Add-Assertion 'Local plan hash size and lines match evidence' ((Get-Sha256 $reportPath) -eq
        $evidence.report.sha256 -and (Get-Item $reportPath).Length -eq $evidence.report.bytes -and
        (Get-LineCount $reportPath) -eq $evidence.report.lines)
}
Add-Assertion 'Every routed asset has one cache plan state' (
    $evidence.summary.assets.files -eq 40090 -and $evidence.summary.assets.bytes -eq 8882019027 -and
    $evidence.summary.assets.conversion_jobs -eq 34601 -and $evidence.summary.assets.aliases -eq 5489)
Add-Assertion 'Ready keys aliases and manual blocks close exactly' (
    $evidence.summary.cache_keys.ready_jobs -eq 33801 -and
    $evidence.summary.cache_keys.distinct_ready_keys -eq 33801 -and
    $evidence.summary.cache_keys.alias_assignments -eq 5489 -and
    $evidence.summary.cache_keys.assets_with_ready_key -eq 39290 -and
    $evidence.summary.cache_keys.blocked_manual_jobs -eq 800 -and
    $evidence.summary.cache_keys.timestamps_in_key -eq 0 -and
    $evidence.summary.cache_keys.absolute_paths_in_key -eq 0)

$expectedFamilies=[ordered]@{
    anim=@(1069,1069,0,1039,30,655802200);mp3=@(64,61,3,61,0,124002521)
    qtx=@(24798,24798,0,24042,756,3910277648);skem=@(1068,990,78,988,2,515443174)
    sm=@(2924,2826,98,2814,12,2307762148);ter=@(8876,3632,5244,3632,0,1309215704)
    wav=@(450,419,31,419,0,54949730);zif=@(841,806,35,806,0,4565902)
}
$familiesPassed=$true
foreach($item in $expectedFamilies.GetEnumerator()){
    $a=$evidence.summary.by_family.($item.Key);$x=$item.Value
    $familiesPassed=$familiesPassed -and $a.files -eq $x[0] -and $a.conversion_jobs -eq $x[1] -and
        $a.aliases -eq $x[2] -and $a.ready_jobs -eq $x[3] -and $a.blocked_jobs -eq $x[4] -and
        $a.bytes -eq $x[5]
}
Add-Assertion 'Every family has frozen job alias ready and blocked counts' $familiesPassed
Add-Assertion 'Full-data invalidation proofs have exact scope' (
    $evidence.summary.invalidation_proof.identity_rebuild_stable_keys -eq 33801 -and
    $evidence.summary.invalidation_proof.source_mutation_changed_keys -eq 1 -and
    $evidence.summary.invalidation_proof.routing_policy_mutation_changed_keys -eq 33801 -and
    $evidence.summary.invalidation_proof.target_profile_mutation_changed_keys -eq 33801 -and
    $evidence.summary.invalidation_proof.descriptor_graph_mutation_changed_keys -eq 32515)
$toolExpected=[ordered]@{anim=1039;mp3=61;qtx=24042;skem=988;sm=2814;ter=3632;wav=419;zif=806}
$toolPassed=$true
foreach($item in $toolExpected.GetEnumerator()){
    $toolPassed=$toolPassed -and
        $evidence.summary.invalidation_proof.tool_mutation_changed_keys_by_family.($item.Key) -eq $item.Value
}
Add-Assertion 'Tool mutation invalidates only its ready family jobs' $toolPassed
Add-Assertion 'Output verification is mandatory and shared writes unauthorized' (
    $evidence.summary.output_hash_verification_required -and
    -not $evidence.summary.shared_cache_write_authorized)
$toolBindingsPassed=$true
foreach($property in $policy.converter_tool_evidence.PSObject.Properties){
    $upstream=Get-Content (Join-Path $root ([string]$property.Value)) -Raw|ConvertFrom-Json
    $toolBindingsPassed=$toolBindingsPassed -and
        $evidence.key_inputs.converter_source_sha256.($property.Name) -eq $upstream.source_sha256
}
Add-Assertion 'Every family converter key binds completed source evidence' $toolBindingsPassed
Add-Assertion 'Policy schema implementation and isolation hashes are bound' (
    $evidence.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath) -and
    $python -match 'source_payload_sha256' -and $python -match 'target_profile_sha256' -and
    $generator -match "'--network','none'" -and $generator -match "'--read-only'" -and
    $generator -match "'--cap-drop','ALL'" -and $evidence.reproduction.builder_user -eq 'tmxy')
Add-Assertion 'Tracked evidence preserves public repository disclosure boundary' (
    -not $evidence.disclosure.tracked_evidence_contains_asset_paths -and
    -not $evidence.disclosure.tracked_evidence_contains_source_hashes -and
    -not $evidence.disclosure.full_plan_committed_to_git -and
    -not $evidence.disclosure.cache_artifacts_committed_to_git -and
    -not $evidence.disclosure.payload_bytes_copied)

$good=& $verifierPath -PlanPath $planFixture -ManifestPath $manifestFixture -ArtifactRoot $artifactRoot|ConvertFrom-Json
$badOutput=& $verifierPath -PlanPath $planFixture -ManifestPath $corruptFixture -ArtifactRoot $artifactRoot 2>$null
$bad=$badOutput|ConvertFrom-Json
Add-Assertion 'Resolver verifies hits preserves misses and blocks manual jobs' (
    $good.result -eq 'PASS' -and $good.ready_jobs -eq 2 -and $good.verified_hits -eq 1 -and
    $good.misses -eq 1 -and $good.blocked_manual_jobs -eq 1 -and $good.aliases -eq 1 -and
    $good.output_sha256_verified -eq 1)
Add-Assertion 'Resolver rejects a hash-mismatched cached artifact' (
    $bad.result -eq 'FAIL' -and $bad.corrupt -eq 1 -and $bad.verified_hits -eq 0)
$queries=@('ready','alias','blocked-manual-input'|ForEach-Object{
    & $queryPath -ReportPath $planFixture -State $_ -MaximumExamples 10|ConvertFrom-Json
})
Add-Assertion 'All plan states are queryable without hashes or payloads' (
    $queries.Count -eq 3 -and @($queries|Where-Object{$_.result -ne 'PASS' -or $_.matches -lt 1 -or
        $_.query.raw_payloads_emitted -or $_.query.source_hashes_emitted -or $_.query.cache_keys_emitted}).Count -eq 0)

$localCheck=$null
if($VerifyDerivedSources){
    $localCheck=& $generatorPath -RebuildRoot $root -Check|ConvertFrom-Json
    Add-Assertion 'Full deterministic cache plan regeneration passes' (
        $localCheck.result -eq 'PASS' -and $localCheck.completion_criteria_satisfied -and
        $localCheck.report.sha256 -eq $evidence.report.sha256 -and
        $localCheck.summary.cache_keys.ready_jobs -eq 33801)
}
$failed=@($assertions|Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version=1;task_id='P2-16';result=if($failed.Count-eq 0){'PASS'}else{'FAIL'}
    completion_criteria_satisfied=$failed.Count-eq 0;verify_derived_sources=[bool]$VerifyDerivedSources
    report=$evidence.report;summary=$evidence.summary;local_check=$localCheck;assertions=$assertions
}|ConvertTo-Json -Depth 20
if($failed.Count-gt 0){exit 1}
