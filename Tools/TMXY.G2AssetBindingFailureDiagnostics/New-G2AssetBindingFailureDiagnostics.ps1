[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyClientRoot = 'E:\QQXYCodeDev\天命西游',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$legacyRoot = [IO.Path]::GetFullPath($LegacyClientRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A7'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.7 temporary root escaped Rebuild.'
}
$runRoot = Join-Path $localRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length + 1)).Replace('\', '/')
}

function New-FileBinding([string]$ActualPath, [string]$AdvertisedPath, [bool]$Tracked) {
    return [pscustomobject][ordered]@{
        path = $AdvertisedPath
        tracked = $Tracked
        bytes = [int64](Get-Item -LiteralPath $ActualPath).Length
        lines = Get-LineCount $ActualPath
        sha256 = Get-Sha256 $ActualPath
    }
}

function Copy-Output([string]$Source, [string]$Target) {
    $directory = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
}

try {
    foreach ($directory in @($root, $legacyRoot)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Required directory is missing: $directory"
        }
    }
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2AssetBindingFailureDiagnostics'
    $generatorPath = Join-Path $moduleRoot 'g2_asset_binding_failure_diagnostics.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-failure-diagnostics-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-failure-diagnostics-v1.schema.json'
    $detailSchemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-binding-failure-detail-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generatorPath, $policyPath, $schemaPath, $detailSchemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20A.7 input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.7 requires the qualified non-root Clang 21 builder image.'
    }

    $names = [ordered]@{
        assetTsv = 'assets.tsv'
        candidateTsv = 'candidates.tsv'
        probe = 'probe.jsonl'
        probeStderr = 'probe.stderr.txt'
        detail = 'p2-20a-asset-binding-failure-diagnostics.jsonl'
        json = 'p2-20a-asset-binding-failure-diagnostics-report.json'
        markdown = 'p2-20a-asset-binding-failure-diagnostics-report.md'
        evidence = 'p2-20a-asset-binding-failure-diagnostics.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $names.Keys) { $generated[$name] = Join-Path $runRoot $names[$name] }
    $targets = [ordered]@{
        detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-binding-failure-diagnostics.jsonl'
        json = Join-Path $root 'Data\Reports\p2-20a-asset-binding-failure-diagnostics-report.json'
        markdown = Join-Path $root 'Data\Reports\p2-20a-asset-binding-failure-diagnostics-report.md'
        evidence = Join-Path $root 'Data\Inventory\p2-20a-asset-binding-failure-diagnostics.json'
    }
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $baseIsolation = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m',
        $builderReference
    )

    $prepareArguments = $baseIsolation + @(
        'python3', '/workspace/Tools/TMXY.G2AssetBindingFailureDiagnostics/g2_asset_binding_failure_diagnostics.py',
        'prepare', '--root', '/workspace', '--asset-tsv', "/output/$($names.assetTsv)",
        '--candidate-tsv', "/output/$($names.candidateTsv)"
    )
    $prepareText = & $docker @prepareArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.7 deterministic preparation failed.' }
    $prepare = $prepareText | ConvertFrom-Json -Depth 100
    if ($prepare.result -ne 'PASS' -or [int]$prepare.targets -ne 19 -or
        [int]$prepare.candidate_edges -ne 24 -or [int]$prepare.unique_candidates -ne 24) {
        throw 'P2-20A.7 preparation scope drifted.'
    }

    $configureArguments = $baseIsolation + @(
        'cmake', '-S', '/workspace/Tools/TMXY.G2AssetBindingFailureDiagnostics',
        '-B', '/output/build', '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
        '-DTMXY_WARNINGS_AS_ERRORS=ON'
    )
    & $docker @configureArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.7 probe configuration failed.' }
    $buildArguments = $baseIsolation + @(
        'cmake', '--build', '/output/build', '--target',
        'tmxy_g2_asset_binding_failure_probe', '--parallel', '2'
    )
    & $docker @buildArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.7 probe build failed.' }

    $probeArguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$legacyRoot,dst=/legacy/client,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m',
        $builderReference, '/output/build/tmxy_g2_asset_binding_failure_probe',
        '/legacy/client', "/output/$($names.assetTsv)", "/output/$($names.candidateTsv)"
    )
    & $docker @probeArguments 2> $generated.probeStderr |
        Out-File -LiteralPath $generated.probe -Encoding utf8 -NoNewline:$false
    if ($LASTEXITCODE -ne 0) {
        $anonymousError = (Get-Content -LiteralPath $generated.probeStderr -Raw -Encoding UTF8).Trim()
        throw "P2-20A.7 anonymous probe failed: $anonymousError"
    }
    if ((Get-LineCount $generated.probe) -ne 19) { throw 'P2-20A.7 probe count drifted.' }

    $capturedArguments = @()
    if ($Check) {
        if (-not (Test-Path -LiteralPath $targets.json -PathType Leaf)) {
            throw 'P2-20A.7 tracked report is absent in check mode.'
        }
        $existing = Get-Content -LiteralPath $targets.json -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        $capturedArguments = @('--captured-utc', [string]$existing.captured_utc)
    }
    $finalizeArguments = $baseIsolation + @(
        'python3', '/workspace/Tools/TMXY.G2AssetBindingFailureDiagnostics/g2_asset_binding_failure_diagnostics.py',
        'finalize', '--root', '/workspace', '--probe-jsonl', "/output/$($names.probe)",
        '--detail-output', "/output/$($names.detail)", '--json-output', "/output/$($names.json)",
        '--markdown-output', "/output/$($names.markdown)"
    ) + $capturedArguments
    $summaryText = & $docker @finalizeArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.7 deterministic finalization failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfArguments = $baseIsolation + @(
        'python3', '/workspace/Tools/TMXY.G2AssetBindingFailureDiagnostics/g2_asset_binding_failure_diagnostics.py',
        '--self-test'
    )
    $selfText = & $docker @selfArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.7 generator self-test failed.' }
    $self = $selfText | ConvertFrom-Json
    if ($summary.result -ne 'PASS_DIAGNOSTIC' -or $summary.task_status -ne 'BLOCKED' -or
        [int]$summary.targets -ne 19 -or [int]$summary.candidate_edges -ne 24 -or
        [int]$summary.typed_error_edges -ne 24 -or [int]$summary.unclassified_error_edges -ne 0 -or
        [int]$summary.effective_unresolved_targets -ne 19 -or
        [int]$summary.candidate_selections -ne 0 -or $summary.g2_06_satisfied -ne $false -or
        $summary.p3_authorized -ne $false -or $self.result -ne 'PASS' -or
        [int]$self.assertions -lt 10) {
        throw 'P2-20A.7 fail-closed summary or self-test drifted.'
    }
    if (-not (Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)) {
        throw 'P2-20A.7 report failed its closed JSON Schema.'
    }
    foreach ($line in [IO.File]::ReadLines($generated.detail)) {
        if (-not ($line | Test-Json -SchemaFile $detailSchemaPath)) {
            throw 'P2-20A.7 detail failed its closed JSON Schema.'
        }
    }

    $report = Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $sourceFiles = @(
        Join-Path $moduleRoot 'CMakeLists.txt'
        Join-Path $moduleRoot 'g2_asset_binding_failure_diagnostics.py'
        Join-Path $moduleRoot 'New-G2AssetBindingFailureDiagnostics.ps1'
        Join-Path $moduleRoot 'README.md'
        Join-Path $moduleRoot 'apps\failure_probe_main.cpp'
        Join-Path $moduleRoot 'apps\probe_support.cpp'
        Join-Path $moduleRoot 'apps\probe_support.hpp'
        Join-Path $root 'Tools\TMXY.G2AssetDescriptorDiagnostics\sha256.cpp'
        Join-Path $root 'Tools\TMXY.G2AssetDescriptorDiagnostics\sha256.hpp'
        Join-Path $root 'Tools\TMXY.Texture\src\legacy_texture_descriptor_reader.cpp'
        Join-Path $root 'Tools\TMXY.Texture\src\qtx_reader.cpp'
        Join-Path $root 'Tools\TMXY.Texture\src\texture_error.cpp'
        Join-Path $root 'Tools\TMXY.StaticMesh\src\package_static_mesh_reader.cpp'
        Join-Path $root 'Tools\TMXY.StaticMesh\src\sm_reader.cpp'
        Join-Path $root 'Tools\TMXY.StaticMesh\src\static_mesh_error.cpp'
        Join-Path $root 'Tools\TMXY.Animation\src\package_animation_reader.cpp'
        Join-Path $root 'Tools\TMXY.Animation\src\anim_reader.cpp'
        Join-Path $root 'Tools\TMXY.Animation\src\animation_error.cpp'
    )
    foreach ($source in $sourceFiles) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "P2-20A.7 implementation source is missing: $source"
        }
    }
    $sourceBindings = @($sourceFiles | ForEach-Object {
        New-FileBinding $_ (Get-Relative $_) $true
    })
    $sourceAggregateText = ($sourceBindings | ForEach-Object {
        "$($_.path)`t$($_.bytes)`t$($_.lines)`t$($_.sha256)`n"
    }) -join ''
    $sourceAggregate = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($sourceAggregateText))).ToLowerInvariant()
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_revision = 'P2-20A.7'
        captured_utc = [string]$report.captured_utc
        task_id = 'P2-20A'
        criterion_id = 'G2-06'
        result = 'BLOCKED'
        review_execution_result = 'PASS'
        task_status = 'BLOCKED'
        completion_criteria_satisfied = $false
        diagnostic_scope_complete = $true
        remediation_scope_complete = $false
        g2_06_satisfied = $false
        p3_authorized = $false
        measured = $report.measured
        outputs = [pscustomobject][ordered]@{
            detail_export = New-FileBinding $generated.detail 'Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl' $false
            report_json = New-FileBinding $generated.json 'Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json' $true
            report_markdown = New-FileBinding $generated.markdown 'Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.md' $true
        }
        implementation = [pscustomobject][ordered]@{
            files = $sourceBindings
            aggregate_sha256 = $sourceAggregate
            generator_self_test_assertions = [int]$self.assertions
            probe_startup_self_tests = $true
        }
        builder = [pscustomobject][ordered]@{
            image_reference = $builderReference
            image_id = $expectedBuilderId
            user = 'tmxy'
        }
        isolation = [pscustomobject][ordered]@{
            network = 'none'
            read_only_container = $true
            cap_drop = 'ALL'
            no_new_privileges = $true
            repository_mount = 'read-only'
            legacy_client_mount = 'read-only'
        }
        authority_boundary = $report.authority_boundary
        preserved_blockers = $report.preserved_blockers
        disclosure = $report.disclosure
    }
    $evidenceJson = ($evidence | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($generated.evidence, $evidenceJson + "`n", [Text.UTF8Encoding]::new($false))

    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "P2-20A.7 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    [pscustomobject][ordered]@{
        result = 'PASS_DIAGNOSTIC'
        task_status = 'BLOCKED'
        targets = 19
        candidate_edges = 24
        typed_error_edges = 24
        unclassified_error_edges = 0
        effective_unresolved_targets = 19
        effective_unresolved_edges = 24
        candidate_selections = 0
        automatic_resolutions = 0
        owner_dispositions = 0
        g2_06_satisfied = $false
        p3_authorized = $false
        report_sha256 = Get-Sha256 $targets.json
        detail_sha256 = Get-Sha256 $targets.detail
        evidence_sha256 = Get-Sha256 $targets.evidence
    } | ConvertTo-Json -Depth 10
}
finally {
    $resolvedRunRoot = [IO.Path]::GetFullPath($runRoot)
    if ($resolvedRunRoot.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedRunRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRunRoot -Recurse -Force
    }
}
