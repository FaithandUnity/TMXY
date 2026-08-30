[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-28-g1-format-review.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$output = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith(
        $root + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'G1 review output must remain inside Rebuild.'
}

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-JsonEvidence {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $path = Join-Path $root $RelativePath.Replace(
        '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G1 evidence is missing: $RelativePath"
    }
    return [pscustomobject]@{
        path = $path
        relative_path = $RelativePath
        sha256 = Get-LowerSha256 -Path $path
        value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

$evidenceMap = [ordered]@{
    'P1-01' = 'Data/BuildBaseline/p1-01-format-core.json'
    'P1-02' = 'Data/BuildBaseline/p1-02-package-v1.json'
    'P1-03' = 'Data/BuildBaseline/p1-03-legacy-table.json'
    'P1-04' = 'Data/BuildBaseline/p1-04-reference-formats-v0.1.json'
    'P1-05' = 'Data/BuildBaseline/p1-05-package-v2.json'
    'P1-06' = 'Data/BuildBaseline/p1-06-package-v3.json'
    'P1-07' = 'Data/BuildBaseline/p1-07-package-pipeline.json'
    'P1-08' = 'Data/BuildBaseline/p1-08-package-normalized-tree.json'
    'P1-09' = 'Data/BuildBaseline/p1-09-current-table-investigation.json'
    'P1-10' = 'Data/BuildBaseline/p1-10-current-item-csv-relation.json'
    'P1-11' = 'Data/BuildBaseline/p1-11-current-table-representatives.json'
    'P1-12' = 'Data/BuildBaseline/p1-12-legacy-to-ue-transform.json'
    'P1-13' = 'Data/BuildBaseline/p1-13-qtx-texture.json'
    'P1-14' = 'Data/BuildBaseline/p1-14-sm-static-mesh.json'
    'P1-15' = 'Data/BuildBaseline/p1-15-skem-skeletal-mesh.json'
    'P1-16' = 'Data/BuildBaseline/p1-16-anim-animation.json'
    'P1-17' = 'Data/BuildBaseline/p1-17-ter-terrain.json'
    'P1-18' = 'Data/BuildBaseline/p1-18-auxiliary-assets.json'
    'P1-19' = 'Data/BuildBaseline/p1-19-asset-interchange.json'
    'P1-20' = 'Data/BuildBaseline/p1-20-ue-golden-host.json'
    'P1-21' = 'Data/BuildBaseline/p1-21-ue-importer-plugin.json'
    'P1-22' = 'Data/BuildBaseline/p1-22-ue-texture-import.json'
    'P1-23' = 'Data/BuildBaseline/p1-23-ue-static-mesh-import.json'
    'P1-24' = 'Data/BuildBaseline/p1-24-ue-skeletal-mesh-import.json'
    'P1-25' = 'Data/BuildBaseline/p1-25-ue-animation-import.json'
    'P1-26' = 'Data/BuildBaseline/p1-26-ue-terrain-import.json'
    'P1-27' = 'Data/BuildBaseline/p1-27-golden-test-matrix.json'
}

$taskEvidence = [System.Collections.Generic.List[object]]::new()
$taskPassed = [System.Collections.Generic.Dictionary[string, bool]]::new(
    [System.StringComparer]::Ordinal)
foreach ($entry in $evidenceMap.GetEnumerator()) {
    $record = Read-JsonEvidence -RelativePath $entry.Value
    $value = $record.value
    $hasCompletion = $value.PSObject.Properties.Name -contains 'completion_criteria_satisfied'
    $passed = [string]$value.task -eq $entry.Key -and
        [string]$value.result -like 'PASS*' -and
        (-not $hasCompletion -or [bool]$value.completion_criteria_satisfied)
    $taskPassed.Add($entry.Key, $passed)
    $taskEvidence.Add([pscustomobject][ordered]@{
        task = $entry.Key
        passed = $passed
        evidence = $entry.Value
    })
}

$runtimeCaptureRecord = Read-JsonEvidence `
    -RelativePath 'Data/BuildBaseline/p1-09-runtime-key-capture.json'
$runtimeCapture = $runtimeCaptureRecord.value
$representativeReport = (Read-JsonEvidence `
    -RelativePath $evidenceMap['P1-11']).value
$matrixReport = (Read-JsonEvidence -RelativePath $evidenceMap['P1-27']).value
$authorizationRecord = Read-JsonEvidence `
    -RelativePath 'Data/Governance/p1-g1-stage-authorization.json'
$authorization = $authorizationRecord.value
$authorizationPassed = [int]$authorization.schema_version -eq 1 -and
    [string]$authorization.authorization_id -eq 'AUTH-2026-08-28-P1-28' -and
    [string]$authorization.status -eq 'approved' -and
    [string]$authorization.approved_by -eq 'project_lead' -and
    [bool]$authorization.scope.execute_p1_28 -and
    [bool]$authorization.scope.approve_g1_format_gate_when_all_technical_checks_pass -and
    [bool]$authorization.wvr_0001_exception.supersedes_g1_prohibition -and
    -not [bool]$authorization.boundaries.approve_g0 -and
    -not [bool]$authorization.boundaries.claim_release_authority -and
    -not [bool]$authorization.boundaries.write_legacy_directories -and
    -not [bool]$authorization.boundaries.emit_runtime_table_key

$checks = @(
    [pscustomobject][ordered]@{
        id = 'package_v1_golden'
        passed = $taskPassed['P1-02'] -and $taskPassed['P1-27']
        evidence = @('P1-02', 'P1-27')
    },
    [pscustomobject][ordered]@{
        id = 'package_v2_v3_stable'
        passed = $taskPassed['P1-05'] -and $taskPassed['P1-06'] -and
            $taskPassed['P1-07'] -and $taskPassed['P1-08']
        evidence = @('P1-05', 'P1-06', 'P1-07', 'P1-08')
    },
    [pscustomobject][ordered]@{
        id = 'current_table_representatives_and_secret'
        passed = $taskPassed['P1-09'] -and $taskPassed['P1-10'] -and
            $taskPassed['P1-11'] -and
            [string]$runtimeCapture.result -eq 'PASS_CAPTURE' -and
            [bool]$runtimeCapture.completion_criteria_satisfied -and
            [int]$representativeReport.summary.decoded -eq 20 -and
            [int]$representativeReport.summary.failed -eq 0 -and
            -not [bool]$representativeReport.secret_handling.raw_key_emitted
        evidence = @('P1-09', 'P1-10', 'P1-11')
    },
    [pscustomobject][ordered]@{
        id = 'five_resource_structured_outputs'
        passed = @('P1-13', 'P1-14', 'P1-15', 'P1-16', 'P1-17' |
            Where-Object { -not $taskPassed[$_] }).Count -eq 0
        evidence = @('P1-13', 'P1-14', 'P1-15', 'P1-16', 'P1-17', 'P1-19')
    },
    [pscustomobject][ordered]@{
        id = 'five_resource_ue_imports'
        passed = @('P1-22', 'P1-23', 'P1-24', 'P1-25', 'P1-26' |
            Where-Object { -not $taskPassed[$_] }).Count -eq 0
        evidence = @('P1-22', 'P1-23', 'P1-24', 'P1-25', 'P1-26')
    },
    [pscustomobject][ordered]@{
        id = 'coordinate_unit_uv_skeleton_animation'
        passed = @('P1-12', 'P1-23', 'P1-24', 'P1-25', 'P1-26' |
            Where-Object { -not $taskPassed[$_] }).Count -eq 0
        evidence = @('P1-12', 'P1-23', 'P1-24', 'P1-25', 'P1-26')
    },
    [pscustomobject][ordered]@{
        id = 'corrupt_input_fail_closed'
        passed = $taskPassed['P1-27'] -and
            [int]$matrixReport.matrix.suite_count -eq 9 -and
            [int]$matrixReport.matrix.case_count -eq 36 -and
            [int]$matrixReport.matrix.category_counts.corrupt -eq 9
        evidence = @('P1-27')
    },
    [pscustomobject][ordered]@{
        id = 'evidence_levels_and_unknowns'
        passed = $taskPassed['P1-04'] -and $taskPassed['P1-19'] -and
            [int]$matrixReport.matrix.category_counts.unknown -eq 9
        evidence = @('P1-04', 'P1-19', 'P1-27')
    }
)

$unknowns = @(
    [pscustomobject][ordered]@{ id = 'PKG1-U01'; owner = 'package-and-table-proof'; state = 'contained'; isolation = 'Preserve name and class as bytes until a class-specific decoder declares encoding.'; next_task = 'P2-01' },
    [pscustomobject][ordered]@{ id = 'PKG1-U02'; owner = 'resource-proof'; state = 'partially-resolved'; isolation = 'Recognized classes use bounded decoders; every unrecognized body remains an opaque source span.'; next_task = 'P2-01' },
    [pscustomobject][ordered]@{ id = 'PKG1-U03'; owner = 'binary-foundation'; state = 'contained'; isolation = 'Reject empty names or classes in normalized production input; retain corrupt samples separately.'; next_task = 'P2-02' },
    [pscustomobject][ordered]@{ id = 'PKG1-U04'; owner = 'binary-foundation'; state = 'contained'; isolation = 'Require contiguous normal records; classify gap or overlap variants as corrupt without guessing.'; next_task = 'P2-02' },
    [pscustomobject][ordered]@{ id = 'LTBL-U01'; owner = 'package-and-table-proof'; state = 'partially-resolved'; isolation = 'Keep bytes authoritative and require an explicit per-table encoding declaration before normalization.'; next_task = 'P2-04' },
    [pscustomobject][ordered]@{ id = 'LTBL-U02'; owner = 'package-and-table-proof'; state = 'contained'; isolation = 'Require an explicit separator; the frozen production baseline remains comma-only.'; next_task = 'P2-04' },
    [pscustomobject][ordered]@{ id = 'LTBL-U03'; owner = 'binary-foundation'; state = 'contained'; isolation = 'Fail closed on empty or duplicate headers and over-limit rows instead of copying legacy tolerance.'; next_task = 'P2-04' },
    [pscustomobject][ordered]@{ id = 'LTBL-U04'; owner = 'package-and-table-proof'; state = 'resolved'; isolation = 'Use only the authorized keychain-injected current-table path; never fall back to the legacy key.'; next_task = 'P2-04' },
    [pscustomobject][ordered]@{ id = 'CTBL-U01'; owner = 'package-and-table-proof'; state = 'open'; isolation = 'Keep table-specific variable schemas out of fixed-column normalization until P2 inventories every active table.'; next_task = 'P2-04' },
    [pscustomobject][ordered]@{ id = 'CTBL-U02'; owner = 'security-and-runtime'; state = 'open'; isolation = 'Bind each runtime-key capture to executable hash and session fingerprint; never persist or log raw key bytes.'; next_task = 'P2-04' }
)
$unownedUnknowns = @($unknowns | Where-Object { -not [string]$_.owner })
$unisolatedUnknowns = @($unknowns | Where-Object { -not [string]$_.isolation })
$failedTasks = @($taskEvidence | Where-Object { -not $_.passed })
$failedChecks = @($checks | Where-Object { -not $_.passed })
$reviewPassed = $failedTasks.Count -eq 0 -and $failedChecks.Count -eq 0 -and
    $authorizationPassed -and $unownedUnknowns.Count -eq 0 -and
    $unisolatedUnknowns.Count -eq 0

$hostingRecord = Read-JsonEvidence `
    -RelativePath 'Data/Governance/p0-github-hosting-status.json'
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($reviewPassed) { 'PASS' } else { 'FAIL' }
    task = 'P1-28'
    task_status = if ($reviewPassed) { 'COMPLETE' } else { 'BLOCKED' }
    completion_criteria_satisfied = $reviewPassed
    gate = 'G1'
    gate_decision = if ($reviewPassed) { 'APPROVED' } else { 'REJECTED' }
    stage_approval = [pscustomobject][ordered]@{
        passed = $authorizationPassed
        id = [string]$authorization.authorization_id
        evidence = $authorizationRecord.relative_path
        sha256 = $authorizationRecord.sha256
    }
    prerequisites = [pscustomobject][ordered]@{
        passed = $failedTasks.Count -eq 0
        completed = $taskEvidence.Count - $failedTasks.Count
        required = 27
        tasks = @($taskEvidence)
    }
    checks = @($checks)
    check_summary = [pscustomobject][ordered]@{
        passed = $checks.Count - $failedChecks.Count
        required = 8
        failed_ids = @($failedChecks | ForEach-Object { [string]$_.id })
    }
    unknown_items = [pscustomobject][ordered]@{
        total = $unknowns.Count
        owned = $unknowns.Count - $unownedUnknowns.Count
        isolated = $unknowns.Count - $unisolatedUnknowns.Count
        items = $unknowns
    }
    security = [pscustomobject][ordered]@{
        runtime_key_reference_only = $true
        raw_key_emitted = $false
        legacy_inputs_read_only = $true
        legacy_asset_redistribution_authorized = $false
    }
    authority_boundaries = [pscustomobject][ordered]@{
        g1_format_gate = $reviewPassed
        g0_approved = $false
        p0_12_complete = $false
        p0_16_complete = $false
        release_authority = $false
        external_non_g1_blockers = @($hostingRecord.value.blockers)
    }
    next_scope = [pscustomobject][ordered]@{
        phase = 'P2'
        ready_tasks = @('P2-01', 'P2-04', 'P2-12')
        rule = 'Continue under task-specific rights, Secret, source-integrity, and evidence controls.'
    }
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($output)) | Out-Null
[System.IO.File]::WriteAllText($output, $json + "`n", [System.Text.UTF8Encoding]::new($false))
$json
if (-not $reviewPassed) { throw 'P1-28/G1 format review failed closed.' }
