[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$RequestPath = '',
    [string]$ApprovalObservationPath = '',
    [switch]$FixtureMode,
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-postgres-gosu-waiver-decision.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
if ([string]::IsNullOrWhiteSpace($RequestPath)) {
    $RequestPath = Join-Path $root 'Data\Security\p0-12-postgres-gosu-waiver-request.json'
}
$requestFullPath = [IO.Path]::GetFullPath($RequestPath)
$dispositionPath = Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'
$reachabilityPath = Join-Path $root 'Data\Security\p0-12-postgres-gosu-reachability-review.json'
$candidatePath = Join-Path $root 'Data\Security\p0-12-postgres-official-candidate-evaluation.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$composePath = Join-Path $root 'Deploy\compose\compose.yaml'
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Required waiver binding is missing: $Path"
        return ''
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LiveApprovalObservation {
    param(
        [Parameter(Mandatory = $true)][object]$Request,
        [Parameter(Mandatory = $true)][string]$RequestSha256
    )
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        throw 'Active waiver evaluation requires GITHUB_TOKEN for read-only authenticated API verification.'
    }
    $repository = 'FaithandUnity/TMXY'
    $api = if ([string]::IsNullOrWhiteSpace($env:GITHUB_API_URL)) {
        'https://api.github.com'
    }
    else { $env:GITHUB_API_URL.TrimEnd('/') }
    $headers = @{
        Authorization = "Bearer $env:GITHUB_TOKEN"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'TMXY-P0-12-Waiver-Evaluator'
    }
    $prNumber = [int]$Request.approval.pull_request_number
    $pr = Invoke-RestMethod -Uri "$api/repos/$repository/pulls/$prNumber" -Headers $headers
    $reviews = Invoke-RestMethod -Uri "$api/repos/$repository/pulls/$prNumber/reviews?per_page=100" `
        -Headers $headers
    $encodedRef = [Uri]::EscapeDataString([string]$pr.head.sha)
    $content = Invoke-RestMethod -Uri (
        "$api/repos/$repository/contents/Data/Security/p0-12-postgres-gosu-waiver-request.json?ref=$encodedRef") `
        -Headers $headers
    $remoteBytes = [Convert]::FromBase64String(([string]$content.content -replace '\s', ''))
    $remoteSha = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($remoteBytes)).ToLowerInvariant()
    return [pscustomobject][ordered]@{
        mode = 'authenticated_github_api'
        repository = $repository
        pull_request_number = [int]$pr.number
        pull_request_state = [string]$pr.state
        pull_request_draft = [bool]$pr.draft
        pull_request_merged = [bool]$pr.merged
        pull_request_author = [string]$pr.user.login
        head_sha = [string]$pr.head.sha
        request_sha256_at_head = $remoteSha
        local_request_sha256 = $RequestSha256
        reviews = @($reviews | ForEach-Object {
                [pscustomobject][ordered]@{
                    id = [int64]$_.id
                    user = [string]$_.user.login
                    state = [string]$_.state
                    commit_id = [string]$_.commit_id
                    submitted_at = [string]$_.submitted_at
                }
            })
    }
}

function Test-ApprovalObservation {
    param(
        [Parameter(Mandatory = $true)][object]$Observation,
        [Parameter(Mandatory = $true)][object]$Request,
        [Parameter(Mandatory = $true)][string]$RequestSha256
    )
    $emptyResult = [pscustomobject][ordered]@{
        approvals = @()
        owner_authorization_verified = $false
        owner_authorization_mode = 'unverified'
    }
    if ([string]$Observation.repository -ne 'FaithandUnity/TMXY' -or
        [int]$Observation.pull_request_number -ne [int]$Request.approval.pull_request_number -or
        [bool]$Observation.pull_request_draft -or
        ([string]$Observation.pull_request_state -ne 'open' -and
            -not [bool]$Observation.pull_request_merged) -or
        [string]$Observation.head_sha -notmatch '^[a-f0-9]{40}$' -or
        [string]$Observation.request_sha256_at_head -ne $RequestSha256 -or
        [string]$Observation.local_request_sha256 -ne $RequestSha256) {
        Add-Failure 'Approval PR does not bind the exact request at a reviewable current HEAD.'
        return $emptyResult
    }
    $latestReviews = @($Observation.reviews | Group-Object { ([string]$_.user).ToLowerInvariant() } |
        ForEach-Object { @($_.Group | Sort-Object { [DateTimeOffset]$_.submitted_at } -Descending)[0] })
    $approvals = @($latestReviews | Where-Object {
            [string]$_.state -eq 'APPROVED' -and
            [string]$_.commit_id -eq [string]$Observation.head_sha -and
            -not [string]::Equals(
                [string]$_.user,
                [string]$Observation.pull_request_author,
                [StringComparison]::OrdinalIgnoreCase)
        })
    $uniqueApprovers = @($approvals | ForEach-Object { ([string]$_.user).ToLowerInvariant() } |
        Sort-Object -Unique)
    $ownerLogin = ([string]$Request.approval.owner_login).ToLowerInvariant()
    $ownerIsPrAuthor = [string]::Equals(
        $ownerLogin,
        ([string]$Observation.pull_request_author).ToLowerInvariant(),
        [StringComparison]::Ordinal)
    $ownerAuthorizationVerified = if ($ownerIsPrAuthor) {
        [bool]$Request.approval.owner_approval
    }
    else { $uniqueApprovers -contains $ownerLogin }
    $ownerAuthorizationMode = if ($ownerIsPrAuthor) {
        'owner_authenticated_pr_author_exact_request'
    }
    else { 'owner_current_head_review' }
    if ($uniqueApprovers.Count -lt [int]$Request.approval.required_unique_non_author_approvals -or
        -not $ownerAuthorizationVerified) {
        Add-Failure 'Approval PR lacks two current-HEAD non-author reviews or verified owner authorization.'
    }
    return [pscustomobject][ordered]@{
        approvals = $approvals
        owner_authorization_verified = $ownerAuthorizationVerified
        owner_authorization_mode = $ownerAuthorizationMode
    }
}

$bindingPaths = [ordered]@{
    vulnerability_disposition = $dispositionPath
    reachability_review = $reachabilityPath
    official_candidate = $candidatePath
    toolchain_lock = $lockPath
    compose = $composePath
}
$bindingHashes = [ordered]@{}
foreach ($entry in $bindingPaths.GetEnumerator()) {
    $bindingHashes[$entry.Key] = Get-Sha256 -Path $entry.Value
}
$requestSha = Get-Sha256 -Path $requestFullPath
$request = $null
$disposition = $null
$reachability = $null
$candidate = $null
try {
    $request = Get-Content -LiteralPath $requestFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $disposition = Get-Content -LiteralPath $dispositionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reachability = Get-Content -LiteralPath $reachabilityPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $candidate = Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch { Add-Failure "Could not parse waiver inputs: $($_.Exception.Message)" }

if ($null -ne $request -and $null -ne $disposition -and $null -ne $reachability -and
    $null -ne $candidate) {
    if ([int]$request.schema_version -ne 1 -or [string]$request.waiver_id -ne 'WVR-0002' -or
        [string]$request.decision_owner -ne 'FaithandUnity' -or
        [string]$request.execution_owner -ne 'Codex') {
        Add-Failure 'Waiver request identity or decision ownership is invalid.'
    }
    if ([string]$request.component.image_digest -ne
            [string]$disposition.component.locked_index_digest -or
        [string]$request.component.binary -ne 'gosu' -or
        [string]$request.component.version -ne 'v1.19.0' -or
        [string]$request.component.binary_sha256 -ne
            [string]$candidate.locked_probe.gosu_sha256 -or
        [string]$request.component.go_version -ne 'go1.24.6' -or
        [string]$request.component.platform -ne 'linux/amd64') {
        Add-Failure 'Waiver request component scope differs from the locked reviewed gosu binary.'
    }
    $requestIds = @($request.finding_scope.vulnerability_ids | ForEach-Object { [string]$_ } |
        Sort-Object -Unique)
    $dispositionIds = @($disposition.blocking_findings.vulnerability_ids |
        ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if ([int]$request.finding_scope.count -ne 22 -or $requestIds.Count -ne 22 -or
        ($requestIds -join ',') -ne ($dispositionIds -join ',') -or
        [int]$request.finding_scope.reachability_counts.symbol_reachable -ne 0 -or
        [int]$request.finding_scope.reachability_counts.package_only -ne 1 -or
        [int]$request.finding_scope.reachability_counts.module_only -ne 21 -or
        [string]$reachability.review.status -ne
            'REVIEW_COMPLETE_NO_SYMBOL_REACHABILITY_STILL_BLOCKING') {
        Add-Failure 'Waiver finding scope or reachability counts are not the exact reviewed blocker set.'
    }
    foreach ($entry in $bindingPaths.GetEnumerator()) {
        $hashProperty = $request.bindings.PSObject.Properties["$($entry.Key)_sha256"]
        if ($null -eq $hashProperty -or [string]$hashProperty.Value -ne $bindingHashes[$entry.Key]) {
            Add-Failure "Waiver request binding is stale: $($entry.Key)"
        }
    }
    if ([int]$request.duration.maximum_days -ne 30 -or
        [int]$request.approval.required_unique_non_author_approvals -ne 2 -or
        [string]$request.approval.owner_login -ne 'FaithandUnity' -or
        [string]$request.approval.owner_authorization_mode -ne
            'owner_as_pr_author_or_current_head_reviewer' -or
        @($request.approval.approved_review_ids).Count -ne 0 -or
        -not [bool]$request.approval.reviews_must_match_current_head -or
        -not [bool]$request.approval.dismiss_stale_approvals -or
        -not [bool]$request.approval.authenticated_github_api_verification_required -or
        [bool]$request.activation.automatic_activation_allowed -or
        [bool]$request.activation.offline_fixture_can_activate -or
        [bool]$request.activation.release_authority) {
        Add-Failure 'Waiver duration, approval, or non-authority safety contract is invalid.'
    }
}

$observation = $null
$approvalEvaluation = $null
$approvals = @()
$ownerAuthorizationVerified = $false
$ownerAuthorizationMode = 'unverified'
$effective = $false
$decision = 'WAIVER_EVALUATION_FAILED_CLOSED'
$evaluationMode = if ($FixtureMode) { 'offline_fixture_non_authoritative' } else { 'local_draft' }
if ($null -ne $request -and $failures.Count -eq 0) {
    if ([string]$request.status -eq 'draft_not_approved') {
        if ([string]$request.policy_effect -ne 'none_still_blocking' -or
            [bool]$request.approval.owner_approval -or
            [int]$request.approval.pull_request_number -ne 0 -or
            @($request.approval.approved_review_ids).Count -ne 0 -or
            $null -ne $request.duration.effective_utc -or
            $null -ne $request.duration.expires_utc -or
            $null -ne $request.duration.remediation_deadline_utc -or
            [bool]$request.activation.requested -or [bool]$request.activation.effective -or
            -not [string]::IsNullOrWhiteSpace($ApprovalObservationPath)) {
            Add-Failure 'Draft waiver request contains approval, dates, observation, or activation state.'
        }
        else { $decision = 'DRAFT_READY_FOR_OWNER_DECISION_NOT_EFFECTIVE' }
    }
    elseif ([string]$request.status -eq 'active_time_bounded') {
        $effectiveAt = [DateTimeOffset]::MinValue
        $expiresAt = [DateTimeOffset]::MinValue
        $deadline = [DateTimeOffset]::MinValue
        $datesValid = $true
        try {
            $effectiveAt = [DateTimeOffset]$request.duration.effective_utc
            $expiresAt = [DateTimeOffset]$request.duration.expires_utc
            $deadline = [DateTimeOffset]$request.duration.remediation_deadline_utc
        }
        catch { $datesValid = $false }
        if (-not $datesValid -or $effectiveAt -gt [DateTimeOffset]::UtcNow -or
            $expiresAt -le [DateTimeOffset]::UtcNow -or $deadline -ne $expiresAt -or
            ($expiresAt - $effectiveAt).TotalDays -le 0 -or
            ($expiresAt - $effectiveAt).TotalDays -gt 30 -or
            [string]$request.policy_effect -ne 'component_exception_requested' -or
            -not [bool]$request.approval.owner_approval -or
            [int]$request.approval.pull_request_number -le 0 -or
            -not [bool]$request.activation.requested -or
            -not [bool]$request.activation.effective) {
            Add-Failure 'Active waiver request lacks valid approval state or a current maximum-30-day interval.'
        }
        if ($failures.Count -eq 0) {
            try {
                if ($FixtureMode) {
                    if ([string]::IsNullOrWhiteSpace($ApprovalObservationPath)) {
                        throw 'Fixture mode requires an approval observation.'
                    }
                    $observation = Get-Content -LiteralPath (
                        [IO.Path]::GetFullPath($ApprovalObservationPath)) -Raw -Encoding UTF8 |
                        ConvertFrom-Json
                }
                else {
                    $evaluationMode = 'authenticated_github_api'
                    $observation = Get-LiveApprovalObservation -Request $request -RequestSha256 $requestSha
                }
                $approvalEvaluation = Test-ApprovalObservation -Observation $observation `
                    -Request $request -RequestSha256 $requestSha
                $approvals = @($approvalEvaluation.approvals)
                $ownerAuthorizationVerified =
                    [bool]$approvalEvaluation.owner_authorization_verified
                $ownerAuthorizationMode = [string]$approvalEvaluation.owner_authorization_mode
            }
            catch { Add-Failure "Approval verification failed: $($_.Exception.Message)" }
        }
        if ($failures.Count -eq 0) {
            if ($FixtureMode) {
                $decision = 'STRUCTURE_VALID_FIXTURE_NOT_EFFECTIVE'
            }
            else {
                $decision = 'ACTIVE_TIME_BOUNDED_VERIFIED'
                $effective = $true
            }
        }
    }
    else { Add-Failure 'Waiver status is neither draft_not_approved nor active_time_bounded.' }
}

if ($failures.Count -gt 0) { $decision = 'WAIVER_EVALUATION_FAILED_CLOSED' }
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -gt 0) {
        'FAIL'
    }
    elseif ($effective) { 'PASS' } else { 'PASS_DIAGNOSTIC' }
    decision = $decision
    evaluation_mode = $evaluationMode
    waiver_id = if ($null -ne $request) { [string]$request.waiver_id } else { '' }
    request_status = if ($null -ne $request) { [string]$request.status } else { '' }
    request_sha256 = $requestSha
    waiver_effective = $effective
    policy_blocking = -not $effective
    component_policy_exception = $effective
    automatic_activation = $false
    release_authority = $false
    approval = [pscustomobject][ordered]@{
        owner_login = if ($null -ne $request) { [string]$request.approval.owner_login } else { '' }
        owner_authorization_verified = $ownerAuthorizationVerified
        owner_authorization_mode = $ownerAuthorizationMode
        required_unique_non_author_approvals = if ($null -ne $request) {
            [int]$request.approval.required_unique_non_author_approvals
        }
        else { 0 }
        verified_approval_count = $approvals.Count
        verified_approvers = @($approvals | ForEach-Object { [string]$_.user } | Sort-Object -Unique)
        verified_review_ids = @($approvals | ForEach-Object { [int64]$_.id } | Sort-Object -Unique)
        pull_request_number = if ($null -ne $request) {
            [int]$request.approval.pull_request_number
        }
        else { 0 }
        head_sha = if ($null -ne $observation) { [string]$observation.head_sha } else { '' }
        exact_request_at_head = $null -ne $observation -and
            [string]$observation.request_sha256_at_head -eq $requestSha
    }
    duration = if ($null -ne $request) { $request.duration } else { $null }
    component = if ($null -ne $request) { $request.component } else { $null }
    finding_scope = if ($null -ne $request) { $request.finding_scope } else { $null }
    bindings = [pscustomobject][ordered]@{
        request = 'Data/Security/p0-12-postgres-gosu-waiver-request.json'
        request_sha256 = $requestSha
        vulnerability_disposition_sha256 = $bindingHashes.vulnerability_disposition
        reachability_review_sha256 = $bindingHashes.reachability_review
        official_candidate_sha256 = $bindingHashes.official_candidate
        toolchain_lock_sha256 = $bindingHashes.toolchain_lock
        compose_sha256 = $bindingHashes.compose
    }
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    $directory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }
    [IO.File]::WriteAllText($resolvedOutput, $json + "`n", [Text.UTF8Encoding]::new($false))
}
$json
if ($failures.Count -gt 0) { throw 'PostgreSQL gosu waiver decision failed closed.' }
