[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot =
        'E:\QQXYCodeDev\Rebuild\Data\Backups\p1-09-runtime-client',
    [string]$OutputRoot = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-06',
    [string]$EvidencePath =
        'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-06-three-layer-data.json',
    [ValidatePattern('^[a-z0-9][a-z0-9./-]+$')]
    [string]$SecretId = 'tmxy/development/table/qy-3.0.0.413/runtime-key-base64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$credentialTargetPrefix = 'com.docker.pass.shared:docker-pass-cli:'
$expectedKeyFingerprint =
    'cf760550b7af6c220331b258db1df781fe567221eb7c53fbfc65aca522085887'
$expectedExecutableSha256 =
    '7087dfa64bedeb8c9a5dfc4518f46261d163136b5bd97f5071f2c5a12cb29a4b'
$sourceBuild = 'qy-3.0.0.413'

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Initialize-CredentialType {
    if ($null -ne ('TmxyP206Credential' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TmxyP206Credential
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct Credential
    {
        public UInt32 Flags; public UInt32 Type; public IntPtr TargetName;
        public IntPtr Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public UInt32 CredentialBlobSize; public IntPtr CredentialBlob;
        public UInt32 Persist; public UInt32 AttributeCount; public IntPtr Attributes;
        public IntPtr TargetAlias; public IntPtr UserName;
    }
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode,
        SetLastError = true)]
    public static extern bool CredRead(
        string target, UInt32 type, UInt32 flags, out IntPtr credential);
    [DllImport("advapi32.dll")]
    public static extern void CredFree(IntPtr credential);
}
'@
}

function Read-StoredKey {
    param([Parameter(Mandatory = $true)][string]$Id)
    Initialize-CredentialType
    $pointer = [IntPtr]::Zero
    if (-not [TmxyP206Credential]::CredRead(
            $credentialTargetPrefix + $Id, 1, 0, [ref]$pointer)) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "The current-table keychain entry is unavailable (code $code)."
    }
    [byte[]]$blob = $null
    [byte[]]$key = $null
    try {
        $credential = [Runtime.InteropServices.Marshal]::PtrToStructure[
            TmxyP206Credential+Credential]($pointer)
        $blob = [byte[]]::new($credential.CredentialBlobSize)
        [Runtime.InteropServices.Marshal]::Copy(
            $credential.CredentialBlob, $blob, 0, $blob.Length)
        $encoded = [Text.Encoding]::Unicode.GetString($blob).TrimEnd("`0", "`r", "`n")
        try { $key = [Convert]::FromBase64String($encoded) }
        finally { $encoded = $null }
        if ($key.Length -ne 16 -or (Get-LowerSha256 $key) -ne $expectedKeyFingerprint) {
            if ($null -ne $key) { [Array]::Clear($key, 0, $key.Length) }
            throw 'The stored current-table key fingerprint does not match P1-09 evidence.'
        }
        return ,$key
    }
    finally {
        if ($null -ne $blob) { [Array]::Clear($blob, 0, $blob.Length) }
        [TmxyP206Credential]::CredFree($pointer)
    }
}

function Invoke-AesEcbDecrypt {
    param([byte[]]$Ciphertext, [byte[]]$Key)
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [Security.Cryptography.CipherMode]::ECB
        $aes.Padding = [Security.Cryptography.PaddingMode]::None
        $aes.KeySize = 128
        $aes.BlockSize = 128
        $aes.Key = $Key
        $decryptor = $aes.CreateDecryptor()
        try { return ,$decryptor.TransformFinalBlock($Ciphertext, 0, $Ciphertext.Length) }
        finally { $decryptor.Dispose() }
    }
    finally { $aes.Dispose() }
}

function Read-DecodedPayload {
    param([Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Key)
    [byte[]]$ciphertext = [IO.File]::ReadAllBytes($Path)
    [byte[]]$once = $null
    [byte[]]$plaintext = $null
    try {
        if ($ciphertext.Length -eq 0 -or $ciphertext.Length % 16 -ne 0) {
            throw 'Invalid encrypted table length.'
        }
        $once = Invoke-AesEcbDecrypt $ciphertext $Key
        $plaintext = Invoke-AesEcbDecrypt $once $Key
        $padding = [int]$plaintext[0]
        if ($padding -lt 0 -or $padding -ge 16 -or $plaintext.Length -le $padding + 1) {
            throw 'Invalid encrypted table padding length.'
        }
        $payloadEnd = $plaintext.Length - $padding
        for ($index = $payloadEnd; $index -lt $plaintext.Length; ++$index) {
            if ($plaintext[$index] -ne 0) { throw 'Invalid encrypted table zero padding.' }
        }
        [byte[]]$payload = [byte[]]::new($payloadEnd - 1)
        [Array]::Copy($plaintext, 1, $payload, 0, $payload.Length)
        return ,$payload
    }
    finally {
        [Array]::Clear($ciphertext, 0, $ciphertext.Length)
        if ($null -ne $once) { [Array]::Clear($once, 0, $once.Length) }
        if ($null -ne $plaintext) { [Array]::Clear($plaintext, 0, $plaintext.Length) }
    }
}

function Get-TextEncoding {
    param([Parameter(Mandatory = $true)][string]$Classification)
    [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
    switch ($Classification) {
        'ascii' { return [Text.Encoding]::GetEncoding(20127,
                [Text.EncoderExceptionFallback]::new(), [Text.DecoderExceptionFallback]::new()) }
        'gbk' { return [Text.Encoding]::GetEncoding(936,
                [Text.EncoderExceptionFallback]::new(), [Text.DecoderExceptionFallback]::new()) }
        'utf8' { return [Text.UTF8Encoding]::new($false, $true) }
        default { throw "Unsupported active-table encoding classification: $Classification" }
    }
}

function Get-ObservedType {
    param([Parameter(Mandatory = $true)][string]$Value)
    $integer = 0L
    $decimal = 0D
    if ($Value -cmatch '^-?(0|[1-9][0-9]*)$' -and
        [long]::TryParse($Value, [Globalization.NumberStyles]::AllowLeadingSign,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$integer)) { return 'int64' }
    if ($Value -cmatch '^-?(0|[1-9][0-9]*)\.[0-9]+$' -and
        [decimal]::TryParse($Value,
            [Globalization.NumberStyles]::AllowLeadingSign -bor
                [Globalization.NumberStyles]::AllowDecimalPoint,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$decimal)) { return 'decimal' }
    if ($Value -ceq 'true' -or $Value -ceq 'false') { return 'boolean' }
    return 'string'
}

function Merge-ObservedType {
    param([string]$Current, [string]$Observed)
    if ($Current -eq 'none') { return $Observed }
    if ($Current -eq $Observed) { return $Current }
    if (($Current -eq 'int64' -and $Observed -eq 'decimal') -or
        ($Current -eq 'decimal' -and $Observed -eq 'int64')) { return 'decimal' }
    return 'string'
}

function Convert-NormalizedValue {
    param([string]$Value, [string]$Type)
    if ($Value.Length -eq 0) { return $null }
    switch ($Type) {
        'int64' { return [long]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture) }
        'decimal' { return [decimal]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture) }
        'boolean' { return $Value -ceq 'true' }
        default { return $Value }
    }
}

function Get-ColumnId {
    param([Parameter(Mandatory = $true)][int]$OneBased)
    return 'c{0:d4}' -f $OneBased
}

function Get-DelimiterProfile {
    param([Parameter(Mandatory = $true)][string[]]$Lines)
    $candidates = [Collections.Generic.List[object]]::new()
    foreach ($definition in @(
            [pscustomobject]@{ name = 'comma'; character = [char]44 },
            [pscustomobject]@{ name = 'tab'; character = [char]9 },
            [pscustomobject]@{ name = 'asterisk'; character = [char]42 },
            [pscustomobject]@{ name = 'pipe'; character = [char]124 },
            [pscustomobject]@{ name = 'semicolon'; character = [char]59 })) {
        $frequency = [Collections.Generic.Dictionary[int, int]]::new()
        $minimum = [int]::MaxValue
        $maximum = 0
        foreach ($line in $Lines) {
            $count = $line.Split([char]$definition.character).Length
            if ($frequency.ContainsKey($count)) { ++$frequency[$count] }
            else { $frequency.Add($count, 1) }
            $minimum = [Math]::Min($minimum, $count)
            $maximum = [Math]::Max($maximum, $count)
        }
        $mode = $frequency.GetEnumerator() | Sort-Object -Property @(
            @{ Expression = 'Value'; Descending = $true },
            @{ Expression = 'Key'; Descending = $true }) | Select-Object -First 1
        $headerColumns = $Lines[0].Split([char]$definition.character).Length
        if ($headerColumns -gt 1) {
            $candidates.Add([pscustomobject][ordered]@{
                    name = $definition.name
                    character = [char]$definition.character
                    header_columns = $headerColumns
                    modal_columns = [int]$mode.Key
                    modal_line_count = [int]$mode.Value
                    header_matches_mode = $headerColumns -eq [int]$mode.Key
                    minimum_columns = $minimum
                    maximum_columns = $maximum
                })
        }
    }
    $selected = $candidates | Sort-Object -Property @(
        @{ Expression = 'header_matches_mode'; Descending = $true },
        @{ Expression = 'modal_line_count'; Descending = $true },
        @{ Expression = 'modal_columns'; Descending = $true }) | Select-Object -First 1
    if ($null -eq $selected) {
        return [pscustomobject][ordered]@{
            name = 'single-column'; character = [char]44; header_columns = 1
            modal_columns = 1; modal_line_count = $Lines.Count
            header_matches_mode = $true; minimum_columns = 1; maximum_columns = 1
        }
    }
    return $selected
}

function Get-ContentSetSha256 {
    param([Parameter(Mandatory = $true)][object[]]$Files)
    $lines = @($Files | Sort-Object path | ForEach-Object {
            '{0}`0{1}`0{2}' -f $_.path, $_.sha256, $_.bytes
        }) -join "`n"
    [byte[]]$bytes = [Text.Encoding]::UTF8.GetBytes($lines + "`n")
    try { return Get-LowerSha256 $bytes }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Assert-ChildPath {
    param([string]$Child, [string]$Parent, [string]$Message)
    if (-not $Child.StartsWith($Parent + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw $Message }
}

$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd([char[]]'\/')
$evidence = [IO.Path]::GetFullPath($EvidencePath)
$backupRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Backups')).TrimEnd([char[]]'\/')
$exportsRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Exports')).TrimEnd([char[]]'\/')
$inventoryRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Inventory')).TrimEnd([char[]]'\/')
Assert-ChildPath $client $backupRoot 'P2-06 input must be below Rebuild/Data/Backups.'
Assert-ChildPath $output $exportsRoot 'P2-06 output must be below Rebuild/Data/Exports.'
Assert-ChildPath $evidence $root 'P2-06 evidence must remain inside Rebuild.'
if (-not $evidence.StartsWith($inventoryRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -and
    -not $evidence.StartsWith($exportsRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-06 evidence must be below Data/Inventory or Data/Exports.'
}

$p204Path = Join-Path $root 'Data\Inventory\p2-04-current-table-inventory.json'
$p204Sha = Get-FileSha256 $p204Path
$p204 = Get-Content -LiteralPath $p204Path -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $p204.completion_criteria_satisfied -or $p204.summary.active -ne 225 -or
    $p204.summary.historical_shadow -ne 113) { throw 'P2-04 evidence is not complete.' }
$exePath = Join-Path $client 'QY.exe'
if ((Get-FileSha256 $exePath) -ne $expectedExecutableSha256) {
    throw 'The sandbox executable does not match the P1-09 binding.'
}

$staging = $output + '.__staging_' + $PID
$previous = $null
$previousManifest = Join-Path $output 'manifest.json'
if (Test-Path -LiteralPath $previousManifest -PathType Leaf) {
    $previous = Get-Content -LiteralPath $previousManifest -Raw -Encoding UTF8 |
        ConvertFrom-Json
}
if (Test-Path -LiteralPath $staging) {
    Assert-ChildPath $staging $exportsRoot 'Unsafe P2-06 staging cleanup target.'
    Remove-Item -LiteralPath $staging -Recurse -Force
}
[IO.Directory]::CreateDirectory($staging) | Out-Null

[byte[]]$key = Read-StoredKey $SecretId
$tableReports = [Collections.Generic.List[object]]::new()
$fileReports = [Collections.Generic.List[object]]::new()
$typeTotals = [ordered]@{ boolean = 0; int64 = 0; decimal = 0; string = 0 }
$totalNulls = 0L
try {
    foreach ($table in @($p204.tables | Sort-Object path)) {
        if ($table.lifecycle -ne 'active') {
            $tableReports.Add([pscustomobject][ordered]@{
                    source_path = $table.path
                    lifecycle = 'historical-shadow'
                    source_sha256 = $table.sha256
                    generated = $false
                    replacement_path = $table.replacement.path
                })
            continue
        }
        $sourcePath = Join-Path $client ([string]$table.path).Replace('/', '\')
        if ((Get-FileSha256 $sourcePath) -ne $table.sha256) {
            throw "Source hash changed for $($table.path)."
        }
        [byte[]]$payload = Read-DecodedPayload $sourcePath $key
        try {
            if ($payload.Length -ne $table.decode.payload_bytes) {
                throw "Decoded length differs from P2-04 for $($table.path)."
            }
            $encoding = Get-TextEncoding ([string]$table.encoding.classification)
            $text = $encoding.GetString($payload)
            $lines = @($text.Split([string[]]@("`r`n"),
                    [StringSplitOptions]::None) | Where-Object Length -gt 0)
            if ($lines.Count -lt 1 -or $lines.Count - 1 -ne $table.schema.rows) {
                throw "Decoded row count differs from P2-04 for $($table.path)."
            }
            $delimiter = Get-DelimiterProfile -Lines $lines
            [string[]]$headers = $lines[0].Split([char]$delimiter.character)
            $rows = @($lines | Select-Object -Skip 1)
            $width = [int]$delimiter.maximum_columns
            if ($headers.Length -gt $width) { throw "Invalid physical width for $($table.path)." }
            $sourceRelative = [string]$table.path
            $extension = [IO.Path]::GetExtension($sourceRelative)
            $logical = $sourceRelative.Substring(0, $sourceRelative.Length - $extension.Length)
            if ($logical -match '(^|/)\.\.?(\/|$)') { throw 'Unsafe table path.' }
            $tableRoot = Join-Path $staging ('tables\' + $logical.Replace('/', '\'))
            [IO.Directory]::CreateDirectory($tableRoot) | Out-Null
            $rawPath = Join-Path $tableRoot 'raw.csv'
            [IO.File]::WriteAllBytes($rawPath, $payload)

            $types = [string[]]::new($width)
            $emptyCounts = [long[]]::new($width)
            $missingCounts = [long[]]::new($width)
            for ($column = 0; $column -lt $width; ++$column) { $types[$column] = 'none' }
            foreach ($line in $rows) {
                [string[]]$fields = $line.Split([char]$delimiter.character)
                for ($column = 0; $column -lt $width; ++$column) {
                    if ($column -ge $fields.Length) { ++$missingCounts[$column]; continue }
                    if ($fields[$column].Length -eq 0) { ++$emptyCounts[$column]; continue }
                    $types[$column] = Merge-ObservedType $types[$column] `
                        (Get-ObservedType $fields[$column])
                }
            }
            for ($column = 0; $column -lt $width; ++$column) {
                if ($types[$column] -eq 'none') { $types[$column] = 'string' }
                $typeTotals[$types[$column]] = [int]$typeTotals[$types[$column]] + 1
                $totalNulls += $emptyCounts[$column] + $missingCounts[$column]
            }

            $normalizedPath = Join-Path $tableRoot 'normalized.jsonl'
            $writer = [IO.StreamWriter]::new(
                $normalizedPath, $false, [Text.UTF8Encoding]::new($false))
            $writer.NewLine = "`n"
            try {
                foreach ($line in $rows) {
                    [string[]]$fields = $line.Split([char]$delimiter.character)
                    $record = [ordered]@{}
                    for ($column = 0; $column -lt $width; ++$column) {
                        $value = if ($column -lt $fields.Length) { $fields[$column] } else { '' }
                        $record[(Get-ColumnId ($column + 1))] =
                            Convert-NormalizedValue $value $types[$column]
                    }
                    $writer.WriteLine(($record | ConvertTo-Json -Compress -Depth 3))
                }
            }
            finally { $writer.Dispose() }

            $rawSha = Get-FileSha256 $rawPath
            $normalizedSha = Get-FileSha256 $normalizedPath
            $candidateColumns = @($table.schema.primary_key.one_based_columns |
                ForEach-Object { Get-ColumnId ([int]$_) })
            $columns = for ($column = 0; $column -lt $width; ++$column) {
                [pscustomobject][ordered]@{
                    id = Get-ColumnId ($column + 1)
                    source_ordinal = $column + 1
                    source_name = if ($column -lt $headers.Length) { $headers[$column] } else { '' }
                    source_header_present = $column -lt $headers.Length
                    type = $types[$column]
                    nullable = ($emptyCounts[$column] + $missingCounts[$column]) -gt 0
                    empty_count = $emptyCounts[$column]
                    missing_count = $missingCounts[$column]
                    default = $null
                    enum = @()
                    range = $null
                    unit = 'unresolved'
                    localization = 'unresolved'
                    evidence_level = 'L1-observed'
                }
            }
            $mapping = for ($column = 0; $column -lt $width; ++$column) {
                [pscustomobject][ordered]@{
                    source_ordinal = $column + 1
                    source_name = if ($column -lt $headers.Length) { $headers[$column] } else { '' }
                    normalized_column = Get-ColumnId ($column + 1)
                    conversion = if ($types[$column] -eq 'string') {
                        'decode-source-encoding-and-preserve-text'
                    } else { "parse-$($types[$column])-only-after-column-wide-inference" }
                    empty_or_missing = 'null'
                }
            }
            $schemaObject = [pscustomobject][ordered]@{
                schema_version = 1
                logical_name = $logical
                source = [pscustomobject][ordered]@{
                    path = $table.path; build = $sourceBuild; sha256 = $table.sha256
                    encoding = $table.encoding.classification
                }
                raw = [pscustomobject][ordered]@{
                    file = 'raw.csv'; sha256 = $rawSha; bytes = $payload.Length
                    fidelity = 'decoded-payload-byte-identical'; delimiter = $delimiter.name
                    line_ending = 'crlf'; header_sha256 = $table.schema.header_sha256
                }
                normalized = [pscustomobject][ordered]@{
                    file = 'normalized.jsonl'; format = 'jsonl'; encoding = 'utf-8-no-bom'
                    sha256 = $normalizedSha; bytes = (Get-Item $normalizedPath).Length
                    row_count = $rows.Count
                    null_policy = 'empty-or-missing-source-field-to-null'
                    type_policy = 'conservative-observed-value-inference-v1'
                    stable_column_ids = $true
                }
                ownership = [pscustomobject][ordered]@{
                    classification = 'pending-p2-08'; authoritative = $false
                    decision_task = 'P2-08'
                }
                key = [pscustomobject][ordered]@{
                    status = 'candidate-from-p2-04'; normalized_columns = $candidateColumns
                    candidate_classification = $table.schema.primary_key.classification
                    verified_unique = $table.schema.primary_key.verified_unique
                    authoritative = $false; decision_task = 'P2-07'
                }
                columns = @($columns)
                references = [pscustomobject][ordered]@{
                    status = 'pending-p2-07'; foreign_keys = @(); decision_task = 'P2-07'
                }
                loading = [pscustomobject][ordered]@{
                    mode = 'unresolved'; hot_reload = 'unresolved'
                    release_group = 'unresolved'; decision_task = 'P2-08'
                }
                old_to_new = @($mapping)
                evidence = [pscustomobject][ordered]@{
                    level = 'L1-structural'; semantic_authority = $false
                    source_inventory = 'Data/Inventory/p2-04-current-table-inventory.json'
                    source_inventory_sha256 = $p204Sha
                    next_tasks = @('P2-07', 'P2-08', 'P2-09')
                }
            }
            $schemaPath = Join-Path $tableRoot 'schema.yaml'
            $schemaJson = ($schemaObject | ConvertTo-Json -Depth 12).Replace("`r`n", "`n")
            [IO.File]::WriteAllText(
                $schemaPath, $schemaJson + "`n", [Text.UTF8Encoding]::new($false))

            $relativeRoot = 'tables/' + $logical
            $files = @(
                [pscustomobject][ordered]@{ path = "$relativeRoot/raw.csv"; sha256 = $rawSha
                    bytes = (Get-Item $rawPath).Length; kind = 'raw' },
                [pscustomobject][ordered]@{ path = "$relativeRoot/normalized.jsonl";
                    sha256 = $normalizedSha; bytes = (Get-Item $normalizedPath).Length
                    kind = 'normalized' },
                [pscustomobject][ordered]@{ path = "$relativeRoot/schema.yaml";
                    sha256 = Get-FileSha256 $schemaPath; bytes = (Get-Item $schemaPath).Length
                    kind = 'schema' }
            )
            foreach ($fileReport in $files) { $fileReports.Add($fileReport) }
            $tableReports.Add([pscustomobject][ordered]@{
                    source_path = $table.path; lifecycle = 'active'
                    source_sha256 = $table.sha256; generated = $true
                    logical_name = $logical; source_encoding = $table.encoding.classification
                    rows = $rows.Count; columns = $width
                    delimiter = $delimiter.name
                    header_columns = $delimiter.header_columns
                    modal_columns = $delimiter.modal_columns
                    minimum_columns = $delimiter.minimum_columns
                    maximum_columns = $delimiter.maximum_columns
                    fixed_column_count = $delimiter.minimum_columns -eq $delimiter.maximum_columns
                    p2_04_comma_maximum_columns = $table.schema.maximum_columns
                    candidate_key_columns = $candidateColumns
                    type_counts = [pscustomobject][ordered]@{
                        boolean = @($types | Where-Object { $_ -eq 'boolean' }).Count
                        int64 = @($types | Where-Object { $_ -eq 'int64' }).Count
                        decimal = @($types | Where-Object { $_ -eq 'decimal' }).Count
                        string = @($types | Where-Object { $_ -eq 'string' }).Count
                    }
                    null_cells = [long](($emptyCounts | Measure-Object -Sum).Sum) +
                        [long](($missingCounts | Measure-Object -Sum).Sum)
                    files = $files
                })
        }
        finally {
            if ($null -ne $payload) { [Array]::Clear($payload, 0, $payload.Length) }
            $text = $null
        }
    }
}
finally { if ($null -ne $key) { [Array]::Clear($key, 0, $key.Length) } }

$contentSetSha = Get-ContentSetSha256 @($fileReports)
$previousMatch = $null -ne $previous -and
    [string]$previous.content_set_sha256 -eq $contentSetSha
$activeReports = @($tableReports | Where-Object generated)
$historicalReports = @($tableReports | Where-Object { -not $_.generated })
$manifest = [pscustomobject][ordered]@{
    schema_version = 1; task = 'P2-06'; source_build = $sourceBuild
    generated_utc = [DateTimeOffset]::UtcNow.ToString('o')
    source_inventory_sha256 = $p204Sha
    content_set_sha256 = $contentSetSha
    reproducibility = [pscustomobject][ordered]@{
        deterministic_serialization = $true
        previous_export_present = $null -ne $previous
        previous_export_match = $previousMatch
    }
    summary = [pscustomobject][ordered]@{
        source_tables = $tableReports.Count; active_tables = $activeReports.Count
        historical_shadows = $historicalReports.Count; generated_tables = $activeReports.Count
        generated_files = $fileReports.Count
        rows = [long](($activeReports | Measure-Object rows -Sum).Sum)
        columns = [long](($activeReports | Measure-Object columns -Sum).Sum)
        raw_bytes = [long](($fileReports | Where-Object kind -eq raw |
                Measure-Object bytes -Sum).Sum)
        normalized_bytes = [long](($fileReports | Where-Object kind -eq normalized |
                Measure-Object bytes -Sum).Sum)
        schema_bytes = [long](($fileReports | Where-Object kind -eq schema |
                Measure-Object bytes -Sum).Sum)
        null_cells = $totalNulls
        inferred_column_types = [pscustomobject]$typeTotals
        delimiter_counts = @($activeReports | Group-Object delimiter | Sort-Object Name |
            ForEach-Object { [pscustomobject][ordered]@{
                    delimiter = $_.Name; tables = $_.Count
                } })
    }
    files = @($fileReports)
}
$manifestPath = Join-Path $staging 'manifest.json'
$manifestJson = ($manifest | ConvertTo-Json -Depth 8).Replace("`r`n", "`n")
[IO.File]::WriteAllText($manifestPath, $manifestJson + "`n", [Text.UTF8Encoding]::new($false))

$completed = $tableReports.Count -eq 338 -and $activeReports.Count -eq 225 -and
    $historicalReports.Count -eq 113 -and $fileReports.Count -eq 675 -and
    [long](($activeReports | Measure-Object rows -Sum).Sum) -eq 214885 -and
    [long](($fileReports | Where-Object kind -eq raw | Measure-Object bytes -Sum).Sum) -eq
        29658173L
if (-not $completed) { throw 'P2-06 completion criteria were not satisfied.' }

$oldOutput = $output + '.__previous_' + $PID
if (Test-Path -LiteralPath $oldOutput) {
    Assert-ChildPath $oldOutput $exportsRoot 'Unsafe P2-06 previous-output cleanup target.'
    Remove-Item -LiteralPath $oldOutput -Recurse -Force
}
if (Test-Path -LiteralPath $output) { Move-Item -LiteralPath $output -Destination $oldOutput }
Move-Item -LiteralPath $staging -Destination $output
if (Test-Path -LiteralPath $oldOutput) {
    Assert-ChildPath $oldOutput $exportsRoot 'Unsafe P2-06 previous-output cleanup target.'
    Remove-Item -LiteralPath $oldOutput -Recurse -Force
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = 'PASS'; task = 'P2-06'; task_status = 'COMPLETE'
    completion_criteria_satisfied = $true
    source = [pscustomobject][ordered]@{
        build = $sourceBuild
        inventory = 'Data/Inventory/p2-04-current-table-inventory.json'
        inventory_sha256 = $p204Sha
        executable_sha256 = $expectedExecutableSha256
    }
    runtime_key_binding = [pscustomobject][ordered]@{
        provider_reference = "se://$SecretId"; fingerprint = $expectedKeyFingerprint
        command_line_or_environment_input = $false; raw_key_emitted = $false
        plaintext_or_field_values_emitted_to_evidence = $false
        in_memory_key_cleared = $true
    }
    output = [pscustomobject][ordered]@{
        local_root = 'Data/Exports/P2-06'; git_ignored = $true
        object_store_publication = 'not-authorized'
        schema_contract = 'Contracts/data-schema/table-schema-v1.schema.json'
        content_set_sha256 = $contentSetSha
        manifest_sha256 = Get-FileSha256 (Join-Path $output 'manifest.json')
        previous_export_match = $previousMatch
    }
    summary = $manifest.summary
    tables = @($tableReports)
    guarantees = [pscustomobject][ordered]@{
        active_table_three_layer_coverage = '225/225'
        historical_shadow_outputs = 0
        raw_payload_byte_identical = $true
        normalized_utf8_no_bom = $true
        empty_or_missing_to_null = $true
        delimiter_detection_full_table = $true
        semantic_types_are_provisional = $true
        ownership_is_pending_p2_08 = $true
        keys_and_references_are_pending_p2_07 = $true
        field_identifiers_or_values_in_committed_evidence = $false
    }
    reproduction = [pscustomobject][ordered]@{
        command = 'pwsh -NoProfile -File Tools/TMXY.Table/New-ThreeLayerTableData.ps1'
        rerun_same_output_to_verify = $true
        prior_content_set_match = $previousMatch
    }
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($evidence)) | Out-Null
$reportJson = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n")
[IO.File]::WriteAllText($evidence, $reportJson + "`n", [Text.UTF8Encoding]::new($false))
$report | ConvertTo-Json -Depth 5
