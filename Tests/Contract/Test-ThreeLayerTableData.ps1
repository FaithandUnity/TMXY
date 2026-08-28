[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$RequireLocalExports
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$evidencePath = Join-Path $root 'Data\Inventory\p2-06-three-layer-data.json'
$p204Path = Join-Path $root 'Data\Inventory\p2-04-current-table-inventory.json'
$schemaContractPath = Join-Path $root 'Contracts\data-schema\table-schema-v1.schema.json'
$generatorPath = Join-Path $root 'Tools\TMXY.Table\New-ThreeLayerTableData.ps1'
$docPath = Join-Path $root 'Docs\Formats\THREE-LAYER-TABLE-DATA.md'
$outputRoot = Join-Path $root 'Data\Exports\P2-06'
$assertions = [Collections.Generic.List[object]]::new()

function Add-Assertion {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name; result = if ($Passed) { 'PASS' } else { 'FAIL' }; detail = $Detail
        })
}
function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-JsonlMetrics([string]$Path) {
    $reader = [IO.StreamReader]::new(
        $Path, [Text.UTF8Encoding]::new($false, $true), $false)
    $count = 0
    $firstValid = $false
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($count -eq 0) {
                try {
                    $first = $line | ConvertFrom-Json
                    $firstValid = @($first.psobject.Properties).Count -gt 0
                }
                catch { $firstValid = $false }
            }
            ++$count
        }
    }
    finally { $reader.Dispose() }
    [pscustomobject]@{ lines = $count; first_json_valid = $firstValid }
}

foreach ($path in @($evidencePath, $p204Path, $schemaContractPath, $generatorPath, $docPath)) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" (Test-Path -LiteralPath $path -PathType Leaf)
}
$evidenceText = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8
$evidence = $evidenceText | ConvertFrom-Json
$p204 = Get-Content -LiteralPath $p204Path -Raw -Encoding UTF8 | ConvertFrom-Json
$contract = Get-Content -LiteralPath $schemaContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
$topLevelParameters = $generator.Substring(0, $generator.IndexOf('Set-StrictMode'))

Add-Assertion 'P2-06 evidence complete' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-Assertion 'P2-04 evidence SHA bound' ($evidence.source.inventory_sha256 -eq (Get-Sha256 $p204Path))
Add-Assertion 'Source population retained' ($evidence.summary.source_tables -eq 338 -and
    $evidence.summary.active_tables -eq 225 -and $evidence.summary.historical_shadows -eq 113)
Add-Assertion 'Three files per active table' ($evidence.summary.generated_tables -eq 225 -and
    $evidence.summary.generated_files -eq 675)
Add-Assertion 'All active rows retained' ($evidence.summary.rows -eq 214885 -and
    $evidence.summary.raw_bytes -eq 29658173)
Add-Assertion 'Content-set digest present' ([string]$evidence.output.content_set_sha256 -cmatch '^[0-9a-f]{64}$')
Add-Assertion 'Deterministic rerun proven' ([bool]$evidence.output.previous_export_match -and
    [bool]$evidence.reproduction.prior_content_set_match)
Add-Assertion 'Bulk output excluded from Git' ([bool]$evidence.output.git_ignored -and
    $evidence.output.local_root -eq 'Data/Exports/P2-06')
Add-Assertion 'No plaintext in committed evidence' (-not $evidence.runtime_key_binding.raw_key_emitted -and
    -not $evidence.runtime_key_binding.plaintext_or_field_values_emitted_to_evidence -and
    -not $evidence.guarantees.field_identifiers_or_values_in_committed_evidence)
Add-Assertion 'No command-line or environment key input' (-not $evidence.runtime_key_binding.command_line_or_environment_input -and
    $topLevelParameters -notmatch '(?im)\$(key|password|secretvalue)\b' -and
    $generator -notmatch '(?i)GetEnvironmentVariable|\$env:')
Add-Assertion 'Credential provider is the sole key source' ($generator -match 'CredRead' -and
    $generator -match 'Read-StoredKey' -and $generator -match 'expectedKeyFingerprint')
Add-Assertion 'Schema contract is YAML-compatible JSON object' ($contract.type -eq 'object' -and
    @($contract.required).Count -ge 12)
Add-Assertion 'Semantic authority remains deferred' ([bool]$evidence.guarantees.semantic_types_are_provisional -and
    [bool]$evidence.guarantees.ownership_is_pending_p2_08 -and
    [bool]$evidence.guarantees.keys_and_references_are_pending_p2_07)

$tables = @($evidence.tables)
$active = @($tables | Where-Object { $_.lifecycle -eq 'active' })
$historical = @($tables | Where-Object { $_.lifecycle -eq 'historical-shadow' })
Add-Assertion 'Evidence has one record per source table' ($tables.Count -eq 338 -and
    @($tables.source_path | Sort-Object -Unique).Count -eq 338)
Add-Assertion 'Active records all generated' (@($active | Where-Object { -not $_.generated }).Count -eq 0)
Add-Assertion 'Historical records are replacement-only' (@($historical | Where-Object {
            $_.generated -or -not $_.replacement_path }).Count -eq 0)
Add-Assertion 'Stable normalized column IDs only' (@($active | Where-Object {
            @($_.candidate_key_columns | Where-Object { $_ -notmatch '^c[0-9]{4}$' }).Count -gt 0
        }).Count -eq 0)
Add-Assertion 'Every observed column has one type' ([long](
        $evidence.summary.inferred_column_types.boolean +
        $evidence.summary.inferred_column_types.int64 +
        $evidence.summary.inferred_column_types.decimal +
        $evidence.summary.inferred_column_types.string) -eq [long]$evidence.summary.columns)
$delimiterCounts = @{}
foreach ($entry in @($evidence.summary.delimiter_counts)) {
    $delimiterCounts[[string]$entry.delimiter] = [int]$entry.tables
}
Add-Assertion 'All table delimiters classified' ($delimiterCounts['comma'] -eq 222 -and
    $delimiterCounts['asterisk'] -eq 1 -and $delimiterCounts['single-column'] -eq 2)
$quest = @($active | Where-Object source_path -eq 'Table/quest_table.tbl')
Add-Assertion 'Quest asterisk compatibility parsed' ($quest.Count -eq 1 -and
    $quest[0].delimiter -eq 'asterisk' -and $quest[0].header_columns -eq 78 -and
    $quest[0].modal_columns -eq 78 -and $quest[0].minimum_columns -eq 78 -and
    $quest[0].maximum_columns -eq 79 -and $quest[0].columns -eq 79)
Add-Assertion 'Logical names have no extension residue' (@($active | Where-Object {
            $_.logical_name.EndsWith('.', [StringComparison]::Ordinal)
        }).Count -eq 0)

$localPresent = Test-Path -LiteralPath $outputRoot -PathType Container
if ($RequireLocalExports) { Add-Assertion 'Local exports required and present' $localPresent }
if ($localPresent) {
    $manifestPath = Join-Path $outputRoot 'manifest.json'
    Add-Assertion 'Local manifest present' (Test-Path -LiteralPath $manifestPath -PathType Leaf)
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Assertion 'Local manifest hash bound' ((Get-Sha256 $manifestPath) -eq $evidence.output.manifest_sha256)
    Add-Assertion 'Local content-set bound' ($manifest.content_set_sha256 -eq $evidence.output.content_set_sha256)
    $files = @(Get-ChildItem -LiteralPath $outputRoot -Recurse -File)
    Add-Assertion 'Local file population exact' ($files.Count -eq 676)
    $hashFailures = 0
    $schemaFailures = 0
    $rowFailures = 0
    $bomFailures = 0
    foreach ($table in $active) {
        $logical = [string]$table.logical_name
        $tableRoot = Join-Path $outputRoot ('tables\' + $logical.Replace('/', '\'))
        $rawPath = Join-Path $tableRoot 'raw.csv'
        $normalizedPath = Join-Path $tableRoot 'normalized.jsonl'
        $schemaPath = Join-Path $tableRoot 'schema.yaml'
        foreach ($file in @($table.files)) {
            $actual = Join-Path $outputRoot ([string]$file.path).Replace('/', '\')
            if (-not (Test-Path -LiteralPath $actual -PathType Leaf) -or
                (Get-Sha256 $actual) -ne $file.sha256 -or
                (Get-Item -LiteralPath $actual).Length -ne $file.bytes) { ++$hashFailures }
        }
        try {
            $schemaBytes = [IO.File]::ReadAllBytes($schemaPath)
            if ($schemaBytes.Length -ge 3 -and $schemaBytes[0] -eq 0xef -and
                $schemaBytes[1] -eq 0xbb -and $schemaBytes[2] -eq 0xbf) { ++$bomFailures }
            $schema = [Text.UTF8Encoding]::new($false, $true).GetString($schemaBytes) |
                ConvertFrom-Json
            if ($schema.schema_version -ne 1 -or $schema.logical_name -ne $logical -or
                $schema.raw.file -ne 'raw.csv' -or $schema.normalized.file -ne 'normalized.jsonl' -or
                $schema.ownership.classification -ne 'pending-p2-08' -or
                $schema.references.status -ne 'pending-p2-07' -or
                @($schema.columns).Count -ne $table.columns -or
                @($schema.old_to_new).Count -ne $table.columns) { ++$schemaFailures }
        }
        catch { ++$schemaFailures }
        $normalizedBytes = [IO.File]::ReadAllBytes($normalizedPath)
        if ($normalizedBytes.Length -ge 3 -and $normalizedBytes[0] -eq 0xef -and
            $normalizedBytes[1] -eq 0xbb -and $normalizedBytes[2] -eq 0xbf) { ++$bomFailures }
        $jsonl = Get-JsonlMetrics $normalizedPath
        if ($jsonl.lines -ne $table.rows -or -not $jsonl.first_json_valid) { ++$rowFailures }
    }
    Add-Assertion 'All local file hashes and sizes verified' ($hashFailures -eq 0) "$hashFailures failures"
    Add-Assertion 'All local schemas parse and satisfy required shape' ($schemaFailures -eq 0) "$schemaFailures failures"
    Add-Assertion 'All normalized JSONL row counts verified' ($rowFailures -eq 0) "$rowFailures failures"
    Add-Assertion 'Normalized and schema files are BOM-free' ($bomFailures -eq 0) "$bomFailures failures"
}
else {
    Add-Assertion 'Hosted contract permits absent ignored bulk output' (-not $RequireLocalExports)
}

$failures = @($assertions | Where-Object result -eq 'FAIL')
$report = [pscustomobject][ordered]@{
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    task = 'P2-06'; completion_criteria_satisfied = $failures.Count -eq 0
    assertions = $assertions.Count; passed = $assertions.Count - $failures.Count
    failed = $failures.Count; local_exports = if ($localPresent) { 'verified' } else { 'not-present' }
    details = @($assertions)
}
$report | ConvertTo-Json -Depth 5
if ($failures.Count -gt 0) { throw 'P2-06 three-layer table data contract failed.' }
