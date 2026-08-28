[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\Rebuild\Data\Backups\p1-09-runtime-client',
    [string]$OutputPath =
        'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-10-current-item-csv-relation.json',
    [ValidatePattern('^[a-z0-9][a-z0-9./-]+$')]
    [string]$SecretId = 'tmxy/development/table/qy-3.0.0.413/runtime-key-base64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$credentialTargetPrefix = 'com.docker.pass.shared:docker-pass-cli:'
$expectedKeyFingerprint =
    'cf760550b7af6c220331b258db1df781fe567221eb7c53fbfc65aca522085887'
$itemRelativePath = 'CLSVShare/item_table.tbl'
$residualRelativePath = 'CLSVShare/item_tabletemp.csv'

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Initialize-CredentialType {
    if ($null -ne ('TmxyP110Credential' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TmxyP110Credential
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
    $target = $credentialTargetPrefix + $Id
    if (-not [TmxyP110Credential]::CredRead($target, 1, 0, [ref]$pointer)) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "The current-table keychain entry is unavailable (code $code)."
    }
    [byte[]]$blob = $null
    [byte[]]$key = $null
    try {
        $credential = [System.Runtime.InteropServices.Marshal]::PtrToStructure[
            TmxyP110Credential+Credential]($pointer)
        $blob = [byte[]]::new($credential.CredentialBlobSize)
        [System.Runtime.InteropServices.Marshal]::Copy(
            $credential.CredentialBlob, $blob, 0, $blob.Length)
        $encoded = [System.Text.Encoding]::Unicode.GetString($blob).TrimEnd("`0", "`r", "`n")
        try { $key = [System.Convert]::FromBase64String($encoded) }
        finally { $encoded = $null }
        if ($key.Length -ne 16 -or (Get-LowerSha256 -Bytes $key) -ne $expectedKeyFingerprint) {
            [System.Array]::Clear($key, 0, $key.Length)
            throw 'The stored current-table key fingerprint does not match P1-09 evidence.'
        }
        return ,$key
    }
    finally {
        if ($null -ne $blob) { [System.Array]::Clear($blob, 0, $blob.Length) }
        [TmxyP110Credential]::CredFree($pointer)
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

function Read-CurrentPayload {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Key
    )
    [byte[]]$ciphertext = [System.IO.File]::ReadAllBytes($Path)
    [byte[]]$once = $null
    [byte[]]$plaintext = $null
    try {
        if ($ciphertext.Length -eq 0 -or $ciphertext.Length % 16 -ne 0) {
            throw 'Current item TBL is empty or not block aligned.'
        }
        $once = Invoke-AesEcbDecrypt -Ciphertext $ciphertext -Key $Key
        $plaintext = Invoke-AesEcbDecrypt -Ciphertext $once -Key $Key
        $padding = [int]$plaintext[0]
        if ($padding -lt 0 -or $padding -ge 16 -or $plaintext.Length -le $padding + 1) {
            throw 'Current item TBL padding length is invalid.'
        }
        $payloadEnd = $plaintext.Length - $padding
        for ($index = $payloadEnd; $index -lt $plaintext.Length; ++$index) {
            if ($plaintext[$index] -ne 0) { throw 'Current item TBL padding is nonzero.' }
        }
        [byte[]]$payload = [byte[]]::new($payloadEnd - 1)
        [System.Array]::Copy($plaintext, 1, $payload, 0, $payload.Length)
        return ,$payload
    }
    finally {
        [System.Array]::Clear($ciphertext, 0, $ciphertext.Length)
        if ($null -ne $once) { [System.Array]::Clear($once, 0, $once.Length) }
        if ($null -ne $plaintext) {
            [System.Array]::Clear($plaintext, 0, $plaintext.Length)
        }
    }
}

function Get-LineIndex {
    param([Parameter(Mandatory = $true)][byte[]]$Payload)
    $lines = [System.Collections.Generic.List[object]]::new()
    $start = 0
    for ($index = 0; $index -lt $Payload.Length; ++$index) {
        if ($Payload[$index] -eq 0) { throw 'CSV relation input contains an embedded NUL.' }
        if ($Payload[$index] -eq 10) {
            if ($index -eq 0 -or $Payload[$index - 1] -ne 13) {
                throw 'CSV relation input contains a lone LF.'
            }
        }
        elseif ($Payload[$index] -eq 13) {
            if ($index + 1 -ge $Payload.Length -or $Payload[$index + 1] -ne 10) {
                throw 'CSV relation input contains a lone CR.'
            }
            if ($index -gt $start) {
                $lines.Add([pscustomobject][ordered]@{
                        offset = $start
                        length = $index - $start
                    })
            }
            ++$index
            $start = $index + 1
        }
    }
    if ($start -lt $Payload.Length) {
        $lines.Add([pscustomobject][ordered]@{
                offset = $start
                length = $Payload.Length - $start
            })
    }
    if ($lines.Count -lt 2) { throw 'CSV relation input has no data rows.' }
    return ,$lines
}

function Get-RangeBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Length
    )
    [byte[]]$result = [byte[]]::new($Length)
    [System.Array]::Copy($Bytes, $Offset, $result, 0, $Length)
    return ,$result
}

function Get-CommaCount {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Length
    )
    $count = 0
    for ($index = $Offset; $index -lt $Offset + $Length; ++$index) {
        if ($Bytes[$index] -eq 44) { ++$count }
    }
    return $count
}

function Get-RowIndex {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Payload,
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[object]]$Lines
    )
    $header = $Lines[0]
    [byte[]]$headerBytes = Get-RangeBytes -Bytes $Payload -Offset $header.offset `
        -Length $header.length
    try {
        $headerFingerprint = Get-LowerSha256 -Bytes $headerBytes
    }
    finally {
        [System.Array]::Clear($headerBytes, 0, $headerBytes.Length)
    }
    $columns = (Get-CommaCount -Bytes $Payload -Offset $header.offset `
        -Length $header.length) + 1
    $rows = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::Ordinal)
    $duplicateKeys = 0
    $decimalKeys = $true
    $consistentRows = 0
    for ($lineIndex = 1; $lineIndex -lt $Lines.Count; ++$lineIndex) {
        $line = $Lines[$lineIndex]
        $firstComma = -1
        for ($index = $line.offset; $index -lt $line.offset + $line.length; ++$index) {
            if ($Payload[$index] -eq 44) {
                $firstComma = $index
                break
            }
        }
        if ($firstComma -le $line.offset) {
            throw 'CSV relation row has no nonempty first field.'
        }
        [byte[]]$keyBytes = Get-RangeBytes -Bytes $Payload -Offset $line.offset `
            -Length ($firstComma - $line.offset)
        [byte[]]$rowBytes = Get-RangeBytes -Bytes $Payload -Offset $line.offset `
            -Length $line.length
        try {
            for ($index = 0; $index -lt $keyBytes.Length; ++$index) {
                if ($keyBytes[$index] -lt 48 -or $keyBytes[$index] -gt 57) {
                    $decimalKeys = $false
                    break
                }
            }
            $key = [System.Convert]::ToBase64String($keyBytes)
            $rowFingerprint = Get-LowerSha256 -Bytes $rowBytes
            if ($rows.ContainsKey($key)) { ++$duplicateKeys }
            else { $rows.Add($key, $rowFingerprint) }
            if ((Get-CommaCount -Bytes $Payload -Offset $line.offset `
                    -Length $line.length) + 1 -eq $columns) {
                ++$consistentRows
            }
        }
        finally {
            [System.Array]::Clear($keyBytes, 0, $keyBytes.Length)
            [System.Array]::Clear($rowBytes, 0, $rowBytes.Length)
        }
    }
    return [pscustomobject][ordered]@{
        header_fingerprint = $headerFingerprint
        columns = $columns
        row_count = $Lines.Count - 1
        consistent_column_rows = $consistentRows
        primary_key_unique_count = $rows.Count
        duplicate_primary_keys = $duplicateKeys
        primary_keys_ascii_decimal = $decimalKeys
        rows = $rows
    }
}

function Test-ByteEquality {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][int]$LeftOffset,
        [Parameter(Mandatory = $true)][int]$LeftLength,
        [Parameter(Mandatory = $true)][byte[]]$Right,
        [Parameter(Mandatory = $true)][int]$RightOffset,
        [Parameter(Mandatory = $true)][int]$RightLength
    )
    if ($LeftLength -ne $RightLength) { return $false }
    for ($index = 0; $index -lt $LeftLength; ++$index) {
        if ($Left[$LeftOffset + $index] -ne $Right[$RightOffset + $index]) { return $false }
    }
    return $true
}

$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
$sandbox = [System.IO.Path]::GetFullPath((Join-Path $root 'Data\Backups')).TrimEnd([char[]]'\/')
if (-not $client.StartsWith($sandbox + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P1-10 comparison is restricted to the client sandbox under Data/Backups.'
}
if (-not $output.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P1-10 evidence output must remain inside Rebuild.'
}
$itemPath = Join-Path $client $itemRelativePath.Replace(
    '/', [System.IO.Path]::DirectorySeparatorChar)
$residualPath = Join-Path $client $residualRelativePath.Replace(
    '/', [System.IO.Path]::DirectorySeparatorChar)
$item = Get-Item -LiteralPath $itemPath -ErrorAction Stop
$residual = Get-Item -LiteralPath $residualPath -ErrorAction Stop
$itemSha = (Get-FileHash -LiteralPath $itemPath -Algorithm SHA256).Hash.ToLowerInvariant()
$residualSha = (Get-FileHash -LiteralPath $residualPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($item.Length -ne 7046704 -or
    $itemSha -ne 'f0ccd185f736802661becb9581896497e2101f6a9dbcb28578d5351f71f820ce' -or
    $residual.Length -ne 6551430 -or
    $residualSha -ne '2a16d952fe398571a3ae2f926acb7ecd8b3c2a843bc0b62e1cb2be463fcf39dd') {
    throw 'P1-10 frozen item-table input changed.'
}

[byte[]]$key = Read-StoredKey -Id $SecretId
[byte[]]$currentPayload = $null
[byte[]]$residualPayload = $null
try {
    $currentPayload = Read-CurrentPayload -Path $itemPath -Key $key
    $residualPayload = [System.IO.File]::ReadAllBytes($residualPath)
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
    $strictGbk = [System.Text.Encoding]::GetEncoding(
        936,
        [System.Text.EncoderExceptionFallback]::new(),
        [System.Text.DecoderExceptionFallback]::new())
    $currentGbk = $true
    $residualGbk = $true
    try { [void]$strictGbk.GetString($currentPayload) }
    catch [System.Text.DecoderFallbackException] { $currentGbk = $false }
    try { [void]$strictGbk.GetString($residualPayload) }
    catch [System.Text.DecoderFallbackException] { $residualGbk = $false }

    $currentLines = Get-LineIndex -Payload $currentPayload
    $residualLines = Get-LineIndex -Payload $residualPayload
    $currentIndex = Get-RowIndex -Payload $currentPayload -Lines $currentLines
    $residualIndex = Get-RowIndex -Payload $residualPayload -Lines $residualLines

    $sharedKeys = 0
    $identicalRows = 0
    $changedRows = 0
    foreach ($entry in $currentIndex.rows.GetEnumerator()) {
        if ($residualIndex.rows.ContainsKey($entry.Key)) {
            ++$sharedKeys
            if ($residualIndex.rows[$entry.Key] -eq $entry.Value) { ++$identicalRows }
            else { ++$changedRows }
        }
    }
    $currentOnly = $currentIndex.rows.Count - $sharedKeys
    $residualOnly = $residualIndex.rows.Count - $sharedKeys

    $commonPrefixBytes = 0
    $minimumBytes = [System.Math]::Min($currentPayload.Length, $residualPayload.Length)
    while ($commonPrefixBytes -lt $minimumBytes -and
        $currentPayload[$commonPrefixBytes] -eq $residualPayload[$commonPrefixBytes]) {
        ++$commonPrefixBytes
    }
    $headerEqual = Test-ByteEquality -Left $currentPayload `
        -LeftOffset $currentLines[0].offset -LeftLength $currentLines[0].length `
        -Right $residualPayload -RightOffset $residualLines[0].offset `
        -RightLength $residualLines[0].length
    $ordinalIdentical = 0
    $firstDifferentLine = -1
    $minimumLines = [System.Math]::Min($currentLines.Count, $residualLines.Count)
    for ($lineIndex = 0; $lineIndex -lt $minimumLines; ++$lineIndex) {
        $same = Test-ByteEquality -Left $currentPayload `
            -LeftOffset $currentLines[$lineIndex].offset `
            -LeftLength $currentLines[$lineIndex].length `
            -Right $residualPayload -RightOffset $residualLines[$lineIndex].offset `
            -RightLength $residualLines[$lineIndex].length
        if ($same) { ++$ordinalIdentical }
        elseif ($firstDifferentLine -lt 0) { $firstDifferentLine = $lineIndex }
    }

    $completion = $currentGbk -and $residualGbk -and
        $currentIndex.columns -gt 1 -and $residualIndex.columns -gt 1 -and
        $currentIndex.duplicate_primary_keys -eq 0 -and
        $residualIndex.duplicate_primary_keys -eq 0 -and
        ($currentPayload.Length -ne $residualPayload.Length -or $changedRows -gt 0 -or
            $currentOnly -gt 0 -or $residualOnly -gt 0)
    $report = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [System.DateTimeOffset]::UtcNow.ToString('o')
        result = if ($completion) { 'PASS' } else { 'FAIL' }
        task = 'P1-10'
        task_status = if ($completion) { 'COMPLETE' } else { 'IN_PROGRESS' }
        completion_criteria_satisfied = $completion
        inputs = @(
            [pscustomobject][ordered]@{
                role = 'current_encrypted_table'
                path = $itemRelativePath
                size = $item.Length
                sha256 = $itemSha
            },
            [pscustomobject][ordered]@{
                role = 'residual_plaintext_candidate'
                path = $residualRelativePath
                size = $residual.Length
                sha256 = $residualSha
            }
        )
        processing = [pscustomobject][ordered]@{
            runtime_key_fingerprint = $expectedKeyFingerprint
            secret_reference = "se://$SecretId"
            double_aes128_decode = $true
            current_payload_bytes = $currentPayload.Length
            current_strict_gbk = $currentGbk
            residual_strict_gbk = $residualGbk
            raw_key_emitted = $false
            plaintext_emitted = $false
            buffers_cleared = $true
        }
        schema_relation = [pscustomobject][ordered]@{
            header_exact_match = $headerEqual
            current_header_sha256 = $currentIndex.header_fingerprint
            residual_header_sha256 = $residualIndex.header_fingerprint
            current_columns = $currentIndex.columns
            residual_columns = $residualIndex.columns
            current_rows = $currentIndex.row_count
            residual_rows = $residualIndex.row_count
            current_consistent_column_rows = $currentIndex.consistent_column_rows
            residual_consistent_column_rows = $residualIndex.consistent_column_rows
        }
        primary_key_relation = [pscustomobject][ordered]@{
            field_ordinal = 0
            current_unique = $currentIndex.duplicate_primary_keys -eq 0
            residual_unique = $residualIndex.duplicate_primary_keys -eq 0
            current_ascii_decimal = $currentIndex.primary_keys_ascii_decimal
            residual_ascii_decimal = $residualIndex.primary_keys_ascii_decimal
            shared = $sharedKeys
            identical_rows = $identicalRows
            changed_rows = $changedRows
            current_only = $currentOnly
            residual_only = $residualOnly
        }
        positional_relation = [pscustomobject][ordered]@{
            common_prefix_bytes = $commonPrefixBytes
            compared_line_ordinals = $minimumLines
            identical_line_ordinals = $ordinalIdentical
            first_different_line_ordinal = $firstDifferentLine
        }
        conclusion = [pscustomobject][ordered]@{
            exact_replacement = $false
            residual_can_replace_current_table = $false
            permitted_use = 'schema and historical row-difference evidence only'
        }
    }
    $json = ($report | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.Directory]::CreateDirectory(
        [System.IO.Path]::GetDirectoryName($output)) | Out-Null
    [System.IO.File]::WriteAllText(
        $output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    $json
    if (-not $completion) { throw 'P1-10 relation evidence did not satisfy its contract.' }
}
finally {
    [System.Array]::Clear($key, 0, $key.Length)
    if ($null -ne $currentPayload) {
        [System.Array]::Clear($currentPayload, 0, $currentPayload.Length)
    }
    if ($null -ne $residualPayload) {
        [System.Array]::Clear($residualPayload, 0, $residualPayload.Length)
    }
}
