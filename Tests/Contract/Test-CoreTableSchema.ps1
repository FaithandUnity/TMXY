[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$RequireLocalExports
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\core-table-policy-v1.json'
$contractPath = Join-Path $root 'Contracts\data-schema\core-table-registry-v1.schema.json'
$registryPath = Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-07-core-table-schema.json'
$p206Path = Join-Path $root 'Data\Inventory\p2-06-three-layer-data.json'
$generatorPath = Join-Path $root 'Tools\TMXY.Table\New-CoreTableSchema.ps1'
$docPath = Join-Path $root 'Docs\Formats\CORE-TABLE-SCHEMA.md'
$exportRoot = Join-Path $root 'Data\Exports\P2-06\tables'
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

$requiredFiles = @(
    $policyPath,
    $contractPath,
    $registryPath,
    $evidencePath,
    $p206Path,
    $generatorPath,
    $docPath
)
foreach ($path in $requiredFiles) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    $report = [pscustomobject][ordered]@{
        schema_version = 1
        task_id = 'P2-07'
        result = 'FAIL'
        completion_criteria_satisfied = $false
        assertions = $assertions
    }
    $report | ConvertTo-Json -Depth 20
    exit 1
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$p206 = Get-Content -LiteralPath $p206Path -Raw -Encoding UTF8 | ConvertFrom-Json
$generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8

Add-Assertion 'Evidence completes P2-07' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-Assertion 'Registry is authoritative for frozen import build' (
    $registry.schema_version -eq 1 -and
    $registry.registry_id -eq 'tmxy-core-table-registry-v1' -and
    $registry.task_id -eq 'P2-07' -and
    $registry.status -eq 'authoritative-frozen-build-import-contract' -and
    $registry.scope.authority -eq 'frozen-source-build-import-only')
Add-Assertion 'P2-06 source build and content are bound' (
    $registry.source_build -eq $policy.source_build -and
    $registry.source_build -eq $p206.source.build -and
    $registry.source.p2_06_evidence_sha256 -eq (Get-Sha256 $p206Path) -and
    $registry.source.p2_06_content_set_sha256 -eq $p206.output.content_set_sha256 -and
    $evidence.source.p2_06_evidence_sha256 -eq (Get-Sha256 $p206Path) -and
    $evidence.source.p2_06_content_set_sha256 -eq $p206.output.content_set_sha256)
Add-Assertion 'Policy contract and generator hashes are bound' (
    $registry.source.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $registry.source.contract_sha256 -eq (Get-Sha256 $contractPath) -and
    $evidence.source.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.source.registry_contract_sha256 -eq (Get-Sha256 $contractPath) -and
    $evidence.source.generator_sha256 -eq (Get-Sha256 $generatorPath))
Add-Assertion 'Registry output hash is bound' (
    $evidence.output.registry_path -eq 'Data/Schemas/core-table-registry-v1.json' -and
    $evidence.output.registry_sha256 -eq (Get-Sha256 $registryPath))
Add-Assertion 'JSON Schema contract is draft 2020-12' (
    $contract.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $contract.type -eq 'object' -and
    $contract.additionalProperties -eq $false -and
    $contract.properties.tables.minItems -eq 12 -and
    $contract.properties.tables.maxItems -eq 12)

$summary = $registry.summary
Add-Assertion 'Frozen core population is exact' (
    $summary.tables -eq 12 -and
    $summary.physical_rows -eq 87844 -and
    $summary.canonical_rows -eq 87044 -and
    $summary.columns -eq 355 -and
    $summary.columns_with_type_and_rule -eq 355)
Add-Assertion 'All keys and references are declared' (
    $summary.primary_keys -eq 12 -and
    $summary.foreign_keys -eq 14 -and
    $summary.active_reference_rows -eq 55361 -and
    $summary.inactive_reference_rows -eq 129154)
Add-Assertion 'All validation violation counts are zero' (
    $summary.type_violations -eq 0 -and
    $summary.range_violations -eq 0 -and
    $summary.key_violations -eq 0 -and
    $summary.dangling_references -eq 0 -and
    $summary.result -eq 'PASS')
Add-Assertion 'Evidence and registry summaries agree' (
    ($summary | ConvertTo-Json -Compress) -ceq
        ($evidence.summary | ConvertTo-Json -Compress))

$tables = @($registry.tables)
$policyTables = @($policy.tables)
$policyForeignKeys = @($policy.foreign_keys)
Add-Assertion 'Core paths are unique and match policy' (
    $tables.Count -eq 12 -and
    @($tables.source_path | Sort-Object -Unique).Count -eq 12 -and
    (($tables.source_path | Sort-Object) -join "`n") -ceq
        (($policyTables.source_path | Sort-Object) -join "`n"))
Add-Assertion 'Every table has PASS primary-key validation' (
    @($tables | Where-Object {
            $_.result -ne 'PASS' -or
            $_.primary_key.result -ne 'PASS' -or
            $_.primary_key.null_violations -ne 0 -or
            $_.primary_key.divergent_duplicate_groups -ne 0
        }).Count -eq 0)
Add-Assertion 'Every declared key column exists' (
    @($tables | Where-Object {
            $columnIds = @($_.columns.id)
            @($_.primary_key.column_ids | Where-Object { $_ -notin $columnIds }).Count -gt 0
        }).Count -eq 0)

$profession = @($tables | Where-Object source_path -eq 'CLSVShare/Profession_lvl.tbl')
Add-Assertion 'Profession duplicates canonicalize only identical rows' (
    $profession.Count -eq 1 -and
    $profession[0].physical_rows -eq 16000 -and
    $profession[0].canonical_rows -eq 15200 -and
    $profession[0].primary_key.duplicate_policy -eq 'collapse-identical-rows' -and
    $profession[0].primary_key.duplicate_groups -eq 700 -and
    $profession[0].primary_key.duplicate_occurrences -eq 800 -and
    $profession[0].primary_key.divergent_duplicate_groups -eq 0)
Add-Assertion 'All other tables reject duplicate keys' (
    @($tables | Where-Object {
            $_.source_path -ne 'CLSVShare/Profession_lvl.tbl' -and
            ($_.primary_key.duplicate_policy -ne 'reject' -or
                $_.primary_key.duplicate_occurrences -ne 0)
        }).Count -eq 0)

$columnFailures = [Collections.Generic.List[string]]::new()
$foreignKeyFailures = [Collections.Generic.List[string]]::new()
$allForeignKeys = [Collections.Generic.List[object]]::new()
foreach ($table in $tables) {
    if ($table.physical_rows -ne
        (@($table.columns | Select-Object -First 1)[0].null_count +
            @($table.columns | Select-Object -First 1)[0].non_null_count)) {
        $columnFailures.Add("$($table.source_path):row-accounting")
    }
    foreach ($column in @($table.columns)) {
        if ($column.id -notmatch '^c[0-9]{4}$' -or
            $column.type -notin @('boolean', 'int64', 'decimal', 'string') -or
            $column.null_count + $column.non_null_count -ne $table.physical_rows -or
            $column.type_violations -ne 0 -or $column.range_violations -ne 0 -or
            $column.change_policy -ne 'schema-version-bump-and-full-revalidation') {
            $columnFailures.Add("$($table.source_path):$($column.id):base")
            continue
        }
        $kind = [string]$column.bounds.kind
        if ($column.non_null_count -eq 0) {
            if ($kind -ne 'no-observed-non-null-values') {
                $columnFailures.Add("$($table.source_path):$($column.id):empty")
            }
        }
        elseif ($column.type -in @('int64', 'decimal')) {
            if ($kind -ne 'numeric-inclusive' -or
                $column.bounds.minimum -gt $column.bounds.maximum) {
                $columnFailures.Add("$($table.source_path):$($column.id):numeric")
            }
        }
        elseif ($column.type -eq 'string') {
            if ($kind -ne 'utf8-byte-length-inclusive' -or
                $column.bounds.minimum_utf8_bytes -gt
                    $column.bounds.maximum_utf8_bytes) {
                $columnFailures.Add("$($table.source_path):$($column.id):string")
            }
        }
        elseif ($kind -ne 'boolean-domain') {
            $columnFailures.Add("$($table.source_path):$($column.id):boolean")
        }
    }
    foreach ($foreignKey in @($table.foreign_keys)) {
        $allForeignKeys.Add($foreignKey)
        $target = @($tables | Where-Object source_path -ceq $foreignKey.target_table)
        if ($target.Count -ne 1 -or
            $foreignKey.result -ne 'PASS' -or
            -not $foreignKey.type_compatible -or
            $foreignKey.dangling_rows -ne 0 -or
            $foreignKey.active_rows + $foreignKey.inactive_rows -ne $table.physical_rows -or
            @($foreignKey.source_column_ids | Where-Object {
                    $_ -notin @($table.columns.id)
                }).Count -gt 0 -or
            ($target.Count -eq 1 -and
                @($foreignKey.target_column_ids | Where-Object {
                        $_ -notin @($target[0].columns.id)
                    }).Count -gt 0)) {
            $foreignKeyFailures.Add([string]$foreignKey.id)
        }
        if ($target.Count -eq 1 -and $foreignKey.target_key_mode -eq 'primary-key' -and
            (($foreignKey.target_column_ids -join ',') -cne
                ($target[0].primary_key.column_ids -join ','))) {
            $foreignKeyFailures.Add("$($foreignKey.id):target-key")
        }
    }
}
Add-Assertion 'Every one of 355 columns has type and range rule' (
    @($tables.columns).Count -eq 355 -and $columnFailures.Count -eq 0)
Add-Assertion 'All 14 foreign keys are type-safe and zero-dangling' (
    $allForeignKeys.Count -eq 14 -and
    @($allForeignKeys.id | Sort-Object -Unique).Count -eq 14 -and
    $foreignKeyFailures.Count -eq 0)
Add-Assertion 'Policy and registry foreign-key IDs match' (
    (($allForeignKeys.id | Sort-Object) -join "`n") -ceq
        (($policyForeignKeys.id | Sort-Object) -join "`n"))
Add-Assertion 'Deferred candidates are explicit, not silently accepted' (
    @($policy.deferred_reference_candidates).Count -eq 3 -and
    $evidence.deferred_reference_candidates -eq 3)
Add-Assertion 'No row payload is present in committed evidence' (
    -not $evidence.guarantees.raw_rows_or_field_values_emitted_to_evidence -and
    $evidence.guarantees.all_core_tables_have_authoritative_primary_key -and
    $evidence.guarantees.all_core_columns_have_type_and_validation_rule -and
    $evidence.guarantees.all_declared_foreign_keys_have_zero_dangling_rows)
Add-Assertion 'Ownership remains assigned to P2-08' (
    $evidence.guarantees.ownership_remains_p2_08)
Add-Assertion 'Generator consumes normalized exports without secrets' (
    $generator -notmatch '(?i)CredRead|GetEnvironmentVariable|runtime-key|password' -and
    $generator -match 'normalized\.jsonl' -and
    $generator -match '\[switch\]\$Check')

$localCheck = $null
if ($RequireLocalExports) {
    Add-Assertion 'Local P2-06 exports are present' (
        Test-Path -LiteralPath $exportRoot -PathType Container)
    if (Test-Path -LiteralPath $exportRoot -PathType Container) {
        $checkOutput = & $generatorPath -RebuildRoot $root -Check
        $localCheck = $checkOutput | ConvertFrom-Json
        Add-Assertion 'Local deterministic full-data revalidation passes' (
            $localCheck.result -eq 'PASS' -and
            $localCheck.registry_match -and
            $localCheck.evidence_match -and
            $localCheck.summary.dangling_references -eq 0)
    }
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
$report = [pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-07'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    authoritative_scope = 'frozen-source-build-import-only'
    require_local_exports = [bool]$RequireLocalExports
    summary = $summary
    local_check = $localCheck
    assertions = $assertions
}
$report | ConvertTo-Json -Depth 30
if ($failed.Count -gt 0) { exit 1 }
