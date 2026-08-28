[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyGenerated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$failures = [Collections.Generic.List[string]]::new()
$assertions = [Collections.Generic.List[object]]::new()

function Add-A([string]$Name, [bool]$Passed) {
    $assertions.Add([pscustomobject][ordered]@{
        name = $Name
        result = if ($Passed) { 'PASS' } else { 'FAIL' }
        detail = ''
    })
    if (-not $Passed) { $failures.Add($Name) }
}

function Get-Sha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$policyPath = Join-Path $root 'Contracts\data-schema\protocol-codegen-policy-v1.json'
$contractPath = Join-Path $root 'Contracts\data-schema\core-data-model-v1.schema.json'
$modelPath = Join-Path $root 'Contracts\data-schema\core-data-model-v1.json'
$backendPath = Join-Path $root 'Contracts\generated\cpp\tmxy\contracts\data\core_data_types.generated.hpp'
$uePath = Join-Path $root 'Contracts\generated\ue\TMXYCoreDataTypes.generated.hpp'
$evidencePath = Join-Path $root 'Data\Inventory\p2-17-protocol-codegen.json'
$generatorPath = Join-Path $root 'Tools\TMXY.ProtocolGen\protocol_gen.py'
$wrapperPath = Join-Path $root 'Tools\TMXY.ProtocolGen\New-ProtocolTypes.ps1'
$backendTestPath = Join-Path $root 'Backend\modules\content\tests\generated_types_test.cpp'
$ueCompilePath = Join-Path $root 'Apps\UEClient\Source\TMXYCore\Private\TMXYCoreDataTypesCompile.cpp'
$registryPath = Join-Path $root 'Data\Schemas\core-table-registry-v1.json'
$auditPath = Join-Path $root 'Data\Inventory\p2-11-id-limit-audit.json'

$required = @($policyPath, $contractPath, $modelPath, $backendPath, $uePath, $evidencePath,
    $generatorPath, $wrapperPath, $backendTestPath, $ueCompilePath, $registryPath, $auditPath)
foreach ($path in $required) { Add-A "Required file $([IO.Path]::GetFileName($path))" (Test-Path -LiteralPath $path -PathType Leaf) }

$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$modelJson = Get-Content -LiteralPath $modelPath -Raw
$model = $modelJson | ConvertFrom-Json -Depth 100
$evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json -Depth 30
$backend = Get-Content -LiteralPath $backendPath -Raw
$ue = Get-Content -LiteralPath $uePath -Raw
$generator = Get-Content -LiteralPath $generatorPath -Raw
$wrapper = Get-Content -LiteralPath $wrapperPath -Raw
$backendTest = Get-Content -LiteralPath $backendTestPath -Raw
$ueCompile = Get-Content -LiteralPath $ueCompilePath -Raw

Add-A 'Generated model validates against its closed JSON Schema' ([bool](Test-Json -Json $modelJson -SchemaFile $contractPath -ErrorAction SilentlyContinue))
Add-A 'Evidence completes P2-17' ($evidence.result -eq 'PASS' -and $evidence.task_status -eq 'COMPLETE' -and $evidence.completion_criteria_satisfied)
Add-A 'One schema covers 12 models and all 355 fields' (@($model.models).Count -eq 12 -and @($model.models.fields).Count -eq 355 -and $evidence.summary.source_fields -eq 355)
Add-A 'All 16 identity components are represented' (@($model.models.fields | Where-Object role -eq 'identity-component').Count -eq 16 -and $evidence.summary.identity_components -eq 16)
Add-A 'Identity policy forbids narrowing and uses uint64 numerics' ($policy.identity.narrowing -eq 'forbidden' -and $policy.identity.numeric_storage -eq 'uint64' -and $evidence.summary.numeric_identity_storage -eq 'uint64')
Add-A 'Source model binds exact P2-07 and P2-11 inputs' ($model.source.core_table_registry_sha256 -eq (Get-Sha $registryPath) -and $model.source.id_limit_audit_sha256 -eq (Get-Sha $auditPath))
Add-A 'Generated output hashes and sizes are frozen' ($evidence.outputs.schema.sha256 -eq (Get-Sha $modelPath) -and $evidence.outputs.backend.sha256 -eq (Get-Sha $backendPath) -and $evidence.outputs.ue.sha256 -eq (Get-Sha $uePath) -and $evidence.outputs.backend.bytes -eq (Get-Item $backendPath).Length -and $evidence.outputs.ue.bytes -eq (Get-Item $uePath).Length)
$schemaSha = Get-Sha $modelPath
Add-A 'Both targets name the identical source schema digest' ($backend -match [regex]::Escape($schemaSha) -and $ue -match [regex]::Escape($schemaSha) -and $evidence.target_contracts.same_schema_sha256 -eq $schemaSha)
Add-A 'Backend receives domain-specific IDs and explicit optionals' ($backend -match 'struct ItemTableId final' -and $backend -match 'struct SkillTableId final' -and $backend -match 'std::uint64_t C0001' -and $backend -match 'std::optional<std::string>')
Add-A 'UE receives matching IDs and explicit optionals' ($ue -match 'struct FItemTableId final' -and $ue -match 'struct FSkillTableId final' -and $ue -match 'uint64 C0001' -and $ue -match 'TOptional<FString>')
Add-A 'Backend and UE compilation anchors consume generated types' ($backendTest -match 'core_data_types[.]generated[.]hpp' -and $backendTest -match 'ItemTableId' -and $ueCompile -match 'TMXYCoreDataTypes[.]generated[.]hpp' -and $ueCompile -match 'ModelCount')
Add-A 'Generator is deterministic and contains no row-value export' ($generator -match 'canonical_json' -and $generator -match 'narrowing' -and $generator -notmatch 'normalized[.]jsonl' -and $generator -notmatch 'minimum|maximum')
Add-A 'Generation runs isolated in the locked builder' ($wrapper -match "'--network', 'none'" -and $wrapper -match "'--read-only'" -and $wrapper -match "'--cap-drop', 'ALL'" -and $evidence.reproduction.repository_mount -eq 'read-only')
Add-A 'Tracked P2-17 artifacts contain no exact extrema or legacy lines' ($modelJson -notmatch 'minimum|maximum|active_distinct|reserved_distinct|source_line' -and $backend -notmatch 'minimum|maximum' -and $ue -notmatch 'minimum|maximum')
Add-A 'Policy and implementation hashes are bound' ($model.policy.sha256 -eq (Get-Sha $policyPath) -and $evidence.inputs.contract_sha256 -eq (Get-Sha $contractPath) -and $evidence.implementation.generator_sha256 -eq (Get-Sha $generatorPath) -and $evidence.implementation.wrapper_sha256 -eq (Get-Sha $wrapperPath))

$local = $null
if ($VerifyGenerated) {
    $local = & $wrapperPath -RebuildRoot $root -Check | ConvertFrom-Json -Depth 30
    Add-A 'Byte-identical isolated regeneration passes' ($local.result -eq 'PASS' -and $local.completion_criteria_satisfied -and $local.outputs.schema.sha256 -eq $schemaSha)
}

$passed = $failures.Count -eq 0
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-17'
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $passed
    verify_generated = [bool]$VerifyGenerated
    summary = $evidence.summary
    outputs = $evidence.outputs
    local_check = $local
    assertions = @($assertions)
} | ConvertTo-Json -Depth 30
if (-not $passed) { throw "P2-17 protocol codegen contract failed: $($failures -join '; ')" }
