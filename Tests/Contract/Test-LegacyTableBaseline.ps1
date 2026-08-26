[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientSourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [string]$DevDocRoot = 'E:\QQXYCodeDev\DevDoc',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-03-legacy-table.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$clientSource = [System.IO.Path]::GetFullPath($ClientSourceRoot).TrimEnd([char[]]'\/')
$devDoc = [System.IO.Path]::GetFullPath($DevDocRoot).TrimEnd([char[]]'\/')
$moduleRoot = Join-Path $root 'Tools\TMXY.Table'

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Resolve-ContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|/)\.\.(/|$)') {
        throw "Evidence path must be portable and relative: $RelativePath"
    }
    $candidate = [System.IO.Path]::GetFullPath(
        (Join-Path $BasePath $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
    $prefix = $BasePath + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Evidence path escapes its read-only root: $RelativePath"
    }
    return $candidate
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

$requiredFiles = @(
    'Tools/CMakeLists.txt',
    'Tools/CMakePresets.json',
    'Tools/cmake/TMXYToolOptions.cmake',
    'Tools/TMXY.Table/CMakeLists.txt',
    'Tools/TMXY.Table/README.md',
    'Tools/TMXY.Table/include/tmxy/table/legacy_table.hpp',
    'Tools/TMXY.Table/include/tmxy/table/legacy_table_reader.hpp',
    'Tools/TMXY.Table/src/aes128_decryptor.hpp',
    'Tools/TMXY.Table/src/aes128_decryptor.cpp',
    'Tools/TMXY.Table/src/legacy_table.cpp',
    'Tools/TMXY.Table/src/legacy_table_reader.cpp',
    'Tools/TMXY.Table/tests/CMakeLists.txt',
    'Tools/TMXY.Table/tests/legacy_table_reader_test.cpp'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "P1-03 required file is missing: $relativePath"
    }
}

$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.cpp', '.hpp') } | Sort-Object FullName)
$forbiddenPattern = '(?i)(#\s*include\s*[<"](?:windows\.h|d3d|afx)|ClientCode|ServerCode|ToolCode)'
foreach ($file in $sourceFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -match $forbiddenPattern) {
        throw "P1-03 forbidden legacy/platform dependency found: $($file.FullName)"
    }
}
$hashLines = foreach ($relativePath in $requiredFiles | Sort-Object) {
    $fileHash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($fileHash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")

$legacySources = @(
    [pscustomobject]@{ path = 'Base/Hdr/IEncryption.h'; size = 1976; sha256 = 'eefbc0267c5c38fd19ebe8b115c02eb7d6b9189d3dbd5657737007f3ba5a28ab' },
    [pscustomobject]@{ path = 'Base/Hdr/QDataTable.h'; size = 1522; sha256 = '4499c0e6c7cc53644d34d0d6a4ec4975e8c4f9e2826d7d2a2dd04d3926b97a8b' },
    [pscustomobject]@{ path = 'Base/Hdr/QParser.h'; size = 1642; sha256 = 'cbe9f9c3ef3f9d2f11bee6db1aa7f2b312d733c204cf3d587577067f77939f8d' },
    [pscustomobject]@{ path = 'Base/Hdr/Rijndael_Imp.h'; size = 1571; sha256 = '6cfe1f9dc4aa59146c4b3517b23de9ca728fa85447205902cec3d30f8387cd89' },
    [pscustomobject]@{ path = 'Base/Src/QDataTable.cpp'; size = 7068; sha256 = '3df15f58bf45de80aa7a8040a1f522f135e7b09487990b40b04805c78937b869' },
    [pscustomobject]@{ path = 'Base/Src/QParser.cpp'; size = 5865; sha256 = 'bab39ccce47907e06dbac0913c2edf2b43350a7efae867cb8b9c61fb56880314' },
    [pscustomobject]@{ path = 'Base/Src/Rijndael_Imp.cpp'; size = 16356; sha256 = 'a7b24ab28dbb08aced67fbea1c239866aa4cdd7e47bc67f8371b7909252087bf' }
)
foreach ($evidence in $legacySources) {
    $evidencePath = Resolve-ContainedPath -BasePath $clientSource -RelativePath ([string]$evidence.path)
    $item = Get-Item -LiteralPath $evidencePath -ErrorAction Stop
    $sha = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne [int64]$evidence.size -or $sha -ne [string]$evidence.sha256) {
        throw "P1-03 legacy source evidence changed: $($evidence.path)"
    }
}

$samplePair = @(
    [pscustomobject]@{ role = 'ciphertext'; path = '游戏资料/CLSVShare/Suit_table.tbl'; size = 4688; sha256 = '1185964f3e0d47aadb82c9c6aae35157cf581a98335babe1b13f685f3fef13b3' },
    [pscustomobject]@{ role = 'expected_plaintext'; path = '游戏资料/CLSVShare/Suit_table.csv'; size = 4686; sha256 = '4d43925eb834bea6d9710fa0112d599b8c96fbe29314612b461b5cdf44a169f2' }
)
foreach ($sample in $samplePair) {
    $samplePath = Resolve-ContainedPath -BasePath $devDoc -RelativePath ([string]$sample.path)
    $item = Get-Item -LiteralPath $samplePath -ErrorAction Stop
    $sha = (Get-FileHash -LiteralPath $samplePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne [int64]$sample.size -or $sha -ne [string]$sample.sha256) {
        throw "P1-03 frozen legacy table sample changed: $($sample.path)"
    }
}
$cipherPath = Resolve-ContainedPath -BasePath $devDoc -RelativePath ([string]$samplePair[0].path)
$csvPath = Resolve-ContainedPath -BasePath $devDoc -RelativePath ([string]$samplePair[1].path)
$keySourcePath = Resolve-ContainedPath -BasePath $clientSource -RelativePath 'Base/Src/QDataTable.cpp'

$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$builderReference = [string]$lock.backend_toolchain.container_image_reference
$expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
$imageRecords = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
$imagePresent = $LASTEXITCODE -eq 0 -and $imageRecords.Count -gt 0
$actualBuilderId = if ($imagePresent) { [string]$imageRecords[0].Id } else { '' }
$builderUser = if ($imagePresent) { [string]$imageRecords[0].Config.User } else { '' }
if (-not $imagePresent -or $actualBuilderId -ne $expectedBuilderId -or $builderUser -ne 'tmxy') {
    throw 'P1-03 requires the qualified non-root Clang 21 builder image.'
}

$containerScript = @'
set -euo pipefail
mkdir -p /tmp/tmxy-rebuild/Tools
cp /workspace/.clang-format /tmp/tmxy-rebuild/
cp /workspace/.clang-tidy /tmp/tmxy-rebuild/
cp /workspace/Tools/CMakeLists.txt /tmp/tmxy-rebuild/Tools/
cp /workspace/Tools/CMakePresets.json /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/cmake /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.FormatCore /tmp/tmxy-rebuild/Tools/
cp -a /workspace/Tools/TMXY.Table /tmp/tmxy-rebuild/Tools/
cd /tmp/tmxy-rebuild/Tools
find TMXY.FormatCore TMXY.Table -type f \( -name '*.cpp' -o -name '*.hpp' \) -print0 | xargs -0 clang-format-21 --dry-run --Werror --style=file
cmake --preset ci-linux-clang -DTMXY_BUILD_PACKAGE=OFF -DTMXY_BUILD_TRANSFORM=OFF -DTMXY_BUILD_TEXTURE=OFF -DTMXY_BUILD_STATIC_MESH=OFF -DTMXY_BUILD_SKELETAL_MESH=OFF -DTMXY_BUILD_ANIMATION=OFF -DTMXY_BUILD_TERRAIN=OFF
cmake --build --preset ci-linux-clang
find TMXY.FormatCore TMXY.Table -type f -name '*.cpp' -print0 | xargs -0 clang-tidy-21 -p out/build/ci-linux-clang --quiet
ctest --preset ci-linux-clang
cleanup_key() {
    if [ -f /tmp/legacy-table-key.bin ]; then
        python3 - <<'PY'
import pathlib
key_file = pathlib.Path('/tmp/legacy-table-key.bin')
key_file.write_bytes(bytes(16))
key_file.unlink()
PY
    fi
}
trap cleanup_key EXIT
python3 - <<'PY'
import pathlib
import re
source = pathlib.Path('/legacy/QDataTable.cpp').read_bytes()
matches = re.findall(rb'key_buff\s*\[\s*KEY_SIZE\s*\]\s*=\s*\{([^}]*)\}', source)
if len(matches) != 2:
    raise SystemExit('legacy key evidence shape mismatch')
values = []
for match in matches:
    tokens = [token.strip() for token in match.split(b',') if token.strip()]
    if len(tokens) != 16 or any(not token.isdigit() for token in tokens):
        raise SystemExit('legacy key evidence token shape mismatch')
    values.append(bytes(int(token) for token in tokens))
if values[0] != values[1]:
    raise SystemExit('legacy key evidence copies differ')
pathlib.Path('/tmp/legacy-table-key.bin').write_bytes(values[0])
PY
./out/build/ci-linux-clang/TMXY.Table/tests/tmxy_legacy_table_reader_test /legacy/Suit_table.tbl /legacy/Suit_table.csv /tmp/legacy-table-key.bin
'@
$docker = (Get-Command docker -ErrorAction Stop).Source
$arguments = @(
    'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true', '--tmpfs', '/tmp:rw,exec,nosuid,size=512m',
    '--mount', "type=bind,source=$root,target=/workspace,readonly",
    '--mount', "type=bind,source=$cipherPath,target=/legacy/Suit_table.tbl,readonly",
    '--mount', "type=bind,source=$csvPath,target=/legacy/Suit_table.csv,readonly",
    '--mount', "type=bind,source=$keySourcePath,target=/legacy/QDataTable.cpp,readonly",
    $builderReference, 'bash', '-c', $containerScript
)
$execution = Invoke-NativeProcess -FilePath $docker -Arguments $arguments -WorkingDirectory $root
$sampleLine = @($execution.output -split "`n" |
    Where-Object { $_ -match '^\{"sample_result":"PASS"' } | Select-Object -Last 1)
$sampleResult = if ($sampleLine.Count -eq 1) { $sampleLine[0] | ConvertFrom-Json } else { $null }
$passed = $execution.exit_code -eq 0 -and $execution.output -match '100% tests passed' -and
    $null -ne $sampleResult -and [int]$sampleResult.cipher_bytes -eq 4688 -and
    [int]$sampleResult.payload_bytes -eq 4686 -and [int]$sampleResult.padding_bytes -eq 1 -and
    [int]$sampleResult.column_count -eq 10 -and [int]$sampleResult.row_count -eq 57 -and
    [string]$sampleResult.metadata_fnv1a64 -eq 'c60c5d8848a6a32a'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-03'
    source_file_count = $sourceFiles.Count
    source_sha256 = $sourceSha
    error_schema_version = 1
    legacy_format_evidence = $legacySources
    frozen_sample_pair = [pscustomobject][ordered]@{
        files = $samplePair
        cipher_bytes = if ($null -ne $sampleResult) { [int]$sampleResult.cipher_bytes } else { 0 }
        payload_bytes = if ($null -ne $sampleResult) { [int]$sampleResult.payload_bytes } else { 0 }
        padding_bytes = if ($null -ne $sampleResult) { [int]$sampleResult.padding_bytes } else { 0 }
        column_count = if ($null -ne $sampleResult) { [int]$sampleResult.column_count } else { 0 }
        row_count = if ($null -ne $sampleResult) { [int]$sampleResult.row_count } else { 0 }
        metadata_fnv1a64 = if ($null -ne $sampleResult) { [string]$sampleResult.metadata_fnv1a64 } else { '' }
        payload_matches_expected_sha256 = $passed
    }
    key_handling = [pscustomobject][ordered]@{
        embedded_in_rebuild = $false
        input = 'read-only legacy evidence initializer'
        initializer_copy_count = 2
        key_bytes = 16
        transport = 'ephemeral tmpfs file inside networkless container'
        cleanup = 'overwrite-with-zero-then-unlink-and-container-rm'
        emitted_to_output = $false
    }
    cipher_properties = [pscustomobject][ordered]@{
        block_bytes = 16
        aes_rounds_per_block = 2
        authentication = 'none-legacy-format-requires-external-sha256'
    }
    builder = [pscustomobject][ordered]@{
        reference = $builderReference
        expected_id = $expectedBuilderId
        actual_id = $actualBuilderId
        user = $builderUser
    }
    isolation = [pscustomobject][ordered]@{
        source_mount = 'read-only'
        legacy_mounts = 'three-read-only-single-files'
        network = 'none'
        root_filesystem = 'read-only'
        capabilities = 'none'
        no_new_privileges = $true
        build_and_secret_storage = 'ephemeral_tmpfs'
    }
    stages = @('legacy-evidence-sha256', 'fixed-nonsecret-vectors', 'clang-format-21',
        'cmake-clang-21', 'clang-tidy-21', 'ctest', 'legacy-pair-exact-match')
    execution = [pscustomobject][ordered]@{
        exit_code = $execution.exit_code
        output_line_count = @($execution.output -split "`n").Count
        output_sha256 = Get-TextSha256 -Value $execution.output
    }
}
$json = ($report | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath), $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw "P1-03 locked-builder validation failed: $($execution.output)" }
