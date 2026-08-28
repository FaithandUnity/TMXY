[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot =
        'E:\QQXYCodeDev\Rebuild\Data\Backups\p1-09-runtime-client',
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev',
    [string]$OutputPath =
        'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-05-auxiliary-config-inventory.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedFiles = 212
$expectedBytes = 1909135L
$expectedXmlFiles = 148
$expectedEcfFiles = 64
$expectedExecutableBytes = 5160960L
$expectedExecutableSha256 =
    '7087dfa64bedeb8c9a5dfc4518f46261d163136b5bd97f5071f2c5a12cb29a4b'
$expectedQGameEngineSha256 =
    '35ce22803fac775d5847fc495811a43cbaf53feadaa776c0446be930921596b1'
$sourceBuild = 'qy-3.0.0.413'
$sharedXmlNames = @(
    'box_item.xml',
    'default_charinfo.xml',
    'examination.xml',
    'guildglobals.xml',
    'guildquest.xml',
    'onlinereward.xml',
    'professions.xml',
    'rollboxitem.xml',
    'tiangong_charinfo.xml',
    'westsky.xml',
    'yin_yang_pan.xml'
)

function Get-LowerSha256File {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LowerSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    [byte[]]$bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    try {
        return [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [System.Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )
    return $Path.Substring($Root.Length + 1).Replace('\', '/')
}

function Test-BytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; ++$index) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
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

function Get-EncodingClassification {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $strictGbk = [System.Text.Encoding]::GetEncoding(
        936,
        [System.Text.EncoderExceptionFallback]::new(),
        [System.Text.DecoderExceptionFallback]::new())
    $asciiOnly = $true
    foreach ($value in $Bytes) {
        if ($value -ge 128) { $asciiOnly = $false; break }
    }
    try { [void]$strictUtf8.GetString($Bytes); $utf8Valid = $true }
    catch [System.Text.DecoderFallbackException] { $utf8Valid = $false }
    try { [void]$strictGbk.GetString($Bytes); $gbkValid = $true }
    catch [System.Text.DecoderFallbackException] { $gbkValid = $false }
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

function Get-XmlErrorCategory {
    param([Parameter(Mandatory = $true)][string]$Message)
    if ($Message.Contains('multiple root elements', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'multiple-root-elements'
    }
    if ($Message.Contains('not closed', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'unclosed-element'
    }
    if ($Message.Contains('Expecting whitespace', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'malformed-attribute-spacing'
    }
    if ($Message.Contains('comment cannot contain', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'invalid-comment'
    }
    if ($Message.Contains('invalid attribute character', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'invalid-attribute-character'
    }
    return 'xml-parse-error'
}

function Read-XmlStructure {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][System.Xml.ConformanceLevel]$Conformance
    )
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.ConformanceLevel = $Conformance
    $stringReader = [System.IO.StringReader]::new($Text)
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        $rootName = $null
        $elements = 0
        $attributes = 0
        $textNodes = 0
        $maximumDepth = 0
        while ($reader.Read()) {
            if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                ++$elements
                $attributes += $reader.AttributeCount
                if ($null -eq $rootName) { $rootName = $reader.LocalName }
                $maximumDepth = [System.Math]::Max($maximumDepth, $reader.Depth)
            }
            elseif ($reader.NodeType -in @(
                    [System.Xml.XmlNodeType]::Text,
                    [System.Xml.XmlNodeType]::CDATA)) {
                ++$textNodes
            }
        }
        return [pscustomobject][ordered]@{
            success = $true
            error = 'none'
            root_name = $rootName
            elements = $elements
            attributes = $attributes
            text_nodes = $textNodes
            maximum_depth = $maximumDepth
        }
    }
    catch {
        $exception = if ($null -ne $_.Exception.InnerException) {
            $_.Exception.InnerException
        }
        else { $_.Exception }
        return [pscustomobject][ordered]@{
            success = $false
            error = Get-XmlErrorCategory -Message $exception.Message
            root_name = $null
            elements = $null
            attributes = $null
            text_nodes = $null
            maximum_depth = $null
        }
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $stringReader.Dispose()
    }
}

function Get-XmlInventoryEntry {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$ClientRootPath
    )
    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $text = $null
    try {
        $encoding = Get-EncodingClassification -Bytes $bytes
        if ($encoding.classification -eq 'opaque') {
            throw "XML input has no supported strict encoding: $($File.FullName)"
        }
        $decoder = if ($encoding.classification -eq 'utf8') {
            [System.Text.UTF8Encoding]::new($false, $true)
        }
        else {
            [System.Text.Encoding]::GetEncoding(
                936,
                [System.Text.EncoderExceptionFallback]::new(),
                [System.Text.DecoderExceptionFallback]::new())
        }
        $text = $decoder.GetString($bytes)
        $document = Read-XmlStructure -Text $text -Conformance Document
        $accepted = $document
        $kind = 'xml-document'
        if (-not $document.success) {
            $fragment = Read-XmlStructure -Text $text -Conformance Fragment
            if ($fragment.success) {
                $accepted = $fragment
                $kind = 'xml-fragment'
            }
            else {
                $kind = 'malformed-xml'
                $accepted = $fragment
                if ($document.error -ne 'multiple-root-elements') {
                    $accepted.error = $document.error
                }
            }
        }
        $relative = Get-RelativePath -Root $ClientRootPath -Path $File.FullName
        return [pscustomobject][ordered]@{
            path = $relative
            kind = 'xml'
            group = if ($relative.StartsWith('CLSVShare/')) { 'CLSVShare' }
                elseif ($relative.StartsWith('Table/Regions/')) { 'Table/Regions' }
                else { 'Table/root' }
            bytes = $File.Length
            sha256 = Get-LowerSha256File -Path $File.FullName
            last_write_utc = $File.LastWriteTimeUtc.ToString('o')
            encoding = $encoding
            structure = [pscustomobject][ordered]@{
                classification = $kind
                accepted_by_strict_reader = $accepted.success
                document_conformance = $document.success
                fragment_conformance = $kind -eq 'xml-fragment'
                error = $accepted.error
                root_name = $accepted.root_name
                elements = $accepted.elements
                attributes = $accepted.attributes
                text_nodes = $accepted.text_nodes
                maximum_depth = $accepted.maximum_depth
            }
        }
    }
    finally {
        $text = $null
        [System.Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-EcfInventoryEntry {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$ClientRootPath
    )
    [byte[]]$encoded = [System.IO.File]::ReadAllBytes($File.FullName)
    [byte[]]$decoded = $null
    [byte[]]$roundTrip = $null
    $text = $null
    try {
        $decoded = Convert-EcfBytes -Bytes $encoded
        $roundTrip = Convert-EcfBytes -Bytes $decoded
        $roundTripMatches = Test-BytesEqual -Left $encoded -Right $roundTrip
        $encoding = Get-EncodingClassification -Bytes $decoded
        if ($encoding.classification -eq 'opaque') {
            throw "ECF decode has no supported strict encoding: $($File.FullName)"
        }
        $decoder = if ($encoding.classification -eq 'utf8') {
            [System.Text.UTF8Encoding]::new($false, $true)
        }
        else { [System.Text.Encoding]::GetEncoding(936) }
        $text = $decoder.GetString($decoded)
        $lines = @($text -split "`r?`n")
        $assignments = @($lines | Where-Object { $_ -match '^[^;#\s][^=]*=' })
        $comments = @($lines | Where-Object {
                $_.TrimStart().StartsWith(';') -or $_.TrimStart().StartsWith('#')
            })
        $blank = @($lines | Where-Object { $_.Trim().Length -eq 0 })
        $keys = @($assignments | ForEach-Object { ($_ -split '=', 2)[0].Trim() })
        $uniqueKeys = @($keys | Sort-Object -Unique).Count
        $relative = Get-RelativePath -Root $ClientRootPath -Path $File.FullName
        $editorCandidate = $File.BaseName -match '^(QEdit|QEditor)' -or
            $File.BaseName -eq 'TextureListFrameWindow'
        return [pscustomobject][ordered]@{
            path = $relative
            kind = 'ecf'
            group = 'ClassCfg'
            bytes = $File.Length
            sha256 = Get-LowerSha256File -Path $File.FullName
            last_write_utc = $File.LastWriteTimeUtc.ToString('o')
            encoding = $encoding
            structure = [pscustomobject][ordered]@{
                classification = 'line-oriented-key-value-config'
                transform = 'invert-bytes-and-swap-four-byte-halves-v1'
                transform_is_self_inverse = $true
                round_trip_matches_source = $roundTripMatches
                lines = $lines.Count
                assignment_lines = $assignments.Count
                unique_assignment_keys = $uniqueKeys
                repeated_assignment_count = $assignments.Count - $uniqueKeys
                comment_lines = $comments.Count
                blank_lines = $blank.Count
                other_nonblank_lines = $lines.Count - $assignments.Count -
                    $comments.Count - $blank.Count
                usage_candidate = if ($editorCandidate) {
                    'client-editor-tooling'
                }
                else { 'client-runtime-or-engine' }
            }
        }
    }
    finally {
        $text = $null
        foreach ($buffer in @($encoded, $decoded, $roundTrip)) {
            if ($null -ne $buffer) { [System.Array]::Clear($buffer, 0, $buffer.Length) }
        }
    }
}

function Get-ServerReferenceIndex {
    param([Parameter(Mandatory = $true)][string]$ServerRoot)
    $extensions = @('.c', '.cc', '.cpp', '.h', '.hpp', '.vcproj', '.sln')
    $files = @(Get-ChildItem -LiteralPath $ServerRoot -Recurse -File |
        Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object FullName)
    $references = @{}
    foreach ($name in $sharedXmlNames) {
        $references[$name] = [System.Collections.Generic.List[string]]::new()
    }
    $ecfReferenceFiles = [System.Collections.Generic.List[string]]::new()
    $fingerprintRows = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        try {
            $text = [System.Text.Encoding]::Latin1.GetString($bytes).ToLowerInvariant()
            $relative = Get-RelativePath -Root $ServerRoot -Path $file.FullName
            foreach ($name in $sharedXmlNames) {
                if ($text.Contains($name, [System.StringComparison]::Ordinal)) {
                    $references[$name].Add($relative)
                }
            }
            if ($text.Contains('.ecf', [System.StringComparison]::Ordinal)) {
                $ecfReferenceFiles.Add($relative)
            }
            $fingerprintRows.Add("$relative`:$((Get-LowerSha256File -Path $file.FullName))")
        }
        finally {
            $text = $null
            [System.Array]::Clear($bytes, 0, $bytes.Length)
        }
    }
    return [pscustomobject][ordered]@{
        files_scanned = $files.Count
        population_sha256 = Get-LowerSha256Text -Text ($fingerprintRows -join "`n")
        xml_references = $references
        ecf_reference_files = @($ecfReferenceFiles)
    }
}

function Get-QGameEngineReferenceSet {
    param([Parameter(Mandatory = $true)][string]$Path)
    [byte[]]$encoded = [System.IO.File]::ReadAllBytes($Path)
    [byte[]]$decoded = $null
    try {
        $decoded = Convert-EcfBytes -Bytes $encoded
        $text = [System.Text.Encoding]::GetEncoding(936).GetString($decoded).ToLowerInvariant()
        $references = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
        foreach ($name in $sharedXmlNames + @('help_docs.xml')) {
            if ($text.Contains($name, [System.StringComparison]::Ordinal)) {
                [void]$references.Add($name)
            }
        }
        return $references
    }
    finally {
        $text = $null
        [System.Array]::Clear($encoded, 0, $encoded.Length)
        if ($null -ne $decoded) { [System.Array]::Clear($decoded, 0, $decoded.Length) }
    }
}

[System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [System.IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
$sandboxRoot = [System.IO.Path]::GetFullPath((Join-Path $root 'Data\Backups')).TrimEnd([char[]]'\/')
if (-not $client.StartsWith($sandboxRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-05 input is restricted to a read-only client sandbox under Data/Backups.'
}
if (-not $output.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-05 evidence output must remain inside Rebuild.'
}

$executable = Get-Item -LiteralPath (Join-Path $client 'QY.exe') -ErrorAction Stop
$executableSha = Get-LowerSha256File -Path $executable.FullName
if ($executable.Length -ne $expectedExecutableBytes -or
    $executableSha -ne $expectedExecutableSha256) {
    throw 'The P2-05 sandbox executable does not match the frozen P1-09 source binding.'
}
$qGameEngine = Get-Item -LiteralPath (Join-Path $client 'ClassCfg\QGameEngine.ecf')
$qGameEngineSha = Get-LowerSha256File -Path $qGameEngine.FullName
if ($qGameEngineSha -ne $expectedQGameEngineSha256) {
    throw 'The QGameEngine ECF does not match the frozen current-client baseline.'
}

$xmlFiles = @(Get-ChildItem -LiteralPath @(
        (Join-Path $client 'Table'),
        (Join-Path $client 'CLSVShare')) -Recurse -File -Filter '*.xml' |
    Sort-Object FullName)
$ecfFiles = @(Get-ChildItem -LiteralPath (Join-Path $client 'ClassCfg') -File -Filter '*.ecf' |
    Sort-Object FullName)
$populationBytes = [long](($xmlFiles + $ecfFiles | Measure-Object Length -Sum).Sum)
if ($xmlFiles.Count -ne $expectedXmlFiles -or $ecfFiles.Count -ne $expectedEcfFiles -or
    $populationBytes -ne $expectedBytes) {
    throw 'The XML/ECF population does not match the frozen current-client baseline.'
}

$entries = [System.Collections.Generic.List[object]]::new()
foreach ($file in $xmlFiles) {
    $entries.Add((Get-XmlInventoryEntry -File $file -ClientRootPath $client))
}
foreach ($file in $ecfFiles) {
    $entries.Add((Get-EcfInventoryEntry -File $file -ClientRootPath $client))
}
$entries = @($entries | Sort-Object path)

$serverIndex = Get-ServerReferenceIndex -ServerRoot (Join-Path $workspace 'ServerCode')
$clientReferences = Get-QGameEngineReferenceSet -Path $qGameEngine.FullName
$regionSourcePath = Join-Path $workspace 'ClientCode\Game\Src\QRegionMgr.cpp'
$classCfgSolutionPath = Join-Path $workspace 'ClientCode\QRender\QRender.sln'
$p204Path = Join-Path $root 'Data\Inventory\p2-04-current-table-inventory.json'

foreach ($entry in $entries) {
    $baseName = [System.IO.Path]::GetFileName($entry.path).ToLowerInvariant()
    $serverReferences = if ($entry.group -eq 'CLSVShare') {
        @($serverIndex.xml_references[$baseName] | Sort-Object -Unique)
    }
    else { @() }
    $clientReference = if ($entry.group -eq 'CLSVShare') {
        $clientReferences.Contains($baseName)
    }
    elseif ($entry.group -eq 'Table/Regions') { $true }
    elseif ($entry.path -eq 'Table/help_docs.xml') {
        $clientReferences.Contains('help_docs.xml')
    }
    else { $entry.group -eq 'ClassCfg' }
    $scope = if ($entry.group -eq 'CLSVShare') { 'shared' } else { 'client-only' }
    $role = if ($entry.group -eq 'CLSVShare') { 'shared-configuration-data' }
        elseif ($entry.path.StartsWith('Table/Regions/Regions/')) {
            'client-region-nested-shadow-copy'
        }
        elseif ($entry.group -eq 'Table/Regions') { 'client-region-runtime-data' }
        elseif ($entry.group -eq 'Table/root') { 'client-help-data' }
        else { $entry.structure.usage_candidate }
    Add-Member -InputObject $entry -NotePropertyName ownership -NotePropertyValue (
        [pscustomobject][ordered]@{
            scope = $scope
            role = $role
            client_reference = $clientReference
            server_reference = @($serverReferences).Count -gt 0
            server_reference_files = @($serverReferences)
            classification_basis = if ($entry.group -eq 'CLSVShare') {
                'CLSVShare namespace plus current-client and complete legacy-server literal-reference scan'
            }
            elseif ($entry.group -eq 'Table/Regions') {
                'QRegionMgr constructs Table/Regions/<world>.xml on the client'
            }
            elseif ($entry.group -eq 'Table/root') {
                'QGameEngine ECF references Table/help_docs.xml'
            }
            else {
                'installed ClassCfg population plus missing ClassCfg project reference in QRender solution'
            }
        })
}

$duplicateGroups = @($entries | Group-Object sha256 | Where-Object Count -gt 1 |
    Sort-Object Name | ForEach-Object {
        $paths = @($_.Group.path | Sort-Object)
        $names = @($paths | ForEach-Object {
                [System.IO.Path]::GetFileName($_).ToLowerInvariant()
            } | Sort-Object -Unique)
        [pscustomobject][ordered]@{
            sha256 = $_.Name
            files = $_.Count
            classification = if ($names.Count -eq 1) {
                'nested-path-shadow-exact-copy'
            }
            else { 'same-content-distinct-logical-names' }
            paths = $paths
        }
    })
$basenameCollisions = @($entries | Group-Object {
        [System.IO.Path]::GetFileName($_.path).ToLowerInvariant()
    } | Where-Object Count -gt 1 | Sort-Object Name | ForEach-Object {
        $hashes = @($_.Group.sha256 | Sort-Object -Unique)
        [pscustomobject][ordered]@{
            basename = $_.Name
            files = $_.Count
            distinct_hashes = $hashes.Count
            classification = if ($hashes.Count -eq 1) {
                'exact-shadow-copy'
            }
            else { 'divergent-override-candidate' }
            paths = @($_.Group.path | Sort-Object)
        }
    })

$xmlEntries = @($entries | Where-Object kind -eq 'xml')
$ecfEntries = @($entries | Where-Object kind -eq 'ecf')
$sharedEntries = @($entries | Where-Object { $_.ownership.scope -eq 'shared' })
$clientOnlyEntries = @($entries | Where-Object { $_.ownership.scope -eq 'client-only' })
$malformedXml = @($xmlEntries | Where-Object {
        $_.structure.classification -eq 'malformed-xml'
    })
$fragmentXml = @($xmlEntries | Where-Object {
        $_.structure.classification -eq 'xml-fragment'
    })
$repeatedAssignments = @($ecfEntries | Where-Object {
        $_.structure.repeated_assignment_count -gt 0
    })
$completed = $entries.Count -eq $expectedFiles -and
    $xmlEntries.Count -eq $expectedXmlFiles -and
    $ecfEntries.Count -eq $expectedEcfFiles -and
    @($ecfEntries | Where-Object { -not $_.structure.round_trip_matches_source }).Count -eq 0 -and
    @($entries | Where-Object { $_.ownership.scope -notin @('client-only', 'shared') }).Count -eq 0 -and
    @($xmlEntries | Where-Object { -not $_.structure.classification }).Count -eq 0 -and
    @($ecfEntries | Where-Object { $_.encoding.classification -eq 'opaque' }).Count -eq 0

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [System.DateTimeOffset]::UtcNow.ToString('o')
    result = if ($completed) { 'PASS' } else { 'FAIL' }
    task = 'P2-05'
    task_status = if ($completed) { 'COMPLETE' } else { 'IN_PROGRESS' }
    completion_criteria_satisfied = $completed
    source = [pscustomobject][ordered]@{
        kind = 'read-only-sandbox-client'
        build = $sourceBuild
        sandbox_relative_path = 'Data/Backups/p1-09-runtime-client'
        executable = [pscustomobject][ordered]@{
            path = 'QY.exe'
            bytes = $executable.Length
            sha256 = $executableSha
        }
        population = [pscustomobject][ordered]@{
            files = $entries.Count
            bytes = $populationBytes
            xml_files = $xmlEntries.Count
            ecf_files = $ecfEntries.Count
        }
        p2_04_evidence = 'Data/Inventory/p2-04-current-table-inventory.json'
        p2_04_evidence_sha256 = Get-LowerSha256File -Path $p204Path
    }
    summary = [pscustomobject][ordered]@{
        files = $entries.Count
        bytes = $populationBytes
        classified = @($entries | Where-Object { $_.ownership.scope }).Count
        unresolved = @($entries | Where-Object { -not $_.ownership.scope }).Count
        client_only = $clientOnlyEntries.Count
        shared = $sharedEntries.Count
        xml = [pscustomobject][ordered]@{
            files = $xmlEntries.Count
            strict_documents = @($xmlEntries | Where-Object {
                    $_.structure.classification -eq 'xml-document'
                }).Count
            strict_fragments = $fragmentXml.Count
            malformed_isolated = $malformedXml.Count
            encodings = @($xmlEntries | Group-Object { $_.encoding.classification } |
                Sort-Object Name | ForEach-Object {
                    [pscustomobject][ordered]@{ encoding = $_.Name; files = $_.Count }
                })
            parsed_elements = [long](($xmlEntries.structure |
                    Measure-Object elements -Sum).Sum)
            parsed_attributes = [long](($xmlEntries.structure |
                    Measure-Object attributes -Sum).Sum)
        }
        ecf = [pscustomobject][ordered]@{
            files = $ecfEntries.Count
            round_trip_verified = @($ecfEntries | Where-Object {
                    $_.structure.round_trip_matches_source
                }).Count
            editor_tooling_candidates = @($ecfEntries | Where-Object {
                    $_.structure.usage_candidate -eq 'client-editor-tooling'
                }).Count
            runtime_or_engine_candidates = @($ecfEntries | Where-Object {
                    $_.structure.usage_candidate -eq 'client-runtime-or-engine'
                }).Count
            lines = [long](($ecfEntries.structure | Measure-Object lines -Sum).Sum)
            assignment_lines = [long](($ecfEntries.structure |
                    Measure-Object assignment_lines -Sum).Sum)
            repeated_assignments = [long](($ecfEntries.structure |
                    Measure-Object repeated_assignment_count -Sum).Sum)
            encodings = @($ecfEntries | Group-Object { $_.encoding.classification } |
                Sort-Object Name | ForEach-Object {
                    [pscustomobject][ordered]@{ encoding = $_.Name; files = $_.Count }
                })
        }
        exact_duplicate_groups = $duplicateGroups.Count
        exact_duplicate_files = @($duplicateGroups | ForEach-Object { $_.files } |
            Measure-Object -Sum).Sum
        basename_collision_groups = $basenameCollisions.Count
        divergent_override_candidates = @($basenameCollisions | Where-Object {
                $_.classification -eq 'divergent-override-candidate'
            }).Count
    }
    ownership = [pscustomobject][ordered]@{
        shared_namespace_files = $sharedEntries.Count
        shared_with_server_literal_reference = @($sharedEntries | Where-Object {
                $_.ownership.server_reference
            }).Count
        shared_with_client_literal_reference = @($sharedEntries | Where-Object {
                $_.ownership.client_reference
            }).Count
        client_only_region_runtime = @($entries | Where-Object {
                $_.ownership.role -eq 'client-region-runtime-data'
            }).Count
        client_only_region_nested_shadows = @($entries | Where-Object {
                $_.ownership.role -eq 'client-region-nested-shadow-copy'
            }).Count
        client_only_help = @($entries | Where-Object {
                $_.ownership.role -eq 'client-help-data'
            }).Count
        client_only_ecf = $ecfEntries.Count
    }
    duplicates_and_overrides = [pscustomobject][ordered]@{
        exact_content_groups = $duplicateGroups
        basename_collisions = $basenameCollisions
        ecf_repeated_assignment_files = @($repeatedAssignments | ForEach-Object {
                [pscustomobject][ordered]@{
                    path = $_.path
                    repeated_assignments = $_.structure.repeated_assignment_count
                }
            })
        deletion_authorized = $false
        interpretation =
            'Exact duplicates and repeated assignments are inventory facts only; P2-05 does not delete files or choose winning values.'
    }
    malformed_xml_isolation = @($malformedXml | ForEach-Object {
            [pscustomobject][ordered]@{
                path = $_.path
                error = $_.structure.error
                compatibility_action = 'preserve-raw-and-require-explicit-tolerant-parser-test'
            }
        })
    source_evidence = [pscustomobject][ordered]@{
        client_region_loader = [pscustomobject][ordered]@{
            path = 'ClientCode/Game/Src/QRegionMgr.cpp'
            sha256 = Get-LowerSha256File -Path $regionSourcePath
        }
        classcfg_solution_reference = [pscustomobject][ordered]@{
            path = 'ClientCode/QRender/QRender.sln'
            sha256 = Get-LowerSha256File -Path $classCfgSolutionPath
            referenced_project = 'ClassCfg/ClassCfg.vcproj'
            referenced_project_present = Test-Path -LiteralPath (
                Join-Path $workspace 'ClientCode\QRender\ClassCfg\ClassCfg.vcproj')
        }
        client_config = [pscustomobject][ordered]@{
            path = 'ClassCfg/QGameEngine.ecf'
            sha256 = $qGameEngineSha
            decoded_content_emitted = $false
        }
        legacy_server_scan = [pscustomobject][ordered]@{
            files_scanned = $serverIndex.files_scanned
            population_sha256 = $serverIndex.population_sha256
            ecf_literal_reference_files = @($serverIndex.ecf_reference_files)
        }
    }
    confidentiality = [pscustomobject][ordered]@{
        xml_text_emitted = $false
        xml_attribute_values_emitted = $false
        ecf_decoded_lines_emitted = $false
        ecf_assignment_keys_emitted = $false
        ecf_assignment_values_emitted = $false
        decoded_byte_buffers_cleared = $true
    }
    files = $entries
    next_scope = [pscustomobject][ordered]@{
        tasks = @('P2-06', 'P2-08', 'P2-11')
        detail =
            'Build raw/normalized/schema layers without normalizing the six malformed XML files or selecting ECF repeated assignments implicitly.'
    }
}

$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($output)) | Out-Null
[System.IO.File]::WriteAllText($output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$report | ConvertTo-Json -Depth 5
if (-not $completed) { throw 'P2-05 auxiliary configuration inventory is incomplete.' }
