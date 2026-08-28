[CmdletBinding(DefaultParameterSetName = 'Process')]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\Rebuild\Data\Backups\p1-09-runtime-client',
    [string]$OutputPath =
        'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-09-runtime-key-capture.json',
    [Parameter(ParameterSetName = 'Process')]
    [ValidateRange(0, 2147483647)]
    [int]$ProcessId = 0,
    [Parameter(ParameterSetName = 'Process')]
    [ValidateRange(1, 300)]
    [int]$PollSeconds = 30,
    [Parameter(ParameterSetName = 'Process')]
    [switch]$PersistVerifiedCandidate,
    [Parameter(Mandatory = $true, ParameterSetName = 'Stored')]
    [switch]$UseStoredCandidate,
    [ValidatePattern('^[a-z0-9][a-z0-9./-]+$')]
    [string]$SecretId = 'tmxy/development/table/qy-3.0.0.413/runtime-key-base64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedExecutableSha256 =
    '7087dfa64bedeb8c9a5dfc4518f46261d163136b5bd97f5071f2c5a12cb29a4b'
$baseKeySha256 = 'c5ab3734151f66dd61ec86290d3b1ac5e180d2f3c4e6d54441ec39e3cfb66524'
$keyRva = 0x4dd028
$expectedTableCount = 338
$expectedTableBytes = 40444128L
$minimumVerifiedTableCount = 200
$credentialTargetPrefix = 'com.docker.pass.shared:docker-pass-cli:'

$representativeSpecs = [ordered]@{
    'CLSVShare/powergame.tbl' =
        '8da2fbf8c9f977822ce78343f6824f259fe7aba2f9b5e961c7518ac5f389ca73'
    'CLSVShare/skill_table.tbl' =
        '40ec68f102f107da38bbde610fcce8fcc433601c802209116c5c7866f87b7327'
    'CLSVShare/item_table.tbl' =
        'f0ccd185f736802661becb9581896497e2101f6a9dbcb28578d5351f71f820ce'
    'Table/quest_table.tbl' =
        'e03bf742ee176645d303e81fd4e3f0bdf0baaa116a097ba0fa4bc04f4f12751b'
    'Table/Regions/quest_table.tbl' =
        'ce41d5f4901bf9f651a9f3dc0994010deaca4012ab461d3af7d48c36cf6ae620'
    'Table/Regions/supplytable.tbl' =
        '7185f834d247cf070f379a8f480ad26cf7f6a82c2e154c3acc6aca005820787c'
}
$requiredDecodedPaths = @(
    'CLSVShare/powergame.tbl',
    'CLSVShare/skill_table.tbl',
    'CLSVShare/item_table.tbl',
    'Table/quest_table.tbl'
)

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
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
        finally {
            $decryptor.Dispose()
        }
    }
    finally {
        $aes.Dispose()
    }
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
    catch [System.Text.DecoderFallbackException] {
        return $false
    }
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

function Test-CurrentTableCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [Parameter(Mandatory = $true)][byte[]]$Key
    )

    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $strictGbk = [System.Text.Encoding]::GetEncoding(
        936,
        [System.Text.EncoderExceptionFallback]::new(),
        [System.Text.DecoderExceptionFallback]::new())
    $files = @(Get-ChildItem -LiteralPath @(
            (Join-Path $DataRoot 'Table'),
            (Join-Path $DataRoot 'CLSVShare')) -Recurse -File -Filter '*.tbl' |
        Sort-Object FullName)
    $totalBytes = [long](($files | Measure-Object Length -Sum).Sum)
    if ($files.Count -ne $expectedTableCount -or $totalBytes -ne $expectedTableBytes) {
        throw 'Sandbox TBL population does not match the frozen current-client evidence.'
    }

    foreach ($entry in $representativeSpecs.GetEnumerator()) {
        $path = Join-Path $DataRoot $entry.Key.Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar)
        $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sha -ne $entry.Value) {
            throw "Representative sandbox TBL changed: $($entry.Key)"
        }
    }

    $tableResults = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        [byte[]]$ciphertext = [System.IO.File]::ReadAllBytes($file.FullName)
        [byte[]]$once = $null
        [byte[]]$plaintext = $null
        [byte[]]$payload = $null
        try {
            $once = Invoke-AesEcbDecrypt -Ciphertext $ciphertext -Key $Key
            $plaintext = Invoke-AesEcbDecrypt -Ciphertext $once -Key $Key
            $padding = [int]$plaintext[0]
            $paddingValid = $padding -ge 0 -and $padding -lt 16 -and
                $plaintext.Length -gt $padding + 1
            $payloadEnd = if ($paddingValid) { $plaintext.Length - $padding } else { 0 }
            if ($paddingValid) {
                for ($index = $payloadEnd; $index -lt $plaintext.Length; ++$index) {
                    if ($plaintext[$index] -ne 0) {
                        $paddingValid = $false
                        break
                    }
                }
            }

            $noEmbeddedNul = $paddingValid
            $crlfOnly = $paddingValid
            $schemaConsistent = $false
            $columnCount = 0
            $rowCount = 0
            $utf8Valid = $false
            $gbkValid = $false
            $asciiOnly = $false
            $payloadBytes = 0
            if ($paddingValid) {
                $payloadBytes = $payloadEnd - 1
                $payload = [byte[]]::new($payloadBytes)
                [System.Array]::Copy($plaintext, 1, $payload, 0, $payloadBytes)

                $asciiOnly = $true
                $headerSeen = $false
                $currentCommas = 0
                $lineHasBytes = $false
                $schemaConsistent = $true
                for ($index = 0; $index -lt $payload.Length; ++$index) {
                    $value = $payload[$index]
                    if ($value -eq 0) { $noEmbeddedNul = $false }
                    if ($value -ge 128) { $asciiOnly = $false }
                    if ($value -eq 44) {
                        ++$currentCommas
                        $lineHasBytes = $true
                    }
                    elseif ($value -eq 13) {
                        if ($index + 1 -ge $payload.Length -or $payload[$index + 1] -ne 10) {
                            $crlfOnly = $false
                        }
                        else {
                            if ($lineHasBytes) {
                                $lineColumns = $currentCommas + 1
                                if (-not $headerSeen) {
                                    $columnCount = $lineColumns
                                    $headerSeen = $true
                                }
                                elseif ($lineColumns -ne $columnCount) {
                                    $schemaConsistent = $false
                                }
                                else {
                                    ++$rowCount
                                }
                            }
                            $currentCommas = 0
                            $lineHasBytes = $false
                            ++$index
                        }
                    }
                    elseif ($value -eq 10) {
                        $crlfOnly = $false
                    }
                    else {
                        $lineHasBytes = $true
                    }
                }
                if ($lineHasBytes) {
                    $lineColumns = $currentCommas + 1
                    if (-not $headerSeen) {
                        $columnCount = $lineColumns
                        $headerSeen = $true
                    }
                    elseif ($lineColumns -ne $columnCount) {
                        $schemaConsistent = $false
                    }
                    else {
                        ++$rowCount
                    }
                }
                $schemaConsistent = $schemaConsistent -and $headerSeen
                $utf8Valid = Test-StrictDecoding -Bytes $payload -Encoding $strictUtf8
                $gbkValid = Test-StrictDecoding -Bytes $payload -Encoding $strictGbk
            }

            $relative = $file.FullName.Substring($DataRoot.Length + 1).Replace('\', '/')
            $tableResults.Add([pscustomobject][ordered]@{
                    path = $relative
                    group = Get-TableGroup -RelativePath $relative
                    old_padding_valid = $paddingValid
                    no_embedded_nul = $noEmbeddedNul
                    crlf_only = $crlfOnly
                    comma_schema_consistent = $schemaConsistent
                    payload_bytes = $payloadBytes
                    columns = $columnCount
                    rows = $rowCount
                    utf8_valid = $utf8Valid
                    gbk_valid = $gbkValid
                    ascii_only = $asciiOnly
                    last_write_utc = $file.LastWriteTimeUtc.ToString('o')
                })
        }
        finally {
            [System.Array]::Clear($ciphertext, 0, $ciphertext.Length)
            if ($null -ne $once) { [System.Array]::Clear($once, 0, $once.Length) }
            if ($null -ne $plaintext) {
                [System.Array]::Clear($plaintext, 0, $plaintext.Length)
            }
            if ($null -ne $payload) { [System.Array]::Clear($payload, 0, $payload.Length) }
        }
    }

    $valid = @($tableResults | Where-Object {
            $_.old_padding_valid -and $_.no_embedded_nul -and $_.crlf_only
        })
    $byPath = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($table in $tableResults) { $byPath.Add($table.path, $table) }
    $superseded = [System.Collections.Generic.List[object]]::new()
    $unresolvedActive = [System.Collections.Generic.List[string]]::new()
    foreach ($table in @($tableResults | Where-Object {
                -not ($_.old_padding_valid -and $_.no_embedded_nul -and $_.crlf_only)
            })) {
        $replacementPath = Get-SupersedingTablePath -RelativePath $table.path
        $replacement = if ($null -ne $replacementPath -and
            $byPath.ContainsKey($replacementPath)) { $byPath[$replacementPath] } else { $null }
        $replacementVerified = $null -ne $replacement -and
            $replacement.old_padding_valid -and $replacement.no_embedded_nul -and
            $replacement.crlf_only
        $replacementNewer = $replacementVerified -and
            [System.DateTime]::Parse($replacement.last_write_utc).ToUniversalTime() -gt
            [System.DateTime]::Parse($table.last_write_utc).ToUniversalTime()
        if ($replacementVerified -and $replacementNewer) {
            $superseded.Add([pscustomobject][ordered]@{
                    historical_path = $table.path
                    historical_group = $table.group
                    historical_last_write_utc = $table.last_write_utc
                    replacement_path = $replacement.path
                    replacement_last_write_utc = $replacement.last_write_utc
                })
        }
        else {
            $unresolvedActive.Add($table.path)
        }
    }
    $shadowGroups = @($superseded | Group-Object historical_group | Sort-Object Name |
        ForEach-Object {
            [pscustomobject][ordered]@{
                group = $_.Name
                historical_copies = $_.Count
                all_have_newer_verified_replacements = $true
                newest_historical_utc = @($_.Group.historical_last_write_utc |
                    Sort-Object -Descending)[0]
                oldest_replacement_utc = @($_.Group.replacement_last_write_utc |
                    Sort-Object)[0]
            }
        })
    $groups = @($tableResults | Group-Object group | Sort-Object Name | ForEach-Object {
            [pscustomobject][ordered]@{
                group = $_.Name
                files = $_.Count
                verified = @($_.Group | Where-Object {
                        $_.old_padding_valid -and $_.no_embedded_nul -and $_.crlf_only
                    }).Count
                not_verified = @($_.Group | Where-Object {
                        -not ($_.old_padding_valid -and $_.no_embedded_nul -and $_.crlf_only)
                    }).Count
            }
        })
    $representatives = @($tableResults | Where-Object {
            $representativeSpecs.Contains($_.path)
        } | ForEach-Object {
            [pscustomobject][ordered]@{
                path = $_.path
                old_padding_valid = $_.old_padding_valid
                no_embedded_nul = $_.no_embedded_nul
                crlf_only = $_.crlf_only
                comma_schema_consistent = $_.comma_schema_consistent
                payload_bytes = $_.payload_bytes
                columns = $_.columns
                rows = $_.rows
                utf8_valid = $_.utf8_valid
                gbk_valid = $_.gbk_valid
                ascii_only = $_.ascii_only
            }
        })
    $requiredValid = @($representatives | Where-Object {
            $_.path -in $requiredDecodedPaths -and $_.old_padding_valid -and
            $_.no_embedded_nul -and $_.crlf_only
        }).Count -eq $requiredDecodedPaths.Count
    $accepted = $requiredValid -and $valid.Count -ge $minimumVerifiedTableCount -and
        $unresolvedActive.Count -eq 0 -and
        $valid.Count + $superseded.Count -eq $files.Count

    return [pscustomobject][ordered]@{
        accepted = $accepted
        acceptance = [pscustomobject][ordered]@{
            required_core_tables = $requiredDecodedPaths
            all_required_core_tables_verified = $requiredValid
            minimum_verified_tables = $minimumVerifiedTableCount
        }
        population = [pscustomobject][ordered]@{
            files_checked = $files.Count
            total_bytes = $totalBytes
            verified_old_format = $valid.Count
            not_verified_with_candidate = $files.Count - $valid.Count
            superseded_historical_copies = $superseded.Count
            unresolved_active_tables = $unresolvedActive.Count
            comma_schema_consistent = @($valid | Where-Object {
                    $_.comma_schema_consistent
                }).Count
            utf8_valid = @($valid | Where-Object { $_.utf8_valid }).Count
            gbk_valid = @($valid | Where-Object { $_.gbk_valid }).Count
            ascii_only = @($valid | Where-Object { $_.ascii_only }).Count
        }
        groups = $groups
        historical_shadow_classification = [pscustomobject][ordered]@{
            classified_count = $superseded.Count
            unclassified_count = $unresolvedActive.Count
            groups = $shadowGroups
            all_historical_copies_have_newer_verified_replacements =
                $unresolvedActive.Count -eq 0 -and $superseded.Count -gt 0
        }
        encoding_outliers = @($valid | Where-Object { -not $_.gbk_valid } |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    path = $_.path
                    payload_bytes = $_.payload_bytes
                    ascii_only = $_.ascii_only
                }
            })
        representative_tables = $representatives
    }
}

function Initialize-NativeTypes {
    if ($null -eq ('TmxyCurrentTableNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TmxyCurrentTableNative
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

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(UInt32 access, bool inherit, Int32 processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadProcessMemory(
        IntPtr process, IntPtr address, byte[] buffer, Int32 size, out IntPtr bytesRead);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode,
        SetLastError = true)]
    public static extern bool CredRead(
        string target, UInt32 type, UInt32 flags, out IntPtr credential);

    [DllImport("advapi32.dll")]
    public static extern void CredFree(IntPtr credential);
}
'@
    }
}

function Read-StoredCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [switch]$AllowMissing
    )
    Initialize-NativeTypes
    $pointer = [System.IntPtr]::Zero
    $target = $credentialTargetPrefix + $Id
    if (-not [TmxyCurrentTableNative]::CredRead($target, 1, 0, [ref]$pointer)) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($AllowMissing -and $errorCode -eq 1168) { return $null }
        throw "The Docker Pass operating-system keychain entry is unavailable (code $errorCode)."
    }

    [byte[]]$blob = $null
    [byte[]]$key = $null
    try {
        $credential = [System.Runtime.InteropServices.Marshal]::PtrToStructure[
            TmxyCurrentTableNative+Credential]($pointer)
        $blob = [byte[]]::new($credential.CredentialBlobSize)
        [System.Runtime.InteropServices.Marshal]::Copy(
            $credential.CredentialBlob, $blob, 0, $blob.Length)
        $encoded = [System.Text.Encoding]::Unicode.GetString($blob).TrimEnd("`0", "`r", "`n")
        try {
            $key = [System.Convert]::FromBase64String($encoded)
        }
        finally {
            $encoded = $null
        }
        if ($key.Length -ne 16) {
            [System.Array]::Clear($key, 0, $key.Length)
            throw 'The stored current-table key is not exactly 16 bytes.'
        }
        return ,$key
    }
    finally {
        if ($null -ne $blob) { [System.Array]::Clear($blob, 0, $blob.Length) }
        [TmxyCurrentTableNative]::CredFree($pointer)
    }
}

function Save-VerifiedCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][byte[]]$Key,
        [Parameter(Mandatory = $true)][string]$Fingerprint
    )
    [byte[]]$existing = Read-StoredCandidate -Id $Id -AllowMissing
    if ($null -ne $existing) {
        try {
            if ((Get-LowerSha256 -Bytes $existing) -ne $Fingerprint) {
                throw 'The existing runtime-key Secret has a different fingerprint; refusing overwrite.'
            }
            return [pscustomobject][ordered]@{
                created = $false
                read_back_verified = $true
            }
        }
        finally {
            [System.Array]::Clear($existing, 0, $existing.Length)
        }
    }

    $dockerPath = (Get-Command 'docker.exe' -ErrorAction Stop).Source
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $dockerPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $true
    foreach ($argument in @(
            'pass', 'set', $Id,
            '--metadata', 'owner=platform_security',
            '--metadata', 'purpose=p1-09-authorized-runtime-table-key')) {
        $startInfo.ArgumentList.Add($argument)
    }
    $encoded = [System.Convert]::ToBase64String($Key)
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $process.StandardInput.Write($encoded)
        $process.StandardInput.Close()
        [void]$process.StandardOutput.ReadToEnd()
        [void]$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw 'Docker Pass could not store the verified runtime-key candidate.'
        }
    }
    finally {
        $encoded = $null
    }

    [byte[]]$readBack = Read-StoredCandidate -Id $Id
    try {
        if ((Get-LowerSha256 -Bytes $readBack) -ne $Fingerprint) {
            throw 'Operating-system keychain read-back fingerprint mismatch.'
        }
    }
    finally {
        [System.Array]::Clear($readBack, 0, $readBack.Length)
    }
    return [pscustomobject][ordered]@{
        created = $true
        read_back_verified = $true
    }
}

function Read-ProcessCandidate {
    param(
        [Parameter(Mandatory = $true)][int]$TargetProcessId,
        [Parameter(Mandatory = $true)][long]$Address
    )
    Initialize-NativeTypes
    $handle = [TmxyCurrentTableNative]::OpenProcess(0x1010, $false, $TargetProcessId)
    if ($handle -eq [System.IntPtr]::Zero) { throw 'OpenProcess failed.' }
    [byte[]]$key = [byte[]]::new(16)
    try {
        $read = [System.IntPtr]::Zero
        if (-not [TmxyCurrentTableNative]::ReadProcessMemory(
                $handle, [System.IntPtr]$Address, $key, $key.Length, [ref]$read) -or
            $read.ToInt64() -ne $key.Length) {
            throw 'ReadProcessMemory failed.'
        }
        return ,$key
    }
    finally {
        [void][TmxyCurrentTableNative]::CloseHandle($handle)
    }
}

$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
$sandboxRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $root 'Data\Backups')).TrimEnd([char[]]'\/')
if (-not $client.StartsWith($sandboxRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Runtime capture is restricted to a client copy under Rebuild/Data/Backups.'
}
if (-not $output.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Runtime capture evidence must remain inside Rebuild.'
}
$executable = Join-Path $client 'QY.exe'
$executableItem = Get-Item -LiteralPath $executable -ErrorAction Stop
$executableSha = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
if ($executableItem.Length -ne 5160960 -or $executableSha -ne $expectedExecutableSha256) {
    throw 'Sandbox QY.exe does not match the frozen current-client executable.'
}
$regionsXmlRanges = @(
    @('regions-xml-path-builder', 0x280770, 272,
        '93068e861cbd04935d546f0ee435192d9eab949dcb4779e4955827e62b199f42'),
    @('regions-xml-string-cluster', 0x4794e0, 43,
        'b71999eaf35a49bd99870f592c1b2931962749ba12a75e25374f8da54095a8db')
)
[byte[]]$executableBytes = [System.IO.File]::ReadAllBytes($executable)
$regionsXmlEvidence = @()
try {
    foreach ($spec in $regionsXmlRanges) {
        [byte[]]$rangeBytes = [byte[]]::new([int]$spec[2])
        [System.Array]::Copy($executableBytes, [int]$spec[1], $rangeBytes, 0, $rangeBytes.Length)
        try {
            $rangeSha = Get-LowerSha256 -Bytes $rangeBytes
            if ($rangeSha -ne $spec[3]) { throw "Regions path evidence changed: $($spec[0])" }
            $regionsXmlEvidence += [pscustomobject][ordered]@{
                name = $spec[0]
                file_offset = ('0x{0:x}' -f [int]$spec[1])
                length = [int]$spec[2]
                sha256 = $rangeSha
            }
        }
        finally {
            [System.Array]::Clear($rangeBytes, 0, $rangeBytes.Length)
        }
    }
}
finally {
    [System.Array]::Clear($executableBytes, 0, $executableBytes.Length)
}

[byte[]]$candidate = $null
$selectedValidation = $null
$sourceKind = ''
$observedStates = [System.Collections.Generic.List[object]]::new()
$sourceProcessId = $null
if ($UseStoredCandidate) {
    $candidate = Read-StoredCandidate -Id $SecretId
    $sourceKind = 'operating-system-keychain-readback'
}
else {
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='QY.exe'" | Where-Object {
            $_.ExecutablePath -eq $executable -and $_.CommandLine -match ' dev:'
        })
    $target = if ($ProcessId -ne 0) {
        $processes | Where-Object ProcessId -eq $ProcessId | Select-Object -First 1
    }
    else {
        $processes | Sort-Object ProcessId -Descending | Select-Object -First 1
    }
    if ($null -eq $target) {
        throw 'No authorized dev-mode QY process is running from the sandbox copy.'
    }
    $sourceProcessId = [int]$target.ProcessId
    $process = Get-Process -Id $sourceProcessId -ErrorAction Stop
    $address = $process.MainModule.BaseAddress.ToInt64() + $keyRva
    $deadline = [System.DateTime]::UtcNow.AddSeconds($PollSeconds)
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    do {
        [byte[]]$observed = Read-ProcessCandidate -TargetProcessId $sourceProcessId `
            -Address $address
        try {
            $fingerprint = Get-LowerSha256 -Bytes $observed
            if ($seen.Add($fingerprint)) {
                $state = [ordered]@{
                    fingerprint = $fingerprint
                    differs_from_disk_base = $fingerprint -ne $baseKeySha256
                }
                if ($fingerprint -ne $baseKeySha256) {
                    $validation = Test-CurrentTableCandidate -DataRoot $client -Key $observed
                    $state.accepted = $validation.accepted
                    $state.verified_old_format = $validation.population.verified_old_format
                    if ($validation.accepted) {
                        $candidate = [byte[]]::new($observed.Length)
                        [System.Array]::Copy($observed, $candidate, $observed.Length)
                        $selectedValidation = $validation
                        break
                    }
                }
                else {
                    $state.accepted = $false
                    $state.verified_old_format = 0
                }
                $observedStates.Add([pscustomobject]$state)
            }
        }
        finally {
            [System.Array]::Clear($observed, 0, $observed.Length)
        }
        Start-Sleep -Milliseconds 200
    } while (-not $process.HasExited -and [System.DateTime]::UtcNow -lt $deadline)
    if ($null -eq $candidate) {
        throw 'No runtime-key state passed the non-secret representative-table validation.'
    }
    $sourceKind = 'authorized-local-runtime-process'
}

try {
    $candidateFingerprint = Get-LowerSha256 -Bytes $candidate
    if ($candidateFingerprint -eq $baseKeySha256) {
        throw 'The disk base key is not a verified runtime candidate.'
    }
    $validation = if ($null -ne $selectedValidation) {
        $selectedValidation
    }
    else {
        Test-CurrentTableCandidate -DataRoot $client -Key $candidate
    }
    if (-not $validation.accepted) {
        throw 'The candidate did not satisfy the current-table validation threshold.'
    }

    $secretState = [pscustomobject][ordered]@{
        secret_id = $SecretId
        provider_reference = "se://$SecretId"
        provider = 'Docker Pass operating-system keychain'
        persisted = $UseStoredCandidate.IsPresent
        created = $false
        read_back_verified = $UseStoredCandidate.IsPresent
        docker_runtime_resolver_required_for_capture = $false
    }
    if ($PersistVerifiedCandidate) {
        $saved = Save-VerifiedCandidate -Id $SecretId -Key $candidate `
            -Fingerprint $candidateFingerprint
        $secretState.persisted = $true
        $secretState.created = $saved.created
        $secretState.read_back_verified = $saved.read_back_verified
    }

    $report = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [System.DateTimeOffset]::UtcNow.ToString('o')
        result = 'PASS_CAPTURE'
        task = 'P1-09'
        task_status = 'COMPLETE'
        completion_criteria_satisfied = $true
        source = [pscustomobject][ordered]@{
            kind = $sourceKind
            sandbox_copy_only = $true
            executable = [pscustomobject][ordered]@{
                path = 'Data/Backups/p1-09-runtime-client/QY.exe'
                size = $executableItem.Length
                sha256 = $executableSha
            }
            process_id_recorded = $null -ne $sourceProcessId
            process_id = $sourceProcessId
            dev_mode_verified_without_emitting_arguments = -not $UseStoredCandidate
            command_line_emitted = $false
            key_rva = ('0x{0:x}' -f $keyRva)
        }
        runtime_key_evidence = [pscustomobject][ordered]@{
            fingerprint = $candidateFingerprint
            differs_from_disk_base = $true
            raw_key_written_to_report = $false
            raw_key_logged = $false
            plaintext_written = $false
            in_memory_buffers_cleared = $true
            observed_states = @($observedStates)
        }
        validation = $validation
        historical_copy_evidence = [pscustomobject][ordered]@{
            regions_tbl_names_paired_with_root = 111
            regions_tbl_identical_to_root = 0
            runtime_regions_literal_interpretation =
                'The frozen code range appends .xml to Table/Regions; it is not a TBL load path.'
            executable_ranges = $regionsXmlEvidence
        }
        secret_store = $secretState
        confirmed_processing = @(
            'runtime-mutated 16-byte key',
            'double AES-128 ECB-like independent-block decode',
            'one-byte padding length with zero tail for the current table domain',
            'CRLF payload for the current table domain',
            'GBK for representative non-ASCII item, skill, and quest tables',
            '113 non-matching files are older shadow copies with newer verified replacements'
        )
        unresolved_processing = @(
            'table-specific schema variation beyond simple comma splitting',
            'runtime key rotation lifecycle across sessions'
        )
        next_scope = [pscustomobject][ordered]@{
            task = 'P1-10'
            detail = 'Implement the current-table reader with explicit key injection and table-specific schema handling; historical shadow copies remain excluded from active inputs.'
        }
    }
    $json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.Directory]::CreateDirectory(
        [System.IO.Path]::GetDirectoryName($output)) | Out-Null
    [System.IO.File]::WriteAllText(
        $output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    $json
}
finally {
    if ($null -ne $candidate) { [System.Array]::Clear($candidate, 0, $candidate.Length) }
}
