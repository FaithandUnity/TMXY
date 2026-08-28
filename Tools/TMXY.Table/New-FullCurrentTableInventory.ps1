[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot =
        'E:\QQXYCodeDev\Rebuild\Data\Backups\p1-09-runtime-client',
    [string]$OutputPath =
        'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-04-current-table-inventory.json',
    [ValidatePattern('^[a-z0-9][a-z0-9./-]+$')]
    [string]$SecretId = 'tmxy/development/table/qy-3.0.0.413/runtime-key-base64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$credentialTargetPrefix = 'com.docker.pass.shared:docker-pass-cli:'
$expectedTableCount = 338
$expectedTableBytes = 40444128L
$expectedActiveCount = 225
$expectedHistoricalCount = 113
$expectedExecutableBytes = 5160960L
$expectedExecutableSha256 =
    '7087dfa64bedeb8c9a5dfc4518f46261d163136b5bd97f5071f2c5a12cb29a4b'
$expectedKeyFingerprint =
    'cf760550b7af6c220331b258db1df781fe567221eb7c53fbfc65aca522085887'
$sourceBuild = 'qy-3.0.0.413'

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Initialize-CredentialType {
    if ($null -ne ('TmxyP204Credential' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TmxyP204Credential
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct Credential
    {
        public UInt32 Flags;
        public UInt32 Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public UInt32 CredentialBlobSize;
        public IntPtr CredentialBlob;
        public UInt32 Persist;
        public UInt32 AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
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
    $pointer = [System.IntPtr]::Zero
    if (-not [TmxyP204Credential]::CredRead(
            $credentialTargetPrefix + $Id, 1, 0, [ref]$pointer)) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "The current-table keychain entry is unavailable (code $code)."
    }
    [byte[]]$blob = $null
    [byte[]]$key = $null
    try {
        $credential = [System.Runtime.InteropServices.Marshal]::PtrToStructure[
            TmxyP204Credential+Credential]($pointer)
        $blob = [byte[]]::new($credential.CredentialBlobSize)
        [System.Runtime.InteropServices.Marshal]::Copy(
            $credential.CredentialBlob, $blob, 0, $blob.Length)
        $encoded = [System.Text.Encoding]::Unicode.GetString($blob).TrimEnd("`0", "`r", "`n")
        try { $key = [System.Convert]::FromBase64String($encoded) }
        finally { $encoded = $null }
        if ($key.Length -ne 16 -or (Get-LowerSha256 -Bytes $key) -ne
            $expectedKeyFingerprint) {
            if ($null -ne $key) { [System.Array]::Clear($key, 0, $key.Length) }
            throw 'The stored current-table key fingerprint does not match P1-09 evidence.'
        }
        return ,$key
    }
    finally {
        if ($null -ne $blob) { [System.Array]::Clear($blob, 0, $blob.Length) }
        [TmxyP204Credential]::CredFree($pointer)
    }
}

function Invoke-AesEcbDecrypt {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Ciphertext,
        [Parameter(Mandatory = $true)][byte[]]$Key
    )
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [System.Security.Cryptography.CipherMode]::ECB
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::None
        $aes.KeySize = 128
        $aes.BlockSize = 128
        $aes.Key = $Key
        $decryptor = $aes.CreateDecryptor()
        try {
            [byte[]]$result = $decryptor.TransformFinalBlock(
                $Ciphertext, 0, $Ciphertext.Length)
            return ,$result
        }
        finally { $decryptor.Dispose() }
    }
    finally { $aes.Dispose() }
}

function Test-StrictDecoding {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][System.Text.Encoding]$Encoding
    )
    try {
        [void]$Encoding.GetString($Bytes)
        return $true
    }
    catch [System.Text.DecoderFallbackException] { return $false }
}

function Get-TableGroup {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    if ($RelativePath.StartsWith('CLSVShare/', [System.StringComparison]::Ordinal)) {
        return 'CLSVShare'
    }
    if ($RelativePath.StartsWith('Table/Regions/', [System.StringComparison]::Ordinal)) {
        return 'Table/Regions'
    }
    if ($RelativePath.StartsWith('Table/local/', [System.StringComparison]::Ordinal)) {
        return 'Table/local'
    }
    if ($RelativePath.StartsWith('Table/help/', [System.StringComparison]::Ordinal)) {
        return 'Table/help'
    }
    return 'Table/root'
}

function Get-SupersedingTablePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    if ($RelativePath.StartsWith('Table/Regions/', [System.StringComparison]::Ordinal)) {
        return 'Table/' + [System.IO.Path]::GetFileName($RelativePath)
    }
    if ($RelativePath -eq 'Table/local/quest_table.tbl') {
        return 'Table/quest_table.tbl'
    }
    if ($RelativePath -eq 'Table/help/localitem.tbl') {
        return 'Table/local/localitem.tbl'
    }
    return $null
}

function Get-EncodingClassification {
    param([Parameter(Mandatory = $true)][byte[]]$Payload)
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $strictGbk = [System.Text.Encoding]::GetEncoding(
        936,
        [System.Text.EncoderExceptionFallback]::new(),
        [System.Text.DecoderExceptionFallback]::new())
    $asciiOnly = $true
    foreach ($value in $Payload) {
        if ($value -ge 128) { $asciiOnly = $false; break }
    }
    $utf8Valid = Test-StrictDecoding -Bytes $Payload -Encoding $strictUtf8
    $gbkValid = Test-StrictDecoding -Bytes $Payload -Encoding $strictGbk
    $classification = if ($asciiOnly) { 'ascii' }
    elseif ($gbkValid -and -not $utf8Valid) { 'gbk' }
    elseif ($utf8Valid -and -not $gbkValid) { 'utf8' }
    elseif ($utf8Valid -and $gbkValid) { 'utf8-or-gbk' }
    else { 'opaque' }
    return [pscustomobject][ordered]@{
        classification = $classification
        strict_utf8 = $utf8Valid
        strict_gbk = $gbkValid
        ascii_only = $asciiOnly
    }
}

function Get-PrimaryKeyCandidate {
    param(
        [Parameter(Mandatory = $true)][string[]]$DataLines,
        [Parameter(Mandatory = $true)][int]$HeaderColumns
    )
    if ($DataLines.Count -eq 0) {
        return [pscustomobject][ordered]@{
            classification = 'empty-table-no-candidate'
            one_based_columns = @()
            verified_unique = $false
            search_limit_columns = [Math]::Min($HeaderColumns, 8)
            duplicate_row_occurrences = 0
        }
    }

    $searchLimit = [Math]::Min($HeaderColumns, 8)
    for ($prefixColumns = 1; $prefixColumns -le $searchLimit; ++$prefixColumns) {
        $seen = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
        $unique = $true
        foreach ($line in $DataLines) {
            $fields = $line.Split([char]',')
            if ($fields.Length -lt $prefixColumns) { $unique = $false; break }
            for ($fieldIndex = 0; $fieldIndex -lt $prefixColumns; ++$fieldIndex) {
                if ($fields[$fieldIndex].Length -eq 0) { $unique = $false; break }
            }
            if (-not $unique) { break }
            $candidate = [string]::Join(',', $fields[0..($prefixColumns - 1)])
            if (-not $seen.Add($candidate)) { $unique = $false; break }
        }
        if ($unique -and $seen.Count -eq $DataLines.Count) {
            return [pscustomobject][ordered]@{
                classification = if ($prefixColumns -eq 1) {
                    'unique-first-field-candidate'
                }
                else { 'unique-contiguous-prefix-candidate' }
                one_based_columns = @(1..$prefixColumns)
                verified_unique = $true
                search_limit_columns = $searchLimit
                duplicate_row_occurrences = 0
            }
        }
    }

    $fullRows = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $duplicateRows = 0
    foreach ($line in $DataLines) {
        if (-not $fullRows.Add($line)) { ++$duplicateRows }
    }
    return [pscustomobject][ordered]@{
        classification = if ($duplicateRows -eq 0) {
            'composite-key-required-beyond-prefix-search'
        }
        else { 'duplicate-data-rows-no-row-unique-candidate' }
        one_based_columns = @()
        verified_unique = $false
        search_limit_columns = $searchLimit
        duplicate_row_occurrences = $duplicateRows
    }
}

function Get-DelimitedMetrics {
    param([Parameter(Mandatory = $true)][byte[]]$Payload)
    $latin1 = [System.Text.Encoding]::Latin1.GetString($Payload)
    try {
        $rawLines = $latin1.Split(
            [string[]]@("`r`n"), [System.StringSplitOptions]::None)
        $nonemptyLines = @($rawLines | Where-Object Length -gt 0)
        if ($nonemptyLines.Count -eq 0) { throw 'no-nonempty-lines' }
        $emptyLines = $rawLines.Count - $nonemptyLines.Count
        if ($latin1.EndsWith("`r`n", [System.StringComparison]::Ordinal)) {
            --$emptyLines
        }
        $header = $nonemptyLines[0]
        [string[]]$dataLines = if ($nonemptyLines.Count -gt 1) {
            @($nonemptyLines | Select-Object -Skip 1)
        }
        else { @() }
        $headerFields = $header.Split([char]',')
        $headerSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
        $duplicateHeaders = 0
        $emptyHeaders = 0
        foreach ($field in $headerFields) {
            if ($field.Length -eq 0) { ++$emptyHeaders }
            if (-not $headerSet.Add($field)) { ++$duplicateHeaders }
        }
        $columnFrequency = [System.Collections.Generic.Dictionary[int, int]]::new()
        $emptyFields = 0L
        $rowsWithEmptyFields = 0
        foreach ($line in @($nonemptyLines)) {
            $fields = $line.Split([char]',')
            if ($columnFrequency.ContainsKey($fields.Length)) {
                ++$columnFrequency[$fields.Length]
            }
            else { $columnFrequency.Add($fields.Length, 1) }
        }
        foreach ($line in $dataLines) {
            $lineEmptyFields = @($line.Split([char]',') | Where-Object Length -eq 0).Count
            $emptyFields += $lineEmptyFields
            if ($lineEmptyFields -gt 0) { ++$rowsWithEmptyFields }
        }
        $mode = $columnFrequency.GetEnumerator() | Sort-Object -Property @(
            @{ Expression = 'Value'; Descending = $true },
            @{ Expression = 'Key'; Descending = $false }) | Select-Object -First 1
        [byte[]]$headerBytes = [System.Text.Encoding]::Latin1.GetBytes($header)
        try { $headerSha = Get-LowerSha256 -Bytes $headerBytes }
        finally { [System.Array]::Clear($headerBytes, 0, $headerBytes.Length) }
        return [pscustomobject][ordered]@{
            separator = 'comma'
            rows = $dataLines.Count
            header_columns = $headerFields.Length
            modal_columns = [int]$mode.Key
            modal_line_count = [int]$mode.Value
            minimum_columns = [int](($columnFrequency.Keys | Measure-Object -Minimum).Minimum)
            maximum_columns = [int](($columnFrequency.Keys | Measure-Object -Maximum).Maximum)
            fixed_column_count = $columnFrequency.Count -eq 1
            empty_lines = $emptyLines
            empty_header_fields = $emptyHeaders
            duplicate_header_fields = $duplicateHeaders
            header_sha256 = $headerSha
            empty_data_fields = $emptyFields
            rows_with_empty_fields = $rowsWithEmptyFields
            primary_key = Get-PrimaryKeyCandidate -DataLines $dataLines `
                -HeaderColumns $headerFields.Length
        }
    }
    finally { $latin1 = $null }
}

function Read-CurrentTableMetrics {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Key
    )
    [byte[]]$ciphertext = [System.IO.File]::ReadAllBytes($Path)
    [byte[]]$once = $null
    [byte[]]$plaintext = $null
    [byte[]]$payload = $null
    $failure = 'none'
    try {
        if ($ciphertext.Length -eq 0) { $failure = 'empty-ciphertext'; throw $failure }
        if ($ciphertext.Length % 16 -ne 0) { $failure = 'ciphertext-not-block-aligned'; throw $failure }
        $once = Invoke-AesEcbDecrypt -Ciphertext $ciphertext -Key $Key
        $plaintext = Invoke-AesEcbDecrypt -Ciphertext $once -Key $Key
        $padding = [int]$plaintext[0]
        if ($padding -lt 0 -or $padding -ge 16 -or
            $plaintext.Length -le $padding + 1) {
            $failure = 'invalid-padding-length'; throw $failure
        }
        $payloadEnd = $plaintext.Length - $padding
        for ($index = $payloadEnd; $index -lt $plaintext.Length; ++$index) {
            if ($plaintext[$index] -ne 0) {
                $failure = 'nonzero-padding'; throw $failure
            }
        }
        $payload = [byte[]]::new($payloadEnd - 1)
        [System.Array]::Copy($plaintext, 1, $payload, 0, $payload.Length)
        foreach ($value in $payload) {
            if ($value -eq 0) { $failure = 'embedded-nul'; throw $failure }
        }
        for ($index = 0; $index -lt $payload.Length; ++$index) {
            if ($payload[$index] -eq 10 -and
                ($index -eq 0 -or $payload[$index - 1] -ne 13)) {
                $failure = 'lone-lf'; throw $failure
            }
            if ($payload[$index] -eq 13 -and
                ($index + 1 -ge $payload.Length -or $payload[$index + 1] -ne 10)) {
                $failure = 'lone-cr'; throw $failure
            }
        }
        $encoding = Get-EncodingClassification -Payload $payload
        if ($encoding.classification -eq 'opaque') {
            $failure = 'unsupported-text-encoding'; throw $failure
        }
        $schema = Get-DelimitedMetrics -Payload $payload
        return [pscustomobject][ordered]@{
            success = $true
            failure = 'none'
            payload_bytes = $payload.Length
            padding_bytes = $padding
            encoding = $encoding
            schema = $schema
        }
    }
    catch {
        if ($failure -eq 'none') { $failure = 'decode-or-structure-failure' }
        return [pscustomobject][ordered]@{
            success = $false
            failure = $failure
            payload_bytes = $null
            padding_bytes = $null
            encoding = [pscustomobject][ordered]@{
                classification = 'unavailable'
                strict_utf8 = $false
                strict_gbk = $false
                ascii_only = $false
            }
            schema = [pscustomobject][ordered]@{
                separator = 'unavailable'
                rows = $null
                header_columns = $null
                modal_columns = $null
                modal_line_count = $null
                minimum_columns = $null
                maximum_columns = $null
                fixed_column_count = $null
                empty_lines = $null
                empty_header_fields = $null
                duplicate_header_fields = $null
                header_sha256 = $null
                empty_data_fields = $null
                rows_with_empty_fields = $null
                primary_key = [pscustomobject][ordered]@{
                    classification = 'not-available-decode-failed'
                    one_based_columns = @()
                    verified_unique = $false
                    search_limit_columns = 0
                    duplicate_row_occurrences = $null
                }
            }
        }
    }
    finally {
        [System.Array]::Clear($ciphertext, 0, $ciphertext.Length)
        if ($null -ne $once) { [System.Array]::Clear($once, 0, $once.Length) }
        if ($null -ne $plaintext) { [System.Array]::Clear($plaintext, 0, $plaintext.Length) }
        if ($null -ne $payload) { [System.Array]::Clear($payload, 0, $payload.Length) }
    }
}

$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
$sandbox = [System.IO.Path]::GetFullPath((Join-Path $root 'Data\Backups')).TrimEnd([char[]]'\/')
if (-not $client.StartsWith($sandbox + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-04 input is restricted to a read-only client sandbox under Data/Backups.'
}
if (-not $output.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-04 evidence output must remain inside Rebuild.'
}
$executable = Join-Path $client 'QY.exe'
$executableItem = Get-Item -LiteralPath $executable -ErrorAction Stop
$executableSha = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
if ($executableItem.Length -ne $expectedExecutableBytes -or
    $executableSha -ne $expectedExecutableSha256) {
    throw 'The sandbox executable does not match the P1-09 source binding.'
}
$captureEvidencePath = Join-Path $root 'Data\BuildBaseline\p1-09-runtime-key-capture.json'
$captureEvidenceSha = (Get-FileHash -LiteralPath $captureEvidencePath `
    -Algorithm SHA256).Hash.ToLowerInvariant()
$files = @(Get-ChildItem -LiteralPath @(
        (Join-Path $client 'Table'),
        (Join-Path $client 'CLSVShare')) -Recurse -File -Filter '*.tbl' |
    Sort-Object FullName)
$totalBytes = [long](($files | Measure-Object Length -Sum).Sum)
if ($files.Count -ne $expectedTableCount -or $totalBytes -ne $expectedTableBytes) {
    throw 'The sandbox TBL population does not match the frozen P1-09 population.'
}

[byte[]]$key = Read-StoredKey -Id $SecretId
try {
    $raw = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($client.Length + 1).Replace('\', '/')
        $raw.Add([pscustomobject][ordered]@{
                path = $relative
                group = Get-TableGroup -RelativePath $relative
                ciphertext_bytes = $file.Length
                sha256 = (Get-FileHash -LiteralPath $file.FullName `
                    -Algorithm SHA256).Hash.ToLowerInvariant()
                last_write_utc = $file.LastWriteTimeUtc.ToString('o')
                metrics = Read-CurrentTableMetrics -Path $file.FullName -Key $key
            })
    }
    $byPath = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($entry in $raw) { $byPath.Add($entry.path, $entry) }

    $tables = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $raw) {
        $lifecycle = 'active'
        $replacement = $null
        if (-not $entry.metrics.success) {
            $replacementPath = Get-SupersedingTablePath -RelativePath $entry.path
            if ($null -ne $replacementPath -and $byPath.ContainsKey($replacementPath)) {
                $candidate = $byPath[$replacementPath]
                $newer = [System.DateTimeOffset]::Parse($candidate.last_write_utc) -gt
                    [System.DateTimeOffset]::Parse($entry.last_write_utc)
                if ($candidate.metrics.success -and $newer) {
                    $lifecycle = 'historical-shadow'
                    $replacement = [pscustomobject][ordered]@{
                        path = $candidate.path
                        sha256 = $candidate.sha256
                        last_write_utc = $candidate.last_write_utc
                        active_decode_verified = $true
                        newer_than_historical = $true
                    }
                }
                else { $lifecycle = 'unresolved' }
            }
            else { $lifecycle = 'unresolved' }
        }
        $tables.Add([pscustomobject][ordered]@{
                path = $entry.path
                group = $entry.group
                lifecycle = $lifecycle
                source_version = [pscustomobject][ordered]@{
                    container_snapshot = $sourceBuild
                    content_version = if ($lifecycle -eq 'active') {
                        $sourceBuild
                    }
                    elseif ($lifecycle -eq 'historical-shadow') {
                        'unknown-pre-qy-3.0.0.413'
                    }
                    else { 'unresolved' }
                    exact_content_version_known = $lifecycle -eq 'active'
                }
                ciphertext_bytes = $entry.ciphertext_bytes
                sha256 = $entry.sha256
                last_write_utc = $entry.last_write_utc
                decode = [pscustomobject][ordered]@{
                    attempted = $true
                    success = $entry.metrics.success
                    format = if ($entry.metrics.success) {
                        'double-aes-128-ecb-like-zero-tail-v1'
                    }
                    else { 'not-verified-with-active-runtime-key' }
                    failure = $entry.metrics.failure
                    payload_bytes = $entry.metrics.payload_bytes
                    padding_bytes = $entry.metrics.padding_bytes
                }
                encoding = $entry.metrics.encoding
                schema = $entry.metrics.schema
                replacement = $replacement
            })
    }

    $active = @($tables | Where-Object lifecycle -eq 'active')
    $historical = @($tables | Where-Object lifecycle -eq 'historical-shadow')
    $unresolved = @($tables | Where-Object lifecycle -eq 'unresolved')
    $encodingCounts = @($active | Group-Object { $_.encoding.classification } |
        Sort-Object Name | ForEach-Object {
            [pscustomobject][ordered]@{ encoding = $_.Name; tables = $_.Count }
        })
    $primaryCounts = @($active | Group-Object { $_.schema.primary_key.classification } |
        Sort-Object Name | ForEach-Object {
            [pscustomobject][ordered]@{ classification = $_.Name; tables = $_.Count }
        })
    $schemaCounts = @($active | Group-Object { if ($_.schema.fixed_column_count) {
                    'fixed-columns'
                }
                else { 'variable-columns' } } | Sort-Object Name | ForEach-Object {
            [pscustomobject][ordered]@{ classification = $_.Name; tables = $_.Count }
        })
    $groups = @($tables | Group-Object group | Sort-Object Name | ForEach-Object {
            [pscustomobject][ordered]@{
                group = $_.Name
                files = $_.Count
                active = @($_.Group | Where-Object lifecycle -eq 'active').Count
                historical_shadow = @($_.Group |
                    Where-Object lifecycle -eq 'historical-shadow').Count
                unresolved = @($_.Group | Where-Object lifecycle -eq 'unresolved').Count
            }
        })
    $completed = $tables.Count -eq $expectedTableCount -and
        $active.Count -eq $expectedActiveCount -and
        $historical.Count -eq $expectedHistoricalCount -and
        $unresolved.Count -eq 0 -and
        @($active | Where-Object { -not $_.decode.success -or
                $_.encoding.classification -in @('unavailable', 'opaque') -or
                -not $_.schema.primary_key.classification }).Count -eq 0 -and
        @($historical | Where-Object { $null -eq $_.replacement -or
                $_.decode.success -or $_.decode.failure -eq 'none' }).Count -eq 0

    $report = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [System.DateTimeOffset]::UtcNow.ToString('o')
        result = if ($completed) { 'PASS' } else { 'FAIL' }
        task = 'P2-04'
        task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
        completion_criteria_satisfied = $completed
        source = [pscustomobject][ordered]@{
            kind = 'read-only-sandbox-client'
            build = $sourceBuild
            sandbox_relative_path = 'Data/Backups/p1-09-runtime-client'
            executable = [pscustomobject][ordered]@{
                path = 'QY.exe'
                bytes = $executableItem.Length
                sha256 = $executableSha
            }
            population = [pscustomobject][ordered]@{
                files = $files.Count
                ciphertext_bytes = $totalBytes
            }
        }
        runtime_key_binding = [pscustomobject][ordered]@{
            provider_reference = "se://$SecretId"
            fingerprint = $expectedKeyFingerprint
            p1_09_capture_evidence = 'Data/BuildBaseline/p1-09-runtime-key-capture.json'
            p1_09_capture_evidence_sha256 = $captureEvidenceSha
            executable_sha256 = $executableSha
            raw_key_emitted = $false
            plaintext_emitted = $false
            field_identifiers_emitted = $false
            in_memory_buffers_cleared = $true
        }
        summary = [pscustomobject][ordered]@{
            files = $tables.Count
            active = $active.Count
            historical_shadow = $historical.Count
            unresolved = $unresolved.Count
            decoded = @($tables | Where-Object { $_.decode.success }).Count
            decode_failures_classified = @($tables | Where-Object {
                    -not $_.decode.success -and $_.decode.failure -ne 'none'
                }).Count
            active_rows = [long](($active.schema | Measure-Object rows -Sum).Sum)
            active_payload_bytes = [long](($active.decode |
                    Measure-Object payload_bytes -Sum).Sum)
            encoding_counts = $encodingCounts
            schema_counts = $schemaCounts
            primary_key_counts = $primaryCounts
        }
        groups = $groups
        tables = @($tables)
        interpretation = [pscustomobject][ordered]@{
            row_count_excludes_header = $true
            column_counts_are_comma_delimited_physical_widths = $true
            primary_keys_are_candidates_not_authoritative_schema = $true
            primary_key_prefix_search_limit = 8
            historical_row_column_encoding_unavailable_reason =
                'The active runtime key intentionally does not decode the superseded ciphertext; no legacy key is guessed.'
            historical_replacement_rule =
                'Each failed Table/Regions, Table/help, or stale Table/local copy must have a newer successfully decoded active replacement.'
        }
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-05', 'P2-06', 'P2-11')
            detail = 'Use the explicit lifecycle, physical schema, encoding, and key-candidate classifications without normalizing historical shadows.'
        }
    }
    $json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.Directory]::CreateDirectory(
        [System.IO.Path]::GetDirectoryName($output)) | Out-Null
    [System.IO.File]::WriteAllText(
        $output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    $report | ConvertTo-Json -Depth 5
    if (-not $completed) { throw 'P2-04 current-table inventory did not satisfy completion criteria.' }
}
finally { [System.Array]::Clear($key, 0, $key.Length) }
