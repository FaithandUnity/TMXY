[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$localRoot = [IO.Path]::GetFullPath((Join-Path $root 'Data\Local\P2-20'))
if (-not $localRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2-20A.6 temporary root escaped Rebuild.'
}
$runRoot = Join-Path $localRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length + 1)).Replace('\', '/')
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Get-TextSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function New-FileBinding([string]$Path, [bool]$Tracked) {
    return [pscustomobject][ordered]@{
        path = Get-Relative $Path
        tracked = $Tracked
        bytes = [int64](Get-Item -LiteralPath $Path).Length
        lines = Get-LineCount $Path
        sha256 = Get-Sha256 $Path
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
    $moduleRoot = Join-Path $root 'Tools\TMXY.G2AssetIdentityNormalization'
    $generatorPath = Join-Path $moduleRoot 'identity_normalization.py'
    $policyPath = Join-Path $root 'Contracts\data-schema\g2-asset-identity-normalization-policy-v1.json'
    $schemaPath = Join-Path $root 'Contracts\data-schema\g2-asset-identity-normalization-v1.schema.json'
    $a4Path = Join-Path $root 'Data\Reports\p2-20a-asset-descriptor-diagnostics-report.json'
    $lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    foreach ($required in @($generatorPath, $policyPath, $schemaPath, $a4Path, $lockPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing P2-20A.6 input: $required"
        }
    }

    $a4 = Get-Content -LiteralPath $a4Path -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    if ($a4.evidence_revision -ne 'P2-20A.4' -or
        [string]$a4.captured_utc -notmatch '^\d{4}-\d{2}-\d{2}T') {
        throw 'P2-20A.6 requires the frozen P2-20A.4 capture identity.'
    }
    $capturedUtc = [string]$a4.captured_utc
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builderReference = [string]$lock.backend_toolchain.container_image_reference
    $expectedBuilderId = [string]$lock.backend_toolchain.container_image_digest
    $image = @(docker image inspect $builderReference 2>$null | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $image.Count -ne 1 -or
        [string]$image[0].Id -ne $expectedBuilderId -or
        [string]$image[0].Config.User -ne 'tmxy') {
        throw 'P2-20A.6 requires the qualified non-root Clang 21 builder image.'
    }

    $detailName = 'p2-20a-asset-identity-normalization.jsonl'
    $reportName = 'p2-20a-asset-identity-normalization-report.json'
    $markdownName = 'p2-20a-asset-identity-normalization-report.md'
    $generatedDetail = Join-Path $runRoot $detailName
    $generatedReport = Join-Path $runRoot $reportName
    $generatedMarkdown = Join-Path $runRoot $markdownName
    $trackedDetail = Join-Path $root "Data\Exports\P2-20\$detailName"
    $trackedReport = Join-Path $root "Data\Reports\$reportName"
    $trackedMarkdown = Join-Path $root "Data\Reports\$markdownName"
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $isolation = @(
        'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges',
        '--mount', "type=bind,src=$root,dst=/workspace,readonly",
        '--mount', "type=bind,src=$runRoot,dst=/output",
        '--tmpfs', '/tmp:rw,nosuid,nodev,size=64m',
        $builderReference
    )
    $summaryText = & $docker @($isolation + @(
            'python3', '/workspace/Tools/TMXY.G2AssetIdentityNormalization/identity_normalization.py',
            '--root', '/workspace', '--detail-output', "/output/$detailName",
            '--json-output', "/output/$reportName", '--markdown-output', "/output/$markdownName",
            '--captured-utc', $capturedUtc))
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.6 deterministic generation failed.' }
    $summary = $summaryText | ConvertFrom-Json -Depth 100
    $selfText = & $docker @($isolation + @(
            'python3', '/workspace/Tools/TMXY.G2AssetIdentityNormalization/identity_normalization.py',
            '--self-test'))
    if ($LASTEXITCODE -ne 0) { throw 'P2-20A.6 generator self-test failed.' }
    $self = $selfText | ConvertFrom-Json
    if (-not (Get-Content -LiteralPath $generatedReport -Raw -Encoding UTF8 |
            Test-Json -SchemaFile $schemaPath)) {
        throw 'P2-20A.6 report failed its closed JSON Schema.'
    }
    if ($summary.result -ne 'PASS_DIAGNOSTIC' -or $summary.task_status -ne 'BLOCKED' -or
        [int]$summary.case_fold_collision_targets -ne 13 -or
        [int]$summary.strict_semantic_equivalent_targets -ne 0 -or
        [int]$summary.effective_ambiguous_targets -ne 15 -or
        $summary.g2_06_satisfied -ne $false -or $summary.p3_authorized -ne $false -or
        $self.result -ne 'PASS' -or [int]$self.assertions -lt 10) {
        throw 'P2-20A.6 fail-closed summary or self-test drifted.'
    }

    $generated = [ordered]@{
        detail = $generatedDetail; report = $generatedReport; markdown = $generatedMarkdown
    }
    $tracked = [ordered]@{
        detail = $trackedDetail; report = $trackedReport; markdown = $trackedMarkdown
    }
    if ($Check) {
        foreach ($name in $tracked.Keys) {
            if (-not (Test-Path -LiteralPath $tracked[$name] -PathType Leaf) -or
                (Get-Sha256 $tracked[$name]) -ne (Get-Sha256 $generated[$name])) {
                throw "Tracked P2-20A.6 output differs from deterministic regeneration: $name"
            }
        }
    }
    else {
        foreach ($name in $tracked.Keys) { Copy-Output $generated[$name] $tracked[$name] }
    }

    $report = Get-Content -LiteralPath $trackedReport -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    $sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    $evidencePath = Join-Path $root 'Data\Inventory\p2-20a-asset-identity-normalization.json'
    $evidence = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_revision = 'P2-20A.6'
        captured_utc = $capturedUtc
        task_id = 'P2-20A'
        criterion_id = 'G2-06'
        result = 'BLOCKED'
        review_execution_result = 'PASS'
        task_status = 'BLOCKED'
        completion_criteria_satisfied = $false
        diagnostic_scope_complete = $true
        scope_complete = $false
        g2_06_satisfied = $false
        p3_authorized = $false
        input_bindings = $report.input_bindings
        measured = $report.measured
        outputs = [pscustomobject][ordered]@{
            report_json = New-FileBinding $trackedReport $true
            report_markdown = New-FileBinding $trackedMarkdown $true
            detail_export = New-FileBinding $trackedDetail $false
        }
        contracts = [pscustomobject][ordered]@{
            policy = Get-Relative $policyPath
            policy_sha256 = Get-Sha256 $policyPath
            schema = Get-Relative $schemaPath
            schema_sha256 = Get-Sha256 $schemaPath
        }
        implementation = [pscustomobject][ordered]@{
            source_files = $sourceFiles.Count
            source_sha256 = $sourceSha
            generator = Get-Relative $generatorPath
            generator_sha256 = Get-Sha256 $generatorPath
            wrapper = Get-Relative $MyInvocation.MyCommand.Path
            wrapper_sha256 = Get-Sha256 $MyInvocation.MyCommand.Path
            self_test_assertions = [int]$self.assertions
        }
        builder = [pscustomobject][ordered]@{
            image_reference = $builderReference
            image_id = $expectedBuilderId
            user = 'tmxy'
        }
        isolation = [pscustomobject][ordered]@{
            repository_mount = 'read-only'
            network = 'none'
            capabilities = 'none'
            no_new_privileges = $true
        }
        disclosure = $report.disclosure
        next_scope = [pscustomobject][ordered]@{
            tasks = @('P2-20A-authoritative-binding-remediation', 'P2-20-g2-rerun')
            detail = 'Obtain authoritative dispositions for all 15 ambiguous and 19 unresolved targets; ASCII-lower identity collision alone cannot select a candidate.'
        }
    }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw 'Tracked P2-20A.6 evidence is missing.'
        }
        $frozen = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -Depth 100 -DateKind String
        if (($frozen | ConvertTo-Json -Depth 100 -Compress) -cne
            ($evidence | ConvertTo-Json -Depth 100 -Compress)) {
            throw 'Tracked P2-20A.6 evidence differs from deterministic full-object regeneration.'
        }
    }
    else {
        $json = ($evidence | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n")
        [IO.File]::WriteAllText($evidencePath, $json + "`n", [Text.UTF8Encoding]::new($false))
    }

    [pscustomobject][ordered]@{
        result = 'PASS_DIAGNOSTIC'
        task_status = 'BLOCKED'
        case_fold_collision_targets = 13
        case_fold_collision_edges = 26
        strict_semantic_equivalent_targets = 0
        effective_ambiguous_targets = 15
        effective_ambiguous_edges = 30
        candidate_selections = 0
        generator_self_test_assertions = [int]$self.assertions
        g2_06_satisfied = $false
        p3_authorized = $false
        report_sha256 = Get-Sha256 $trackedReport
        detail_sha256 = Get-Sha256 $trackedDetail
        markdown_sha256 = Get-Sha256 $trackedMarkdown
        evidence_sha256 = Get-Sha256 $evidencePath
    } | ConvertTo-Json -Depth 10
}
finally {
    $resolvedRunRoot = [IO.Path]::GetFullPath($runRoot)
    if ($resolvedRunRoot.StartsWith($localRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedRunRoot) -match '^[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedRunRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRunRoot -Recurse -Force
    }
}
