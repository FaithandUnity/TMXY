[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$LegacyClientSourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [string]$LegacyToolSourceRoot = 'E:\QQXYCodeDev\ToolCode',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$legacyRoot = [IO.Path]::GetFullPath($LegacyClientRoot).TrimEnd([char[]]'\/')
$clientSourceRoot = [IO.Path]::GetFullPath($LegacyClientSourceRoot).TrimEnd([char[]]'\/')
$toolSourceRoot = [IO.Path]::GetFullPath($LegacyToolSourceRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A12'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.12 temporary root escaped Rebuild.'
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

function Copy-Output([string]$Source, [string]$Target) {
    $directory = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
}

try {
    foreach ($directory in @($root, $legacyRoot, $clientSourceRoot, $toolSourceRoot)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Required P2-20A.12 directory is missing: $directory"
        }
    }
    $module = Join-Path $root 'Tools\TMXY.G2StaticMeshPayloadSectionPrefix'
    $generator = Join-Path $module 'g2_static_mesh_payload_section_prefix.py'
    $a7Generator = Join-Path $root `
        'Tools\TMXY.G2AssetBindingFailureDiagnostics\g2_asset_binding_failure_diagnostics.py'
    $policyPath = Join-Path $root `
        'Contracts\data-schema\g2-static-mesh-payload-section-prefix-policy-v1.json'
    $schemaPath = Join-Path $root `
        'Contracts\data-schema\g2-static-mesh-payload-section-prefix-v1.schema.json'
    $detailSchemaPath = Join-Path $root `
        'Contracts\data-schema\g2-static-mesh-payload-section-prefix-detail-v1.schema.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generator, $a7Generator, $policyPath, $schemaPath,
            $detailSchemaPath, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20A.12 input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.12 requires the qualified non-root Clang 21 builder image.'
    }

    $names = [ordered]@{
        a7Assets = 'a7-assets.tsv'
        a7Candidates = 'a7-candidates.tsv'
        assets = 'sm-assets.tsv'
        candidates = 'sm-candidates.tsv'
        probe = 'probe.jsonl'
        probeStderr = 'probe.stderr.txt'
        detail = 'p2-20a-static-mesh-payload-section-prefix.jsonl'
        json = 'p2-20a-static-mesh-payload-section-prefix-report.json'
        markdown = 'p2-20a-static-mesh-payload-section-prefix-report.md'
        evidence = 'p2-20a-static-mesh-payload-section-prefix.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $names.Keys) { $generated[$name] = Join-Path $runRoot $names[$name] }
    $targets = [ordered]@{
        detail = Join-Path $root `
            'Data\Exports\P2-20\p2-20a-static-mesh-payload-section-prefix.jsonl'
        json = Join-Path $root `
            'Data\Reports\p2-20a-static-mesh-payload-section-prefix-report.json'
        markdown = Join-Path $root `
            'Data\Reports\p2-20a-static-mesh-payload-section-prefix-report.md'
        evidence = Join-Path $root `
            'Data\Inventory\p2-20a-static-mesh-payload-section-prefix.json'
    }
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $baseIsolation = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m', $builderReference
    )

    $a7Prepare = $baseIsolation + @(
        'python3',
        '/workspace/Tools/TMXY.G2AssetBindingFailureDiagnostics/g2_asset_binding_failure_diagnostics.py',
        'prepare', '--root', '/workspace', '--asset-tsv', "/output/$($names.a7Assets)",
        '--candidate-tsv', "/output/$($names.a7Candidates)"
    )
    $a7Text = & $docker @a7Prepare
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.12 A.7 scope preparation failed.' }
    $a7 = $a7Text | ConvertFrom-Json -Depth 20
    if ($a7.result -ne 'PASS' -or [int]$a7.targets -ne 19 -or
        [int]$a7.candidate_edges -ne 24) {
        throw 'P2-20A.12 A.7 scope drifted before selection.'
    }

    $prepareArguments = $baseIsolation + @(
        'python3',
        '/workspace/Tools/TMXY.G2StaticMeshPayloadSectionPrefix/g2_static_mesh_payload_section_prefix.py',
        'prepare', '--root', '/workspace', '--a7-asset-tsv', "/output/$($names.a7Assets)",
        '--a7-candidate-tsv', "/output/$($names.a7Candidates)",
        '--asset-tsv', "/output/$($names.assets)",
        '--candidate-tsv', "/output/$($names.candidates)"
    )
    $prepareText = & $docker @prepareArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.12 deterministic scope selection failed.' }
    $prepare = $prepareText | ConvertFrom-Json -Depth 20
    if ($prepare.result -ne 'PASS' -or [int]$prepare.targets -ne 1 -or
        [int]$prepare.candidate_edges -ne 2 -or [int]$prepare.unique_candidates -ne 2 -or
        $prepare.family -ne 'sm') {
        throw 'P2-20A.12 frozen SM scope drifted.'
    }

    $configureArguments = $baseIsolation + @(
        'cmake', '-S', '/workspace/Tools/TMXY.G2StaticMeshPayloadSectionPrefix',
        '-B', '/output/build', '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
        '-DTMXY_WARNINGS_AS_ERRORS=ON'
    )
    & $docker @configureArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.12 probe configuration failed.' }
    $buildArguments = $baseIsolation + @(
        'cmake', '--build', '/output/build', '--target',
        'tmxy_g2_static_mesh_prefix_probe', '--parallel', '2'
    )
    & $docker @buildArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.12 probe build failed.' }

    $probeArguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$legacyRoot,dst=/legacy/client,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=16m', $builderReference,
        '/output/build/tmxy_g2_static_mesh_prefix_probe', '/legacy/client',
        "/output/$($names.assets)", "/output/$($names.candidates)"
    )
    & $docker @probeArguments 2> $generated.probeStderr |
        Out-File -LiteralPath $generated.probe -Encoding utf8 -NoNewline:$false
    if ($LASTEXITCODE -ne 0) {
        $anonymousError = (Get-Content -LiteralPath $generated.probeStderr -Raw -Encoding UTF8).Trim()
        throw "P2-20A.12 anonymous probe failed: $anonymousError"
    }
    if ((Get-LineCount $generated.probe) -ne 1) {
        throw 'P2-20A.12 probe target count drifted.'
    }

    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100
    $expectedByHash = @{}
    foreach ($item in @($policy.legacy_source_roles)) {
        $expectedByHash[[string]$item.sha256] = [string]$item.role
    }
    $resolvedByRole = @{}
    foreach ($sourceRoot in @($clientSourceRoot, $toolSourceRoot)) {
        foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.cpp') {
            $digest = Get-Sha256 $file.FullName
            if ($expectedByHash.ContainsKey($digest)) {
                $role = $expectedByHash[$digest]
                if ($resolvedByRole.ContainsKey($role)) {
                    throw "P2-20A.12 legacy role hash is not unique: $role"
                }
                $resolvedByRole[$role] = $file.FullName
            }
        }
    }
    if ($resolvedByRole.Count -ne @($policy.legacy_source_roles).Count) {
        throw 'P2-20A.12 did not resolve every hash-locked legacy source role.'
    }
    $legacyMounts = @()
    $legacyArguments = @()
    foreach ($role in @($resolvedByRole.Keys | Sort-Object)) {
        $containerPath = "/legacy-$role.cpp"
        $legacyMounts += @('--mount',
            "type=bind,src=$($resolvedByRole[$role]),dst=$containerPath,readonly")
        $legacyArguments += @('--legacy-source', "$role=$containerPath")
    }

    $capturedArguments = @()
    if ($Check) {
        if (-not (Test-Path -LiteralPath $targets.json -PathType Leaf)) {
            throw 'P2-20A.12 tracked report is absent in check mode.'
        }
        $existing = Get-Content -LiteralPath $targets.json -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        $capturedArguments = @('--captured-utc', [string]$existing.captured_utc)
    }
    $finalIsolation = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output"
    ) + $legacyMounts + @('--tmpfs', '/tmp:rw,nosuid,nodev,size=32m', $builderReference)
    $finalizeArguments = $finalIsolation + @(
        'python3',
        '/workspace/Tools/TMXY.G2StaticMeshPayloadSectionPrefix/g2_static_mesh_payload_section_prefix.py',
        'finalize', '--root', '/workspace', '--probe-jsonl', "/output/$($names.probe)",
        '--detail-output', "/output/$($names.detail)", '--json-output', "/output/$($names.json)",
        '--markdown-output', "/output/$($names.markdown)",
        '--evidence-output', "/output/$($names.evidence)",
        '--builder-reference', $builderReference, '--builder-id', $expectedBuilderId
    ) + $legacyArguments + $capturedArguments
    $summaryText = & $docker @finalizeArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.12 deterministic finalization failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfArguments = $baseIsolation + @(
        'python3',
        '/workspace/Tools/TMXY.G2StaticMeshPayloadSectionPrefix/g2_static_mesh_payload_section_prefix.py',
        '--self-test'
    )
    $selfText = & $docker @selfArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.12 generator self-test failed.' }
    $self = $selfText | ConvertFrom-Json
    if ($summary.result -ne 'PASS_DIAGNOSTIC' -or $summary.task_status -ne 'BLOCKED' -or
        [int]$summary.targets -ne 1 -or [int]$summary.candidate_edges -ne 2 -or
        [int]$summary.strict_rejected_edges -ne 2 -or [int]$summary.prefix_pass_edges -ne 2 -or
        [int]$summary.body_variants -ne 1 -or [int]$summary.descriptor_semantic_variants -ne 1 -or
        [int]$summary.strict_semantic_variants -ne 1 -or [int]$summary.prefix_semantic_variants -ne 1 -or
        [int]$summary.candidate_selections -ne 0 -or [int]$summary.automatic_resolutions -ne 0 -or
        $summary.g2_06_satisfied -ne $false -or $summary.p3_authorized -ne $false -or
        $self.result -ne 'PASS' -or [int]$self.assertions -ne 20) {
        throw 'P2-20A.12 fail-closed summary or self-test drifted.'
    }
    if (-not (Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)) {
        throw 'P2-20A.12 report failed its closed JSON Schema.'
    }
    foreach ($line in [IO.File]::ReadLines($generated.detail)) {
        if (-not ($line | Test-Json -SchemaFile $detailSchemaPath)) {
            throw 'P2-20A.12 detail failed its closed JSON Schema.'
        }
    }

    foreach ($name in $targets.Keys) {
        if ($Check) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -cne (Get-Sha256 $generated[$name])) {
                throw "P2-20A.12 output differs from deterministic regeneration: $name"
            }
        }
        else { Copy-Output $generated[$name] $targets[$name] }
    }
    [pscustomobject][ordered]@{
        result = 'PASS_DIAGNOSTIC'
        task_status = 'BLOCKED'
        targets = 1
        candidate_edges = 2
        strict_rejected_edges = 2
        prefix_pass_edges = 2
        body_variants = 1
        descriptor_semantic_variants = 1
        strict_semantic_variants = 1
        prefix_semantic_variants = 1
        candidate_selections = 0
        automatic_resolutions = 0
        authority_state_changed = $false
        adapter_applied = $false
        recovery_applied = $false
        source_basis = 'SOURCE_DERIVED'
        legacy_binary_executed = $false
        runtime_parity_proven = $false
        g2_06_satisfied = $false
        p3_authorized = $false
        report_sha256 = Get-Sha256 $targets.json
        detail_sha256 = Get-Sha256 $targets.detail
        evidence_sha256 = Get-Sha256 $targets.evidence
    } | ConvertTo-Json -Depth 20
}
finally {
    $resolvedRunRoot = [IO.Path]::GetFullPath($runRoot)
    if ($resolvedRunRoot.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedRunRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRunRoot -Recurse -Force
    }
}
