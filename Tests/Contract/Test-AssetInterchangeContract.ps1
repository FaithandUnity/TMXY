[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-19-asset-interchange.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)
    return ($Value | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json
}

function Test-AgainstSchema {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )
    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    return [bool](Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)
}

$requiredFiles = @(
    'Contracts/data-schema/asset-interchange-v1.schema.json',
    'Contracts/interchange/format-registry-v1.json',
    'Contracts/examples/asset-interchange-v1.example.json',
    'Docs/Formats/ASSET-INTERCHANGE-V1.md',
    'Docs/ADR/ADR-015-versioned-asset-interchange.md',
    'Tests/Contract/Test-AssetInterchangeContract.ps1',
    'Contracts/data-schema/package-tree-v1.schema.json',
    'Tools/TMXY.Package/src/package_normalized_tree.cpp',
    'Tools/TMXY.Texture/src/texture_export.cpp',
    'Tools/TMXY.StaticMesh/src/static_mesh_export.cpp',
    'Tools/TMXY.SkeletalMesh/src/skeletal_mesh_export.cpp',
    'Tools/TMXY.Animation/src/animation_export.cpp',
    'Tools/TMXY.Terrain/src/terrain_export.cpp'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure -Message "P1-19 required file is missing: $relativePath"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$schemaPath = Join-Path $root $requiredFiles[0]
$registryPath = Join-Path $root $requiredFiles[1]
$examplePath = Join-Path $root $requiredFiles[2]
$schemaText = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
$registryText = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8
$exampleText = Get-Content -LiteralPath $examplePath -Raw -Encoding UTF8
$schema = $schemaText | ConvertFrom-Json
$registry = $registryText | ConvertFrom-Json
$example = $exampleText | ConvertFrom-Json

if (-not (Test-Json -Json $schemaText -ErrorAction SilentlyContinue)) {
    Add-Failure -Message 'P1-19 JSON Schema is not valid JSON.'
}
if (-not (Test-AgainstSchema -Value $example -SchemaPath $schemaPath)) {
    Add-Failure -Message 'P1-19 positive example does not validate against the schema.'
}
$schemaPassed = [string]$schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    [string]$schema.properties.schema.const -eq 'tmxy.asset.interchange' -and
    [int]$schema.properties.schema_version.const -eq 1 -and
    [string]$schema.properties.format_version.const -eq '1.0.0' -and
    -not [bool]$schema.additionalProperties -and
    $null -ne $schema.properties.unknown_fields -and
    $null -ne $schema.properties.extensions
if (-not $schemaPassed) {
    Add-Failure -Message 'P1-19 manifest schema identity or preservation boundary changed.'
}

$negativeCases = [ordered]@{}
$absolutePath = Copy-JsonObject -Value $example
$absolutePath.source_inputs[0].relative_path = 'E:\unsafe\source.sm'
$negativeCases.absolute_path = -not (Test-AgainstSchema -Value $absolutePath -SchemaPath $schemaPath)
$rootExtra = Copy-JsonObject -Value $example
$rootExtra | Add-Member -NotePropertyName guessed_semantics -NotePropertyValue $true
$negativeCases.unscoped_root_property = -not (Test-AgainstSchema -Value $rootExtra -SchemaPath $schemaPath)
$lostUnknown = Copy-JsonObject -Value $example
$lostUnknown.unknown_fields[0].PSObject.Properties.Remove('source_span')
$negativeCases.unknown_without_backing = -not (Test-AgainstSchema -Value $lostUnknown -SchemaPath $schemaPath)
$unscopedExtension = Copy-JsonObject -Value $example
$unscopedExtension.extensions = [pscustomobject]@{ plain = [pscustomobject]@{ value = 1 } }
$negativeCases.unscoped_extension = -not (Test-AgainstSchema -Value $unscopedExtension -SchemaPath $schemaPath)
foreach ($case in $negativeCases.GetEnumerator()) {
    if (-not $case.Value) { Add-Failure -Message "P1-19 negative schema case was accepted: $($case.Key)" }
}

if ([string]$registry.schema -ne 'tmxy.asset.interchange.registry' -or
    [int]$registry.schema_version -ne 1 -or [string]$registry.registry_version -ne '1.0.0' -or
    [string]$registry.manifest_schema -ne $requiredFiles[0]) {
    Add-Failure -Message 'P1-19 registry identity changed.'
}
$formats = @($registry.formats)
$formatIds = @($formats | ForEach-Object { [string]$_.format_id })
$duplicateFormatIds = @($formatIds | Group-Object | Where-Object Count -gt 1)
$requiredFormatIds = @(
    'tmxy.package.tree-json',
    'tmxy.asset.metadata-json',
    'microsoft.dds',
    'khronos.gltf-json',
    'khronos.gltf-bin',
    'tmxy.terrain.height-f32le',
    'tmxy.terrain.layers-rgba8',
    'riff.wave.pcm',
    'tmxy.navigation.graph-json',
    'wavefront.obj',
    'w3c.png',
    'truevision.tga',
    'rfc4180.csv'
)
if ($formats.Count -ne 13 -or $duplicateFormatIds.Count -ne 0 -or
    (Compare-Object ($requiredFormatIds | Sort-Object) ($formatIds | Sort-Object))) {
    Add-Failure -Message 'P1-19 format registry entries changed or are not unique.'
}
$semverPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
foreach ($format in $formats) {
    if ([string]$format.format_version -notmatch $semverPattern) {
        Add-Failure -Message "P1-19 registry version is not semantic: $($format.format_id)"
    }
    foreach ($extension in @($format.extensions)) {
        if ([string]$extension -notmatch '^\.[a-z0-9.]+$') {
            Add-Failure -Message "P1-19 invalid registered extension: $extension"
        }
    }
    $specification = [string]$format.specification
    if ($specification -notmatch '^https://' -and
        -not (Test-Path -LiteralPath (Join-Path $root $specification) -PathType Leaf)) {
        Add-Failure -Message "P1-19 local specification is missing: $specification"
    }
}

$authorityExpectations = [ordered]@{
    'tmxy.package.tree-json' = $true
    'microsoft.dds' = $true
    'khronos.gltf-json' = $true
    'khronos.gltf-bin' = $true
    'tmxy.terrain.height-f32le' = $true
    'tmxy.terrain.layers-rgba8' = $true
    'wavefront.obj' = $false
    'w3c.png' = $false
    'truevision.tga' = $false
    'rfc4180.csv' = $false
}
foreach ($entry in $authorityExpectations.GetEnumerator()) {
    $format = @($formats | Where-Object format_id -eq $entry.Key)
    if ($format.Count -ne 1 -or [bool]$format[0].import_authority -ne $entry.Value) {
        Add-Failure -Message "P1-19 import authority changed: $($entry.Key)"
    }
}
$authoritativeCount = @($formats | Where-Object import_authority).Count
$reviewOnlyCount = @($formats | Where-Object { -not [bool]$_.import_authority }).Count
if ($authoritativeCount -ne 9 -or $reviewOnlyCount -ne 4) {
    Add-Failure -Message 'P1-19 authoritative/review registry boundary changed.'
}

$versionPolicy = $registry.version_policy
if ([string]$versionPolicy.major -ne 'reject-unknown-major' -or
    [string]$versionPolicy.minor -ne 'accept-only-when-all-required-features-are-supported' -or
    -not [bool]$versionPolicy.published_registry_entries_are_immutable -or
    -not [bool]$versionPolicy.unknown_extensions_must_survive_read_write) {
    Add-Failure -Message 'P1-19 compatibility policy changed.'
}
$bundleRules = $registry.bundle_rules
if ([string]$bundleRules.manifest_name -ne 'manifest.json' -or
    -not [bool]$bundleRules.paths_are_relative -or
    -not [bool]$bundleRules.absolute_paths_forbidden -or
    -not [bool]$bundleRules.parent_segments_forbidden -or
    [bool]$bundleRules.timestamps_in_manifest -or
    [string]$bundleRules.text_encoding -ne 'utf-8-without-bom' -or
    [string]$bundleRules.text_line_endings -ne 'lf') {
    Add-Failure -Message 'P1-19 deterministic bundle rules changed.'
}

$sourceIds = @($example.source_inputs | ForEach-Object { [string]$_.id })
$artifactIds = @($example.artifacts | ForEach-Object { [string]$_.id })
if (@($sourceIds | Group-Object | Where-Object Count -gt 1).Count -ne 0 -or
    @($artifactIds | Group-Object | Where-Object Count -gt 1).Count -ne 0) {
    Add-Failure -Message 'P1-19 example contains duplicate source or artifact IDs.'
}
foreach ($artifact in @($example.artifacts)) {
    if ([string]$artifact.format_id -notin $formatIds) {
        Add-Failure -Message "P1-19 example uses an unregistered format: $($artifact.format_id)"
    }
    foreach ($dependency in @($artifact.depends_on)) {
        if ([string]$dependency -notin $artifactIds) {
            Add-Failure -Message "P1-19 example has a missing artifact dependency: $dependency"
        }
    }
}
foreach ($unknown in @($example.unknown_fields)) {
    if ([string]$unknown.preservation -eq 'source-span' -and
        [string]$unknown.source_span.source_input_id -notin $sourceIds) {
        Add-Failure -Message 'P1-19 unknown source span references a missing source input.'
    }
    if ([string]$unknown.preservation -eq 'opaque-sidecar' -and
        [string]$unknown.artifact_id -notin $artifactIds) {
        Add-Failure -Message 'P1-19 opaque unknown references a missing artifact.'
    }
    if ([string]$unknown.preservation -eq 'namespaced-extension' -and
        $null -eq $example.extensions.PSObject.Properties[[string]$unknown.extension_key]) {
        Add-Failure -Message 'P1-19 unknown extension reference is not preserved in extensions.'
    }
}

$dependencyReports = @(
    'p1-08-package-normalized-tree.json',
    'p1-13-qtx-texture.json',
    'p1-14-sm-static-mesh.json',
    'p1-15-skem-skeletal-mesh.json',
    'p1-16-anim-animation.json',
    'p1-17-ter-terrain.json',
    'p1-18-auxiliary-assets.json'
)
$dependencyHashes = [ordered]@{}
foreach ($name in $dependencyReports) {
    $path = Join-Path $root "Data\BuildBaseline\$name"
    $report = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$report.result -ne 'PASS') {
        Add-Failure -Message "P1-19 dependency is not passing: $name"
    }
    if ($name -ne 'p1-08-package-normalized-tree.json' -and
        -not [bool]$report.completion_criteria_satisfied) {
        Add-Failure -Message "P1-19 dependency is not complete: $name"
    }
    $dependencyHashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$exporterMarkers = [ordered]@{
    'Tools/TMXY.Package/src/package_normalized_tree.cpp' = @('tmxy.package.tree', 'source-span')
    'Tools/TMXY.Texture/src/texture_export.cpp' = @('schema_version', 'names.dds_name', 'names.png_name', 'names.tga_name')
    'Tools/TMXY.StaticMesh/src/static_mesh_export.cpp' = @('schema_version', 'TMXY static mesh OBJ preview')
    'Tools/TMXY.SkeletalMesh/src/skeletal_mesh_export.cpp' = @('schema_version', 'OBJ review artifact')
    'Tools/TMXY.Animation/src/animation_export.cpp' = @('schema_version', 'root_motion')
    'Tools/TMXY.Terrain/src/terrain_export.cpp' = @('schema_version', 'float32 little-endian source units', 'four uint8 source alpha channels')
}
$exporterHashes = [ordered]@{}
foreach ($relativePath in $exporterMarkers.Keys) {
    $path = Join-Path $root $relativePath
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach ($marker in $exporterMarkers[$relativePath]) {
        if (-not $content.Contains($marker, [System.StringComparison]::Ordinal)) {
            Add-Failure -Message "P1-19 exporter marker is missing: $relativePath -> $marker"
        }
    }
    $exporterHashes[$relativePath] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$document = Get-Content -LiteralPath (Join-Path $root $requiredFiles[3]) -Raw -Encoding UTF8
$documentMarkers = @('## Deterministic bundle rules', '## Format ownership',
    '## JSON, BIN, glTF, and DDS boundaries', '## Unknown fields and extensions',
    '## Version compatibility', '## Importer obligations')
foreach ($marker in $documentMarkers) {
    if (-not $document.Contains($marker, [System.StringComparison]::Ordinal)) {
        Add-Failure -Message "P1-19 document marker is missing: $marker"
    }
}

$hashFiles = @($requiredFiles[0..5])
$hashLines = foreach ($relativePath in $hashFiles | Sort-Object) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $root $relativePath) -Algorithm SHA256).Hash
    "$relativePath|$($hash.ToLowerInvariant())"
}
$sourceSha = Get-TextSha256 -Value (($hashLines -join "`n") + "`n")
$passed = $failures.Count -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P1-19'
    completion_criteria_satisfied = $passed
    interchange_version = '1.0.0'
    source_sha256 = $sourceSha
    schema = [pscustomobject][ordered]@{
        path = $requiredFiles[0]
        sha256 = (Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
        draft = [string]$schema.'$schema'
        positive_example_passed = Test-AgainstSchema -Value $example -SchemaPath $schemaPath
        negative_case_count = $negativeCases.Count
        negative_cases = $negativeCases
    }
    registry = [pscustomobject][ordered]@{
        path = $requiredFiles[1]
        sha256 = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash.ToLowerInvariant()
        format_count = $formats.Count
        authoritative_format_count = $authoritativeCount
        review_only_format_count = $reviewOnlyCount
        format_ids = $formatIds
    }
    boundary = [pscustomobject][ordered]@{
        container = 'versioned manifest plus separately hashed standard payloads'
        texture_authority = 'DDS complete validated mip chain'
        mesh_skeleton_animation_authority = 'glTF 2.0 JSON plus external BIN and metadata JSON'
        terrain_authority = 'f32le height plus rgba8 layer planes and metadata JSON'
        review_only = @('OBJ', 'PNG', 'TGA', 'CSV')
        unknown_preservation = @('source-span', 'opaque-sidecar', 'namespaced-extension')
        path_policy = 'relative forward-slash paths only; absolute and parent paths rejected'
        timestamps = 'forbidden from deterministic manifest'
    }
    version_policy = $versionPolicy
    dependency_report_sha256 = $dependencyHashes
    exporter_source_sha256 = $exporterHashes
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath), $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'P1-19 asset interchange contract failed.' }
