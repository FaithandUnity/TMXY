[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyLegacySources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\full-asset-inventory-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\full-asset-inventory-v1.schema.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-12-full-asset-inventory.json'
$catalogPath = Join-Path $root 'Data\Exports\P2-12\p2-12-full-asset-inventory.jsonl'
$generatorPath = Join-Path $root 'Tools\TMXY.AssetInventory\New-FullAssetInventory.ps1'
$scannerPath = Join-Path $root 'Tools\TMXY.AssetInventory\apps\asset_inventory_main.cpp'
$docPath = Join-Path $root 'Docs\Formats\FULL-ASSET-INVENTORY.md'
$fixturePath = Join-Path $root 'Tests\Fixtures\AssetInventory\smoke-manifest.tsv'
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

$required = @($policyPath, $schemaPath, $evidencePath, $generatorPath, $scannerPath,
    $docPath, $fixturePath)
foreach ($path in $required) {
    Add-Assertion "Required file $([IO.Path]::GetFileName($path))" `
        (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject][ordered]@{
        schema_version = 1; task_id = 'P2-12'; result = 'FAIL'
        completion_criteria_satisfied = $false; assertions = $assertions
    } | ConvertTo-Json -Depth 10
    exit 1
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
$scanner = Get-Content -LiteralPath $scannerPath -Raw -Encoding UTF8
$document = Get-Content -LiteralPath $docPath -Raw -Encoding UTF8

Add-Assertion 'Evidence completes P2-12' ($evidence.result -eq 'PASS' -and
    $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-Assertion 'Policy is frozen to the target build and eight families' (
    $policy.schema_version -eq 1 -and $policy.task_id -eq 'P2-12' -and
    $policy.source_build -eq 'qy-3.0.0.413' -and @($policy.target_extensions).Count -eq 8)
Add-Assertion 'JSON Schema contract is draft 2020-12 and closed' (
    $schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and
    $schema.properties.input.properties.files.const -eq 40090 -and
    $schema.properties.summary.properties.families.minItems -eq 8)
Add-Assertion 'Frozen Manifest population is exact' (
    $evidence.input.client_version -eq '3.0.0.413' -and
    $evidence.input.files -eq 40090 -and $evidence.input.bytes -eq 8882019027 -and
    $evidence.input.source_copy_policy -eq 'reference_only' -and
    [string]$evidence.input.manifest_sha256 -match '^[0-9a-f]{64}$' -and
    [string]$evidence.input.selected_set_sha256 -match '^[0-9a-f]{64}$')
Add-Assertion 'Every target has a closed structure state' (
    $evidence.summary.files -eq 40090 -and
    $evidence.summary.structurally_valid -eq 39290 -and
    $evidence.summary.unresolved_structure -eq 786 -and
    $evidence.summary.corrupt -eq 14 -and $evidence.summary.unsupported -eq 0 -and
    ($evidence.summary.structurally_valid + $evidence.summary.unresolved_structure +
        $evidence.summary.corrupt) -eq 40090)

$families = @($evidence.summary.families)
Add-Assertion 'All eight family counts and bytes match policy' (
    $families.Count -eq 8 -and @($families.family | Sort-Object -Unique).Count -eq 8 -and
    @($families | Where-Object {
            $expected = $policy.expected_families.PSObject.Properties[$_.family].Value
            $_.files -ne $expected.files -or $_.bytes -ne $expected.bytes -or
            ($_.pass + $_.unresolved + $_.corrupt) -ne $_.files
        }).Count -eq 0)
Add-Assertion 'TER ZIF WAV and MP3 are completely valid' (
    @($families | Where-Object family -in @('ter', 'zif', 'wav', 'mp3') | Where-Object {
            $_.pass -ne $_.files -or $_.unresolved -ne 0 -or $_.corrupt -ne 0
        }).Count -eq 0)
Add-Assertion 'Headerless descriptor uncertainty is not mislabeled corrupt' (
    @($families | Where-Object family -eq 'qtx')[0].unresolved -eq 756 -and
    @($families | Where-Object family -eq 'qtx')[0].corrupt -eq 0 -and
    @($families | Where-Object family -eq 'anim')[0].unresolved -eq 30 -and
    @($families | Where-Object family -eq 'anim')[0].corrupt -eq 0)
Add-Assertion 'Independent structural failures are isolated to SM and SKEM' (
    @($families | Where-Object family -eq 'sm')[0].corrupt -eq 12 -and
    @($families | Where-Object family -eq 'skem')[0].corrupt -eq 2 -and
    @($families | Where-Object { $_.family -notin @('sm', 'skem') -and $_.corrupt -ne 0 }).Count -eq 0)
Add-Assertion 'Package ambiguity remains explicit' (
    @($families | Where-Object family -eq 'qtx')[0].package_ambiguous_equivalent -eq 3517 -and
    @($families | Where-Object family -eq 'qtx')[0].package_ambiguous_divergent -eq 391 -and
    @($families | Where-Object family -eq 'anim')[0].package_ambiguous_divergent -eq 8)

Add-Assertion 'Ignored catalog is source-bound and contains no payload' (
    $evidence.catalog.path -eq 'Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl' -and
    -not $evidence.catalog.tracked -and $evidence.catalog.lines -eq 40090 -and
    [string]$evidence.catalog.sha256 -match '^[0-9a-f]{64}$' -and
    -not $evidence.catalog.contains_payload_bytes -and
    -not $evidence.catalog.contains_decoded_assets)
Add-Assertion 'Policy and JSON Schema hashes are bound by evidence' (
    $evidence.contracts.policy -eq 'Contracts/data-schema/full-asset-inventory-policy-v1.json' -and
    $evidence.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.contracts.schema -eq 'Contracts/data-schema/full-asset-inventory-v1.schema.json' -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath))
if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
    Add-Assertion 'Local ignored catalog hash line count and bytes match evidence' (
        (Get-Sha256 $catalogPath) -eq $evidence.catalog.sha256 -and
        (Get-Item -LiteralPath $catalogPath).Length -eq $evidence.catalog.bytes -and
        @([IO.File]::ReadLines($catalogPath)).Count -eq 40090)
}
Add-Assertion 'Evidence dependencies remain hash-bound' (
    @($evidence.dependencies.PSObject.Properties | Where-Object {
        [string]$_.Value -notmatch '^[0-9a-f]{64}$'
        }).Count -eq 0 -and @($evidence.dependencies.PSObject.Properties).Count -eq 7 -and
    $evidence.implementation.dependency_binding -eq
        'stable task result, completion state, and source fingerprint')
Add-Assertion 'Locked builder and isolation are fail-closed' (
    $evidence.builder.expected_id -eq $evidence.builder.actual_id -and
    $evidence.builder.user -eq 'tmxy' -and $evidence.isolation.source_mount -eq 'read-only' -and
    $evidence.isolation.client_mount -eq 'read-only' -and $evidence.isolation.network -eq 'none' -and
    $evidence.isolation.root_filesystem -eq 'read-only' -and
    $evidence.isolation.capabilities -eq 'none' -and $evidence.isolation.no_new_privileges)
Add-Assertion 'Production readers and exact Package candidates are used' (
    $scanner -match 'LegacyTextureDescriptorReader' -and $scanner -match 'SmReader' -and
    $scanner -match 'SkemReader' -and $scanner -match 'AnimReader' -and
    $scanner -match 'TerReader' -and $scanner -match 'ambiguous_divergent')
Add-Assertion 'Generator has no write path to legacy inputs or network access' (
    $generator -match "'--network', 'none'" -and $generator -match 'client_mount = ''read-only''' -and
    $generator -notmatch '(?i)WriteAll(Text|Bytes).+Client|Set-Content.+Client|Remove-Item.+Client')
Add-Assertion 'Documentation preserves unresolved and corrupt evidence semantics' (
    $document -match '40,090' -and $document -match 'UNRESOLVED' -and
    $document -match '12 SM and 2 SKEM' -and $document -match 'deletes or repairs\s+nothing')

$localCheck = $null
if ($VerifyLegacySources) {
    $localCheck = & $generatorPath -RebuildRoot $root -Check | ConvertFrom-Json
    Add-Assertion 'Full deterministic legacy-source recheck passes' (
        $localCheck.result -eq 'PASS' -and $localCheck.completion_criteria_satisfied -and
        $localCheck.catalog.sha256 -eq $evidence.catalog.sha256 -and
        $localCheck.summary.corrupt -eq 14 -and $localCheck.summary.unresolved_structure -eq 786)
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-12'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    verify_legacy_sources = [bool]$VerifyLegacySources
    summary = $evidence.summary
    local_check = $localCheck
    assertions = $assertions
} | ConvertTo-Json -Depth 20
if ($failed.Count -gt 0) { exit 1 }
