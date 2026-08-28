[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev',
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyLegacySources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\table-ownership-policy-v1.json'
$contractPath = Join-Path $root 'Contracts\data-schema\table-ownership-registry-v1.schema.json'
$registryPath = Join-Path $root 'Data\Schemas\table-ownership-registry-v1.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-08-table-ownership.json'
$p205Path = Join-Path $root 'Data\Inventory\p2-05-auxiliary-config-inventory.json'
$p206Path = Join-Path $root 'Data\Inventory\p2-06-three-layer-data.json'
$p207Path = Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
$generatorPath = Join-Path $root 'Tools\TMXY.Table\New-TableOwnershipRegistry.ps1'
$docPath = Join-Path $root 'Docs\Formats\TABLE-OWNERSHIP.md'
$assertions = [Collections.Generic.List[object]]::new()

function Add-Assertion {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
            detail = $Detail
        })
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$required = @($policyPath, $contractPath, $registryPath, $evidencePath,
    $p205Path, $p206Path, $p207Path, $generatorPath, $docPath)
foreach ($path in $required) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject][ordered]@{
        schema_version = 1
        task_id = 'P2-08'
        result = 'FAIL'
        completion_criteria_satisfied = $false
        assertions = $assertions
    } | ConvertTo-Json -Depth 20
    exit 1
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$p205 = Get-Content -LiteralPath $p205Path -Raw -Encoding UTF8 | ConvertFrom-Json
$p206 = Get-Content -LiteralPath $p206Path -Raw -Encoding UTF8 | ConvertFrom-Json
$p207 = Get-Content -LiteralPath $p207Path -Raw -Encoding UTF8 | ConvertFrom-Json
$generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8

Add-Assertion 'Evidence completes P2-08' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-Assertion 'Registry is authoritative target ownership contract' (
    $registry.schema_version -eq 1 -and
    $registry.registry_id -eq 'tmxy-table-ownership-registry-v1' -and
    $registry.task_id -eq 'P2-08' -and
    $registry.status -eq 'authoritative-target-ownership-contract')
Add-Assertion 'Prior stage hashes and build are bound' (
    $registry.source_build -eq $policy.source_build -and
    $registry.source_build -eq $p206.source.build -and
    $registry.source_build -eq $p207.source_build -and
    $registry.source.p2_05_evidence_sha256 -eq (Get-Sha256 $p205Path) -and
    $registry.source.p2_06_evidence_sha256 -eq (Get-Sha256 $p206Path) -and
    $registry.source.p2_07_registry_sha256 -eq (Get-Sha256 $p207Path) -and
    $evidence.source.p2_05_evidence_sha256 -eq (Get-Sha256 $p205Path) -and
    $evidence.source.p2_06_evidence_sha256 -eq (Get-Sha256 $p206Path) -and
    $evidence.source.p2_07_registry_sha256 -eq (Get-Sha256 $p207Path))
Add-Assertion 'Policy contract generator and registry hashes are bound' (
    $registry.source.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $registry.source.contract_sha256 -eq (Get-Sha256 $contractPath) -and
    $evidence.source.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.source.registry_contract_sha256 -eq (Get-Sha256 $contractPath) -and
    $evidence.source.generator_sha256 -eq (Get-Sha256 $generatorPath) -and
    $evidence.output.registry_sha256 -eq (Get-Sha256 $registryPath))
Add-Assertion 'Source population and client config hashes agree' (
    $registry.source.client_source_population_sha256 -eq
        $evidence.source.client_source_population_sha256 -and
    $registry.source.server_source_population_sha256 -eq
        $evidence.source.server_source_population_sha256 -and
    $registry.source.client_config_sha256 -eq $evidence.source.client_config_sha256 -and
    -not $registry.source.client_config_decoded_content_emitted)
Add-Assertion 'JSON Schema contract is draft 2020-12' (
    $contract.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $contract.type -eq 'object' -and
    $contract.additionalProperties -eq $false -and
    $contract.properties.tables.minItems -eq 225 -and
    $contract.properties.core_columns.minItems -eq 355)
Add-Assertion 'Consumer observations are frozen' (
    $registry.source.client_source_files_scanned -eq 1096 -and
    $registry.source.server_source_files_scanned -eq 1972 -and
    $registry.summary.current_client_config_referenced_tables -eq 127 -and
    $registry.summary.legacy_client_source_referenced_tables -eq 3 -and
    $registry.summary.legacy_server_source_referenced_tables -eq 45 -and
    $registry.summary.observed_consumer_none -eq 98)

$summary = $registry.summary
Add-Assertion 'All 225 active tables are classified' (
    $summary.active_tables -eq 225 -and $summary.classified_tables -eq 225 -and
    $summary.unclassified_tables -eq 0 -and $summary.result -eq 'PASS')
Add-Assertion 'Table schema ownership split is exact' (
    $summary.schema_owner_client -eq 117 -and
    $summary.schema_owner_server -eq 0 -and
    $summary.schema_owner_shared -eq 108 -and
    $summary.runtime_client_presentation -eq 117 -and
    $summary.runtime_server_authoritative -eq 108)
Add-Assertion 'All 355 core columns are classified' (
    $summary.core_tables -eq 12 -and $summary.core_columns -eq 355 -and
    $summary.classified_core_columns -eq 355 -and
    $summary.core_owner_client -eq 48 -and
    $summary.core_owner_server -eq 277 -and
    $summary.core_owner_shared -eq 30 -and
    $summary.core_localizable_columns -eq 36)
Add-Assertion 'Security-sensitive client authority violations are zero' (
    $summary.security_sensitive_client_authority_violations -eq 0)
Add-Assertion 'Evidence and registry summaries agree' (
    ($summary | ConvertTo-Json -Compress) -ceq
        ($evidence.summary | ConvertTo-Json -Compress))

$tables = @($registry.tables)
$activeP206 = @($p206.tables | Where-Object lifecycle -eq 'active')
Add-Assertion 'Registry table paths exactly match P2-06 active paths' (
    $tables.Count -eq 225 -and
    @($tables.source_path | Sort-Object -Unique).Count -eq 225 -and
    (($tables.source_path | Sort-Object) -join "`n") -ceq
        (($activeP206.source_path | Sort-Object) -join "`n"))
Add-Assertion 'Every table source hash is retained' (
    @($tables | Where-Object {
            $path = $_.source_path
            $source = @($activeP206 | Where-Object source_path -ceq $path)
            $source.Count -ne 1 -or $_.source_sha256 -cne $source[0].source_sha256
        }).Count -eq 0)
Add-Assertion 'Ownership and runtime authority combinations are closed' (
    @($tables | Where-Object {
            $_.result -ne 'PASS' -or
            ($_.schema_owner -eq 'client' -and
                $_.runtime_authority -ne 'client-presentation') -or
            ($_.schema_owner -eq 'shared' -and
                $_.runtime_authority -ne 'server-authoritative') -or
            $_.schema_owner -eq 'server'
        }).Count -eq 0)
Add-Assertion 'Server authority never trusts client table values' (
    @($tables | Where-Object {
            $_.runtime_authority -eq 'server-authoritative' -and
            -not $_.server_must_not_trust_client_values
        }).Count -eq 0)
Add-Assertion 'Target consumer lists follow authority' (
    @($tables | Where-Object {
            'client' -notin @($_.target_consumers) -or
            ($_.runtime_authority -eq 'server-authoritative' -and
                'server' -notin @($_.target_consumers)) -or
            ($_.runtime_authority -eq 'client-presentation' -and
                'server' -in @($_.target_consumers))
        }).Count -eq 0)
Add-Assertion 'Observed consumer scope is internally consistent' (
    @($tables | Where-Object {
            $client = $_.observed_consumers.current_client_config -or
                $_.observed_consumers.legacy_client_source_files.Count -gt 0
            $server = $_.observed_consumers.legacy_server_source_files.Count -gt 0
            $expected = if ($client -and $server) { 'shared' }
                elseif ($client) { 'client' }
                elseif ($server) { 'server' }
                else { 'none' }
            $_.observed_consumers.scope -ne $expected
        }).Count -eq 0)
Add-Assertion 'Every legacy server-referenced table remains server-authoritative' (
    @($tables | Where-Object {
            $_.observed_consumers.legacy_server_source_files.Count -gt 0 -and
            $_.runtime_authority -ne 'server-authoritative'
        }).Count -eq 0)

$clientOverrides = @($policy.client_presentation_table_overrides | Sort-Object)
$serverOverrides = @($policy.server_authoritative_table_overrides | Sort-Object)
Add-Assertion 'Client presentation override set is exact' (
    $clientOverrides.Count -eq 9 -and
    @($tables | Where-Object {
            $_.decision_basis -eq 'explicit-client-presentation-table-override'
        }).Count -eq 9)
Add-Assertion 'Server-authoritative Table override set is exact' (
    $serverOverrides.Count -eq 4 -and
    @($tables | Where-Object {
            $_.decision_basis -eq 'explicit-server-authoritative-table-override'
        }).Count -eq 4)
$faceHair = @($tables | Where-Object source_path -in @(
            'CLSVShare/face.tbl', 'CLSVShare/hair.tbl'))
Add-Assertion 'Appearance choice domains remain server-validated' (
    $faceHair.Count -eq 2 -and
    @($faceHair | Where-Object {
            $_.runtime_authority -ne 'server-authoritative' -or
            $_.observed_consumers.legacy_server_source_files.Count -eq 0
        }).Count -eq 0)

$corePaths = @($p207.tables.source_path)
Add-Assertion 'Every P2-07 core table is shared and server-authoritative' (
    @($tables | Where-Object {
            $_.source_path -in $corePaths -and
            ($_.schema_owner -ne 'shared' -or
                $_.runtime_authority -ne 'server-authoritative')
        }).Count -eq 0 -and
    @($tables | Where-Object source_path -in $corePaths).Count -eq 12)

$columns = @($registry.core_columns)
Add-Assertion 'Core field identity is unique and source-bound' (
    $columns.Count -eq 355 -and
    @($columns | ForEach-Object { "$($_.table):$($_.column_id)" } |
        Sort-Object -Unique).Count -eq 355)
Add-Assertion 'Core field ownership roles are closed and coherent' (
    @($columns | Where-Object {
            $_.result -ne 'PASS' -or -not $_.server_must_not_trust_client_value -or
            ($_.owner -eq 'client' -and
                $_.runtime_authority -ne 'client-presentation') -or
            ($_.owner -in @('server', 'shared') -and
                $_.runtime_authority -ne 'server-authoritative') -or
            ($_.role -eq 'client-localization' -and -not $_.localizable) -or
            ($_.role -ne 'client-localization' -and $_.localizable)
        }).Count -eq 0)
Add-Assertion 'All declared key and reference columns are shared identifiers' (
    @($p207.tables | ForEach-Object {
            $table = $_
            $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($id in @($table.primary_key.column_ids)) { [void]$ids.Add([string]$id) }
            foreach ($foreignKey in @($table.foreign_keys)) {
                foreach ($id in @($foreignKey.source_column_ids)) { [void]$ids.Add([string]$id) }
            }
            foreach ($other in @($p207.tables)) {
                foreach ($foreignKey in @($other.foreign_keys | Where-Object {
                            $_.target_table -ceq $table.source_path
                        })) {
                    foreach ($id in @($foreignKey.target_column_ids)) {
                        [void]$ids.Add([string]$id)
                    }
                }
            }
            foreach ($id in $ids) {
                $owned = @($columns | Where-Object {
                        $_.table -ceq $table.source_path -and $_.column_id -ceq $id
                    })
                if ($owned.Count -ne 1 -or $owned[0].role -ne 'shared-identifier') {
                    "$($table.source_path):$id"
                }
            }
        }).Count -eq 0)
Add-Assertion 'Presentation and localization boundaries are explicit' (
    @($columns | Where-Object owner -eq 'client').Count -eq 48 -and
    @($columns | Where-Object role -eq 'client-localization').Count -eq 36 -and
    @($columns | Where-Object role -eq 'client-presentation-resource').Count -eq 12)
Add-Assertion 'Server gameplay fields remain the default majority' (
    @($columns | Where-Object role -eq 'server-gameplay-rule').Count -eq 277)
Add-Assertion 'No decoded config or row values enter evidence' (
    -not $evidence.guarantees.decoded_client_config_or_field_values_emitted_to_evidence -and
    -not $evidence.guarantees.legacy_sources_mutated -and
    $evidence.guarantees.client_copy_does_not_grant_runtime_authority)
Add-Assertion 'Generator has no Secret or legacy-write input' (
    $generator -notmatch '(?i)CredRead|runtime-key|password|Set-Content.+ClientCode|WriteAllText.+ClientCode' -and
    $generator -match 'ReadAllBytes' -and $generator -match '\[switch\]\$Check')

$localCheck = $null
if ($VerifyLegacySources) {
    $checkOutput = & $generatorPath -WorkspaceRoot $WorkspaceRoot `
        -RebuildRoot $root -Check
    $localCheck = $checkOutput | ConvertFrom-Json
    Add-Assertion 'Legacy source and client-config deterministic recheck passes' (
        $localCheck.result -eq 'PASS' -and $localCheck.registry_match -and
        $localCheck.evidence_match -and
        $localCheck.summary.security_sensitive_client_authority_violations -eq 0)
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-08'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    verify_legacy_sources = [bool]$VerifyLegacySources
    summary = $summary
    local_check = $localCheck
    assertions = $assertions
} | ConvertTo-Json -Depth 30
if ($failed.Count -gt 0) { exit 1 }
