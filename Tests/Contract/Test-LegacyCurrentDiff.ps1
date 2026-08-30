[CmdletBinding()]
param([string]$RebuildRoot='E:\QQXYCodeDev\Rebuild',[switch]$VerifyDerivedSources)
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath=Join-Path $root 'Contracts\data-schema\legacy-current-diff-policy-v1.json'
$schemaPath=Join-Path $root 'Contracts\data-schema\legacy-current-diff-v1.schema.json'
$evidencePath=Join-Path $root 'Data\Inventory\p2-09-legacy-current-diff.json'
$reportPath=Join-Path $root 'Data\Exports\P2-09\p2-09-legacy-current-diff.jsonl'
$generatorPath=Join-Path $root 'Tools\TMXY.TableDiff\New-LegacyCurrentDiff.ps1'
$pythonPath=Join-Path $root 'Tools\TMXY.TableDiff\table_diff.py'
$queryPath=Join-Path $root 'Tools\TMXY.TableDiff\Find-LegacyCurrentDiff.ps1'
$fixturePath=Join-Path $root 'Tests\Fixtures\TableDiff\smoke-diff.jsonl'
$p206Path=Join-Path $root 'Data\Inventory\p2-06-three-layer-data.json'
$registryPath=Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
$assertions=[Collections.Generic.List[object]]::new()
function Add-A([string]$Name,[bool]$Passed){$assertions.Add([pscustomobject]@{name=$Name;result=if($Passed){'PASS'}else{'FAIL'};detail=''})}
function Get-Sha([string]$Path){(Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-Lines([string]$Path){$n=0;foreach($line in [IO.File]::ReadLines($Path)){++$n};$n}
foreach($path in @($policyPath,$schemaPath,$evidencePath,$generatorPath,$pythonPath,$queryPath,$fixturePath,$p206Path,$registryPath)){Add-A "Required file $([IO.Path]::GetFileName($path))" (Test-Path $path -PathType Leaf)}
if(@($assertions|Where-Object result -eq 'FAIL').Count){[pscustomobject]@{schema_version=1;task_id='P2-09';result='FAIL';completion_criteria_satisfied=$false;assertions=$assertions}|ConvertTo-Json -Depth 8;exit 1}
$policy=Get-Content $policyPath -Raw|ConvertFrom-Json;$schema=Get-Content $schemaPath -Raw|ConvertFrom-Json;$e=Get-Content $evidencePath -Raw|ConvertFrom-Json
$p206=Get-Content $p206Path -Raw|ConvertFrom-Json;$python=Get-Content $pythonPath -Raw;$generator=Get-Content $generatorPath -Raw
Add-A 'Evidence completes P2-09' ($e.result-eq'PASS'-and$e.task_status-eq'COMPLETE'-and$e.completion_criteria_satisfied)
Add-A 'Schema is closed draft 2020-12 evidence' ($schema.'$schema'-eq'https://json-schema.org/draft/2020-12/schema'-and$schema.type-eq'object'-and$schema.additionalProperties-eq$false-and$schema.properties.task_id.const-eq'P2-09')
Add-A 'Policy forbids inferred build defaults and tracked values' ($policy.legacy_build-eq'unknown-not-inferred'-and$policy.completion_policy.forbids_guessing_legacy_build-and$policy.completion_policy.forbids_treating_observed_mode_as_authoritative_default-and$policy.output_policy.full_diff_tracked_in_git-eq$false-and$policy.output_policy.tracked_evidence_contains_row_values-eq$false)
Add-A 'Evidence binds P2-06 and P2-07 registry' ($e.input.p2_06_evidence_sha256-eq(Get-Sha $p206Path)-and$e.input.core_registry_sha256-eq(Get-Sha $registryPath)-and$p206.result-eq'PASS')
Add-A 'Ignored report is deterministic and complete' ($e.report.path-eq'Data/Exports/P2-09/p2-09-legacy-current-diff.jsonl'-and-not$e.report.tracked-and$e.report.lines-eq 52-and$e.report.bytes-eq 41759-and$e.report.sha256-eq'c6fb188d97db18e1dd87201871a36bad77229f5f53e24d2650871a032bcf2667')
if(Test-Path $reportPath){Add-A 'Local report hash size and lines match evidence' ((Get-Sha $reportPath)-eq$e.report.sha256-and(Get-Item $reportPath).Length-eq$e.report.bytes-and(Get-Lines $reportPath)-eq$e.report.lines)}
Add-A 'All legacy tables pair without claiming a build' ($e.summary.legacy_tables-eq 52-and$e.summary.current_active_tables-eq 113-and$e.summary.paired_tables-eq 52-and$e.summary.unpaired_legacy_tables-eq 0-and$e.summary.legacy_bytes-eq 8609196-and-not$e.summary.legacy_build_known)
Add-A 'Legacy encodings are losslessly classified' ($e.summary.legacy_encodings.'utf-8'-eq 19-and$e.summary.legacy_encodings.gb18030-eq 33)
Add-A 'Schema column type and mode diffs are exact' ($e.summary.equal_headers-eq 40-and$e.summary.columns.shared-eq 608-and$e.summary.columns.legacy_only-eq 18-and$e.summary.columns.current_only-eq 66-and$e.summary.columns.inferred_type_changes-eq 59-and$e.summary.columns.observed_mode_hash_changes-eq 179-and$e.summary.authoritative_default_claims-eq 0)
Add-A 'Row multiset differences close exactly' ($e.summary.rows.legacy-eq 73602-and$e.summary.rows.current-eq 149472-and$e.summary.rows.shared_exact-eq 44500-and$e.summary.rows.legacy_only-eq 29102-and$e.summary.rows.current_only-eq 104972-and$e.summary.rows.shared_exact+$e.summary.rows.legacy_only-eq$e.summary.rows.legacy-and$e.summary.rows.shared_exact+$e.summary.rows.current_only-eq$e.summary.rows.current)
Add-A 'Core key and reference comparisons are complete' ($e.summary.core_primary_key_tables-eq 10-and$e.summary.references.comparable_rules-eq 12-and$e.summary.references.legacy_active_references-eq 19599-and$e.summary.references.current_active_references-eq 39361-and$e.summary.references.legacy_dangling_references-eq 0-and$e.summary.references.current_dangling_references-eq 0-and$e.summary.references.changed_rules-eq 12)
Add-A 'Contracts implementation and isolation are bound' ($e.contracts.policy_sha256-eq(Get-Sha $policyPath)-and$e.contracts.schema_sha256-eq(Get-Sha $schemaPath)-and$python-match'row_multiset'-and$python-match'foreign_key_summary'-and$generator-match"'--network','none'"-and$generator-match"target=/legacy,readonly"-and$e.reproduction.builder_user-eq'tmxy')
Add-A 'Tracked evidence preserves disclosure boundary' (-not$e.disclosure.tracked_evidence_contains_headers-and-not$e.disclosure.tracked_evidence_contains_row_values-and-not$e.disclosure.tracked_evidence_contains_primary_keys-and-not$e.disclosure.full_report_committed_to_git-and-not$e.disclosure.legacy_payloads_copied)
$query=& $queryPath -ReportPath $fixturePath -Table fixture_table|ConvertFrom-Json
Add-A 'Diff query returns counts without values headers or keys' ($query.result-eq'PASS'-and$query.matches-eq 1-and$query.examples[0].primary_key_applicable-and-not$query.query.headers_emitted-and-not$query.query.row_values_emitted-and-not$query.query.primary_keys_emitted)
$local=$null;if($VerifyDerivedSources){$local=& $generatorPath -RebuildRoot $root -Check|ConvertFrom-Json;Add-A 'Full deterministic legacy/current regeneration passes' ($local.result-eq'PASS'-and$local.completion_criteria_satisfied-and$local.report.sha256-eq$e.report.sha256)}
$failed=@($assertions|Where-Object result -eq 'FAIL');[pscustomobject][ordered]@{schema_version=1;task_id='P2-09';result=if($failed.Count-eq 0){'PASS'}else{'FAIL'};completion_criteria_satisfied=$failed.Count-eq 0;verify_derived_sources=[bool]$VerifyDerivedSources;report=$e.report;summary=$e.summary;local_check=$local;assertions=$assertions}|ConvertTo-Json -Depth 20;if($failed.Count){exit 1}
