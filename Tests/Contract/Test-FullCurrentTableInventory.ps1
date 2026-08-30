[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$toolPath = Join-Path $root 'Tools\TMXY.Table\New-FullCurrentTableInventory.ps1'
$evidencePath = Join-Path $root 'Data\Inventory\p2-04-current-table-inventory.json'
$capturePath = Join-Path $root 'Data\BuildBaseline\p1-09-runtime-key-capture.json'
foreach ($path in @($toolPath, $evidencePath, $capturePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P2-04 required artifact is missing: $path"
    }
}

$assertions = [System.Collections.Generic.List[object]]::new()
function Add-Assertion {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed
    )
    $assertions.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed })
}

$toolText = Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
foreach ($fragment in @(
        'CredRead',
        'FromBase64String',
        'TransformFinalBlock',
        'Get-SupersedingTablePath',
        'primary_key_prefix_search_limit',
        'raw_key_emitted = $false',
        'plaintext_emitted = $false',
        'field_identifiers_emitted = $false',
        '[System.Array]::Clear')) {
    Add-Assertion -Name "tool contains $fragment" -Passed (
        $toolText.Contains($fragment, [System.StringComparison]::Ordinal))
}
foreach ($fragment in @('$env:', 'GetEnvironmentVariable', 'Write-Host', 'Write-Verbose')) {
    Add-Assertion -Name "tool excludes $fragment" -Passed (-not
        $toolText.Contains($fragment, [System.StringComparison]::OrdinalIgnoreCase))
}

$evidenceBytes = [System.IO.File]::ReadAllBytes($evidencePath)
try { $evidenceSha = [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($evidenceBytes)).ToLowerInvariant() }
finally { [System.Array]::Clear($evidenceBytes, 0, $evidenceBytes.Length) }
$captureSha = (Get-FileHash -LiteralPath $capturePath -Algorithm SHA256).Hash.ToLowerInvariant()
$report = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$tables = @($report.tables)
$active = @($tables | Where-Object lifecycle -eq 'active')
$historical = @($tables | Where-Object lifecycle -eq 'historical-shadow')
$unresolved = @($tables | Where-Object lifecycle -eq 'unresolved')

Add-Assertion -Name 'result PASS' -Passed ([string]$report.result -eq 'PASS')
Add-Assertion -Name 'task P2-04' -Passed ([string]$report.task -eq 'P2-04')
Add-Assertion -Name 'task complete' -Passed ([string]$report.task_status -eq 'COMPLETE')
Add-Assertion -Name 'completion true' -Passed ([bool]$report.completion_criteria_satisfied)
Add-Assertion -Name '338 report entries' -Passed ($tables.Count -eq 338)
Add-Assertion -Name '338 unique paths' -Passed (
    @($tables.path | Sort-Object -Unique).Count -eq 338)
Add-Assertion -Name '225 active tables' -Passed ($active.Count -eq 225)
Add-Assertion -Name '113 historical shadows' -Passed ($historical.Count -eq 113)
Add-Assertion -Name 'zero unresolved tables' -Passed ($unresolved.Count -eq 0)
Add-Assertion -Name 'frozen ciphertext bytes' -Passed (
    [long]$report.source.population.ciphertext_bytes -eq 40444128L)
Add-Assertion -Name 'frozen executable bytes' -Passed (
    [long]$report.source.executable.bytes -eq 5160960L)
Add-Assertion -Name 'frozen executable hash' -Passed (
    [string]$report.source.executable.sha256 -eq
        '7087dfa64bedeb8c9a5dfc4518f46261d163136b5bd97f5071f2c5a12cb29a4b')
Add-Assertion -Name 'capture evidence hash bound' -Passed (
    [string]$report.runtime_key_binding.p1_09_capture_evidence_sha256 -eq $captureSha)
Add-Assertion -Name 'key fingerprint bound' -Passed (
    [string]$report.runtime_key_binding.fingerprint -eq
        'cf760550b7af6c220331b258db1df781fe567221eb7c53fbfc65aca522085887')
Add-Assertion -Name 'raw key not emitted' -Passed (-not
    [bool]$report.runtime_key_binding.raw_key_emitted)
Add-Assertion -Name 'plaintext not emitted' -Passed (-not
    [bool]$report.runtime_key_binding.plaintext_emitted)
Add-Assertion -Name 'field identifiers not emitted' -Passed (-not
    [bool]$report.runtime_key_binding.field_identifiers_emitted)
Add-Assertion -Name 'buffers cleared' -Passed (
    [bool]$report.runtime_key_binding.in_memory_buffers_cleared)
Add-Assertion -Name '225 decoded' -Passed ([int]$report.summary.decoded -eq 225)
Add-Assertion -Name '113 classified failures' -Passed (
    [int]$report.summary.decode_failures_classified -eq 113)
Add-Assertion -Name 'active row total' -Passed (
    [long]$report.summary.active_rows -eq 214885L)
Add-Assertion -Name 'active payload total' -Passed (
    [long]$report.summary.active_payload_bytes -eq 29658173L)

function Get-SummaryCount {
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $match = @($Items | Where-Object { [string]$_.$Property -eq $Value })
    if ($match.Count -ne 1) { return -1 }
    return [int]$match[0].tables
}

Add-Assertion -Name '165 ASCII tables' -Passed (
    (Get-SummaryCount -Items @($report.summary.encoding_counts) -Property encoding `
        -Value ascii) -eq 165)
Add-Assertion -Name '59 GBK tables' -Passed (
    (Get-SummaryCount -Items @($report.summary.encoding_counts) -Property encoding `
        -Value gbk) -eq 59)
Add-Assertion -Name '1 UTF-8 table' -Passed (
    (Get-SummaryCount -Items @($report.summary.encoding_counts) -Property encoding `
        -Value utf8) -eq 1)
Add-Assertion -Name '181 fixed-column tables' -Passed (
    (Get-SummaryCount -Items @($report.summary.schema_counts) -Property classification `
        -Value 'fixed-columns') -eq 181)
Add-Assertion -Name '44 variable-column tables' -Passed (
    (Get-SummaryCount -Items @($report.summary.schema_counts) -Property classification `
        -Value 'variable-columns') -eq 44)

$groups = @($report.groups)
foreach ($expected in @(
        @('CLSVShare', 113, 113, 0),
        @('Table/help', 1, 0, 1),
        @('Table/local', 2, 1, 1),
        @('Table/Regions', 111, 0, 111),
        @('Table/root', 111, 111, 0))) {
    $match = @($groups | Where-Object group -eq $expected[0])
    Add-Assertion -Name "group $($expected[0])" -Passed (
        $match.Count -eq 1 -and [int]$match[0].files -eq [int]$expected[1] -and
        [int]$match[0].active -eq [int]$expected[2] -and
        [int]$match[0].historical_shadow -eq [int]$expected[3] -and
        [int]$match[0].unresolved -eq 0)
}

$activeComplete = @($active | Where-Object {
        -not $_.decode.success -or $_.decode.failure -ne 'none' -or
        $_.encoding.classification -notin @('ascii', 'gbk', 'utf8') -or
        $null -eq $_.schema.rows -or $null -eq $_.schema.header_columns -or
        [int]$_.schema.header_columns -le 0 -or
        -not [string]$_.schema.primary_key.classification -or
        -not [bool]$_.source_version.exact_content_version_known -or
        $null -ne $_.replacement
    }).Count -eq 0
Add-Assertion -Name 'every active row has complete inventory' -Passed $activeComplete

$historicalComplete = @($historical | Where-Object {
        $_.decode.success -or $_.decode.failure -eq 'none' -or
        $_.encoding.classification -ne 'unavailable' -or
        $null -ne $_.schema.rows -or $null -ne $_.schema.header_columns -or
        $_.schema.primary_key.classification -ne 'not-available-decode-failed' -or
        $null -eq $_.replacement -or -not $_.replacement.active_decode_verified -or
        -not $_.replacement.newer_than_historical -or
        [bool]$_.source_version.exact_content_version_known
    }).Count -eq 0
Add-Assertion -Name 'every historical row is unavailable with a verified replacement' `
    -Passed $historicalComplete
Add-Assertion -Name 'all hashes are lowercase SHA-256' -Passed (
    @($tables | Where-Object { [string]$_.sha256 -notmatch '^[0-9a-f]{64}$' }).Count -eq 0)
Add-Assertion -Name 'all ciphertext byte counts positive' -Passed (
    @($tables | Where-Object { [long]$_.ciphertext_bytes -le 0 }).Count -eq 0)
Add-Assertion -Name 'active source build frozen' -Passed (
    @($active | Where-Object { $_.source_version.content_version -ne 'qy-3.0.0.413' }).Count -eq 0)
Add-Assertion -Name 'historical source version explicit' -Passed (
    @($historical | Where-Object {
            $_.source_version.content_version -ne 'unknown-pre-qy-3.0.0.413'
        }).Count -eq 0)

$arena = @($active | Where-Object path -eq 'CLSVShare/ArenaLevel.tbl')
$item = @($active | Where-Object path -eq 'CLSVShare/item_table.tbl')
$skill = @($active | Where-Object path -eq 'CLSVShare/skill_table.tbl')
$quest = @($active | Where-Object path -eq 'Table/quest_table.tbl')
$historicalQuest = @($historical |
    Where-Object path -eq 'Table/Regions/quest_table.tbl')
Add-Assertion -Name 'UTF-8 outlier identified' -Passed (
    $arena.Count -eq 1 -and $arena[0].encoding.classification -eq 'utf8' -and
    [int]$arena[0].schema.rows -eq 6 -and [int]$arena[0].schema.header_columns -eq 4)
Add-Assertion -Name 'item table inventory frozen' -Passed (
    $item.Count -eq 1 -and [int]$item[0].schema.rows -eq 29223 -and
    [int]$item[0].schema.header_columns -eq 95 -and
    $item[0].schema.primary_key.classification -eq 'unique-first-field-candidate')
Add-Assertion -Name 'skill table inventory frozen' -Passed (
    $skill.Count -eq 1 -and [int]$skill[0].schema.rows -eq 23227 -and
    [int]$skill[0].schema.header_columns -eq 65 -and
    $skill[0].schema.primary_key.classification -eq
        'composite-key-required-beyond-prefix-search')
Add-Assertion -Name 'variable quest table inventory frozen' -Passed (
    $quest.Count -eq 1 -and [int]$quest[0].schema.rows -eq 5943 -and
    -not [bool]$quest[0].schema.fixed_column_count)
Add-Assertion -Name 'historical quest replacement linked' -Passed (
    $historicalQuest.Count -eq 1 -and
    $historicalQuest[0].replacement.path -eq 'Table/quest_table.tbl')
Add-Assertion -Name 'interpretation records physical rows' -Passed (
    [bool]$report.interpretation.row_count_excludes_header -and
    [bool]$report.interpretation.column_counts_are_comma_delimited_physical_widths)
Add-Assertion -Name 'primary keys explicitly non-authoritative' -Passed (
    [bool]$report.interpretation.primary_keys_are_candidates_not_authoritative_schema -and
    [int]$report.interpretation.primary_key_prefix_search_limit -eq 8)

$failed = @($assertions | Where-Object { -not $_.passed })
$passed = $failed.Count -eq 0
$contract = [pscustomobject][ordered]@{
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P2-04'
    completion_criteria_satisfied = $passed
    evidence_path = 'Data/Inventory/p2-04-current-table-inventory.json'
    evidence_sha256 = $evidenceSha
    assertions = $assertions.Count
    failed_assertions = @($failed | ForEach-Object { $_.name })
    raw_key_required_for_contract_test = $false
    plaintext_emitted = $false
}
$contract | ConvertTo-Json -Depth 4
if (-not $passed) { throw 'P2-04 full current-table inventory contract failed.' }
