[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$PolicyPath = 'Contracts\data-schema\core-table-policy-v1.json',
    [string]$RegistryContractPath = 'Contracts\data-schema\core-table-registry-v1.schema.json',
    [string]$P206EvidencePath = 'Data\Inventory\p2-06-three-layer-data.json',
    [string]$ExportRoot = 'Data\Exports\P2-06\tables',
    [string]$OutputPath = 'Data\Schemas\core-table-registry-v1.json',
    [string]$EvidencePath = 'Data\Inventory\p2-07-core-table-schema.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$invariant = [Globalization.CultureInfo]::InvariantCulture
$utf8NoBom = [Text.UTF8Encoding]::new($false, $true)

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $Root $Path))
    }
    if ($candidate -ne $Root -and -not $candidate.StartsWith(
            $Root + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes the rebuild repository: $Path"
    }
    return $candidate
}

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RelativeRepositoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    return [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
}

function Read-JsonLines {
    param([Parameter(Mandatory = $true)][string]$Path)
    $rows = [Collections.Generic.List[object]]::new()
    $reader = [IO.StreamReader]::new($Path, [Text.UTF8Encoding]::new($false, $true), $false)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -eq 0) { throw "Blank JSONL record in $Path" }
            $rows.Add(($line | ConvertFrom-Json))
        }
    }
    finally {
        $reader.Dispose()
    }
    return $rows.ToArray()
}

function Get-ColumnValue {
    param(
        [Parameter(Mandatory = $true)][object]$Row,
        [Parameter(Mandatory = $true)][string]$ColumnId
    )
    $property = $Row.psobject.Properties[$ColumnId]
    if ($null -eq $property) { throw "Normalized row has no $ColumnId property." }
    return $property.Value
}

function Get-ValueToken {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '<null>' }
    if ($Value -is [bool]) { return if ($Value) { 'true' } else { 'false' } }
    if ($Value -is [string]) { return 's:' + $Value }
    return 'n:' + [Convert]::ToString($Value, $invariant)
}

function Get-KeyToken {
    param(
        [Parameter(Mandatory = $true)][object]$Row,
        [Parameter(Mandatory = $true)][string[]]$ColumnIds
    )
    [string[]]$tokens = [string[]]::new($ColumnIds.Count)
    for ($index = 0; $index -lt $ColumnIds.Count; ++$index) {
        $tokens[$index] = Get-ValueToken (
            Get-ColumnValue -Row $Row -ColumnId $ColumnIds[$index])
    }
    return ($tokens -join [char]31)
}

function Test-ObservedType {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Type
    )
    if ($null -eq $Value) { return $true }
    switch ($Type) {
        'boolean' { return $Value -is [bool] }
        'string' { return $Value -is [string] }
        'int64' {
            if ($Value -is [bool] -or $Value -is [string]) { return $false }
            [long]$parsed = 0
            return [long]::TryParse(
                [Convert]::ToString($Value, $invariant),
                [Globalization.NumberStyles]::Integer,
                $invariant,
                [ref]$parsed)
        }
        'decimal' {
            if ($Value -is [bool] -or $Value -is [string]) { return $false }
            [decimal]$parsed = 0
            return [decimal]::TryParse(
                [Convert]::ToString($Value, $invariant),
                [Globalization.NumberStyles]::Float,
                $invariant,
                [ref]$parsed)
        }
        default { throw "Unsupported core-table type: $Type" }
    }
}

function Get-ColumnRule {
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][object]$SourceColumn
    )
    $nullCount = 0
    $nonNullCount = 0
    $typeViolations = 0
    $numericMinimum = $null
    $numericMaximum = $null
    $stringMinimum = [int]::MaxValue
    $stringMaximum = 0

    foreach ($row in $Rows) {
        $value = Get-ColumnValue -Row $row -ColumnId ([string]$SourceColumn.id)
        if ($null -eq $value) {
            ++$nullCount
            continue
        }
        ++$nonNullCount
        if (-not (Test-ObservedType -Value $value -Type ([string]$SourceColumn.type))) {
            ++$typeViolations
            continue
        }
        switch ([string]$SourceColumn.type) {
            'int64' {
                $number = [long]$value
                if ($null -eq $numericMinimum -or $number -lt $numericMinimum) {
                    $numericMinimum = $number
                }
                if ($null -eq $numericMaximum -or $number -gt $numericMaximum) {
                    $numericMaximum = $number
                }
            }
            'decimal' {
                $number = [decimal]::Parse(
                    [Convert]::ToString($value, $invariant),
                    [Globalization.NumberStyles]::Float,
                    $invariant)
                if ($null -eq $numericMinimum -or $number -lt $numericMinimum) {
                    $numericMinimum = $number
                }
                if ($null -eq $numericMaximum -or $number -gt $numericMaximum) {
                    $numericMaximum = $number
                }
            }
            'string' {
                $length = [Text.Encoding]::UTF8.GetByteCount([string]$value)
                $stringMinimum = [Math]::Min($stringMinimum, $length)
                $stringMaximum = [Math]::Max($stringMaximum, $length)
            }
        }
    }

    if ($typeViolations -ne 0) {
        throw "Type validation failed for $($SourceColumn.id): $typeViolations violation(s)."
    }
    if ([bool]$SourceColumn.nullable -ne ($nullCount -gt 0)) {
        throw "Nullability changed for $($SourceColumn.id)."
    }

    $bounds = if ($nonNullCount -eq 0) {
        [pscustomobject][ordered]@{ kind = 'no-observed-non-null-values' }
    }
    elseif ([string]$SourceColumn.type -in @('int64', 'decimal')) {
        [pscustomobject][ordered]@{
            kind = 'numeric-inclusive'
            minimum = $numericMinimum
            maximum = $numericMaximum
        }
    }
    elseif ([string]$SourceColumn.type -eq 'string') {
        [pscustomobject][ordered]@{
            kind = 'utf8-byte-length-inclusive'
            minimum_utf8_bytes = $stringMinimum
            maximum_utf8_bytes = $stringMaximum
        }
    }
    else {
        [pscustomobject][ordered]@{ kind = 'boolean-domain' }
    }

    return [pscustomobject][ordered]@{
        id = [string]$SourceColumn.id
        source_ordinal = [int]$SourceColumn.source_ordinal
        source_name = [string]$SourceColumn.source_name
        type = [string]$SourceColumn.type
        nullable = [bool]$SourceColumn.nullable
        null_count = $nullCount
        non_null_count = $nonNullCount
        type_violations = $typeViolations
        range_violations = 0
        bounds = $bounds
        change_policy = 'schema-version-bump-and-full-revalidation'
    }
}

function Test-IsInactiveReference {
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][object[]]$Values,
        [Parameter(Mandatory = $true)][object[]]$Sentinels
    )
    foreach ($value in $Values) {
        if ($null -eq $value) { continue }
        $isSentinel = $false
        $valueToken = Get-ValueToken $value
        foreach ($sentinel in $Sentinels) {
            if ($valueToken -ceq (Get-ValueToken $sentinel)) {
                $isSentinel = $true
                break
            }
        }
        if (-not $isSentinel) { return $false }
    }
    return $true
}

function ConvertTo-StableJsonText {
    param([Parameter(Mandatory = $true)][object]$InputObject)
    $json = $InputObject | ConvertTo-Json -Depth 100
    return (($json -replace "`r`n", "`n") -replace "`r", "`n") + "`n"
}

$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyFile = Resolve-RepositoryPath -Path $PolicyPath -Root $root
$contractFile = Resolve-RepositoryPath -Path $RegistryContractPath -Root $root
$p206File = Resolve-RepositoryPath -Path $P206EvidencePath -Root $root
$exportDirectory = Resolve-RepositoryPath -Path $ExportRoot -Root $root
$registryFile = Resolve-RepositoryPath -Path $OutputPath -Root $root
$evidenceFile = Resolve-RepositoryPath -Path $EvidencePath -Root $root
$generatorFile = $MyInvocation.MyCommand.Path

foreach ($required in @($policyFile, $contractFile, $p206File, $generatorFile)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required P2-07 input is missing: $required"
    }
}
if (-not (Test-Path -LiteralPath $exportDirectory -PathType Container)) {
    throw "P2-06 local exports are required: $exportDirectory"
}

$policy = Get-Content -LiteralPath $policyFile -Raw -Encoding UTF8 | ConvertFrom-Json
$p206 = Get-Content -LiteralPath $p206File -Raw -Encoding UTF8 | ConvertFrom-Json
if ($policy.schema_version -ne 1 -or $policy.task_id -ne 'P2-07') {
    throw 'Unsupported or invalid P2-07 policy.'
}
if ($p206.result -ne 'PASS' -or -not $p206.completion_criteria_satisfied) {
    throw 'P2-06 evidence is not complete.'
}
if ($policy.source_build -ne $p206.source.build) {
    throw 'P2-07 policy build does not match P2-06 evidence.'
}

$tablePolicies = @($policy.tables)
$foreignKeyPolicies = @($policy.foreign_keys)
if ($tablePolicies.Count -ne 12) { throw 'P2-07 must freeze exactly 12 core tables.' }
if (@($tablePolicies.source_path | Sort-Object -Unique).Count -ne 12) {
    throw 'P2-07 core-table paths must be unique.'
}
if (@($foreignKeyPolicies.id | Sort-Object -Unique).Count -ne $foreignKeyPolicies.Count) {
    throw 'P2-07 foreign-key IDs must be unique.'
}

$rowsByTable = @{}
$sourceSchemaByTable = @{}
$tableRecordByPath = @{}
$columnTypeByTable = @{}
$tableRecords = [Collections.Generic.List[object]]::new()
$physicalRows = 0L
$canonicalRows = 0L
$columnCount = 0
$duplicateOccurrences = 0
$keyViolations = 0

foreach ($tablePolicy in $tablePolicies) {
    $sourcePath = [string]$tablePolicy.source_path
    $relativeBase = $sourcePath.Substring(0, $sourcePath.Length - 4).Replace(
        '/', [IO.Path]::DirectorySeparatorChar)
    $tableDirectory = [IO.Path]::GetFullPath((Join-Path $exportDirectory $relativeBase))
    if (-not $tableDirectory.StartsWith(
            $exportDirectory + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Core-table export path escaped P2-06 output: $sourcePath"
    }
    $schemaFile = Join-Path $tableDirectory 'schema.yaml'
    $normalizedFile = Join-Path $tableDirectory 'normalized.jsonl'
    foreach ($required in @($schemaFile, $normalizedFile)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Core-table export is incomplete: $required"
        }
    }
    $sourceSchema = Get-Content -LiteralPath $schemaFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($sourceSchema.source.path -cne $sourcePath) {
        throw "Source path mismatch for $sourcePath."
    }
    if ((Get-LowerSha256 $normalizedFile) -cne [string]$sourceSchema.normalized.sha256) {
        throw "Normalized content hash mismatch for $sourcePath."
    }
    $rows = @(Read-JsonLines $normalizedFile)
    if ($rows.Count -ne [int]$sourceSchema.normalized.row_count) {
        throw "Normalized row count mismatch for $sourcePath."
    }
    $rowsByTable[$sourcePath] = $rows
    $sourceSchemaByTable[$sourcePath] = $sourceSchema

    $columnIds = @($sourceSchema.columns.id)
    $typeMap = @{}
    foreach ($column in @($sourceSchema.columns)) {
        $typeMap[[string]$column.id] = [string]$column.type
    }
    $columnTypeByTable[$sourcePath] = $typeMap

    $keyColumnIds = @($tablePolicy.primary_key.column_ids | ForEach-Object { [string]$_ })
    if ($keyColumnIds.Count -eq 0 -or
        @($keyColumnIds | Where-Object { $_ -notin $columnIds }).Count -gt 0) {
        throw "Primary key references an unknown column in $sourcePath."
    }
    $keyGroups = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal)
    $nullViolations = 0
    foreach ($row in $rows) {
        [object[]]$values = [object[]]::new($keyColumnIds.Count)
        for ($keyIndex = 0; $keyIndex -lt $keyColumnIds.Count; ++$keyIndex) {
            $values[$keyIndex] = Get-ColumnValue -Row $row `
                -ColumnId $keyColumnIds[$keyIndex]
        }
        $hasNull = $false
        foreach ($value in $values) {
            if ($null -eq $value) { $hasNull = $true; break }
        }
        if ($hasNull) {
            ++$nullViolations
            continue
        }
        $keyToken = Get-KeyToken -Row $row -ColumnIds $keyColumnIds
        $rowJson = $row | ConvertTo-Json -Compress -Depth 20
        if ($keyGroups.ContainsKey($keyToken)) {
            $group = $keyGroups[$keyToken]
            ++$group.count
            if ($group.first_json -cne $rowJson) { $group.divergent = $true }
        }
        else {
            $keyGroups.Add($keyToken, [pscustomobject]@{
                    count = 1
                    first_json = $rowJson
                    divergent = $false
                })
        }
    }
    $duplicateGroups = @($keyGroups.Values | Where-Object count -gt 1).Count
    $tableDuplicateOccurrences = $rows.Count - $keyGroups.Count - $nullViolations
    $divergentDuplicateGroups = @($keyGroups.Values | Where-Object {
            $_.count -gt 1 -and $_.divergent
        }).Count
    $duplicatePolicy = [string]$tablePolicy.primary_key.duplicate_policy
    $tableKeyViolations = $nullViolations + $divergentDuplicateGroups
    if ($duplicatePolicy -eq 'reject') {
        $tableKeyViolations += $tableDuplicateOccurrences
    }
    elseif ($duplicatePolicy -ne 'collapse-identical-rows') {
        throw "Unsupported duplicate policy for ${sourcePath}: $duplicatePolicy"
    }
    if ($tableKeyViolations -ne 0) {
        throw "Primary-key validation failed for $sourcePath."
    }

    $columns = [Collections.Generic.List[object]]::new()
    foreach ($sourceColumn in @($sourceSchema.columns)) {
        $columns.Add((Get-ColumnRule -Rows $rows -SourceColumn $sourceColumn))
    }
    $tableCanonicalRows = $rows.Count - $tableDuplicateOccurrences
    $record = [pscustomobject][ordered]@{
        source_path = $sourcePath
        logical_name = [string]$sourceSchema.logical_name
        role = [string]$tablePolicy.role
        source_schema_sha256 = Get-LowerSha256 $schemaFile
        normalized_sha256 = Get-LowerSha256 $normalizedFile
        physical_rows = $rows.Count
        canonical_rows = $tableCanonicalRows
        primary_key = [pscustomobject][ordered]@{
            column_ids = $keyColumnIds
            duplicate_policy = $duplicatePolicy
            null_violations = $nullViolations
            duplicate_groups = $duplicateGroups
            duplicate_occurrences = $tableDuplicateOccurrences
            divergent_duplicate_groups = $divergentDuplicateGroups
            result = 'PASS'
        }
        columns = $columns
        foreign_keys = [Collections.Generic.List[object]]::new()
        result = 'PASS'
    }
    $tableRecords.Add($record)
    $tableRecordByPath[$sourcePath] = $record
    $physicalRows += $rows.Count
    $canonicalRows += $tableCanonicalRows
    $columnCount += $columns.Count
    $duplicateOccurrences += $tableDuplicateOccurrences
    $keyViolations += $tableKeyViolations
}

$activeReferenceRows = 0L
$inactiveReferenceRows = 0L
$danglingReferences = 0L
foreach ($foreignKey in $foreignKeyPolicies) {
    $sourcePath = [string]$foreignKey.source_table
    $targetPath = [string]$foreignKey.target_table
    if (-not $rowsByTable.ContainsKey($sourcePath) -or
        -not $rowsByTable.ContainsKey($targetPath)) {
        throw "Foreign key $($foreignKey.id) references a non-core table."
    }
    $sourceColumns = @($foreignKey.source_column_ids | ForEach-Object { [string]$_ })
    $targetColumns = @($foreignKey.target_column_ids | ForEach-Object { [string]$_ })
    if ($sourceColumns.Count -ne $targetColumns.Count -or $sourceColumns.Count -eq 0) {
        throw "Foreign key $($foreignKey.id) has incompatible arity."
    }
    $sourceTypes = $columnTypeByTable[$sourcePath]
    $targetTypes = $columnTypeByTable[$targetPath]
    $typeCompatible = $true
    for ($index = 0; $index -lt $sourceColumns.Count; ++$index) {
        if (-not $sourceTypes.ContainsKey($sourceColumns[$index]) -or
            -not $targetTypes.ContainsKey($targetColumns[$index]) -or
            $sourceTypes[$sourceColumns[$index]] -cne $targetTypes[$targetColumns[$index]]) {
            $typeCompatible = $false
        }
    }
    if (-not $typeCompatible) {
        throw "Foreign key $($foreignKey.id) has incompatible column types."
    }
    $targetKeyMode = [string]$foreignKey.target_key_mode
    if ($targetKeyMode -eq 'primary-key') {
        $targetPrimaryColumns = @($tableRecordByPath[$targetPath].primary_key.column_ids)
        if (($targetColumns -join ',') -cne ($targetPrimaryColumns -join ',')) {
            throw "Foreign key $($foreignKey.id) does not target the declared primary key."
        }
    }
    elseif ($targetKeyMode -ne 'distinct-domain') {
        throw "Foreign key $($foreignKey.id) has an unsupported target mode."
    }

    $targetSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($targetRow in @($rowsByTable[$targetPath])) {
        [void]$targetSet.Add((Get-KeyToken -Row $targetRow -ColumnIds $targetColumns))
    }
    $activeRows = 0
    $inactiveRows = 0
    $danglingRows = 0
    $sentinels = @($foreignKey.sentinel_values)
    foreach ($sourceRow in @($rowsByTable[$sourcePath])) {
        [object[]]$values = [object[]]::new($sourceColumns.Count)
        for ($sourceIndex = 0; $sourceIndex -lt $sourceColumns.Count; ++$sourceIndex) {
            $values[$sourceIndex] = Get-ColumnValue -Row $sourceRow `
                -ColumnId $sourceColumns[$sourceIndex]
        }
        if (Test-IsInactiveReference -Values $values -Sentinels $sentinels) {
            ++$inactiveRows
            continue
        }
        ++$activeRows
        if (-not $targetSet.Contains(
                (Get-KeyToken -Row $sourceRow -ColumnIds $sourceColumns))) {
            ++$danglingRows
        }
    }
    if ($danglingRows -ne 0) {
        throw "Foreign key $($foreignKey.id) has $danglingRows dangling row(s)."
    }
    $tableRecordByPath[$sourcePath].foreign_keys.Add(
        [pscustomobject][ordered]@{
            id = [string]$foreignKey.id
            source_column_ids = $sourceColumns
            target_table = $targetPath
            target_column_ids = $targetColumns
            target_key_mode = $targetKeyMode
            sentinel_values = $sentinels
            active_rows = $activeRows
            inactive_rows = $inactiveRows
            dangling_rows = $danglingRows
            type_compatible = $typeCompatible
            result = 'PASS'
        })
    $activeReferenceRows += $activeRows
    $inactiveReferenceRows += $inactiveRows
    $danglingReferences += $danglingRows
}

$summary = [pscustomobject][ordered]@{
    tables = $tableRecords.Count
    physical_rows = $physicalRows
    canonical_rows = $canonicalRows
    columns = $columnCount
    columns_with_type_and_rule = $columnCount
    primary_keys = $tableRecords.Count
    foreign_keys = $foreignKeyPolicies.Count
    active_reference_rows = $activeReferenceRows
    inactive_reference_rows = $inactiveReferenceRows
    duplicate_occurrences_collapsed = $duplicateOccurrences
    type_violations = 0
    range_violations = 0
    key_violations = $keyViolations
    dangling_references = $danglingReferences
    result = 'PASS'
}

$registry = [pscustomobject][ordered]@{
    schema_version = 1
    registry_id = 'tmxy-core-table-registry-v1'
    task_id = 'P2-07'
    status = 'authoritative-frozen-build-import-contract'
    source_build = [string]$policy.source_build
    scope = [pscustomobject][ordered]@{
        table_count = $tableRecords.Count
        authority = 'frozen-source-build-import-only'
        future_change_policy = 'schema-version-bump-and-full-revalidation'
    }
    source = [pscustomobject][ordered]@{
        p2_06_evidence_path = Get-RelativeRepositoryPath -Path $p206File -Root $root
        p2_06_evidence_sha256 = Get-LowerSha256 $p206File
        p2_06_content_set_sha256 = [string]$p206.output.content_set_sha256
        policy_path = Get-RelativeRepositoryPath -Path $policyFile -Root $root
        policy_sha256 = Get-LowerSha256 $policyFile
        contract_path = Get-RelativeRepositoryPath -Path $contractFile -Root $root
        contract_sha256 = Get-LowerSha256 $contractFile
    }
    summary = $summary
    tables = $tableRecords
}
$registryText = ConvertTo-StableJsonText $registry
$registryBytes = $utf8NoBom.GetBytes($registryText)
$registrySha = try {
    $stream = [IO.MemoryStream]::new($registryBytes, $false)
    try {
        ([Security.Cryptography.SHA256]::Create().ComputeHash($stream) |
                ForEach-Object ToString x2) -join ''
    }
    finally { $stream.Dispose() }
}
finally { [Array]::Clear($registryBytes, 0, $registryBytes.Length) }

$tableEvidence = @($tableRecords | ForEach-Object {
        $tableDangling = 0
        foreach ($tableForeignKey in $_.foreign_keys) {
            $tableDangling += [long]$tableForeignKey.dangling_rows
        }
        [pscustomobject][ordered]@{
            source_path = $_.source_path
            physical_rows = $_.physical_rows
            canonical_rows = $_.canonical_rows
            columns = $_.columns.Count
            primary_key_columns = $_.primary_key.column_ids.Count
            duplicate_groups = $_.primary_key.duplicate_groups
            duplicate_occurrences = $_.primary_key.duplicate_occurrences
            divergent_duplicate_groups = $_.primary_key.divergent_duplicate_groups
            foreign_keys = $_.foreign_keys.Count
            dangling_references = $tableDangling
            result = 'PASS'
        }
    })
$evidence = [pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-07'
    result = 'PASS'
    task_status = 'COMPLETE'
    completion_criteria_satisfied = $true
    authority = 'authoritative-for-frozen-build-import'
    source = [pscustomobject][ordered]@{
        build = [string]$policy.source_build
        p2_06_evidence_sha256 = Get-LowerSha256 $p206File
        p2_06_content_set_sha256 = [string]$p206.output.content_set_sha256
        policy_sha256 = Get-LowerSha256 $policyFile
        registry_contract_sha256 = Get-LowerSha256 $contractFile
        generator_sha256 = Get-LowerSha256 $generatorFile
    }
    output = [pscustomobject][ordered]@{
        registry_path = Get-RelativeRepositoryPath -Path $registryFile -Root $root
        registry_sha256 = $registrySha
    }
    summary = $summary
    deferred_reference_candidates = @($policy.deferred_reference_candidates).Count
    tables = $tableEvidence
    guarantees = [pscustomobject][ordered]@{
        all_core_tables_have_authoritative_primary_key = $true
        all_core_columns_have_type_and_validation_rule = $true
        all_declared_foreign_keys_have_zero_dangling_rows = $true
        identical_duplicate_rows_are_explicitly_canonicalized = $true
        raw_rows_or_field_values_emitted_to_evidence = $false
        future_source_changes_require_schema_version_bump = $true
        ownership_remains_p2_08 = $true
    }
    reproduction = [pscustomobject][ordered]@{
        generator = Get-RelativeRepositoryPath -Path $generatorFile -Root $root
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
        task_id = 'P2-07'
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
