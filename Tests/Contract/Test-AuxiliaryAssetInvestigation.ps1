[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-18-auxiliary-assets.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$workspaceRoot = [System.IO.Path]::GetDirectoryName($root)
$clientRoot = Join-Path $workspaceRoot '天命西游'
$legacyRoot = Join-Path $workspaceRoot 'ClientCode'

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
        exit_code = $process.ExitCode
        output = ($stdout + $stderr).Trim()
    }
}

function Get-OrderedCounts {
    param([Parameter(Mandatory = $true)][hashtable]$Counts)
    $ordered = [ordered]@{}
    foreach ($key in $Counts.Keys | Sort-Object) { $ordered[$key] = $Counts[$key] }
    return $ordered
}

$requiredFiles = @(
    'Docs/Formats/AUXILIARY-ASSET-INVESTIGATION.md',
    'Tests/Contract/Test-AuxiliaryAssetInvestigation.ps1',
    'Tools/TMXY.Package/apps/package_tree_export_main.cpp',
    'Data/BuildBaseline/p1-08-package-normalized-tree.json',
    'Data/BuildBaseline/p1-13-qtx-texture.json',
    'Data/Toolchain/toolchain.lock.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-18 required file is missing: $relativePath"
    }
}

$document = Get-Content -LiteralPath (Join-Path $root $requiredFiles[0]) -Raw -Encoding UTF8
$documentMarkers = @(
    '## ZIF: zone navigation XML',
    '## Audio: PCM effects and MPEG music',
    '## UI: texture assets plus code-defined behavior',
    '## Shader: material semantics, not shader source',
    '## Priority and ownership route',
    'P1-18 ends at classification and routing'
)
foreach ($marker in $documentMarkers) {
    if (-not $document.Contains($marker, [System.StringComparison]::Ordinal)) {
        throw "P1-18 document marker is missing: $marker"
    }
}

$dependencies = [ordered]@{}
foreach ($name in @('p1-08-package-normalized-tree.json', 'p1-13-qtx-texture.json')) {
    $path = Join-Path $root "Data\BuildBaseline\$name"
    $report = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$report.result -ne 'PASS') {
        throw "P1-18 dependency is not passing: $name"
    }
    $dependencies[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$evidence = @(
    [pscustomobject]@{ path = 'ClientCode\Game\Src\QAutoPath.cpp'; size = 53819; sha256 = '1ff4091fd69894efe6b8a360ac7267974ed491a4f1420945cb7c2627add01858' },
    [pscustomobject]@{ path = 'ClientCode\Game\Hdr\QAutoPath.h'; size = 7358; sha256 = '548f51d64dd0682a1ba147a8004b0071bb848ffb53a6e9c64287aefb2e492e6b' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QAudioDev.h'; size = 2217; sha256 = '1397e9c0f23407353ee47d5cf5b33e6aae1cf6c7525da3c1942dc4c53f740f04' },
    [pscustomobject]@{ path = 'ClientCode\MSSDev\MSSDev.cpp'; size = 16391; sha256 = '173d63331f1998fad70cc416dfdbfd6e74f3bd262af2c0b75c8ef8dbb8fbf44c' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Hdr\QMaterial.h'; size = 2798; sha256 = 'dce356d0e5cdf683fe8751d90d541373d292c9d027cf4218280c79d0bf6d33ca' },
    [pscustomobject]@{ path = 'ClientCode\QRender\Src\QRenderTypes.cpp'; size = 16776; sha256 = 'b276b91ba85256a91d38a894c786e9ebd2a4f4035a812b333fb4405f0bebff50' },
    [pscustomobject]@{ path = 'ClientCode\Game\Hdr\QGUIFrame.h'; size = 34916; sha256 = '7a6e9b6a9a13962d7daafdc70d920d26d0e04ecf4c84bf7ad7a5b12ba2f921cf' },
    [pscustomobject]@{ path = 'ClientCode\Game\Src\QGUIFrame.cpp'; size = 254650; sha256 = '484e1b0c703c28753773f7d31ee211a5380e8f0cb9aed99fb68c91aebc6fbbeb' },
    [pscustomobject]@{ path = '天命西游\Table\pathInfo.path'; size = 2576658; sha256 = '7887724d0d888c1dd9a9da1c402fb515fb32926951889a5e7e9a80f00e30106c' },
    [pscustomobject]@{ path = '天命西游\Table\pathInfo\zone2174.zif'; size = 394; sha256 = '0a8690bc9ac7e98ff0a9e6cd72533cf1de33e1be45e0fb38c919400d10daa58c' },
    [pscustomobject]@{ path = '天命西游\Table\pathInfo\zone1308.zif'; size = 36854; sha256 = '369e013babfbaeae112d63b5fab712091f0cf197d3b9f3033e032d755f4227a5' },
    [pscustomobject]@{ path = '天命西游\Resource\Sound\uisound\MouseOverTarget.wav'; size = 5612; sha256 = 'e290ce84627d15b84b90ac54f1864a8332c33b39b6f542dd80aeeda4261cc988' },
    [pscustomobject]@{ path = '天命西游\Resource\Sound\sound\Baigujing_Death.wav'; size = 970244; sha256 = '9616377d59d856c6543ce571bd98e5338aeb7577ef0401e5f7e3acb40ea223a6' },
    [pscustomobject]@{ path = '天命西游\music\10.mp3'; size = 701405; sha256 = '73ff33f886d70f084ccd4921473141cb773473e2622b02f316655e519bf91a1b' },
    [pscustomobject]@{ path = '天命西游\music\1005.mp3'; size = 3661079; sha256 = '77d0e071a031c37ba560647d76f0000e6017387273bb7dd5df668842a6be1668' }
)
$evidenceReport = foreach ($item in $evidence) {
    $path = Join-Path $workspaceRoot $item.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P1-18 evidence is missing: $($item.path)"
    }
    $file = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $item.size -or $hash -ne $item.sha256) {
        throw "P1-18 evidence changed: $($item.path)"
    }
    [pscustomobject][ordered]@{ path = $item.path; size = $file.Length; sha256 = $hash }
}

$zifFiles = @(Get-ChildItem -LiteralPath (Join-Path $clientRoot 'Table') -Recurse -File `
    -Filter '*.zif' | Sort-Object FullName)
$zifBytes = [int64]($zifFiles | Measure-Object Length -Sum).Sum
$zifDirectoryCounts = @{}
$zifTotals = [ordered]@{ path_indices = 0; directions = 0; polygons = 0; polygon_ids = 0; routes = 0 }
$zifFailures = [System.Collections.Generic.List[string]]::new()
$utf8BomCount = 0
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$expectedSections = @('AllPath', 'DirInfo', 'PathIndex', 'zPolygon')
foreach ($file in $zifFiles) {
    $relative = [System.IO.Path]::GetRelativePath($clientRoot, $file.FullName)
    $group = ($relative -split '[\\/]')[1]
    $zifDirectoryCounts[$group] = 1 + ($zifDirectoryCounts[$group] ?? 0)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF) { $utf8BomCount++ }
        $xml = [xml]$utf8.GetString($bytes)
        if ($xml.DocumentElement.Name -ne 'Zone') { throw 'root is not Zone' }
        $sections = @($xml.DocumentElement.ChildNodes |
            Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element) |
            ForEach-Object Name | Sort-Object)
        if (Compare-Object $expectedSections $sections) { throw 'section set changed' }
        $directionNodes = @($xml.SelectNodes('/Zone/DirInfo/A'))
        if ($directionNodes.Count -ne 4) { throw 'direction count is not four' }
        $directions = @('N', 'E', 'S', 'W')
        for ($index = 0; $index -lt 4; ++$index) {
            $node = $directionNodes[$index]
            if (-not $node.HasAttribute($directions[$index]) -or -not $node.HasAttribute('inNode')) {
                throw 'direction attributes changed'
            }
            if ($node.GetAttribute($directions[$index]) -eq '1' -and -not $node.HasAttribute('node')) {
                throw 'connected direction has no outbound node'
            }
        }
        foreach ($route in @($xml.SelectNodes('/Zone/AllPath/A'))) {
            if (-not $route.HasAttribute('dir') -or -not $route.HasAttribute('num')) {
                throw 'route attributes changed'
            }
            $routeCount = [int]$route.GetAttribute('num')
            for ($index = 0; $index -lt $routeCount; ++$index) {
                if (-not $route.HasAttribute("n$index")) { throw 'route node sequence is incomplete' }
            }
        }
        $zifTotals.path_indices += @($xml.SelectNodes('/Zone/PathIndex/A')).Count
        $zifTotals.directions += $directionNodes.Count
        $zifTotals.polygons += @($xml.SelectNodes('/Zone/zPolygon/Poly')).Count
        $zifTotals.polygon_ids += @($xml.SelectNodes('/Zone/zPolygon/Poly/ID')).Count
        $zifTotals.routes += @($xml.SelectNodes('/Zone/AllPath/A')).Count
    }
    catch {
        $zifFailures.Add("$relative`: $($_.Exception.Message)")
    }
}
if ($zifFiles.Count -ne 841 -or $zifBytes -ne 4565902 -or $utf8BomCount -ne 0 -or
    $zifDirectoryCounts.pathInfo -ne 806 -or $zifDirectoryCounts.zoneInfo -ne 35 -or
    $zifFailures.Count -ne 0 -or $zifTotals.path_indices -ne 47988 -or
    $zifTotals.directions -ne 3364 -or $zifTotals.polygons -ne 6712 -or
    $zifTotals.polygon_ids -ne 77582 -or $zifTotals.routes -ne 1287) {
    throw "P1-18 ZIF corpus contract failed: $($zifFailures -join '; ')"
}

$wavFiles = @(Get-ChildItem -LiteralPath $clientRoot -Recurse -File -Filter '*.wav' |
    Sort-Object FullName)
$wavFormats = @{}
$wavChunks = @{}
$wavDataBytes = [int64]0
$wavFailures = [System.Collections.Generic.List[string]]::new()
foreach ($file in $wavFiles) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -lt 12 -or [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF' -or
            [System.Text.Encoding]::ASCII.GetString($bytes, 8, 4) -ne 'WAVE') { throw 'invalid signature' }
        $offset = 12
        $formatKey = ''
        while ($offset + 8 -le $bytes.Length) {
            $kind = [System.Text.Encoding]::ASCII.GetString($bytes, $offset, 4)
            $size = [System.BitConverter]::ToUInt32($bytes, $offset + 4)
            $wavChunks[$kind] = 1 + ($wavChunks[$kind] ?? 0)
            $payload = $offset + 8
            if ([int64]$payload + $size -gt $bytes.Length) { throw "invalid $kind chunk bounds" }
            if ($kind -eq 'fmt ' -and $size -ge 16) {
                $formatKey = '{0}|{1}|{2}|{3}' -f
                    [System.BitConverter]::ToUInt16($bytes, $payload),
                    [System.BitConverter]::ToUInt16($bytes, $payload + 2),
                    [System.BitConverter]::ToUInt32($bytes, $payload + 4),
                    [System.BitConverter]::ToUInt16($bytes, $payload + 14)
            }
            elseif ($kind -eq 'data') { $wavDataBytes += $size }
            $offset = $payload + $size + ($size % 2)
        }
        if ([string]::IsNullOrEmpty($formatKey)) { throw 'missing fmt chunk' }
        $wavFormats[$formatKey] = 1 + ($wavFormats[$formatKey] ?? 0)
    }
    catch {
        $relative = [System.IO.Path]::GetRelativePath($clientRoot, $file.FullName)
        $wavFailures.Add("$relative`: $($_.Exception.Message)")
    }
}
$expectedWavFormats = @('1|1|22050|16:32', '1|1|44100|16:406',
    '1|2|22050|16:6', '1|2|44100|16:6')
$actualWavFormats = @($wavFormats.Keys | Sort-Object | ForEach-Object { "$_`:$($wavFormats[$_])" })
$wavBytes = [int64]($wavFiles | Measure-Object Length -Sum).Sum
if ($wavFiles.Count -ne 450 -or $wavBytes -ne 54949730 -or $wavDataBytes -ne 54920176 -or
    $wavFailures.Count -ne 0 -or (Compare-Object $expectedWavFormats $actualWavFormats)) {
    throw "P1-18 WAV corpus contract failed: $($wavFailures -join '; ')"
}

$mp3Files = @(Get-ChildItem -LiteralPath $clientRoot -Recurse -File -Filter '*.mp3' |
    Sort-Object FullName)
$mp3Headers = @{ ID3v2 = 0; 'MPEG-frame' = 0; other = 0 }
foreach ($file in $mp3Files) {
    $stream = [System.IO.File]::OpenRead($file.FullName)
    try {
        $prefix = [byte[]]::new(3)
        $read = $stream.Read($prefix, 0, 3)
    }
    finally { $stream.Dispose() }
    if ($read -eq 3 -and [System.Text.Encoding]::ASCII.GetString($prefix) -eq 'ID3') {
        $mp3Headers.ID3v2++
    }
    elseif ($read -ge 2 -and $prefix[0] -eq 0xFF -and ($prefix[1] -band 0xE0) -eq 0xE0) {
        $mp3Headers.'MPEG-frame'++
    }
    else { $mp3Headers.other++ }
}
$mp3Bytes = [int64]($mp3Files | Measure-Object Length -Sum).Sum
if ($mp3Files.Count -ne 64 -or $mp3Bytes -ne 124002521 -or
    $mp3Headers.ID3v2 -ne 39 -or $mp3Headers.'MPEG-frame' -ne 25 -or
    $mp3Headers.other -ne 0) {
    throw 'P1-18 MP3 corpus contract failed.'
}

$allClientFiles = @(Get-ChildItem -LiteralPath $clientRoot -Recurse -File)
$looseShaderExtensions = @('.fx', '.hlsl', '.vsh', '.psh', '.vert', '.frag')
$looseShaderFiles = @($allClientFiles | Where-Object { $_.Extension -in $looseShaderExtensions })
$standaloneUiFiles = @($allClientFiles | Where-Object { $_.Extension -in @('.ui', '.swf') })
$fontFiles = @($allClientFiles | Where-Object { $_.Extension -ieq '.ttf' })
if ($looseShaderFiles.Count -ne 0 -or $standaloneUiFiles.Count -ne 0 -or
    $fontFiles.Count -ne 3 -or [int64]($fontFiles | Measure-Object Length -Sum).Sum -ne 23475828) {
    throw 'P1-18 loose shader, UI, or font inventory changed.'
}

$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$imageRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$actualBuilderId = if ($imageRecords.Count -gt 0) { [string]$imageRecords[0].Id } else { '' }
$builderUser = if ($imageRecords.Count -gt 0) { [string]$imageRecords[0].Config.User } else { '' }
if ($imageRecords.Count -eq 0 -or $actualBuilderId -ne $expectedBuilderId -or $builderUser -ne 'tmxy') {
    throw 'P1-18 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools /tmp/exports/ui /tmp/exports/material
cp /workspace/.clang-format /tmp/tmxy-rebuild/
cp /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /tmp/tmxy-rebuild/Tools/
cp /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.FormatCore /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.Package /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
cmake --preset ci-linux-clang -DTMXY_BUILD_TABLE=OFF -DTMXY_BUILD_TRANSFORM=OFF \
  -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF \
  -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF >/tmp/configure.log
cmake --build --preset ci-linux-clang >/tmp/build.log
ctest --preset ci-linux-clang --output-on-failure
exporter=./out/build/ci-linux-clang/TMXY.Package/tmxy_package_tree_export
for path in /packages/UI/*; do
  name=$(basename "$path")
  "$exporter" "$path" "Packages/UI/$name" > "/tmp/exports/ui/$name.json"
done
for path in /packages/Material/*; do
  name=$(basename "$path")
  "$exporter" "$path" "Packages/Material/$name" > "/tmp/exports/material/$name.json"
done
python3 - <<'PY'
import collections, hashlib, json, pathlib
result = {}
for group in ('ui', 'material'):
    entries = []
    classes = collections.Counter()
    for path in sorted(pathlib.Path('/tmp/exports', group).glob('*.json')):
        data = json.loads(path.read_text())
        item_classes = collections.Counter(
            bytes.fromhex(item['class_name']['hex']).decode('latin1')
            for item in data['objects'])
        classes.update(item_classes)
        source = data['source']['label']
        source_path = pathlib.Path('/packages') / pathlib.PurePosixPath(source).relative_to('Packages')
        entries.append({
            'name': source.split('/')[-1],
            'format_version': data['package']['format_version'],
            'objects': len(data['objects']),
            'classes': dict(sorted(item_classes.items())),
            'sha256': hashlib.sha256(source_path.read_bytes()).hexdigest(),
        })
    result[group] = {
        'files': entries,
        'file_count': len(entries),
        'object_count': sum(item['objects'] for item in entries),
        'classes': dict(sorted(classes.items())),
    }
print('AUX_PACKAGE_RESULT=' + json.dumps(result, separators=(',', ':'), sort_keys=True))
PY
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$packageRoot = Join-Path $clientRoot 'Packages'
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=1g',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$packageRoot,target=/packages,readonly",
    $builderReference, 'bash', '-c', $containerScript
)
$execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
$packageLine = @($execution.output -split "`n" |
    Where-Object { $_ -like 'AUX_PACKAGE_RESULT=*' } | Select-Object -Last 1)
if ($execution.exit_code -ne 0 -or $execution.output -notmatch '100% tests passed' -or
    $packageLine.Count -ne 1) {
    throw "P1-18 isolated Package inventory failed: $($execution.output)"
}
$packageInventory = $packageLine[0].Substring('AUX_PACKAGE_RESULT='.Length) | ConvertFrom-Json
if ([int]$packageInventory.ui.file_count -ne 4 -or
    [int]$packageInventory.ui.object_count -ne 2890 -or
    [int]$packageInventory.ui.classes.QTexture -ne 2890 -or
    [int]$packageInventory.material.file_count -ne 10 -or
    [int]$packageInventory.material.object_count -ne 14390 -or
    [int]$packageInventory.material.classes.QPhongShader -ne 14390) {
    throw 'P1-18 UI or Material Package classification changed.'
}
$expectedObjectCounts = @{
    ui = @('interface:764', 'tempfile.2.tmp:721', 'tempfile.3.tmp:728', 'tempfile.tmp:677')
    material = @('matchar:3490', 'matnpc:1611', 'matnpc2:15', 'matnpc3:98',
        'matparticle:13', 'tempfile.2.tmp:1378', 'tempfile.3.tmp:1389',
        'tempfile.4.tmp:2162', 'tempfile.5.tmp:2274', 'tempfile.tmp:1960')
}
foreach ($group in @('ui', 'material')) {
    $actual = @($packageInventory.$group.files |
        ForEach-Object { "$($_.name):$($_.objects)" } | Sort-Object)
    if (Compare-Object @($expectedObjectCounts[$group] | Sort-Object) $actual) {
        throw "P1-18 $group Package object counts changed."
    }
}

$hashInputs = @($requiredFiles[0], $requiredFiles[1])
$hashLines = foreach ($relativePath in $hashInputs | Sort-Object) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($hash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = 'PASS'
    task = 'P1-18'
    completion_criteria_satisfied = $true
    source_sha256 = $sourceSha
    dependencies = $dependencies
    classification = [pscustomobject][ordered]@{
        zif = 'BOM-less UTF-8 XML zone-navigation records'
        wav = 'RIFF/WAVE PCM effects'
        mp3 = 'MPEG audio music streams'
        ui = 'Package QTexture metadata plus QTX payload; no standalone layout corpus'
        shader = 'Package material semantics; no loose shader source'
        fonts = 'TTF evidence gated by ownership and redistribution review'
    }
    priority = @(
        '1:UI textures and material semantics',
        '2:PCM effects and MPEG music',
        '3:ZIF navigation graph',
        '4:UI behavior and licensed fonts'
    )
    routes = [pscustomobject][ordered]@{
        zif = 'bounded XML plus companion path binding to a versioned navigation graph'
        audio = 'validated WAV import and reviewed offline MP3 decode to lossless intermediate'
        ui = 'reuse Package/QTX; reconstruct native UE layout and behavior from evidence'
        shader = 'decode QPhongShader semantics into reviewed UE material masters and instances'
    }
    zif = [pscustomobject][ordered]@{
        file_count = $zifFiles.Count
        total_bytes = $zifBytes
        utf8_bom_count = $utf8BomCount
        parse_failure_count = $zifFailures.Count
        directories = Get-OrderedCounts -Counts $zifDirectoryCounts
        records = $zifTotals
    }
    audio = [pscustomobject][ordered]@{
        wav = [pscustomobject][ordered]@{
            file_count = $wavFiles.Count
            total_bytes = $wavBytes
            data_bytes = $wavDataBytes
            format_key = 'codec|channels|sample_rate|bits_per_sample'
            formats = Get-OrderedCounts -Counts $wavFormats
            chunk_presence = Get-OrderedCounts -Counts $wavChunks
        }
        mp3 = [pscustomobject][ordered]@{
            file_count = $mp3Files.Count
            total_bytes = $mp3Bytes
            headers = Get-OrderedCounts -Counts $mp3Headers
            decoded_or_transcoded = $false
        }
    }
    package_inventory = $packageInventory
    loose_shader_source_count = $looseShaderFiles.Count
    standalone_ui_definition_count = $standaloneUiFiles.Count
    fonts = [pscustomobject][ordered]@{
        file_count = $fontFiles.Count
        total_bytes = [int64]($fontFiles | Measure-Object Length -Sum).Sum
        imported = $false
        rights_review_required = $true
    }
    evidence = $evidenceReport
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        installed_packages_mount = 'read-only'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_and_output_storage = 'ephemeral_tmpfs'
    }
    stages = @('document-route-contract', 'legacy-evidence-hash', 'full-zif-xml-validation',
        'full-wav-riff-validation', 'full-mp3-prefix-classification',
        'loose-ui-shader-font-inventory', 'isolated-ui-material-package-classification')
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        output_line_count = @($execution.output -split "`n").Count
        output_sha256 = Get-TextSha256 -Value $execution.output
    }
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath), $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
