[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$toolPath = Join-Path $root 'Tools\TMXY.SupplyChain\Test-PostgresGosuWaiverDecision.ps1'
$requestPath = Join-Path $root 'Data\Security\p0-12-postgres-gosu-waiver-request.json'
$boundPaths = @(
    (Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'),
    (Join-Path $root 'Data\Security\p0-12-postgres-gosu-reachability-review.json'),
    (Join-Path $root 'Data\Security\p0-12-postgres-official-candidate-evaluation.json'),
    (Join-Path $root 'Data\Toolchain\toolchain.lock.json'),
    (Join-Path $root 'Deploy\compose\compose.yaml')
)
$failures = [Collections.Generic.List[string]]::new()

function Assert-WaiverTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { $failures.Add($Message) }
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    $json = ($Value | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
    throw "PostgreSQL gosu waiver evaluator is missing: $toolPath"
}
$beforeHashes = @($boundPaths | ForEach-Object {
        (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
    })
$baseRequest = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'tmxy-postgres-gosu-waiver-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $draftOutput = Join-Path $testRoot 'draft-output.json'
    $draft = (& $toolPath -RebuildRoot $root -RequestPath $requestPath `
            -OutputPath $draftOutput) | ConvertFrom-Json
    Assert-WaiverTest ([string]$draft.result -eq 'PASS_DIAGNOSTIC' -and
        [string]$draft.decision -eq 'DRAFT_READY_FOR_OWNER_DECISION_NOT_EFFECTIVE' -and
        -not [bool]$draft.waiver_effective -and [bool]$draft.policy_blocking -and
        -not [bool]$draft.component_policy_exception -and -not [bool]$draft.release_authority) `
        'The repository draft must be ready for decision but remain ineffective and blocking.'

    $active = $baseRequest | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $active.status = 'active_time_bounded'
    $active.policy_effect = 'component_exception_requested'
    $active.duration.effective_utc = [DateTimeOffset]::UtcNow.AddHours(-1).ToString('o')
    $active.duration.expires_utc = [DateTimeOffset]::UtcNow.AddDays(5).ToString('o')
    $active.duration.remediation_deadline_utc = $active.duration.expires_utc
    $active.approval.owner_approval = $true
    $active.approval.pull_request_number = 99
    $active.approval.approved_review_ids = @(1001, 1002)
    $active.activation.requested = $true
    $active.activation.effective = $true
    $activePath = Join-Path $testRoot 'active.json'
    Write-JsonFixture -Path $activePath -Value $active

    $missingObservationOutput = Join-Path $testRoot 'missing-observation-output.json'
    $missingObservationRejected = $false
    try {
        $null = & $toolPath -RebuildRoot $root -RequestPath $activePath `
            -OutputPath $missingObservationOutput 2>$null
    }
    catch { $missingObservationRejected = $true }
    $missingObservation = Get-Content -LiteralPath $missingObservationOutput -Raw -Encoding UTF8 |
        ConvertFrom-Json
    Assert-WaiverTest ($missingObservationRejected -and
        [string]$missingObservation.result -eq 'FAIL' -and
        [string]$missingObservation.decision -eq 'WAIVER_EVALUATION_FAILED_CLOSED') `
        'An active request without authenticated approval evidence must fail closed.'

    $activeSha = (Get-FileHash -LiteralPath $activePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $headSha = 'a' * 40
    $observation = [pscustomobject][ordered]@{
        mode = 'fixture'; repository = 'FaithandUnity/TMXY'; pull_request_number = 99
        pull_request_state = 'open'; pull_request_draft = $false; pull_request_merged = $false
        pull_request_author = 'request-author'; head_sha = $headSha
        request_sha256_at_head = $activeSha; local_request_sha256 = $activeSha
        reviews = @(
            [pscustomobject]@{ id = 1001; user = 'FaithandUnity'; state = 'APPROVED'; commit_id = $headSha; submitted_at = '2026-08-27T12:00:00Z' },
            [pscustomobject]@{ id = 1002; user = 'independent-reviewer'; state = 'APPROVED'; commit_id = $headSha; submitted_at = '2026-08-27T12:01:00Z' }
        )
    }
    $observationPath = Join-Path $testRoot 'observation.json'
    Write-JsonFixture -Path $observationPath -Value $observation
    $fixture = (& $toolPath -RebuildRoot $root -RequestPath $activePath `
            -ApprovalObservationPath $observationPath -FixtureMode `
            -OutputPath (Join-Path $testRoot 'fixture-output.json')) | ConvertFrom-Json
    Assert-WaiverTest ([string]$fixture.result -eq 'PASS_DIAGNOSTIC' -and
        [string]$fixture.decision -eq 'STRUCTURE_VALID_FIXTURE_NOT_EFFECTIVE' -and
        -not [bool]$fixture.waiver_effective -and [bool]$fixture.policy_blocking -and
        [int]$fixture.approval.verified_approval_count -eq 2) `
        'A structurally valid offline fixture must remain non-authoritative and ineffective.'

    $staleObservation = $observation | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $staleObservation.reviews[1].commit_id = 'b' * 40
    $stalePath = Join-Path $testRoot 'stale-observation.json'
    Write-JsonFixture -Path $stalePath -Value $staleObservation
    $staleOutput = Join-Path $testRoot 'stale-output.json'
    $staleRejected = $false
    try {
        $null = & $toolPath -RebuildRoot $root -RequestPath $activePath `
            -ApprovalObservationPath $stalePath -FixtureMode -OutputPath $staleOutput 2>$null
    }
    catch { $staleRejected = $true }
    $stale = Get-Content -LiteralPath $staleOutput -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-WaiverTest ($staleRejected -and [string]$stale.result -eq 'FAIL') `
        'A stale approval that does not match the current PR HEAD must fail closed.'

    $afterHashes = @($boundPaths | ForEach-Object {
            (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    Assert-WaiverTest (($beforeHashes -join ',') -eq ($afterHashes -join ',')) `
        'Waiver regression tests must not modify bound disposition, review, candidate, lock, or compose evidence.'
}
catch {
    $detail = ''
    $reports = @(Get-ChildItem -LiteralPath $testRoot -Filter '*output.json' -File -ErrorAction SilentlyContinue)
    if ($reports.Count -gt 0) {
        $details = @($reports | ForEach-Object {
                $failedReport = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 |
                    ConvertFrom-Json
                "$($_.Name)=result:$($failedReport.result),decision:$($failedReport.decision),failures:$(@($failedReport.failures) -join '; ')"
            })
        $detail = ' ' + ($details -join ' | ')
    }
    $failures.Add("PostgreSQL gosu waiver regression failed: $($_.Exception.Message)$detail")
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    fixture_count = 4
    effective_fixture_count = 0
    source_mutation_performed = $false
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 5
if ($failures.Count -gt 0) { throw 'PostgreSQL gosu waiver regression failed.' }
