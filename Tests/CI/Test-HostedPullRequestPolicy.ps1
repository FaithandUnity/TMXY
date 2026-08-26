[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][int]$PullRequestNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw 'Repository must use the owner/name form.'
}
if ($PullRequestNumber -lt 1) { throw 'Pull request number must be positive.' }

$credentialValue = [Environment]::GetEnvironmentVariable('TMXY_GITHUB_READ_CREDENTIAL')
if ([string]::IsNullOrWhiteSpace($credentialValue)) {
    throw 'The read-only GitHub credential was not injected by the hosted job.'
}
$headers = @{
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'TMXY-P0-12-review-policy'
    Authorization = 'Bearer ' + $credentialValue
}
$base = "https://api.github.com/repos/$Repository/pulls/$PullRequestNumber"
$pullRequest = Invoke-RestMethod -Method Get -Uri $base -Headers $headers

$files = [System.Collections.Generic.List[object]]::new()
for ($page = 1; $page -le 30; $page++) {
    $batch = @(Invoke-RestMethod -Method Get -Uri "$base/files?per_page=100&page=$page" -Headers $headers)
    foreach ($file in $batch) { $files.Add($file) }
    if ($batch.Count -lt 100) { break }
}

$reviews = [System.Collections.Generic.List[object]]::new()
for ($page = 1; $page -le 30; $page++) {
    $batch = @(Invoke-RestMethod -Method Get -Uri "$base/reviews?per_page=100&page=$page" -Headers $headers)
    foreach ($review in $batch) { $reviews.Add($review) }
    if ($batch.Count -lt 100) { break }
}

$sensitivePatterns = @(
    '^\.github/',
    '^Contracts/proto/',
    '^Data/Governance/',
    '^Data/Security/',
    '^Deploy/',
    '^Docs/Governance/',
    '^Docs/Security/',
    '^Backend/adapters/persistence_postgres/migrations/'
)
$sensitiveFiles = @($files | Where-Object {
    $name = [string]$_.filename
    @($sensitivePatterns | Where-Object { $name -match $_ }).Count -gt 0
})
$requiredApprovalCount = if ($sensitiveFiles.Count -gt 0) { 2 } else { 1 }
$author = [string]$pullRequest.user.login
$headSha = [string]$pullRequest.head.sha

$latestStateByReviewer = @{}
foreach ($review in @($reviews | Sort-Object submitted_at, id)) {
    $reviewer = [string]$review.user.login
    if ([string]::IsNullOrWhiteSpace($reviewer) -or $reviewer -eq $author) { continue }
    $latestStateByReviewer[$reviewer] = [pscustomobject]@{
        state = [string]$review.state
        commit_id = [string]$review.commit_id
    }
}
$approvers = @($latestStateByReviewer.GetEnumerator() | Where-Object {
    [string]$_.Value.state -eq 'APPROVED' -and [string]$_.Value.commit_id -eq $headSha
} | ForEach-Object { [string]$_.Key } | Sort-Object -Unique)
$passed = $approvers.Count -ge $requiredApprovalCount

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    repository = $Repository
    pull_request = $PullRequestNumber
    source_revision = $headSha
    author = $author
    sensitive_change = $sensitiveFiles.Count -gt 0
    sensitive_file_count = $sensitiveFiles.Count
    required_approval_count = $requiredApprovalCount
    qualifying_approval_count = $approvers.Count
    qualifying_approvers = $approvers
    stale_approvals_counted = 0
    author_approval_counted = $false
}
$report | ConvertTo-Json -Depth 5
if (-not $passed) {
    throw "Pull request requires $requiredApprovalCount current non-author approval(s); found $($approvers.Count)."
}

