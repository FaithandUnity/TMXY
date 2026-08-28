[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\Rebuild\Data\Backups\p1-09-runtime-client',
    [string]$OutputPath =
        'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-11-current-table-representatives.json',
    [ValidatePattern('^[a-z0-9][a-z0-9./-]+$')]
    [string]$SecretId = 'tmxy/development/table/qy-3.0.0.413/runtime-key-base64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$credentialTargetPrefix = 'com.docker.pass.shared:docker-pass-cli:'
$expectedKeyFingerprint =
    'cf760550b7af6c220331b258db1df781fe567221eb7c53fbfc65aca522085887'
$sampleSpecs = @(
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/powergame.tbl'; bytes = 48; sha256 = '8da2fbf8c9f977822ce78343f6824f259fe7aba2f9b5e961c7518ac5f389ca73' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/sheli_color_level.tbl'; bytes = 48; sha256 = 'd07c3fbfd6bdbf870694176112fdafe32222fc378b9a4c3929f4fc56ca6fe57d' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/Mount_point_reward.tbl'; bytes = 64; sha256 = 'e2b41584d454eafba563125d8b790952819beac698a009bd80a8674aa2c3739d' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/MSlevel.tbl'; bytes = 64; sha256 = 'f1cad32ff53fe46601b565a21dd58095c5945e5a4d2238daebc5cad18e651d48' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/RecruitmentTable.tbl'; bytes = 64; sha256 = '159a8e05ecc770a453586387f1d94ce1cd18f11b04f3a8e0e7f916361d0d3bda' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/sheli_wing.tbl'; bytes = 64; sha256 = '886424a87c3e815e75d0b75b156e9937c4b4285be8b99b861f06808b929d3e35' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/cardinfo_point_reward.tbl'; bytes = 96; sha256 = 'cd77dd802b433453816512937c9b34d869ca74ef13f7b47cda07116ebbdbaf23' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/functionVIP_levelup_exp.tbl'; bytes = 96; sha256 = 'b4378c3a6b45cebc17a04673932be6f2b7ae92bc20279abe3d7e5b9d9a1153c7' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/fabao_growth.tbl'; bytes = 128; sha256 = '0943a9ea495a417bf555e96e766926a6c13a68c92ae0bb331d2cd2cedb8ed0c9' },
    [pscustomobject]@{ category = 'simple'; path = 'CLSVShare/QStarHoleRate.tbl'; bytes = 128; sha256 = '19f0c8e2a3ada9f53a27cac389b47edb26405f33c17727f51edc5f900e3f7f4e' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/skill_table.tbl'; bytes = 7253248; sha256 = '40ec68f102f107da38bbde610fcce8fcc433601c802209116c5c7866f87b7327' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/item_table.tbl'; bytes = 7046704; sha256 = 'f0ccd185f736802661becb9581896497e2101f6a9dbcb28578d5351f71f820ce' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/rand_eff_table.tbl'; bytes = 1796768; sha256 = '4ff3f7498beb9807908ec20f5cc706da89ece03f1faccc66f066952f94bcdd4f' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/Profession_lvl.tbl'; bytes = 1604416; sha256 = '9117772fa9eeb8cd8dbfc88704224524e0e8022f4ef8d1654576ead90a5dc564' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/states.tbl'; bytes = 1515056; sha256 = '6d0127939cee55e20ccf0761712b4a2d546c148eae7c357a9b57f4da0d67ee7f' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/unit_disp_ids.tbl'; bytes = 708512; sha256 = 'd98d14c49da313ed24e62da275fe33261a35ab5771f3b8bce2526765bf8e464a' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/formula_table.tbl'; bytes = 347792; sha256 = 'bb1b71c1afc283db5d5ada1c0f901e5484b1c2e3c412c5d5a062f1263c7be56d' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/CardInfo.tbl'; bytes = 325168; sha256 = '6b1b50bb5a01278eb465f9ff784fa555f5e4d61f6091b09bcbe35b63e7ebe0d0' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/entry.tbl'; bytes = 258160; sha256 = '09f740c3a12af6c7e4cb171d5cedc02b23de65c1356e730a430cc0a68376c36c' },
    [pscustomobject]@{ category = 'complex'; path = 'CLSVShare/fabao_base_prop.tbl'; bytes = 208112; sha256 = '98afeae5b1d54226f68bbf37f07e862506da21b26ce92a10d6768a721a698381' }
)

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Initialize-CredentialType {
    if ($null -ne ('TmxyP111Credential' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TmxyP111Credential
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
    if (-not [TmxyP111Credential]::CredRead(
            $credentialTargetPrefix + $Id, 1, 0, [ref]$pointer)) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "The current-table keychain entry is unavailable (code $code)."
    }
    [byte[]]$blob = $null
    [byte[]]$key = $null
    try {
        $credential = [System.Runtime.InteropServices.Marshal]::PtrToStructure[
            TmxyP111Credential+Credential]($pointer)
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
        [TmxyP111Credential]::CredFree($pointer)
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

function Get-TableMetrics {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Key
    )
    [byte[]]$ciphertext = [System.IO.File]::ReadAllBytes($Path)
    [byte[]]$once = $null
    [byte[]]$plaintext = $null
    [byte[]]$payload = $null
    try {
        if ($ciphertext.Length -eq 0 -or $ciphertext.Length % 16 -ne 0) {
            throw 'Representative TBL is empty or not block aligned.'
        }
        $once = Invoke-AesEcbDecrypt -Ciphertext $ciphertext -Key $Key
        $plaintext = Invoke-AesEcbDecrypt -Ciphertext $once -Key $Key
        $padding = [int]$plaintext[0]
        if ($padding -lt 0 -or $padding -ge 16 -or $plaintext.Length -le $padding + 1) {
            throw 'Representative TBL padding length is invalid.'
        }
        $payloadEnd = $plaintext.Length - $padding
        for ($index = $payloadEnd; $index -lt $plaintext.Length; ++$index) {
            if ($plaintext[$index] -ne 0) { throw 'Representative TBL padding is nonzero.' }
        }
        $payload = [byte[]]::new($payloadEnd - 1)
        [System.Array]::Copy($plaintext, 1, $payload, 0, $payload.Length)

        [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $gbk = [System.Text.Encoding]::GetEncoding(
            936,
            [System.Text.EncoderExceptionFallback]::new(),
            [System.Text.DecoderExceptionFallback]::new())
        $asciiOnly = $true
        for ($index = 0; $index -lt $payload.Length; ++$index) {
            if ($payload[$index] -eq 0) { throw 'Representative TBL contains embedded NUL.' }
            if ($payload[$index] -ge 128) { $asciiOnly = $false }
        }
        $utf8Valid = $true
        $gbkValid = $true
        try { [void]$utf8.GetString($payload) }
        catch [System.Text.DecoderFallbackException] { $utf8Valid = $false }
        try { [void]$gbk.GetString($payload) }
        catch [System.Text.DecoderFallbackException] { $gbkValid = $false }
        $encoding = if ($asciiOnly) { 'ascii' }
        elseif ($gbkValid -and -not $utf8Valid) { 'gbk' }
        elseif ($utf8Valid -and $gbkValid) { 'utf8-or-gbk' }
        elseif ($utf8Valid) { 'utf8' }
        else { 'opaque' }

        $lines = [System.Collections.Generic.List[object]]::new()
        $start = 0
        for ($index = 0; $index -lt $payload.Length; ++$index) {
            if ($payload[$index] -eq 10) {
                if ($index -eq 0 -or $payload[$index - 1] -ne 13) {
                    throw 'Representative TBL contains lone LF.'
                }
            }
            elseif ($payload[$index] -eq 13) {
                if ($index + 1 -ge $payload.Length -or $payload[$index + 1] -ne 10) {
                    throw 'Representative TBL contains lone CR.'
                }
                if ($index -gt $start) {
                    $lines.Add([pscustomobject]@{ offset = $start; length = $index - $start })
                }
                ++$index
                $start = $index + 1
            }
        }
        if ($start -lt $payload.Length) {
            $lines.Add([pscustomobject]@{
                    offset = $start
                    length = $payload.Length - $start
                })
        }
        if ($lines.Count -eq 0) { throw 'Representative TBL has no nonempty lines.' }

        $columnFrequency = [System.Collections.Generic.Dictionary[int, int]]::new()
        $firstFields = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
        $duplicateFirstFields = 0
        $emptyFirstFields = 0
        $emptyFieldCount = 0L
        $rowsWithEmptyFields = 0
        for ($lineIndex = 0; $lineIndex -lt $lines.Count; ++$lineIndex) {
            $line = $lines[$lineIndex]
            $commas = 0
            $lineEmptyFields = 0
            $fieldStart = $line.offset
            $firstEnd = $line.offset + $line.length
            for ($index = $line.offset; $index -lt $line.offset + $line.length; ++$index) {
                if ($payload[$index] -eq 44) {
                    if ($commas -eq 0) { $firstEnd = $index }
                    if ($index -eq $fieldStart) { ++$lineEmptyFields }
                    ++$commas
                    $fieldStart = $index + 1
                }
            }
            if ($fieldStart -eq $line.offset + $line.length) { ++$lineEmptyFields }
            $columns = $commas + 1
            if ($columnFrequency.ContainsKey($columns)) { ++$columnFrequency[$columns] }
            else { $columnFrequency.Add($columns, 1) }
            if ($lineIndex -gt 0) {
                $emptyFieldCount += $lineEmptyFields
                if ($lineEmptyFields -gt 0) { ++$rowsWithEmptyFields }
                $firstLength = $firstEnd - $line.offset
                if ($firstLength -eq 0) {
                    ++$emptyFirstFields
                }
                else {
                    [byte[]]$firstBytes = Get-RangeBytes -Bytes $payload `
                        -Offset $line.offset -Length $firstLength
                    try {
                        if (-not $firstFields.Add([System.Convert]::ToBase64String($firstBytes))) {
                            ++$duplicateFirstFields
                        }
                    }
                    finally { [System.Array]::Clear($firstBytes, 0, $firstBytes.Length) }
                }
            }
        }
        $headerColumns = 0
        for ($index = $lines[0].offset;
            $index -lt $lines[0].offset + $lines[0].length; ++$index) {
            if ($payload[$index] -eq 44) { ++$headerColumns }
        }
        ++$headerColumns
        $mode = $columnFrequency.GetEnumerator() | Sort-Object -Property @(
            @{ Expression = 'Value'; Descending = $true },
            @{ Expression = 'Key'; Descending = $false }) | Select-Object -First 1
        $minimumColumns = ($columnFrequency.Keys | Measure-Object -Minimum).Minimum
        $maximumColumns = ($columnFrequency.Keys | Measure-Object -Maximum).Maximum
        $dataRows = $lines.Count - 1
        $primaryClassification = if ($emptyFirstFields -gt 0) {
            'first-field-has-empty-values'
        }
        elseif ($duplicateFirstFields -gt 0) {
            'first-field-requires-composite-key'
        }
        else {
            'unique-first-field-candidate'
        }
        return [pscustomobject][ordered]@{
            ciphertext_bytes = $ciphertext.Length
            payload_bytes = $payload.Length
            padding_bytes = $padding
            rows = $dataRows
            header_columns = $headerColumns
            modal_columns = [int]$mode.Key
            modal_line_count = [int]$mode.Value
            minimum_columns = [int]$minimumColumns
            maximum_columns = [int]$maximumColumns
            fixed_column_count = $columnFrequency.Count -eq 1
            encoding = $encoding
            strict_gbk = $gbkValid
            strict_utf8 = $utf8Valid
            primary_key_check = $primaryClassification
            unique_first_field_values = $firstFields.Count
            duplicate_first_field_occurrences = $duplicateFirstFields
            empty_first_field_rows = $emptyFirstFields
            empty_fields = $emptyFieldCount
            rows_with_empty_fields = $rowsWithEmptyFields
            failure_classification = 'none'
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            ciphertext_bytes = $ciphertext.Length
            payload_bytes = 0
            padding_bytes = 0
            rows = 0
            header_columns = 0
            modal_columns = 0
            modal_line_count = 0
            minimum_columns = 0
            maximum_columns = 0
            fixed_column_count = $false
            encoding = 'unavailable'
            strict_gbk = $false
            strict_utf8 = $false
            primary_key_check = 'not-run'
            unique_first_field_values = 0
            duplicate_first_field_occurrences = 0
            empty_first_field_rows = 0
            empty_fields = 0
            rows_with_empty_fields = 0
            failure_classification = 'decode-or-structure-failure'
        }
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

$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
$sandbox = [System.IO.Path]::GetFullPath((Join-Path $root 'Data\Backups')).TrimEnd([char[]]'\/')
if (-not $client.StartsWith($sandbox + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P1-11 inspection is restricted to the client sandbox under Data/Backups.'
}
if (-not $output.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P1-11 evidence output must remain inside Rebuild.'
}
if (@($sampleSpecs | Where-Object category -eq 'simple').Count -ne 10 -or
    @($sampleSpecs | Where-Object category -eq 'complex').Count -ne 10 -or
    @($sampleSpecs.path | Sort-Object -Unique).Count -ne 20) {
    throw 'P1-11 representative selection must contain 10 unique simple and 10 unique complex tables.'
}

[byte[]]$key = Read-StoredKey -Id $SecretId
try {
    $results = @()
    foreach ($spec in $sampleSpecs) {
        $path = Join-Path $client $spec.path.Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar)
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($item.Length -ne $spec.bytes -or $sha -ne $spec.sha256) {
            throw "P1-11 frozen representative changed: $($spec.path)"
        }
        $metrics = Get-TableMetrics -Path $path -Key $key
        $results += [pscustomobject][ordered]@{
            category = $spec.category
            path = $spec.path
            sha256 = $sha
            metrics = $metrics
        }
    }
    $failures = @($results | Where-Object { $_.metrics.failure_classification -ne 'none' })
    $opaque = @($results | Where-Object { $_.metrics.encoding -eq 'opaque' })
    $fixedSchemas = @($results | Where-Object { $_.metrics.fixed_column_count })
    $uniqueFirstFields = @($results | Where-Object {
            $_.metrics.primary_key_check -eq 'unique-first-field-candidate'
        })
    $completed = $results.Count -eq 20 -and $failures.Count -eq 0 -and $opaque.Count -eq 0
    $report = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [System.DateTimeOffset]::UtcNow.ToString('o')
        result = if ($completed) { 'PASS' } else { 'FAIL' }
        task = 'P1-11'
        task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
        completion_criteria_satisfied = $completed
        selection = [pscustomobject][ordered]@{
            strategy = '10 smallest and 10 largest active CLSVShare tables with frozen hashes'
            simple_count = @($results | Where-Object category -eq 'simple').Count
            complex_count = @($results | Where-Object category -eq 'complex').Count
            total_ciphertext_bytes = [long](($results.metrics |
                    Measure-Object ciphertext_bytes -Sum).Sum)
        }
        summary = [pscustomobject][ordered]@{
            decoded = $results.Count - $failures.Count
            failed = $failures.Count
            fixed_column_schema = $fixedSchemas.Count
            variable_column_schema = $results.Count - $fixedSchemas.Count
            unique_first_field_candidate = $uniqueFirstFields.Count
            composite_or_empty_first_field = $results.Count - $uniqueFirstFields.Count
            tables_with_empty_fields = @($results | Where-Object {
                    $_.metrics.empty_fields -gt 0
                }).Count
            encoding_counts = @($results | Group-Object { $_.metrics.encoding } |
                Sort-Object Name | ForEach-Object {
                    [pscustomobject][ordered]@{ encoding = $_.Name; tables = $_.Count }
                })
        }
        samples = $results
        secret_handling = [pscustomobject][ordered]@{
            key_fingerprint = $expectedKeyFingerprint
            secret_reference = "se://$SecretId"
            raw_key_emitted = $false
            plaintext_emitted = $false
            identifiers_emitted = $false
            in_memory_buffers_cleared = $true
        }
        next_scope = [pscustomobject][ordered]@{
            task = 'P1-28'
            detail = 'Run the G1 format review using completed P1-09 through P1-27 evidence.'
        }
    }
    $json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.Directory]::CreateDirectory(
        [System.IO.Path]::GetDirectoryName($output)) | Out-Null
    [System.IO.File]::WriteAllText(
        $output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    $json
    if (-not $completed) { throw 'P1-11 representative-table validation did not complete.' }
}
finally {
    [System.Array]::Clear($key, 0, $key.Length)
}
