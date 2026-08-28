[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyRoot = 'E:\QQXYCodeDev\DevDoc\游戏资料\ltb\解密后',
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-09\p2-09-legacy-current-diff.jsonl',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-09-legacy-current-diff.json',
    [switch]$Check
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$legacy=[IO.Path]::GetFullPath($LegacyRoot).TrimEnd([char[]]'\/')
$report=[IO.Path]::GetFullPath($ReportPath);$output=[IO.Path]::GetFullPath($OutputPath)
$exportRoot=[IO.Path]::GetFullPath((Join-Path $root 'Data\Exports\P2-09')).TrimEnd([char[]]'\/')
if(-not $report.StartsWith($exportRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'P2-09 report escaped its output root.'
}
$moduleRoot=Join-Path $root 'Tools\TMXY.TableDiff';$pythonPath=Join-Path $moduleRoot 'table_diff.py'
$policyPath=Join-Path $root 'Contracts\data-schema\legacy-current-diff-policy-v1.json'
$schemaPath=Join-Path $root 'Contracts\data-schema\legacy-current-diff-v1.schema.json'
$currentRoot=Join-Path $root 'Data\Exports\P2-06\tables'
$p206Path=Join-Path $root 'Data\Inventory\p2-06-three-layer-data.json'
$registryPath=Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
$lockPath=Join-Path $root 'Data\Toolchain\toolchain.lock.json'
foreach($path in @($legacy,$moduleRoot,$pythonPath,$policyPath,$schemaPath,$currentRoot,$p206Path,$registryPath,$lockPath)){
    if(-not(Test-Path $path)){throw "P2-09 input missing: $path"}
}
$legacyFiles=@(Get-ChildItem $legacy -File -Filter *.csv)
if($legacyFiles.Count-ne 52){throw "P2-09 expected 52 legacy CSV files, got $($legacyFiles.Count)."}
[IO.Directory]::CreateDirectory($exportRoot)|Out-Null
function Get-Sha([string]$Path){(Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-TextSha([string]$Text){$b=[Text.Encoding]::UTF8.GetBytes($Text);try{[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)).ToLowerInvariant()}finally{[Array]::Clear($b,0,$b.Length)}}
function Invoke-Native([string]$File,[string[]]$Arguments){$s=[Diagnostics.ProcessStartInfo]::new();$s.FileName=$File;$s.WorkingDirectory=$root;$s.UseShellExecute=$false;$s.CreateNoWindow=$true;$s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true;foreach($a in $Arguments){$s.ArgumentList.Add($a)};$p=[Diagnostics.Process]::Start($s);$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();$p.WaitForExit();[pscustomobject]@{code=$p.ExitCode;out=$o.Result;err=$e.Result}}
$p206=Get-Content $p206Path -Raw|ConvertFrom-Json
if($p206.result-ne'PASS'-or-not$p206.completion_criteria_satisfied){throw 'P2-09 requires completed P2-06.'}
$sourceFiles=@(Get-ChildItem $moduleRoot -Recurse -File|Where-Object Extension -in @('.ps1','.py')|Sort-Object FullName)
$sourceLines=@($sourceFiles|ForEach-Object{"$([IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/'))|$(Get-Sha $_.FullName)"})
$sourceHash=Get-TextSha (($sourceLines-join"`n")+"`n")
$lock=Get-Content $lockPath -Raw|ConvertFrom-Json;$imageRef=[string]$lock.backend_toolchain.container_image_reference;$imageId=[string]$lock.backend_toolchain.container_image_digest
$image=@(docker image inspect $imageRef 2>$null|ConvertFrom-Json)
if($LASTEXITCODE-ne 0-or$image.Count-ne 1-or$image[0].Id-ne$imageId-or$image[0].Config.User-ne'tmxy'){throw 'P2-09 requires qualified builder.'}
$tempName='.p2-09-'+[Guid]::NewGuid().ToString('N')+'.jsonl';$temp=Join-Path $exportRoot $tempName
$script=@'
set -euo pipefail
self=$(python3 /workspace/Tools/TMXY.TableDiff/table_diff.py --self-test)
printf 'SELFTEST\t%s\n' "$self"
summary=$(python3 /workspace/Tools/TMXY.TableDiff/table_diff.py --legacy /legacy --current /workspace/Data/Exports/P2-06/tables --registry /workspace/Data/Schemas/core-table-registry-v1.json --output "$TMXY_TABLE_DIFF_OUTPUT")
printf 'SUMMARY\t%s\n' "$summary"
'@
$docker=(Get-Command docker).Source;$args=@('run','--rm','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true','--tmpfs','/tmp:rw,exec,nosuid,size=1g','--env',"TMXY_TABLE_DIFF_OUTPUT=/output/$tempName",'--mount',"type=bind,source=$root,target=/workspace,readonly",'--mount',"type=bind,source=$legacy,target=/legacy,readonly",'--mount',"type=bind,source=$exportRoot,target=/output",$imageRef,'bash','-c',$script)
try{
    $run=Invoke-Native $docker $args;if($run.code-ne 0){throw "P2-09 failed: $($run.err)"}
    $selfLine=@($run.out-split"`n"|Where-Object{$_.StartsWith("SELFTEST`t")});$sumLine=@($run.out-split"`n"|Where-Object{$_.StartsWith("SUMMARY`t")})
    if($selfLine.Count-ne 1-or$sumLine.Count-ne 1){throw 'P2-09 framing failed.'}
    $self=$selfLine[0].Substring(9)|ConvertFrom-Json;$sum=$sumLine[0].Substring(8)|ConvertFrom-Json
    if((Get-Sha $temp)-ne$sum.report.sha256-or(Get-Item $temp).Length-ne$sum.report.bytes){throw 'P2-09 report hash mismatch.'}
    $complete=$self.result-eq'PASS'-and$self.assertions-eq 5-and$sum.result-eq'PASS'-and$sum.summary.legacy_tables-eq 52-and$sum.summary.paired_tables-eq 52-and$sum.summary.unpaired_legacy_tables-eq 0-and$sum.summary.core_primary_key_tables-eq 10-and-not$sum.summary.legacy_build_known-and$sum.summary.authoritative_default_claims-eq 0
    if($Check){if(-not(Test-Path $report)-or(Get-Sha $report)-ne$sum.report.sha256){throw 'P2-09 report changed.'}}else{Move-Item $temp $report -Force}
    $captured=[DateTimeOffset]::UtcNow.ToString('o');if($Check-and(Test-Path $output)){$captured=[string](Get-Content $output -Raw|ConvertFrom-Json -DateKind String).captured_utc}
    $obj=[pscustomobject][ordered]@{schema_version=1;captured_utc=$captured;task_id='P2-09';result=if($complete){'PASS'}else{'FAIL'};task_status=if($complete){'COMPLETE'}else{'IN_PROGRESS'};completion_criteria_satisfied=$complete
        input=[pscustomobject][ordered]@{legacy_snapshot='legacy-devdoc-decrypted-csv-20120318';legacy_build='unknown-not-inferred';legacy_manifest_sha256=[string]$sum.inputs.legacy_manifest_sha256;current_build='qy-3.0.0.413';p2_06_evidence_sha256=Get-Sha $p206Path;core_registry_sha256=[string]$sum.inputs.core_registry_sha256;copy_policy='reference_only'}
        report=[pscustomobject][ordered]@{path='Data/Exports/P2-09/p2-09-legacy-current-diff.jsonl';tracked=$false;lines=[int]$sum.report.lines;bytes=[int64]$sum.report.bytes;sha256=[string]$sum.report.sha256};summary=$sum.summary
        contracts=[pscustomobject][ordered]@{policy='Contracts/data-schema/legacy-current-diff-policy-v1.json';policy_sha256=Get-Sha $policyPath;schema='Contracts/data-schema/legacy-current-diff-v1.schema.json';schema_sha256=Get-Sha $schemaPath}
        implementation=[pscustomobject][ordered]@{source_files=$sourceFiles.Count;source_sha256=$sourceHash;self_test_assertions=[int]$self.assertions;generator='Tools/TMXY.TableDiff/New-LegacyCurrentDiff.ps1';query='Tools/TMXY.TableDiff/Find-LegacyCurrentDiff.ps1'}
        disclosure=[pscustomobject][ordered]@{tracked_evidence_contains_headers=$false;tracked_evidence_contains_row_values=$false;tracked_evidence_contains_primary_keys=$false;full_report_committed_to_git=$false;legacy_payloads_copied=$false}
        reproduction=[pscustomobject][ordered]@{check_mode='-Check';legacy_mount='read-only';workspace_mount='read-only';network='none';builder_id=$imageId;builder_user='tmxy'}
        next_scope=[pscustomobject][ordered]@{tasks=@('P2-10','P2-11','P2-17');detail='Build explicit Canonical ID mappings from the comparable legacy/current key domains.'}}
    $json=($obj|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")
    if($Check){if((Get-Content $output -Raw).Replace("`r`n","`n").Replace("`r","`n")-ne$json+"`n"){throw 'P2-09 evidence changed.'}}else{[IO.File]::WriteAllText($output,$json+"`n",[Text.UTF8Encoding]::new($false))};$json;if(-not$complete){throw 'P2-09 incomplete.'}
}finally{if(Test-Path $temp){Remove-Item $temp -Force}}
