[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$LegacyClientRoot = 'E:\QQXYCodeDev\天命西游',
    [string]$LegacyClientSourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [ValidateSet('Prepare', 'Finalize')]
    [string]$Mode = 'Finalize',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$legacyRoot = [IO.Path]::GetFullPath($LegacyClientRoot).TrimEnd([char[]]'\/')
$sourceRoot = [IO.Path]::GetFullPath($LegacyClientSourceRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20A13'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.13 temporary root escaped Rebuild.'
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
    foreach ($directory in @($root)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Required P2-20A.13 directory is missing: $directory"
        }
    }
    if ($Mode -eq 'Finalize') {
        foreach ($directory in @($legacyRoot, $sourceRoot)) {
            if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
                throw "Required P2-20A.13 directory is missing: $directory"
            }
        }
    }
    $module = Join-Path $root 'Tools\TMXY.G2QtxDeclaredMipPayloadPrefix'
    $generator = Join-Path $module 'g2_qtx_declared_mip_payload_prefix.py'
    $policyPath = Join-Path $root `
        'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-policy-v1.json'
    $schemaPath = Join-Path $root `
        'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-v1.schema.json'
    $detailSchemaPath = Join-Path $root `
        'Contracts\data-schema\g2-qtx-declared-mip-payload-prefix-detail-v1.schema.json'
    $basePlanContractPath = Join-Path $root `
        'Contracts\data-schema\g2-asset-binding-recovery-base-plan-v1.tsv'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    $requiredFiles = @($generator, $policyPath, $basePlanContractPath, $lockPath)
    if ($Mode -eq 'Finalize') { $requiredFiles += @($schemaPath, $detailSchemaPath) }
    foreach ($required in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20A.13 input: $required"
        }
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.13 requires the qualified non-root Clang 21 builder image.'
    }

    $names = [ordered]@{
        assets = 'qtx-assets.tsv'
        candidates = 'qtx-candidates.tsv'
        probe = 'probe.jsonl'
        probeStderr = 'probe.stderr.txt'
        detail = 'p2-20a-qtx-declared-mip-payload-prefix.jsonl'
        plan = 'p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
        json = 'p2-20a-qtx-declared-mip-payload-prefix-report.json'
        markdown = 'p2-20a-qtx-declared-mip-payload-prefix-report.md'
        evidence = 'p2-20a-qtx-declared-mip-payload-prefix.json'
    }
    $generated = [ordered]@{}
    foreach ($name in $names.Keys) { $generated[$name] = Join-Path $runRoot $names[$name] }
    $targets = [ordered]@{
        detail = Join-Path $root `
            'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix.jsonl'
        plan = Join-Path $root `
            'Data\Exports\P2-20\p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv'
        json = Join-Path $root `
            'Data\Reports\p2-20a-qtx-declared-mip-payload-prefix-report.json'
        markdown = Join-Path $root `
            'Data\Reports\p2-20a-qtx-declared-mip-payload-prefix-report.md'
        evidence = Join-Path $root `
            'Data\Inventory\p2-20a-qtx-declared-mip-payload-prefix.json'
    }
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $baseIsolation = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m', $builderReference
    )

    $prepareArguments = $baseIsolation + @(
        'python3',
        '/workspace/Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/g2_qtx_declared_mip_payload_prefix.py',
        'prepare', '--root', '/workspace', '--asset-tsv', "/output/$($names.assets)",
        '--candidate-tsv', "/output/$($names.candidates)",
        '--effective-plan-output', "/output/$($names.plan)"
    )
    $prepareText = & $docker @prepareArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.13 deterministic scope preparation failed.' }
    $prepare = $prepareText | ConvertFrom-Json -Depth 20
    if ($prepare.result -ne 'PASS' -or [int]$prepare.targets -ne 6 -or
        [int]$prepare.candidate_edges -ne 6 -or [int]$prepare.unique_candidates -ne 6 -or
        [int]$prepare.excluded_targets -ne 4 -or [int]$prepare.excluded_edges -ne 6 -or
        [int]$prepare.effective_plan_rows -ne 21 -or
        [int]$prepare.effective_plan_changed_rows -ne 6 -or $prepare.family -ne 'qtx') {
        throw 'P2-20A.13 frozen QTX scope or effective plan drifted.'
    }
    if ($Mode -eq 'Prepare') {
        if ($Check) {
            if (-not (Test-Path -LiteralPath $targets.plan -PathType Leaf) -or
                (Get-Sha256 $targets.plan) -cne (Get-Sha256 $generated.plan)) {
                throw 'P2-20A.13 effective plan differs from deterministic regeneration.'
            }
        }
        else { Copy-Output $generated.plan $targets.plan }
        [pscustomobject][ordered]@{
            result = 'PASS'
            meaning = 'ACYCLIC_EFFECTIVE_PLAN_ONLY'
            targets = 6
            candidate_edges = 6
            effective_plan_rows = 21
            effective_plan_changed_rows = 6
            effective_plan_unchanged_rows = 15
            effective_plan_sha256 = Get-Sha256 $targets.plan
        } | ConvertTo-Json -Depth 20
        return
    }
    if (-not (Test-Path -LiteralPath $targets.plan -PathType Leaf)) {
        throw 'Run P2-20A.13 Prepare before Finalize.'
    }
    if ((Get-Sha256 $targets.plan) -cne (Get-Sha256 $generated.plan)) {
        throw 'Published P2-20A.13 effective plan differs from acyclic regeneration.'
    }

    $configureArguments = $baseIsolation + @(
        'cmake', '-S', '/workspace/Tools/TMXY.G2QtxDeclaredMipPayloadPrefix',
        '-B', '/output/build', '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
        '-DTMXY_WARNINGS_AS_ERRORS=ON'
    )
    & $docker @configureArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.13 probe configuration failed.' }
    $buildArguments = $baseIsolation + @(
        'cmake', '--build', '/output/build', '--target',
        'tmxy_g2_qtx_declared_mip_prefix_probe', '--parallel', '2'
    )
    & $docker @buildArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.13 probe build failed.' }

    $probeArguments = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$legacyRoot,dst=/legacy/client,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=16m', $builderReference,
        '/output/build/tmxy_g2_qtx_declared_mip_prefix_probe', '/legacy/client',
        "/output/$($names.assets)", "/output/$($names.candidates)"
    )
    & $docker @probeArguments 2> $generated.probeStderr |
        Out-File -LiteralPath $generated.probe -Encoding utf8 -NoNewline:$false
    if ($LASTEXITCODE -ne 0) {
        $anonymousError = (Get-Content -LiteralPath $generated.probeStderr -Raw -Encoding UTF8).Trim()
        throw "P2-20A.13 anonymous probe failed: $anonymousError"
    }
    if ((Get-LineCount $generated.probe) -ne 6) {
        throw 'P2-20A.13 probe target count drifted.'
    }

    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100
    $expectedByHash = @{}
    foreach ($item in @($policy.legacy_source_roles)) {
        $expectedByHash[[string]$item.sha256] = [string]$item.role
    }
    $resolvedByRole = @{}
    foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.cpp') {
        $digest = Get-Sha256 $file.FullName
        if ($expectedByHash.ContainsKey($digest)) {
            $role = $expectedByHash[$digest]
            if ($resolvedByRole.ContainsKey($role)) {
                throw "P2-20A.13 legacy role hash is not unique: $role"
            }
            $resolvedByRole[$role] = $file.FullName
        }
    }
    if ($resolvedByRole.Count -ne @($policy.legacy_source_roles).Count) {
        throw 'P2-20A.13 did not resolve every hash-locked legacy source role.'
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
            throw 'P2-20A.13 tracked report is absent in check mode.'
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
        '/workspace/Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/g2_qtx_declared_mip_payload_prefix.py',
        'finalize', '--root', '/workspace', '--probe-jsonl', "/output/$($names.probe)",
        '--detail-output', "/output/$($names.detail)",
        '--effective-plan', '/workspace/Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv',
        '--json-output', "/output/$($names.json)",
        '--markdown-output', "/output/$($names.markdown)",
        '--evidence-output', "/output/$($names.evidence)",
        '--builder-reference', $builderReference, '--builder-id', $expectedBuilderId
    ) + $legacyArguments + $capturedArguments
    $summaryText = & $docker @finalizeArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.13 deterministic finalization failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfArguments = $baseIsolation + @(
        'python3',
        '/workspace/Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/g2_qtx_declared_mip_payload_prefix.py',
        '--self-test'
    )
    $selfText = & $docker @selfArguments
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.13 generator self-test failed.' }
    $self = $selfText | ConvertFrom-Json
    if ($summary.result -ne 'PASS_DIAGNOSTIC' -or $summary.task_status -ne 'BLOCKED' -or
        [int]$summary.targets -ne 6 -or [int]$summary.candidate_edges -ne 6 -or
        [int]$summary.strict_rejected_edges -ne 6 -or [int]$summary.prefix_pass_edges -ne 6 -or
        [int]$summary.effective_plan_rows -ne 21 -or
        [int]$summary.effective_plan_changed_rows -ne 6 -or
        $summary.upstream_effective_phase -ne 'POST_APPLICATION' -or
        [int]$summary.candidate_selections -ne 0 -or [int]$summary.automatic_resolutions -ne 0 -or
        $summary.authority_state_changed -ne $false -or $summary.g2_06_satisfied -ne $false -or
        $summary.p3_authorized -ne $false -or $self.result -ne 'PASS' -or
        [int]$self.assertions -ne 23) {
        throw 'P2-20A.13 fail-closed summary or self-test drifted.'
    }
    if (-not (Get-Content -LiteralPath $generated.json -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)) {
        throw 'P2-20A.13 report failed its closed JSON Schema.'
    }
    foreach ($line in [IO.File]::ReadLines($generated.detail)) {
        if (-not ($line | Test-Json -SchemaFile $detailSchemaPath)) {
            throw 'P2-20A.13 detail failed its closed JSON Schema.'
        }
    }

    foreach ($name in @('detail', 'json', 'markdown', 'evidence')) {
        if ($Check) {
            if (-not (Test-Path -LiteralPath $targets[$name] -PathType Leaf) -or
                (Get-Sha256 $targets[$name]) -cne (Get-Sha256 $generated[$name])) {
                throw "P2-20A.13 output differs from deterministic regeneration: $name"
            }
        }
        else { Copy-Output $generated[$name] $targets[$name] }
    }
    [pscustomobject][ordered]@{
        result = 'PASS_DIAGNOSTIC'
        task_status = 'BLOCKED'
        targets = 6
        candidate_edges = 6
        strict_rejected_edges = 6
        explicit_prefix_pass_edges = 6
        dds_prefix_only_edges = 6
        effective_plan_rows = 21
        effective_plan_changed_rows = 6
        upstream_effective_phase = [string]$summary.upstream_effective_phase
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
        effective_plan_sha256 = Get-Sha256 $targets.plan
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
