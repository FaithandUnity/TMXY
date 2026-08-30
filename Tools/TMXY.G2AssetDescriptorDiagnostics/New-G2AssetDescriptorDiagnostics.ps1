[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$RecoveryPlanPath = '',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$legacyRoot = [IO.Path]::GetFullPath($LegacyClientRoot).TrimEnd([char[]]'\/')
if ([string]::IsNullOrWhiteSpace($RecoveryPlanPath)) {
    $RecoveryPlanPath = Join-Path $root `
        'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
}
$recoveryPlan = [IO.Path]::GetFullPath($RecoveryPlanPath)
if (-not $recoveryPlan.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.4 recovery plan escaped Rebuild.'
}
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A4'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.4 temporary root escaped Rebuild.'
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

function Copy-Output([string]$Source, [string]$Target) {
    $directory = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
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

try {
    foreach ($requiredDirectory in @($root, $legacyRoot)) {
        if (-not (Test-Path -LiteralPath $requiredDirectory -PathType Container)) {
            throw "Required directory is missing: $requiredDirectory"
        }
    }
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2AssetDescriptorDiagnostics'
    $generatorPath = Join-Path $moduleRoot 'g2_asset_descriptor_diagnostics.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-asset-descriptor-diagnostics-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-descriptor-diagnostics-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generatorPath, $policyPath, $schemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20A.4 input: $required"
        }
    }
    if (-not (Test-Path -LiteralPath $recoveryPlan -PathType Leaf)) {
        throw 'P2-20A.4 requires the A.13 effective recovery plan.'
    }
    $recoveryPlanRelative = Get-Relative $recoveryPlan
    $recoveryPlanContainer = '/workspace/' + $recoveryPlanRelative

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.4 requires the qualified non-root Clang 21 builder image.'
    }

    $names = [ordered]@{
        assetTsv = 'assets.tsv'
        candidateTsv = 'candidates.tsv'
        probe = 'probe.jsonl'
        probeStderr = 'probe.stderr.txt'
        detail = 'p2-20a-asset-descriptor-diagnostics.jsonl'
        json = 'p2-20a-asset-descriptor-diagnostics-report.json'
        markdown = 'p2-20a-asset-descriptor-diagnostics-report.md'
        evidence = 'p2-20a-asset-descriptor-diagnostics.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $names.Keys) { $generated[$name] = Join-Path $runRoot $names[$name] }
    $targets = [ordered]@{
        detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-asset-descriptor-diagnostics.jsonl'
        json = Join-Path $root 'Data\Reports\p2-20a-asset-descriptor-diagnostics-report.json'
        markdown = Join-Path $root 'Data\Reports\p2-20a-asset-descriptor-diagnostics-report.md'
        evidence = Join-Path $root 'Data\Inventory\p2-20a-asset-descriptor-diagnostics.json'
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
        'python3', '/workspace/Tools/TMXY.G2AssetDescriptorDiagnostics/g2_asset_descriptor_diagnostics.py',
        'prepare', '--root', '/workspace', '--asset-tsv', "/output/$($names.assetTsv)",
        '--candidate-tsv', "/output/$($names.candidateTsv)"
    )
    $prepareText = & $docker @prepareArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.4 deterministic preparation failed.' }
    $prepare = $prepareText | ConvertFrom-Json -Depth 100
    if ($prepare.result -ne 'PASS' -or [int]$prepare.targets -ne 3651 -or
        [int]$prepare.candidate_edges -ne 12764 -or
        [int]$prepare.candidate_objects -ne 46865) {
        throw 'P2-20A.4 preparation scope drifted.'
    }

    $configureArguments = $baseIsolation + @(
        'cmake', '-S', '/workspace/Tools', '-B', '/output/build', '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', '-DTMXY_WARNINGS_AS_ERRORS=ON',
        '-DTMXY_BUILD_ASSET_INVENTORY=OFF',
        '-DTMXY_BUILD_G2_ASSET_DESCRIPTOR_DIAGNOSTICS=ON'
    )
    & $docker @configureArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.4 probe configuration failed.' }
    $buildArguments = $baseIsolation + @(
        'cmake', '--build', '/output/build', '--target', 'tmxy_g2_asset_descriptor_probe',
        '--parallel', '2'
    )
    & $docker @buildArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.4 probe build failed.' }

    $probeArguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$legacyRoot,dst=/legacy/client,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m',
        $builderReference,
        '/output/build/TMXY.G2AssetDescriptorDiagnostics/tmxy_g2_asset_descriptor_probe',
        '/legacy/client', "/output/$($names.assetTsv)", "/output/$($names.candidateTsv)",
        $recoveryPlanContainer
    )
    & $docker @probeArguments 2> $generated.probeStderr |
        Out-File -LiteralPath $generated.probe -Encoding utf8 -NoNewline:$false
    if ($LASTEXITCODE -ne 0) {
        $anonymousError = (Get-Content -LiteralPath $generated.probeStderr -Raw -Encoding UTF8).Trim()
        throw "P2-20A.4 anonymous probe failed: $anonymousError"
    }
    if ((Get-LineCount $generated.probe) -ne 3651) {
        throw 'P2-20A.4 probe target count drifted.'
    }

    $capturedArguments = @()
    if ($Check) {
        if (-not (Test-Path -LiteralPath $targets.json -PathType Leaf)) {
            throw 'P2-20A.4 tracked report is absent in check mode.'
        }
        $existing = Get-Content -LiteralPath $targets.json -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        $capturedArguments = @('--captured-utc', [string]$existing.captured_utc)
    }
    $finalizeArguments = $baseIsolation + @(
        'python3', '/workspace/Tools/TMXY.G2AssetDescriptorDiagnostics/g2_asset_descriptor_diagnostics.py',
        'finalize', '--root', '/workspace', '--probe-jsonl', "/output/$($names.probe)",
        '--recovery-plan', $recoveryPlanContainer,
        '--detail-output', "/output/$($names.detail)", '--json-output', "/output/$($names.json)",
        '--markdown-output', "/output/$($names.markdown)"
    ) + $capturedArguments
    $summaryText = & $docker @finalizeArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.4 deterministic finalization failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfArguments = $baseIsolation + @(
        'python3', '/workspace/Tools/TMXY.G2AssetDescriptorDiagnostics/g2_asset_descriptor_diagnostics.py',
        '--self-test'
    )
    $selfText = & $docker @selfArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.4 generator self-test failed.' }
    $selfTest = $selfText | ConvertFrom-Json
    if ($summary.result -ne 'BLOCKED' -or $summary.review_execution_result -ne 'PASS' -or
        [int]$summary.targets -ne 3651 -or [int]$summary.candidate_edges -ne 12764 -or
        $selfTest.result -ne 'PASS' -or [int]$selfTest.assertions -lt 6) {
        throw 'P2-20A.4 summary or self-test failed.'
    }
    if (-not (Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)) {
        throw 'P2-20A.4 report failed its closed JSON Schema.'
    }

    $report = Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $sourceFiles = @(
        Join-Path $moduleRoot 'CMakeLists.txt'
        Join-Path $moduleRoot 'diagnostic_common.py'
        Join-Path $moduleRoot 'diagnostic_classification.py'
        Join-Path $moduleRoot 'diagnostic_self_test.py'
        Join-Path $moduleRoot 'g2_asset_descriptor_diagnostics.py'
        Join-Path $moduleRoot 'semantic_hash.cpp'
        Join-Path $moduleRoot 'semantic_hash.hpp'
        Join-Path $moduleRoot 'sha256.cpp'
        Join-Path $moduleRoot 'sha256.hpp'
        Join-Path $moduleRoot 'apps\asset_descriptor_probe_main.cpp'
        Join-Path $moduleRoot 'apps\probe_output.cpp'
        Join-Path $moduleRoot 'apps\probe_output.hpp'
        Join-Path $moduleRoot 'apps\probe_types.hpp'
        Join-Path $moduleRoot 'apps\qtx_recovery.cpp'
        Join-Path $moduleRoot 'apps\qtx_recovery.hpp'
        Join-Path $moduleRoot 'apps\recovery_plan.cpp'
        Join-Path $moduleRoot 'apps\recovery_plan.hpp'
        Join-Path $root 'Tools\TMXY.Texture\include\tmxy\texture\legacy_texture_descriptor_reader.hpp'
        Join-Path $root 'Tools\TMXY.Texture\include\tmxy\texture\qtx_reader.hpp'
        Join-Path $root 'Tools\TMXY.Texture\include\tmxy\texture\texture_error.hpp'
        Join-Path $root 'Tools\TMXY.Texture\include\tmxy\texture\texture_result.hpp'
        Join-Path $root 'Tools\TMXY.Texture\include\tmxy\texture\texture_types.hpp'
        Join-Path $root 'Tools\TMXY.Texture\src\block_compression.cpp'
        Join-Path $root 'Tools\TMXY.Texture\src\dds_writer.cpp'
        Join-Path $root 'Tools\TMXY.Texture\src\legacy_texture_descriptor_reader.cpp'
        Join-Path $root 'Tools\TMXY.Texture\src\qtx_reader.cpp'
        Join-Path $root 'Tools\TMXY.Texture\src\texture_decode.cpp'
        Join-Path $root 'Tools\TMXY.Texture\src\texture_decode_internal.hpp'
        Join-Path $root 'Tools\TMXY.Texture\src\texture_error.cpp'
        Join-Path $root 'Tools\TMXY.Animation\include\tmxy\animation\anim_reader.hpp'
        Join-Path $root 'Tools\TMXY.Animation\include\tmxy\animation\animation_types.hpp'
        Join-Path $root 'Tools\TMXY.Animation\include\tmxy\animation\package_animation_reader.hpp'
        Join-Path $root 'Tools\TMXY.Animation\src\anim_reader.cpp'
        Join-Path $root 'Tools\TMXY.Animation\src\package_animation_reader.cpp'
        Join-Path $root 'Tools\TMXY.AssetInventory\apps\descriptor_semantic_signature.cpp'
        Join-Path $root 'Tools\TMXY.AssetInventory\apps\descriptor_semantic_signature.hpp'
    )
    $sourceBindings = @($sourceFiles | ForEach-Object {
        New-FileBinding $_ (Get-Relative $_) $true
    })
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_revision = 'P2-20A.4'
        captured_utc = [string]$report.captured_utc
        task_id = 'P2-20A'
        criterion_id = 'G2-06'
        result = 'BLOCKED'
        review_execution_result = 'PASS'
        task_status = 'BLOCKED'
        completion_criteria_satisfied = $false
        diagnostic_scope_complete = $true
        g2_06_satisfied = $false
        p3_authorized = $false
        measured = $report.measured
        outputs = [pscustomobject][ordered]@{
            detail_export = New-FileBinding $generated.detail 'Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl' $false
            report_json = New-FileBinding $generated.json 'Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json' $true
            report_markdown = New-FileBinding $generated.markdown 'Data/Reports/p2-20a-asset-descriptor-diagnostics-report.md' $true
        }
        implementation = [pscustomobject][ordered]@{
            files = $sourceBindings
            generator_self_test_assertions = [int]$selfTest.assertions
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
            legacy_client_mount = 'read-only'
        }
        disclosure = $report.disclosure
    }
    $evidenceJson = ($evidence | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText(
        $generated.evidence, $evidenceJson + "`n", [Text.UTF8Encoding]::new($false))

    if ($Check) {
        foreach ($name in $targets.Keys) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "P2-20A.4 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $targets.Keys) { Copy-Output $generated[$name] $targets[$name] }
    }

    [pscustomobject][ordered]@{
        result = 'PASS_DIAGNOSTIC'
        task_status = 'BLOCKED'
        targets = [int]$summary.targets
        candidate_edges = [int]$summary.candidate_edges
        resolved = [int]$summary.resolved
        ambiguous = [int]$summary.ambiguous
        unresolved = [int]$summary.unresolved
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
