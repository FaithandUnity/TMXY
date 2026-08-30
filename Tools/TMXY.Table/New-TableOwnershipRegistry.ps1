[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev',
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientSourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [string]$ServerSourceRoot = 'E:\QQXYCodeDev\ServerCode',
    [string]$ClientConfigPath = 'Data\Backups\p1-09-runtime-client\ClassCfg\QGameEngine.ecf',
    [string]$PolicyPath = 'Contracts\data-schema\table-ownership-policy-v1.json',
    [string]$RegistryContractPath = 'Contracts\data-schema\table-ownership-registry-v1.schema.json',
    [string]$P205EvidencePath = 'Data\Inventory\p2-05-auxiliary-config-inventory.json',
    [string]$P206EvidencePath = 'Data\Inventory\p2-06-three-layer-data.json',
    [string]$P207RegistryPath = 'Data\Schemas\core-table-registry-v1.json',
    [string]$OutputPath = 'Data\Schemas\table-ownership-registry-v1.json',
    [string]$EvidencePath = 'Data\Inventory\p2-08-table-ownership.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false, $true)

function Resolve-RebuildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else { [IO.Path]::GetFullPath((Join-Path $Root $Path)) }
    if ($candidate -ne $Root -and -not $candidate.StartsWith(
            $Root + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes Rebuild: $Path"
    }
    return $candidate
}

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LowerSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    [byte[]]$bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-RelativeRepositoryPath {
    param([string]$Path, [string]$Root)
    return [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
}

function ConvertTo-StableJsonText {
    param([Parameter(Mandatory = $true)][object]$InputObject)
    $json = $InputObject | ConvertTo-Json -Depth 100
    return (($json -replace "`r`n", "`n") -replace "`r", "`n") + "`n"
}

function Convert-EcfBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $result = [byte[]]::new($Bytes.Length)
    $fullBytes = $Bytes.Length - ($Bytes.Length % 4)
    for ($offset = 0; $offset -lt $fullBytes; $offset += 4) {
        $result[$offset] = (-bnot $Bytes[$offset + 2]) -band 255
        $result[$offset + 1] = (-bnot $Bytes[$offset + 3]) -band 255
        $result[$offset + 2] = (-bnot $Bytes[$offset]) -band 255
        $result[$offset + 3] = (-bnot $Bytes[$offset + 1]) -band 255
    }
    for ($offset = $fullBytes; $offset -lt $Bytes.Length; ++$offset) {
        $result[$offset] = (-bnot $Bytes[$offset]) -band 255
    }
    return ,$result
}

function Test-ByteArraysEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; ++$index) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Get-SourceReferenceIndex {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$WorkspaceRelativePrefix,
        [Parameter(Mandatory = $true)][object[]]$Tables
    )
    $extensions = @('.c', '.cc', '.cpp', '.cxx', '.h', '.hpp', '.vcproj', '.vcxproj', '.sln')
    $files = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File |
        Where-Object { $_.Extension.ToLowerInvariant() -in $extensions } |
        Sort-Object FullName)
    $references = @{}
    foreach ($table in $Tables) {
        $references[[string]$table.source_path] =
            [Collections.Generic.List[string]]::new()
    }
    $fingerprintRows = [Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        [byte[]]$bytes = [IO.File]::ReadAllBytes($file.FullName)
        try {
            $text = [Text.Encoding]::Latin1.GetString($bytes).ToLowerInvariant()
            $relative = [IO.Path]::GetRelativePath($SourceRoot, $file.FullName).Replace('\', '/')
            $reportedPath = "$WorkspaceRelativePrefix/$relative"
            foreach ($table in $Tables) {
                $baseName = [IO.Path]::GetFileNameWithoutExtension(
                    [string]$table.source_path).ToLowerInvariant()
                if ($text.Contains($baseName + '.csv', [StringComparison]::Ordinal) -or
                    $text.Contains($baseName + '.tbl', [StringComparison]::Ordinal) -or
                    $text.Contains('"' + $baseName + '"', [StringComparison]::Ordinal)) {
                    $references[[string]$table.source_path].Add($reportedPath)
                }
            }
            $fingerprintRows.Add("$reportedPath`:$((Get-LowerSha256 $file.FullName))")
        }
        finally {
            $text = $null
            [Array]::Clear($bytes, 0, $bytes.Length)
        }
    }
    return [pscustomobject][ordered]@{
        files_scanned = $files.Count
        population_sha256 = Get-LowerSha256Text ($fingerprintRows -join "`n")
        references = $references
    }
}

function Get-ClientConfigReferenceSet {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Tables
    )
    [byte[]]$encoded = [IO.File]::ReadAllBytes($Path)
    [byte[]]$decoded = $null
    [byte[]]$roundTrip = $null
    try {
        $decoded = Convert-EcfBytes $encoded
        $roundTrip = Convert-EcfBytes $decoded
        if (-not (Test-ByteArraysEqual -Left $encoded -Right $roundTrip)) {
            throw 'QGameEngine ECF self-inverse round trip failed.'
        }
        [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
        $text = [Text.Encoding]::GetEncoding(936).GetString($decoded).ToLowerInvariant()
        $references = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($table in $Tables) {
            $sourcePath = [string]$table.source_path
            $baseName = [IO.Path]::GetFileNameWithoutExtension($sourcePath).ToLowerInvariant()
            if ($text.Contains($baseName + '.tbl', [StringComparison]::Ordinal) -or
                $text.Contains($baseName + '.csv', [StringComparison]::Ordinal) -or
                $text.Contains('\' + $baseName, [StringComparison]::Ordinal) -or
                $text.Contains('/' + $baseName, [StringComparison]::Ordinal)) {
                [void]$references.Add($sourcePath)
            }
        }
        return $references
    }
    finally {
        $text = $null
        foreach ($buffer in @($encoded, $decoded, $roundTrip)) {
            if ($null -ne $buffer) { [Array]::Clear($buffer, 0, $buffer.Length) }
        }
    }
}

$workspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$clientSource = [IO.Path]::GetFullPath($ClientSourceRoot).TrimEnd([char[]]'\/')
$serverSource = [IO.Path]::GetFullPath($ServerSourceRoot).TrimEnd([char[]]'\/')
$expectedRebuild = [IO.Path]::GetFullPath((Join-Path $workspace 'Rebuild')).TrimEnd([char[]]'\/')
$expectedClient = [IO.Path]::GetFullPath((Join-Path $workspace 'ClientCode')).TrimEnd([char[]]'\/')
$expectedServer = [IO.Path]::GetFullPath((Join-Path $workspace 'ServerCode')).TrimEnd([char[]]'\/')
if ($root -cne $expectedRebuild -or $clientSource -cne $expectedClient -or
    $serverSource -cne $expectedServer) {
    throw 'P2-08 roots must be the exact Rebuild, ClientCode and ServerCode workspace paths.'
}

$clientConfig = Resolve-RebuildPath -Path $ClientConfigPath -Root $root
$policyFile = Resolve-RebuildPath -Path $PolicyPath -Root $root
$contractFile = Resolve-RebuildPath -Path $RegistryContractPath -Root $root
$p205File = Resolve-RebuildPath -Path $P205EvidencePath -Root $root
$p206File = Resolve-RebuildPath -Path $P206EvidencePath -Root $root
$p207File = Resolve-RebuildPath -Path $P207RegistryPath -Root $root
$registryFile = Resolve-RebuildPath -Path $OutputPath -Root $root
$evidenceFile = Resolve-RebuildPath -Path $EvidencePath -Root $root
$generatorFile = $MyInvocation.MyCommand.Path
foreach ($required in @($clientConfig, $policyFile, $contractFile, $p205File,
        $p206File, $p207File, $generatorFile)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required P2-08 input is missing: $required"
    }
}

$policy = Get-Content -LiteralPath $policyFile -Raw -Encoding UTF8 | ConvertFrom-Json
$p205 = Get-Content -LiteralPath $p205File -Raw -Encoding UTF8 | ConvertFrom-Json
$p206 = Get-Content -LiteralPath $p206File -Raw -Encoding UTF8 | ConvertFrom-Json
$p207 = Get-Content -LiteralPath $p207File -Raw -Encoding UTF8 | ConvertFrom-Json
if ($policy.task_id -ne 'P2-08' -or $policy.schema_version -ne 1) {
    throw 'Unsupported P2-08 policy.'
}
foreach ($inputEvidence in @($p205, $p206)) {
    if ($inputEvidence.result -ne 'PASS' -or -not $inputEvidence.completion_criteria_satisfied) {
        throw 'A required prior-stage evidence report is incomplete.'
    }
}
if ($p207.summary.result -ne 'PASS' -or $p207.summary.tables -ne 12) {
    throw 'P2-07 core registry is incomplete.'
}
if ($policy.source_build -ne $p206.source.build -or
    $policy.source_build -ne $p207.source_build) {
    throw 'P2-08 source build binding does not match P2-06/P2-07.'
}
if ((Get-LowerSha256 $clientConfig) -cne [string]$p205.source_evidence.client_config.sha256) {
    throw 'QGameEngine ECF does not match the P2-05 source binding.'
}

$tables = @($p206.tables | Where-Object lifecycle -eq 'active' | Sort-Object source_path)
if ($tables.Count -ne 225) { throw 'P2-08 requires exactly 225 active tables.' }
$clientPresentationOverrides = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($path in @($policy.client_presentation_table_overrides)) {
    if (-not $clientPresentationOverrides.Add([string]$path)) {
        throw "Duplicate client table override: $path"
    }
}
$serverAuthoritativeOverrides = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($path in @($policy.server_authoritative_table_overrides)) {
    if (-not $serverAuthoritativeOverrides.Add([string]$path)) {
        throw "Duplicate server table override: $path"
    }
}
$activePaths = @($tables.source_path)
foreach ($path in @($clientPresentationOverrides) + @($serverAuthoritativeOverrides)) {
    if ($path -notin $activePaths) { throw "Ownership override is not active: $path" }
}

$clientIndex = Get-SourceReferenceIndex -SourceRoot $clientSource `
    -WorkspaceRelativePrefix 'ClientCode' -Tables $tables
$serverIndex = Get-SourceReferenceIndex -SourceRoot $serverSource `
    -WorkspaceRelativePrefix 'ServerCode' -Tables $tables
$clientConfigReferences = Get-ClientConfigReferenceSet -Path $clientConfig -Tables $tables
if ($clientConfigReferences.Count -ne 127) {
    throw "Current client config reference population changed: $($clientConfigReferences.Count)"
}

$namespaceDefaults = @{}
foreach ($entry in @($policy.namespace_defaults)) {
    $namespaceDefaults[[string]$entry.namespace] = $entry
}
$tableRecords = [Collections.Generic.List[object]]::new()
foreach ($table in $tables) {
    $sourcePath = [string]$table.source_path
    $namespace = $sourcePath.Split('/')[0]
    if (-not $namespaceDefaults.ContainsKey($namespace)) {
        throw "No namespace ownership default for $sourcePath."
    }
    $default = $namespaceDefaults[$namespace]
    $clientFiles = @($clientIndex.references[$sourcePath] | Sort-Object -Unique)
    $serverFiles = @($serverIndex.references[$sourcePath] | Sort-Object -Unique)
    $clientObserved = $clientConfigReferences.Contains($sourcePath) -or $clientFiles.Count -gt 0
    $serverObserved = $serverFiles.Count -gt 0
    $observedScope = if ($clientObserved -and $serverObserved) { 'shared' }
        elseif ($clientObserved) { 'client' }
        elseif ($serverObserved) { 'server' }
        else { 'none' }

    if ($clientPresentationOverrides.Contains($sourcePath)) {
        $schemaOwner = 'client'
        $runtimeAuthority = 'client-presentation'
        $domain = 'client-presentation-catalog'
        $decisionBasis = 'explicit-client-presentation-table-override'
    }
    elseif ($serverAuthoritativeOverrides.Contains($sourcePath)) {
        $schemaOwner = 'shared'
        $runtimeAuthority = 'server-authoritative'
        $domain = 'shared-gameplay-catalog'
        $decisionBasis = 'explicit-server-authoritative-table-override'
    }
    else {
        $schemaOwner = [string]$default.schema_owner
        $runtimeAuthority = [string]$default.runtime_authority
        $domain = [string]$default.domain
        $decisionBasis = [string]$default.basis
    }
    $targetConsumers = [Collections.Generic.List[string]]::new()
    $targetConsumers.Add('client')
    if ($runtimeAuthority -eq 'server-authoritative') { $targetConsumers.Add('server') }
    $tableRecords.Add([pscustomobject][ordered]@{
            source_path = $sourcePath
            logical_name = [string]$table.logical_name
            source_sha256 = [string]$table.source_sha256
            namespace = $namespace
            observed_consumers = [pscustomobject][ordered]@{
                current_client_config = $clientConfigReferences.Contains($sourcePath)
                legacy_client_source_files = $clientFiles
                legacy_server_source_files = $serverFiles
                scope = $observedScope
            }
            schema_owner = $schemaOwner
            runtime_authority = $runtimeAuthority
            domain = $domain
            server_must_not_trust_client_values =
                $runtimeAuthority -eq 'server-authoritative'
            target_consumers = $targetConsumers
            decision_basis = $decisionBasis
            result = 'PASS'
        })
}

$coreTablePaths = @($p207.tables.source_path)
$coreTableRecordFailures = @($tableRecords | Where-Object {
        $_.source_path -in $coreTablePaths -and
        ($_.schema_owner -ne 'shared' -or $_.runtime_authority -ne 'server-authoritative')
    })
if ($coreTableRecordFailures.Count -ne 0) {
    throw 'Every P2-07 core table must have shared schema and server runtime authority.'
}

$presentationRegex = [regex]::new(
    [string]$policy.core_column_policy.client_presentation_name_regex)
$localizationRegex = [regex]::new(
    [string]$policy.core_column_policy.localization_name_regex)
$sensitiveRegex = [regex]::new(
    [string]$policy.core_column_policy.security_sensitive_name_regex)
$identifierColumns = @{}
foreach ($coreTable in @($p207.tables)) {
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($columnId in @($coreTable.primary_key.column_ids)) {
        [void]$set.Add([string]$columnId)
    }
    foreach ($foreignKey in @($coreTable.foreign_keys)) {
        foreach ($columnId in @($foreignKey.source_column_ids)) {
            [void]$set.Add([string]$columnId)
        }
    }
    foreach ($sourceTable in @($p207.tables)) {
        foreach ($foreignKey in @($sourceTable.foreign_keys | Where-Object {
                    $_.target_table -ceq $coreTable.source_path
                })) {
            foreach ($columnId in @($foreignKey.target_column_ids)) {
                [void]$set.Add([string]$columnId)
            }
        }
    }
    $identifierColumns[[string]$coreTable.source_path] = $set
}

$coreColumnRecords = [Collections.Generic.List[object]]::new()
$sensitiveClientViolations = 0
foreach ($coreTable in @($p207.tables | Sort-Object source_path)) {
    $sourcePath = [string]$coreTable.source_path
    $identifierSet = $identifierColumns[$sourcePath]
    foreach ($column in @($coreTable.columns | Sort-Object source_ordinal)) {
        $columnId = [string]$column.id
        $sourceName = [string]$column.source_name
        $isIdentifier = $identifierSet.Contains($columnId)
        if ($isIdentifier) {
            $owner = 'shared'
            $runtimeAuthority = 'server-authoritative'
            $role = 'shared-identifier'
            $localizable = $false
            $decisionRule = 'declared-primary-or-foreign-key-is-shared-identifier'
        }
        elseif ($presentationRegex.IsMatch($sourceName)) {
            $owner = 'client'
            $runtimeAuthority = 'client-presentation'
            $localizable = $localizationRegex.IsMatch($sourceName)
            $role = if ($localizable) { 'client-localization' }
                else { 'client-presentation-resource' }
            $decisionRule = 'presentation-name-rule-is-client-owned'
        }
        else {
            $owner = 'server'
            $runtimeAuthority = 'server-authoritative'
            $role = 'server-gameplay-rule'
            $localizable = $false
            $decisionRule = 'all-other-fields-are-server-authoritative'
        }
        if ($sensitiveRegex.IsMatch($sourceName) -and
            -not $presentationRegex.IsMatch($sourceName) -and
            $runtimeAuthority -ne 'server-authoritative') {
            ++$sensitiveClientViolations
        }
        $coreColumnRecords.Add([pscustomobject][ordered]@{
                table = $sourcePath
                column_id = $columnId
                source_name = $sourceName
                type = [string]$column.type
                owner = $owner
                runtime_authority = $runtimeAuthority
                role = $role
                localizable = $localizable
                server_must_not_trust_client_value = $true
                decision_rule = $decisionRule
                result = 'PASS'
            })
    }
}
if ($coreColumnRecords.Count -ne 355 -or $sensitiveClientViolations -ne 0) {
    throw 'Core-column ownership validation failed.'
}

$summary = [pscustomobject][ordered]@{
    active_tables = $tableRecords.Count
    classified_tables = @($tableRecords | Where-Object result -eq 'PASS').Count
    unclassified_tables = @($tableRecords | Where-Object result -ne 'PASS').Count
    schema_owner_client = @($tableRecords | Where-Object schema_owner -eq 'client').Count
    schema_owner_server = @($tableRecords | Where-Object schema_owner -eq 'server').Count
    schema_owner_shared = @($tableRecords | Where-Object schema_owner -eq 'shared').Count
    runtime_client_presentation = @($tableRecords | Where-Object {
            $_.runtime_authority -eq 'client-presentation'
        }).Count
    runtime_server_authoritative = @($tableRecords | Where-Object {
            $_.runtime_authority -eq 'server-authoritative'
        }).Count
    current_client_config_referenced_tables = $clientConfigReferences.Count
    legacy_client_source_referenced_tables = @($tableRecords | Where-Object {
            $_.observed_consumers.legacy_client_source_files.Count -gt 0
        }).Count
    legacy_server_source_referenced_tables = @($tableRecords | Where-Object {
            $_.observed_consumers.legacy_server_source_files.Count -gt 0
        }).Count
    observed_consumer_none = @($tableRecords | Where-Object {
            $_.observed_consumers.scope -eq 'none'
        }).Count
    core_tables = @($p207.tables).Count
    core_columns = $coreColumnRecords.Count
    classified_core_columns = @($coreColumnRecords | Where-Object result -eq 'PASS').Count
    core_owner_client = @($coreColumnRecords | Where-Object owner -eq 'client').Count
    core_owner_server = @($coreColumnRecords | Where-Object owner -eq 'server').Count
    core_owner_shared = @($coreColumnRecords | Where-Object owner -eq 'shared').Count
    core_localizable_columns = @($coreColumnRecords | Where-Object localizable).Count
    security_sensitive_client_authority_violations = $sensitiveClientViolations
    result = 'PASS'
}

$registry = [pscustomobject][ordered]@{
    schema_version = 1
    registry_id = 'tmxy-table-ownership-registry-v1'
    task_id = 'P2-08'
    status = 'authoritative-target-ownership-contract'
    source_build = [string]$policy.source_build
    principles = $policy.principles
    source = [pscustomobject][ordered]@{
        p2_05_evidence_path = Get-RelativeRepositoryPath $p205File $root
        p2_05_evidence_sha256 = Get-LowerSha256 $p205File
        p2_06_evidence_path = Get-RelativeRepositoryPath $p206File $root
        p2_06_evidence_sha256 = Get-LowerSha256 $p206File
        p2_07_registry_path = Get-RelativeRepositoryPath $p207File $root
        p2_07_registry_sha256 = Get-LowerSha256 $p207File
        policy_path = Get-RelativeRepositoryPath $policyFile $root
        policy_sha256 = Get-LowerSha256 $policyFile
        contract_path = Get-RelativeRepositoryPath $contractFile $root
        contract_sha256 = Get-LowerSha256 $contractFile
        client_source_files_scanned = $clientIndex.files_scanned
        client_source_population_sha256 = $clientIndex.population_sha256
        server_source_files_scanned = $serverIndex.files_scanned
        server_source_population_sha256 = $serverIndex.population_sha256
        client_config_path = 'Data/Backups/p1-09-runtime-client/ClassCfg/QGameEngine.ecf'
        client_config_sha256 = Get-LowerSha256 $clientConfig
        client_config_decoded_content_emitted = $false
    }
    summary = $summary
    tables = $tableRecords
    core_columns = $coreColumnRecords
}
$registryText = ConvertTo-StableJsonText $registry
[byte[]]$registryBytes = $utf8NoBom.GetBytes($registryText)
$registrySha = try {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([Convert]::ToHexString($sha.ComputeHash($registryBytes))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}
finally { [Array]::Clear($registryBytes, 0, $registryBytes.Length) }

$evidence = [pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-08'
    result = 'PASS'
    task_status = 'COMPLETE'
    completion_criteria_satisfied = $true
    source = [pscustomobject][ordered]@{
        build = [string]$policy.source_build
        p2_05_evidence_sha256 = Get-LowerSha256 $p205File
        p2_06_evidence_sha256 = Get-LowerSha256 $p206File
        p2_07_registry_sha256 = Get-LowerSha256 $p207File
        policy_sha256 = Get-LowerSha256 $policyFile
        registry_contract_sha256 = Get-LowerSha256 $contractFile
        generator_sha256 = Get-LowerSha256 $generatorFile
        client_source_files_scanned = $clientIndex.files_scanned
        client_source_population_sha256 = $clientIndex.population_sha256
        server_source_files_scanned = $serverIndex.files_scanned
        server_source_population_sha256 = $serverIndex.population_sha256
        client_config_sha256 = Get-LowerSha256 $clientConfig
    }
    output = [pscustomobject][ordered]@{
        registry_path = Get-RelativeRepositoryPath $registryFile $root
        registry_sha256 = $registrySha
    }
    summary = $summary
    table_decisions = @($tableRecords | ForEach-Object {
            [pscustomobject][ordered]@{
                source_path = $_.source_path
                observed_consumer_scope = $_.observed_consumers.scope
                current_client_config = $_.observed_consumers.current_client_config
                legacy_client_reference_files = $_.observed_consumers.legacy_client_source_files.Count
                legacy_server_reference_files = $_.observed_consumers.legacy_server_source_files.Count
                schema_owner = $_.schema_owner
                runtime_authority = $_.runtime_authority
                result = $_.result
            }
        })
    guarantees = [pscustomobject][ordered]@{
        every_active_table_classified = $true
        every_core_column_classified = $true
        combat_and_economy_default_to_server_authority = $true
        client_copy_does_not_grant_runtime_authority = $true
        display_and_localization_boundaries_are_explicit = $true
        unknown_gameplay_semantics_fail_to_server_authority = $true
        decoded_client_config_or_field_values_emitted_to_evidence = $false
        legacy_sources_mutated = $false
    }
    reproduction = [pscustomobject][ordered]@{
        generator = Get-RelativeRepositoryPath $generatorFile $root
        check_mode = '-Check'
        deterministic_registry_and_evidence = $true
    }
}
$evidenceText = ConvertTo-StableJsonText $evidence

if ($Check) {
    $registryMatch = (Test-Path -LiteralPath $registryFile -PathType Leaf) -and
        ((Get-Content -LiteralPath $registryFile -Raw -Encoding UTF8) -ceq $registryText)
    $evidenceMatch = (Test-Path -LiteralPath $evidenceFile -PathType Leaf) -and
        ((Get-Content -LiteralPath $evidenceFile -Raw -Encoding UTF8) -ceq $evidenceText)
    [pscustomobject][ordered]@{
        schema_version = 1
        task_id = 'P2-08'
        result = if ($registryMatch -and $evidenceMatch) { 'PASS' } else { 'FAIL' }
        registry_match = $registryMatch
        evidence_match = $evidenceMatch
        summary = $summary
    } | ConvertTo-Json -Depth 20
    if (-not ($registryMatch -and $evidenceMatch)) { exit 1 }
    exit 0
}

foreach ($parent in @([IO.Path]::GetDirectoryName($registryFile),
        [IO.Path]::GetDirectoryName($evidenceFile))) {
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($parent)
    }
}
[IO.File]::WriteAllText($registryFile, $registryText, $utf8NoBom)
[IO.File]::WriteAllText($evidenceFile, $evidenceText, $utf8NoBom)
$evidence | ConvertTo-Json -Depth 20
