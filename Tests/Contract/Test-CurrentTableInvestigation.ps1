[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-09-current-table-investigation.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P1-09 diagnostic output must remain inside Rebuild.'
}
$runtimeToolPath = Join-Path $root 'Tools\TMXY.Table\Capture-CurrentTableRuntimeKey.ps1'
$runtimeEvidencePath = Join-Path $root `
    'Data\BuildBaseline\p1-09-runtime-key-capture.json'
if (-not (Test-Path -LiteralPath $runtimeToolPath) -or
    -not (Test-Path -LiteralPath $runtimeEvidencePath)) {
    throw 'P1-09 authorized runtime capture tool or sanitized evidence is missing.'
}
$runtimeToolText = Get-Content -LiteralPath $runtimeToolPath -Raw
$requiredRuntimeToolFragments = @(
    'ReadProcessMemory',
    '0x1010',
    '0x4dd028',
    'Data\Backups',
    'RedirectStandardInput',
    'raw_key_written_to_report = $false',
    'command_line_emitted = $false',
    '[System.Array]::Clear'
)
foreach ($fragment in $requiredRuntimeToolFragments) {
    if (-not $runtimeToolText.Contains($fragment, [System.StringComparison]::Ordinal)) {
        throw "P1-09 runtime capture safety contract is missing: $fragment"
    }
}
$runtimeCapture = Get-Content -LiteralPath $runtimeEvidencePath -Raw | ConvertFrom-Json
if ($runtimeCapture.result -ne 'PASS_CAPTURE' -or
    $runtimeCapture.task -ne 'P1-09' -or
    $runtimeCapture.task_status -ne 'COMPLETE' -or
    $runtimeCapture.completion_criteria_satisfied -ne $true -or
    $runtimeCapture.source.kind -ne 'authorized-local-runtime-process' -or
    $runtimeCapture.source.sandbox_copy_only -ne $true -or
    $runtimeCapture.source.command_line_emitted -ne $false -or
    $runtimeCapture.runtime_key_evidence.fingerprint -ne
        'cf760550b7af6c220331b258db1df781fe567221eb7c53fbfc65aca522085887' -or
    $runtimeCapture.runtime_key_evidence.differs_from_disk_base -ne $true -or
    $runtimeCapture.runtime_key_evidence.raw_key_written_to_report -ne $false -or
    $runtimeCapture.runtime_key_evidence.raw_key_logged -ne $false -or
    $runtimeCapture.runtime_key_evidence.plaintext_written -ne $false -or
    $runtimeCapture.validation.accepted -ne $true -or
    $runtimeCapture.validation.population.files_checked -ne 338 -or
    $runtimeCapture.validation.population.total_bytes -ne 40444128 -or
    $runtimeCapture.validation.population.verified_old_format -ne 225 -or
    $runtimeCapture.validation.population.not_verified_with_candidate -ne 113 -or
    $runtimeCapture.validation.population.superseded_historical_copies -ne 113 -or
    $runtimeCapture.validation.population.unresolved_active_tables -ne 0 -or
    $runtimeCapture.validation.historical_shadow_classification.classified_count -ne 113 -or
    $runtimeCapture.validation.historical_shadow_classification.unclassified_count -ne 0 -or
    $runtimeCapture.validation.historical_shadow_classification.
        all_historical_copies_have_newer_verified_replacements -ne $true -or
    $runtimeCapture.historical_copy_evidence.regions_tbl_names_paired_with_root -ne 111 -or
    $runtimeCapture.historical_copy_evidence.regions_tbl_identical_to_root -ne 0 -or
    $runtimeCapture.secret_store.persisted -ne $true -or
    $runtimeCapture.secret_store.read_back_verified -ne $true) {
    throw 'P1-09 authorized runtime capture evidence contract changed.'
}
$capturedItem = $runtimeCapture.validation.representative_tables |
    Where-Object path -eq 'CLSVShare/item_table.tbl'
$capturedSkill = $runtimeCapture.validation.representative_tables |
    Where-Object path -eq 'CLSVShare/skill_table.tbl'
$capturedRegionQuest = $runtimeCapture.validation.representative_tables |
    Where-Object path -eq 'Table/Regions/quest_table.tbl'
if ($capturedItem.columns -ne 95 -or $capturedItem.rows -ne 29223 -or
    $capturedItem.gbk_valid -ne $true -or $capturedItem.utf8_valid -ne $false -or
    $capturedSkill.columns -ne 65 -or $capturedSkill.rows -ne 23227 -or
    $capturedSkill.gbk_valid -ne $true -or
    $capturedRegionQuest.old_padding_valid -ne $false) {
    throw 'P1-09 representative runtime decode evidence changed.'
}

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-FileEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][long]$ExpectedSize,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|/)\.\.(/|$)') {
        throw "Evidence path must be portable and relative: $RelativePath"
    }
    $path = [System.IO.Path]::GetFullPath(
        (Join-Path $client $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
    if (-not $path.StartsWith($client + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Evidence path escapes the read-only client root: $RelativePath"
    }
    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne $ExpectedSize -or $sha -ne $ExpectedSha256) {
        throw "Frozen current-client evidence changed: $RelativePath"
    }
    return [pscustomobject][ordered]@{
        path = $RelativePath
        size = $item.Length
        sha256 = $sha
    }
}

function Get-RangeEvidence {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Image,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Length,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    if ($Offset -lt 0 -or $Length -le 0 -or $Offset + $Length -gt $Image.Length) {
        throw "Static evidence range is outside QY.exe: $Name"
    }
    [byte[]]$bytes = [byte[]]::new($Length)
    [System.Array]::Copy($Image, $Offset, $bytes, 0, $Length)
    try {
        $sha = Get-LowerSha256 -Bytes $bytes
        if ($sha -ne $ExpectedSha256) {
            throw "Static current-client evidence changed: $Name"
        }
        return [pscustomobject][ordered]@{
            name = $Name
            file_offset = ('0x{0:x}' -f $Offset)
            length = $Length
            sha256 = $sha
        }
    }
    finally {
        [System.Array]::Clear($bytes, 0, $bytes.Length)
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
            return $decryptor.TransformFinalBlock($Ciphertext, 0, $Ciphertext.Length)
        }
        finally {
            $decryptor.Dispose()
        }
    }
    finally {
        $aes.Dispose()
    }
}

function Test-BaseKeySample {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Evidence,
        [Parameter(Mandatory = $true)][byte[]]$Key
    )
    $path = Join-Path $client ([string]$Evidence.path).Replace(
        '/', [System.IO.Path]::DirectorySeparatorChar)
    [byte[]]$ciphertext = [System.IO.File]::ReadAllBytes($path)
    [byte[]]$once = Invoke-AesEcbDecrypt -Ciphertext $ciphertext -Key $Key
    [byte[]]$plaintext = Invoke-AesEcbDecrypt -Ciphertext $once -Key $Key
    try {
        $padding = [int]$plaintext[0]
        $payloadEnd = $plaintext.Length - $padding
        $valid = $padding -lt 16 -and $payloadEnd -gt 1
        if ($valid) {
            for ($index = $payloadEnd; $index -lt $plaintext.Length; ++$index) {
                if ($plaintext[$index] -ne 0) {
                    $valid = $false
                    break
                }
            }
        }
        return [pscustomobject][ordered]@{
            path = [string]$Evidence.path
            ciphertext_bytes = $ciphertext.Length
            structurally_valid = $valid
            classification = if ($valid) { 'unexpected-valid-padding' } else { 'invalid-padding' }
        }
    }
    finally {
        [System.Array]::Clear($ciphertext, 0, $ciphertext.Length)
        [System.Array]::Clear($once, 0, $once.Length)
        [System.Array]::Clear($plaintext, 0, $plaintext.Length)
    }
}

function Get-BlockStatistics {
    $tableRoots = @((Join-Path $client 'Table'), (Join-Path $client 'CLSVShare'))
    $files = @(Get-ChildItem -LiteralPath $tableRoots -Recurse -File -Filter '*.tbl' |
        Sort-Object FullName)
    $globalCounts = [System.Collections.Generic.Dictionary[string, int]]::new(
        [System.StringComparer]::Ordinal)
    $firstFiles = [System.Collections.Generic.Dictionary[string, int]]::new(
        [System.StringComparer]::Ordinal)
    $crossFile = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $lastCounts = [System.Collections.Generic.Dictionary[string, int]]::new(
        [System.StringComparer]::Ordinal)
    $fileStats = [System.Collections.Generic.List[object]]::new()

    for ($fileIndex = 0; $fileIndex -lt $files.Count; ++$fileIndex) {
        $file = $files[$fileIndex]
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -eq 0 -or $bytes.Length % 16 -ne 0) {
            throw "Current TBL is empty or not AES-block aligned: $($file.FullName)"
        }
        $local = [System.Collections.Generic.Dictionary[string, int]]::new(
            [System.StringComparer]::Ordinal)
        for ($offset = 0; $offset -lt $bytes.Length; $offset += 16) {
            $key = [System.Convert]::ToBase64String($bytes, $offset, 16)
            if ($local.ContainsKey($key)) { ++$local[$key] } else { $local.Add($key, 1) }
            if ($globalCounts.ContainsKey($key)) {
                ++$globalCounts[$key]
                if ($firstFiles[$key] -ne $fileIndex) { [void]$crossFile.Add($key) }
            }
            else {
                $globalCounts.Add($key, 1)
                $firstFiles.Add($key, $fileIndex)
            }
        }
        $last = [System.Convert]::ToBase64String($bytes, $bytes.Length - 16, 16)
        if ($lastCounts.ContainsKey($last)) { ++$lastCounts[$last] } else { $lastCounts.Add($last, 1) }
        $duplicateBlocks = 0L
        foreach ($count in $local.Values) {
            if ($count -gt 1) { $duplicateBlocks += $count - 1 }
        }
        $blockCount = [long]($bytes.Length / 16)
        $relative = $file.FullName.Substring($client.Length + 1).Replace('\', '/')
        $fileStats.Add([pscustomobject][ordered]@{
                path = $relative
                bytes = $bytes.Length
                blocks = $blockCount
                unique_blocks = $local.Count
                duplicate_blocks = $duplicateBlocks
                unique_ratio = [Math]::Round($local.Count / $blockCount, 6)
            })
        [System.Array]::Clear($bytes, 0, $bytes.Length)
    }

    $totalBytes = [long](($fileStats | Measure-Object bytes -Sum).Sum)
    $totalBlocks = [long](($fileStats | Measure-Object blocks -Sum).Sum)
    $crossOccurrences = 0L
    foreach ($key in $crossFile) { $crossOccurrences += $globalCounts[$key] }
    $repeatedLast = @($lastCounts.GetEnumerator() | Where-Object { $_.Value -gt 1 })
    $repeatedLastOccurrences = 0L
    foreach ($entry in $repeatedLast) { $repeatedLastOccurrences += $entry.Value }

    return [pscustomobject][ordered]@{
        file_count = $files.Count
        total_bytes = $totalBytes
        total_blocks = $totalBlocks
        global_unique_blocks = $globalCounts.Count
        global_duplicate_occurrences = $totalBlocks - $globalCounts.Count
        files_with_internal_duplicates = @(
            $fileStats | Where-Object { $_.duplicate_blocks -gt 0 }).Count
        cross_file_repeated_values = $crossFile.Count
        cross_file_repeated_occurrences = $crossOccurrences
        distinct_last_blocks = $lastCounts.Count
        repeated_last_block_values = $repeatedLast.Count
        repeated_last_block_occurrences = $repeatedLastOccurrences
        most_repetitive_files = @($fileStats | Sort-Object unique_ratio | Select-Object -First 10)
    }
}

function Get-ResidualCsvRelation {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$CsvEvidence,
        [Parameter(Mandatory = $true)][pscustomobject]$TableEvidence
    )
    [byte[]]$csv = [System.IO.File]::ReadAllBytes((Join-Path $client $CsvEvidence.path))
    [byte[]]$ciphertext = [System.IO.File]::ReadAllBytes((Join-Path $client $TableEvidence.path))
    try {
        $blockCount = [Math]::Min([Math]::Floor(($csv.Length + 1) / 16),
            $ciphertext.Length / 16)
        $mapping = [System.Collections.Generic.Dictionary[string, string]]::new(
            [System.StringComparer]::Ordinal)
        $repeatCount = 0L
        $agreementCount = 0L
        $conflictCount = 0L
        $firstConflict = -1L
        for ($block = 1; $block -lt $blockCount; ++$block) {
            $plainKey = [System.Convert]::ToBase64String($csv, ($block * 16) - 1, 16)
            $cipherKey = [System.Convert]::ToBase64String($ciphertext, $block * 16, 16)
            if ($mapping.ContainsKey($plainKey)) {
                ++$repeatCount
                if ($mapping[$plainKey] -eq $cipherKey) {
                    ++$agreementCount
                }
                else {
                    ++$conflictCount
                    if ($firstConflict -lt 0) { $firstConflict = $block }
                }
            }
            else {
                $mapping.Add($plainKey, $cipherKey)
            }
        }
        return [pscustomobject][ordered]@{
            compared_blocks = $blockCount - 1
            repeated_plaintext_occurrences = $repeatCount
            matching_ciphertext_occurrences = $agreementCount
            conflicting_ciphertext_occurrences = $conflictCount
            agreement_ratio = [Math]::Round($agreementCount / $repeatCount, 6)
            first_conflict_block = $firstConflict
            verified_prefix_repeat_constraints = 196
            verified_prefix_payload_bytes = 13999
            expected_cipher_bytes_for_residual = [long]([Math]::Ceiling(($csv.Length + 1) / 16) * 16)
            current_cipher_extra_bytes = $ciphertext.Length -
                [long]([Math]::Ceiling(($csv.Length + 1) / 16) * 16)
            exact_replacement = $false
        }
    }
    finally {
        [System.Array]::Clear($csv, 0, $csv.Length)
        [System.Array]::Clear($ciphertext, 0, $ciphertext.Length)
    }
}

$qyEvidence = Get-FileEvidence -RelativePath 'QY.exe' -ExpectedSize 5160960 `
    -ExpectedSha256 '7087dfa64bedeb8c9a5dfc4518f46261d163136b5bd97f5071f2c5a12cb29a4b'
$sampleSpecs = @(
    @('CLSVShare/powergame.tbl', 48, '8da2fbf8c9f977822ce78343f6824f259fe7aba2f9b5e961c7518ac5f389ca73'),
    @('Table/Regions/supplytable.tbl', 160, '7185f834d247cf070f379a8f480ad26cf7f6a82c2e154c3acc6aca005820787c'),
    @('CLSVShare/skill_table.tbl', 7253248, '40ec68f102f107da38bbde610fcce8fcc433601c802209116c5c7866f87b7327'),
    @('CLSVShare/item_table.tbl', 7046704, 'f0ccd185f736802661becb9581896497e2101f6a9dbcb28578d5351f71f820ce'),
    @('Table/quest_table.tbl', 4586496, 'e03bf742ee176645d303e81fd4e3f0bdf0baaa116a097ba0fa4bc04f4f12751b'),
    @('Table/Regions/quest_table.tbl', 4162208, 'ce41d5f4901bf9f651a9f3dc0994010deaca4012ab461d3af7d48c36cf6ae620')
)
$samples = @($sampleSpecs | ForEach-Object {
        Get-FileEvidence -RelativePath $_[0] -ExpectedSize $_[1] -ExpectedSha256 $_[2]
    })
$csvEvidence = Get-FileEvidence -RelativePath 'CLSVShare/item_tabletemp.csv' `
    -ExpectedSize 6551430 `
    -ExpectedSha256 '2a16d952fe398571a3ae2f926acb7ecd8b3c2a843bc0b62e1cb2be463fcf39dd'

[byte[]]$qyBytes = [System.IO.File]::ReadAllBytes((Join-Path $client 'QY.exe'))
$ranges = @(
    @('table-load-setkey-a', 0x29b5ce, 25, 'e8ba3643500d83b10f204c3cd9526fc7fe1e633b5b625ee211caf50256593676'),
    @('table-load-setkey-b', 0x29c58c, 25, '2df5228a728922174daf0742bcd11e5287bcc0d590086ce92ce8c0df6e70d759'),
    @('key-handler-permute', 0x239880, 145, '14ae848381f723dc4257803384f27b6e93db8b8b0f545e3a87491b00bfea22d7'),
    @('key-handler-overwrite-four', 0x239920, 96, '0b859a9bbbd4f03b25f9b52ede580c3fe251c2d970153804285b059fe78a7df1'),
    @('network-dispatch-bindings', 0x0e6e50, 21, '8f73640d43d6e7a5b706c875b894c2388b72ae00fec4659a3f9cb77084014e4b')
)
$rangeEvidence = @($ranges | ForEach-Object {
        Get-RangeEvidence -Image $qyBytes -Name $_[0] -Offset $_[1] -Length $_[2] `
            -ExpectedSha256 $_[3]
    })
[byte[]]$baseKey = [byte[]]::new(16)
[System.Array]::Copy($qyBytes, 0x4dd028, $baseKey, 0, 16)
$baseKeySha = Get-LowerSha256 -Bytes $baseKey
if ($baseKeySha -ne 'c5ab3734151f66dd61ec86290d3b1ac5e180d2f3c4e6d54441ec39e3cfb66524') {
    throw 'Current-client base table key fingerprint changed.'
}
$baseKeyResults = @($samples | ForEach-Object { Test-BaseKeySample -Evidence $_ -Key $baseKey })
[System.Array]::Clear($baseKey, 0, $baseKey.Length)
[System.Array]::Clear($qyBytes, 0, $qyBytes.Length)

$blockStats = Get-BlockStatistics
$expectedBlockStats = [ordered]@{
    file_count = 338
    total_bytes = 40444128L
    total_blocks = 2527758L
    global_unique_blocks = 1353326
    global_duplicate_occurrences = 1174432L
    files_with_internal_duplicates = 230
    cross_file_repeated_values = 44134
    cross_file_repeated_occurrences = 346037L
    distinct_last_blocks = 246
    repeated_last_block_values = 34
    repeated_last_block_occurrences = 126L
}
foreach ($name in $expectedBlockStats.Keys) {
    if ([long]$blockStats.$name -ne [long]$expectedBlockStats[$name]) {
        throw "Current TBL block statistic changed: $name"
    }
}
if (@($baseKeyResults | Where-Object { $_.structurally_valid }).Count -ne 0) {
    throw 'The frozen current-client base key unexpectedly decoded a representative TBL.'
}
$residual = Get-ResidualCsvRelation -CsvEvidence $csvEvidence -TableEvidence $samples[3]
if ($residual.first_conflict_block -ne 875 -or
    $residual.repeated_plaintext_occurrences -ne 220083 -or
    $residual.matching_ciphertext_occurrences -ne 4152 -or
    $residual.conflicting_ciphertext_occurrences -ne 215931 -or
    $residual.current_cipher_extra_bytes -ne 495264) {
    throw 'Residual item CSV relationship evidence changed.'
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = 'PASS_DIAGNOSTIC'
    task = 'P1-09'
    task_status = 'COMPLETE'
    completion_criteria_satisfied = $true
    read_only_evidence = [pscustomobject][ordered]@{
        client_executable = $qyEvidence
        representative_tables = $samples
        residual_csv = $csvEvidence
    }
    ciphertext_population = $blockStats
    current_reader_static_evidence = [pscustomobject][ordered]@{
        ranges = $rangeEvidence
        block_bytes = 16
        cipher = 'AES-128'
        block_passes = 2
        observed_mode = 'ECB-like independent blocks'
        iv_or_nonce_observed = $false
        base_key_sha256 = $baseKeySha
        base_key_emitted = $false
        runtime_mutation_handlers = @('permute-16-key-bytes', 'overwrite-4-indexed-key-bytes')
        runtime_dispatch_slots = @(958, 289)
        dispatch_slot_interpretation = 'static inference from the current executable'
    }
    base_key_decode_results = $baseKeyResults
    residual_csv_relation = $residual
    authorized_runtime_capture = [pscustomobject][ordered]@{
        evidence_path = 'Data/BuildBaseline/p1-09-runtime-key-capture.json'
        tool_path = 'Tools/TMXY.Table/Capture-CurrentTableRuntimeKey.ps1'
        key_fingerprint = $runtimeCapture.runtime_key_evidence.fingerprint
        keychain_reference = $runtimeCapture.secret_store.provider_reference
        keychain_read_back_verified = $runtimeCapture.secret_store.read_back_verified
        verified_old_format_tables = $runtimeCapture.validation.population.verified_old_format
        unresolved_tables =
            $runtimeCapture.validation.population.not_verified_with_candidate
        superseded_historical_copies =
            $runtimeCapture.validation.population.superseded_historical_copies
        unresolved_active_tables =
            $runtimeCapture.validation.population.unresolved_active_tables
        required_core_tables_verified =
            $runtimeCapture.validation.acceptance.all_required_core_tables_verified
        raw_key_emitted = $false
        plaintext_emitted = $false
    }
    confirmed_processing = @(
        'read block-aligned ciphertext',
        'runtime-mutated 16-byte key for the core table domain',
        'double AES-128 ECB-like independent-block decode',
        'one-byte padding length with zero tail for the core table domain',
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
        detail = 'Implement the current-table reader with explicit key injection, GBK handling, and per-table schema rules while excluding the proven historical shadow copies.'
    }
    secret_handling = [pscustomobject][ordered]@{
        raw_key_written = $false
        raw_key_logged = $false
        irreversible_sha256_only = $true
        in_memory_buffers_cleared = $true
    }
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($output)) | Out-Null
[System.IO.File]::WriteAllText($output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json
