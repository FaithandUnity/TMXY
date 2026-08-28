[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$CatalogPath = 'E:\QQXYCodeDev\Rebuild\Data\Exports\P2-12\p2-12-full-asset-inventory.jsonl',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Inventory\p2-12-full-asset-inventory.json',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$client = [IO.Path]::GetFullPath($ClientRoot).TrimEnd([char[]]'\/')
$catalog = [IO.Path]::GetFullPath($CatalogPath)
$output = [IO.Path]::GetFullPath($OutputPath)
foreach ($candidate in @($catalog, $output)) {
    if (-not $candidate.StartsWith(
            $root + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'P2-12 outputs must remain inside Rebuild.'
    }
}

$manifestPath = Join-Path $root 'Data\RawManifests\client-3.0.0.413.files.jsonl'
$manifestSummaryPath = Join-Path $root 'Data\RawManifests\client-3.0.0.413.summary.json'
$moduleRoot = Join-Path $root 'Tools\TMXY.AssetInventory'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$policyPath = Join-Path $root 'Contracts\data-schema\full-asset-inventory-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\full-asset-inventory-v1.schema.json'
foreach ($path in @($client, $manifestPath, $manifestSummaryPath, $moduleRoot, $lockPath,
        $policyPath, $schemaPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "P2-12 input is missing: $path" }
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdoutTask.GetAwaiter().GetResult()
        stderr = $stderrTask.GetAwaiter().GetResult()
    }
}

function New-AuxiliaryRecord {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][string]$Family,
        [Parameter(Mandatory = $true)][string]$Contract,
        [Parameter(Mandatory = $true)][string]$Structure,
        [Parameter(Mandatory = $true)][string]$ErrorCode,
        [Parameter(Mandatory = $true)]$Metrics
    )
    [pscustomobject][ordered]@{
        path = [string]$Entry.path
        sha256 = [string]$Entry.sha256
        bytes = [int64]$Entry.size
        family = $Family
        format_contract = $Contract
        structure = $Structure
        package_candidates = 0
        descriptor_variants = 0
        valid_variants = 0
        package_state = 'not_applicable'
        error = $ErrorCode
        error_offset = 0
        metrics = $Metrics
    }
}

function Test-ZifRecord {
    param([Parameter(Mandatory = $true)]$Entry)
    $metrics = [ordered]@{}
    try {
        $path = Join-Path $client ([string]$Entry.path).Replace(
            '/', [IO.Path]::DirectorySeparatorChar)
        $bytes = [IO.File]::ReadAllBytes($path)
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $xml = [xml]$utf8.GetString($bytes)
        if ($xml.DocumentElement.Name -ne 'Zone') { throw 'root' }
        $sections = @($xml.DocumentElement.ChildNodes |
            Where-Object NodeType -eq ([Xml.XmlNodeType]::Element) |
            ForEach-Object Name | Sort-Object)
        if (Compare-Object @('AllPath', 'DirInfo', 'PathIndex', 'zPolygon') $sections) {
            throw 'sections'
        }
        $directions = @($xml.SelectNodes('/Zone/DirInfo/A'))
        if ($directions.Count -ne 4) { throw 'directions' }
        foreach ($route in @($xml.SelectNodes('/Zone/AllPath/A'))) {
            if (-not $route.HasAttribute('dir') -or -not $route.HasAttribute('num')) {
                throw 'route_attributes'
            }
            $count = [int]$route.GetAttribute('num')
            for ($index = 0; $index -lt $count; ++$index) {
                if (-not $route.HasAttribute("n$index")) { throw 'route_sequence' }
            }
        }
        $metrics.path_indices = @($xml.SelectNodes('/Zone/PathIndex/A')).Count
        $metrics.directions = $directions.Count
        $metrics.polygons = @($xml.SelectNodes('/Zone/zPolygon/Poly')).Count
        $metrics.polygon_ids = @($xml.SelectNodes('/Zone/zPolygon/Poly/ID')).Count
        $metrics.routes = @($xml.SelectNodes('/Zone/AllPath/A')).Count
        New-AuxiliaryRecord -Entry $Entry -Family 'zif' -Contract 'zif-xml-v1' `
            -Structure 'PASS' -ErrorCode 'none' -Metrics ([pscustomobject]$metrics)
    }
    catch {
        New-AuxiliaryRecord -Entry $Entry -Family 'zif' -Contract 'zif-xml-v1' `
            -Structure 'FAIL' -ErrorCode 'invalid_zif_xml' -Metrics ([pscustomobject]$metrics)
    }
}

function Test-WavRecord {
    param([Parameter(Mandatory = $true)]$Entry)
    $metrics = [ordered]@{}
    try {
        $path = Join-Path $client ([string]$Entry.path).Replace(
            '/', [IO.Path]::DirectorySeparatorChar)
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes.Length -lt 12 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF' -or
            [Text.Encoding]::ASCII.GetString($bytes, 8, 4) -ne 'WAVE') { throw 'signature' }
        $offset = 12
        $formatSeen = $false
        $dataBytes = [int64]0
        $chunkCount = 0
        while ($offset + 8 -le $bytes.Length) {
            $kind = [Text.Encoding]::ASCII.GetString($bytes, $offset, 4)
            $size = [BitConverter]::ToUInt32($bytes, $offset + 4)
            $payload = $offset + 8
            if ([int64]$payload + $size -gt $bytes.Length) { throw 'chunk_bounds' }
            if ($kind -eq 'fmt ' -and $size -ge 16) {
                $metrics.codec = [BitConverter]::ToUInt16($bytes, $payload)
                $metrics.channels = [BitConverter]::ToUInt16($bytes, $payload + 2)
                $metrics.sample_rate = [BitConverter]::ToUInt32($bytes, $payload + 4)
                $metrics.bits_per_sample = [BitConverter]::ToUInt16($bytes, $payload + 14)
                $formatSeen = $true
            }
            elseif ($kind -eq 'data') { $dataBytes += $size }
            ++$chunkCount
            $offset = $payload + $size + ($size % 2)
        }
        if (-not $formatSeen -or $dataBytes -le 0) { throw 'required_chunks' }
        $metrics.data_bytes = $dataBytes
        $metrics.chunks = $chunkCount
        New-AuxiliaryRecord -Entry $Entry -Family 'wav' -Contract 'riff-wave-pcm-v1' `
            -Structure 'PASS' -ErrorCode 'none' -Metrics ([pscustomobject]$metrics)
    }
    catch {
        New-AuxiliaryRecord -Entry $Entry -Family 'wav' -Contract 'riff-wave-pcm-v1' `
            -Structure 'FAIL' -ErrorCode 'invalid_riff_wave' -Metrics ([pscustomobject]$metrics)
    }
}

function Test-Mp3Record {
    param([Parameter(Mandatory = $true)]$Entry)
    $metrics = [ordered]@{}
    try {
        $path = Join-Path $client ([string]$Entry.path).Replace(
            '/', [IO.Path]::DirectorySeparatorChar)
        $stream = [IO.File]::OpenRead($path)
        try {
            $prefix = [byte[]]::new(10)
            $read = $stream.Read($prefix, 0, $prefix.Length)
        }
        finally { $stream.Dispose() }
        if ($read -ge 10 -and [Text.Encoding]::ASCII.GetString($prefix, 0, 3) -eq 'ID3') {
            if (($prefix[6] -band 0x80) -ne 0 -or ($prefix[7] -band 0x80) -ne 0 -or
                ($prefix[8] -band 0x80) -ne 0 -or ($prefix[9] -band 0x80) -ne 0) {
                throw 'id3_size'
            }
            $metrics.header = 'ID3v2'
        }
        elseif ($read -ge 2 -and $prefix[0] -eq 0xFF -and ($prefix[1] -band 0xE0) -eq 0xE0) {
            $metrics.header = 'MPEG-frame'
        }
        else { throw 'prefix' }
        New-AuxiliaryRecord -Entry $Entry -Family 'mp3' -Contract 'mpeg-audio-prefix-v1' `
            -Structure 'PASS' -ErrorCode 'none' -Metrics ([pscustomobject]$metrics)
    }
    catch {
        New-AuxiliaryRecord -Entry $Entry -Family 'mp3' -Contract 'mpeg-audio-prefix-v1' `
            -Structure 'FAIL' -ErrorCode 'invalid_mpeg_audio_prefix' -Metrics ([pscustomobject]$metrics)
    }
}

$manifestSummary = Get-Content -LiteralPath $manifestSummaryPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($manifestHash -ne [string]$manifestSummary.files_manifest_sha256 -or
    [int]$manifestSummary.file_count -ne 45532) {
    throw 'P2-12 frozen client Manifest binding failed.'
}

$extensions = @('.qtx', '.sm', '.skem', '.anim', '.ter', '.zif', '.wav', '.mp3')
$customExtensions = @('.qtx', '.sm', '.skem', '.anim', '.ter')
$entries = [Collections.Generic.List[object]]::new()
foreach ($line in [IO.File]::ReadLines($manifestPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $entry = $line | ConvertFrom-Json
    $extension = [IO.Path]::GetExtension([string]$entry.path).ToLowerInvariant()
    if ($extensions -contains $extension) {
        if (([string]$entry.path).IndexOfAny([char[]]"`t`r`n") -ge 0) {
            throw 'P2-12 refuses resource paths containing TSV control separators.'
        }
        $entries.Add([pscustomobject][ordered]@{
            path = [string]$entry.path
            size = [int64]$entry.size
            sha256 = [string]$entry.sha256
            extension = $extension
        })
    }
}
$entries = @($entries | Sort-Object path)
$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedCounts = [ordered]@{}
foreach ($extension in @($policy.target_extensions | Sort-Object)) {
    $family = ([string]$extension).TrimStart('.')
    $expectedCounts[$extension] = [int]$policy.expected_families.PSObject.Properties[$family].Value.files
}
foreach ($extension in $expectedCounts.Keys) {
    if (@($entries | Where-Object extension -eq $extension).Count -ne $expectedCounts[$extension]) {
        throw "P2-12 frozen family count changed: $extension"
    }
}
if ($entries.Count -ne 40090 -or @($entries.path | Sort-Object -Unique).Count -ne 40090) {
    throw 'P2-12 requires exactly 40,090 unique target assets.'
}
$inputLines = @($entries | ForEach-Object { "$($_.path)|$($_.size)|$($_.sha256)" })
$inputSetHash = Get-TextSha256 -Value (($inputLines -join "`n") + "`n")

$catalogDirectory = [IO.Path]::GetDirectoryName($catalog)
[IO.Directory]::CreateDirectory($catalogDirectory) | Out-Null
$tsvPath = Join-Path $catalogDirectory 'p2-12-custom-assets.tsv'
$customEntries = @($entries | Where-Object { $customExtensions -contains $_.extension })
$tsv = @($customEntries | ForEach-Object { "$($_.path)`t$($_.size)`t$($_.sha256)" }) -join "`n"
[IO.File]::WriteAllText($tsvPath, $tsv + "`n", [Text.UTF8Encoding]::new($false))

$sourceRoots = @($moduleRoot, 'TMXY.FormatCore', 'TMXY.Package', 'TMXY.Transform',
    'TMXY.Texture', 'TMXY.StaticMesh', 'TMXY.SkeletalMesh', 'TMXY.Animation',
    'TMXY.Terrain' | ForEach-Object {
        if ($_ -is [string] -and $_ -ne $moduleRoot) { Join-Path $root "Tools\$_" }
        else { $_ }
    })
$sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoots -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp', '.ps1') -or $_.Name -eq 'CMakeLists.txt' } |
    Sort-Object FullName)
$sourceLines = @($sourceFiles | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative|$hash"
    })
$sourceHash = Get-TextSha256 -Value (($sourceLines -join "`n") + "`n")

$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or [string]$image[0].Id -ne $expectedBuilderId -or
    [string]$image[0].Config.User -ne 'tmxy') {
    throw 'P2-12 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools
cp /workspace/.clang-format /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /workspace/Tools/TMXY.FormatCore /workspace/Tools/TMXY.Package /workspace/Tools/TMXY.Transform /workspace/Tools/TMXY.Texture /workspace/Tools/TMXY.StaticMesh /workspace/Tools/TMXY.SkeletalMesh /workspace/Tools/TMXY.Animation /workspace/Tools/TMXY.Terrain /workspace/Tools/TMXY.AssetInventory /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
find TMXY.AssetInventory -type f \( -name '*.cpp' -o -name '*.hpp' \) -print0 | xargs -0 clang-format-21 --dry-run --Werror --style=file
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_ASSET_INVENTORY=ON
cmake --build --preset ci-linux-clang
clang-tidy-21 -p out/build/ci-linux-clang TMXY.AssetInventory/apps/asset_inventory_main.cpp --quiet
ctest --preset ci-linux-clang
./out/build/ci-linux-clang/TMXY.AssetInventory/tmxy_asset_inventory /legacy/client /workspace/Data/Exports/P2-12/p2-12-custom-assets.tsv
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=2g',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$client,target=/legacy/client,readonly",
    $builderReference, 'bash', '-c', $containerScript
)
$execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
if ($execution.exit_code -ne 0) {
    throw "P2-12 locked scanner failed: $($execution.stderr.Trim())"
}

$recordsByPath = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::Ordinal)
$linesByPath = [Collections.Generic.Dictionary[string, string]]::new(
    [StringComparer]::Ordinal)
foreach ($line in @($execution.stdout -split "`n")) {
    if (-not $line.StartsWith('{"path":', [StringComparison]::Ordinal)) { continue }
    $record = $line | ConvertFrom-Json
    $path = [string]$record.path
    if ($recordsByPath.ContainsKey($path)) { throw "P2-12 duplicate scanner row: $path" }
    $recordsByPath.Add($path, $record)
    $linesByPath.Add($path, $line)
}
if ($recordsByPath.Count -ne $customEntries.Count) {
    throw "P2-12 scanner returned $($recordsByPath.Count) of $($customEntries.Count) custom assets."
}

foreach ($entry in $entries | Where-Object extension -eq '.zif') {
    $record = Test-ZifRecord -Entry $entry
    $recordsByPath.Add($entry.path, $record)
    $linesByPath.Add($entry.path, ($record | ConvertTo-Json -Depth 8 -Compress))
}
foreach ($entry in $entries | Where-Object extension -eq '.wav') {
    $record = Test-WavRecord -Entry $entry
    $recordsByPath.Add($entry.path, $record)
    $linesByPath.Add($entry.path, ($record | ConvertTo-Json -Depth 8 -Compress))
}
foreach ($entry in $entries | Where-Object extension -eq '.mp3') {
    $record = Test-Mp3Record -Entry $entry
    $recordsByPath.Add($entry.path, $record)
    $linesByPath.Add($entry.path, ($record | ConvertTo-Json -Depth 8 -Compress))
}

$catalogLines = [Collections.Generic.List[string]]::new($entries.Count)
$records = [Collections.Generic.List[object]]::new($entries.Count)
foreach ($entry in $entries) {
    if (-not $recordsByPath.ContainsKey($entry.path)) {
        throw "P2-12 omitted target asset: $($entry.path)"
    }
    $record = $recordsByPath[$entry.path]
    if ([int64]$record.bytes -ne $entry.size -or [string]$record.sha256 -ne $entry.sha256 -or
        [string]$record.family -ne $entry.extension.TrimStart('.')) {
        throw "P2-12 Manifest binding mismatch: $($entry.path)"
    }
    $records.Add($record)
    $catalogLines.Add($linesByPath[$entry.path])
}
$catalogText = ($catalogLines -join "`n") + "`n"
$catalogHash = Get-TextSha256 -Value $catalogText

$familyReports = @($records | Group-Object family | Sort-Object Name | ForEach-Object {
        $group = @($_.Group)
        [pscustomobject][ordered]@{
            family = $_.Name
            files = $group.Count
            bytes = [int64](($group | Measure-Object bytes -Sum).Sum)
            pass = @($group | Where-Object structure -eq 'PASS').Count
            unresolved = @($group | Where-Object structure -eq 'UNRESOLVED').Count
            corrupt = @($group | Where-Object structure -eq 'FAIL').Count
            package_missing = @($group | Where-Object package_state -eq 'missing').Count
            package_ambiguous_equivalent = @($group |
                Where-Object package_state -eq 'ambiguous_equivalent').Count
            package_ambiguous_divergent = @($group |
                Where-Object package_state -eq 'ambiguous_divergent').Count
        }
    })
$corrupt = @($records | Where-Object structure -eq 'FAIL')
$unresolved = @($records | Where-Object structure -eq 'UNRESOLVED')
$unsupported = @($records | Where-Object format_contract -eq 'unsupported')
$classified = $records.Count -eq $entries.Count -and $unsupported.Count -eq 0 -and
    @($records | Where-Object { $_.structure -notin @('PASS', 'FAIL', 'UNRESOLVED') }).Count -eq 0

$dependencies = [ordered]@{}
foreach ($name in @('p2-01-package-inventory.json', 'p1-13-qtx-texture.json',
        'p1-14-sm-static-mesh.json', 'p1-15-skem-skeletal-mesh.json',
        'p1-16-anim-animation.json', 'p1-17-ter-terrain.json',
        'p1-18-auxiliary-assets.json')) {
    $path = if ($name.StartsWith('p2-', [StringComparison]::Ordinal)) {
        Join-Path $root "Data\Inventory\$name"
    }
    else { Join-Path $root "Data\BuildBaseline\$name" }
    $dependency = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$dependency.result -notin @('PASS', 'PASS_DIAGNOSTIC')) {
        throw "P2-12 dependency is not passing: $name"
    }
    $sourceFingerprint = if ($dependency.PSObject.Properties.Name -contains 'source_sha256') {
        [string]$dependency.source_sha256
    }
    elseif ($dependency.PSObject.Properties.Name -contains 'implementation' -and
        $dependency.implementation.PSObject.Properties.Name -contains 'source_sha256') {
        [string]$dependency.implementation.source_sha256
    }
    else { '' }
    if ($sourceFingerprint -notmatch '^[0-9a-f]{64}$') {
        throw "P2-12 dependency has no stable source fingerprint: $name"
    }
    $completion = if ($dependency.PSObject.Properties.Name -contains
        'completion_criteria_satisfied') { [bool]$dependency.completion_criteria_satisfied }
        else { $true }
    $dependencies[$name] = Get-TextSha256 -Value (
        "$name|$([string]$dependency.result)|$completion|$sourceFingerprint`n")
}

$captured = [DateTimeOffset]::UtcNow.ToString('o')
if ($Check -and (Test-Path -LiteralPath $output -PathType Leaf)) {
    $captured = [string](Get-Content -LiteralPath $output -Raw -Encoding UTF8 |
        ConvertFrom-Json -DateKind String).captured_utc
}
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = $captured
    result = if ($classified) { 'PASS' } else { 'FAIL' }
    task = 'P2-12'
    task_status = if ($classified) { 'COMPLETE' } else { 'IN_PROGRESS' }
    completion_criteria_satisfied = $classified
    input = [pscustomobject][ordered]@{
        client_version = '3.0.0.413'
        manifest = 'Data/RawManifests/client-3.0.0.413.files.jsonl'
        manifest_sha256 = $manifestHash
        selected_set_sha256 = $inputSetHash
        files = $entries.Count
        bytes = [int64](($entries | Measure-Object size -Sum).Sum)
        source_copy_policy = 'reference_only'
    }
    summary = [pscustomobject][ordered]@{
        files = $records.Count
        bytes = [int64](($records | Measure-Object bytes -Sum).Sum)
        structurally_valid = @($records | Where-Object structure -eq 'PASS').Count
        unresolved_structure = $unresolved.Count
        corrupt = $corrupt.Count
        unsupported = $unsupported.Count
        families = $familyReports
        package_candidate_policy = 'retain all exact logical-name candidates; classify equivalent or divergent descriptors'
        unresolved_policy = 'retain and route; never guess a missing headerless descriptor'
        corrupt_policy = 'retain source hash and parser error; never repair or delete during inventory'
    }
    catalog = [pscustomobject][ordered]@{
        path = 'Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl'
        tracked = $false
        lines = $catalogLines.Count
        bytes = [Text.Encoding]::UTF8.GetByteCount($catalogText)
        sha256 = $catalogHash
        contains_payload_bytes = $false
        contains_decoded_assets = $false
    }
    contracts = [pscustomobject][ordered]@{
        policy = 'Contracts/data-schema/full-asset-inventory-policy-v1.json'
        policy_sha256 = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToLowerInvariant()
        schema = 'Contracts/data-schema/full-asset-inventory-v1.schema.json'
        schema_sha256 = (Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    dependencies = [pscustomobject]$dependencies
    implementation = [pscustomobject][ordered]@{
        source_files = $sourceFiles.Count
        source_sha256 = $sourceHash
        scanner = 'Tools/TMXY.AssetInventory/apps/asset_inventory_main.cpp'
        generator = 'Tools/TMXY.AssetInventory/New-FullAssetInventory.ps1'
        production_readers = @('TMXY.Texture', 'TMXY.StaticMesh', 'TMXY.SkeletalMesh',
            'TMXY.Animation', 'TMXY.Terrain')
        dependency_binding = 'stable task result, completion state, and source fingerprint'
        package_names_emitted = $false
        object_names_emitted = $false
        payload_bytes_emitted = $false
    }
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = [string]$image[0].Id
        user = [string]$image[0].Config.User
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        client_mount = 'read-only'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_storage = 'ephemeral_tmpfs'
    }
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        custom_asset_lines = $customEntries.Count
        auxiliary_asset_lines = $entries.Count - $customEntries.Count
        stderr_sha256 = Get-TextSha256 -Value $execution.stderr
    }
    next_scope = [pscustomobject][ordered]@{
        tasks = @('P2-13', 'P2-14', 'P2-15', 'P2-16')
        detail = 'Build reference closure, duplicate/orphan analysis, conversion routing, and content-addressed cache policy from this catalog.'
    }
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"

if ($Check) {
    if (-not (Test-Path -LiteralPath $catalog -PathType Leaf) -or
        (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash.ToLowerInvariant() -ne $catalogHash) {
        throw 'P2-12 catalog differs from the frozen generated catalog.'
    }
    if (-not (Test-Path -LiteralPath $output -PathType Leaf) -or
        [IO.File]::ReadAllText($output, [Text.Encoding]::UTF8) -ne $json) {
        $changedSections = [Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $output -PathType Leaf) {
            $recorded = Get-Content -LiteralPath $output -Raw -Encoding UTF8 |
                ConvertFrom-Json -DateKind String
            foreach ($property in $report.PSObject.Properties.Name) {
                $actualSection = $report.$property | ConvertTo-Json -Depth 12 -Compress
                $recordedSection = $recorded.$property | ConvertTo-Json -Depth 12 -Compress
                if ($actualSection -cne $recordedSection) { $changedSections.Add($property) }
            }
        }
        throw "P2-12 evidence differs from the regenerated report; sections: $($changedSections -join ', ')."
    }
}
else {
    [IO.File]::WriteAllText($catalog, $catalogText, [Text.UTF8Encoding]::new($false))
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
    [IO.File]::WriteAllText($output, $json, [Text.UTF8Encoding]::new($false))
}
$json
if (-not $classified) { throw 'P2-12 inventory did not classify every target asset.' }
