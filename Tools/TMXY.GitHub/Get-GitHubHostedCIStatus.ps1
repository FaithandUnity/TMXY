[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$Repository = 'FaithandUnity/TMXY',
    [string]$RemoteName = 'origin',
    [string]$CredentialEnvironmentName = 'GH_TOKEN',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Governance\p0-github-hosting-status.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw 'Repository must use the owner/name form.'
}
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')

function Get-ReadCredential {
    $value = [Environment]::GetEnvironmentVariable($CredentialEnvironmentName)
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    $credentialLines = @("protocol=https`nhost=github.com`n`n" | git credential fill 2>$null)
    if ($LASTEXITCODE -ne 0) { return '' }
    foreach ($line in $credentialLines) {
        if ($line -match '^password=(.+)$') { return $Matches[1] }
    }
    return ''
}

function Invoke-GitHubRead {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][hashtable]$Headers
    )
    try {
        $body = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
        return [pscustomobject]@{ name = $Name; status = 200; body = $body; message = '' }
    }
    catch {
        $status = if ($null -ne $_.Exception.Response) {
            [int]$_.Exception.Response.StatusCode
        }
        else { -1 }
        $message = ''
        if (-not [string]::IsNullOrWhiteSpace([string]$_.ErrorDetails.Message)) {
            try { $message = [string](($_.ErrorDetails.Message | ConvertFrom-Json).message) }
            catch { $message = 'GitHub API returned a non-JSON error.' }
        }
        return [pscustomobject]@{ name = $Name; status = $status; body = $null; message = $message }
    }
}

function Get-ViewerPermission {
    param([Parameter(Mandatory = $true)][object]$Permissions)
    if ([bool]$Permissions.admin) { return 'admin' }
    if ([bool]$Permissions.maintain) { return 'maintain' }
    if ([bool]$Permissions.push) { return 'push' }
    if ([bool]$Permissions.triage) { return 'triage' }
    if ([bool]$Permissions.pull) { return 'pull' }
    return 'unknown'
}

$credentialValue = Get-ReadCredential
if ([string]::IsNullOrWhiteSpace($credentialValue)) {
    throw 'No read credential is available from the named environment variable or Git Credential Manager.'
}
$headers = @{
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'TMXY-P0-12-hosting-audit'
    Authorization = 'Bearer ' + $credentialValue
}
$base = "https://api.github.com/repos/$Repository"
$requests = @(
    @('repository', $base),
    @('branch', "$base/branches/main"),
    @('protection', "$base/branches/main/protection"),
    @('rulesets', "$base/rulesets"),
    @('runners', "$base/actions/runners?per_page=100"),
    @('actions_permissions', "$base/actions/permissions"),
    @('workflow_permissions', "$base/actions/permissions/workflow"),
    @('artifact_retention', "$base/actions/permissions/artifact-and-log-retention"),
    @('fork_pr_contributor_approval', "$base/actions/permissions/fork-pr-contributor-approval"),
    @('environments', "$base/environments?per_page=100"),
    @('p0_release_environment', "$base/environments/p0-release"),
    @('collaborators', "$base/collaborators?affiliation=direct&per_page=100"),
    @('secrets', "$base/actions/secrets?per_page=100"),
    @('variables', "$base/actions/variables?per_page=100"),
    @('workflows', "$base/actions/workflows?per_page=100"),
    @('artifacts', "$base/actions/artifacts?per_page=1")
)
$results = @{}
foreach ($request in $requests) {
    $results[$request[0]] = Invoke-GitHubRead -Name $request[0] -Uri $request[1] -Headers $headers
}

$remoteUrl = (& git -C $root remote get-url $RemoteName 2>$null).Trim()
$head = (& git -C $root rev-parse HEAD 2>$null).Trim()
$branchName = (& git -C $root branch --show-current 2>$null).Trim()
$branchProtected = $results.branch.status -eq 200 -and [bool]$results.branch.body.protected
$repositoryPublic = [string]$results.repository.body.visibility -eq 'public'
$forkApprovalPolicy = if ($results.fork_pr_contributor_approval.status -eq 200) {
    [string]$results.fork_pr_contributor_approval.body.approval_policy
}
else { 'unknown' }
$forkApprovalPolicySatisfied = -not $repositoryPublic -or
    $forkApprovalPolicy -eq 'all_external_contributors'
$expectedRequiredChecks = @(
    'policy/repository',
    'security/secrets',
    'backend/clang21',
    'backend/static-analysis',
    'backend/postgres-migration',
    'client/ue58-build-automation',
    'supply-chain/policy',
    'release/provenance'
)
$protection = if ($results.protection.status -eq 200) { $results.protection.body } else { $null }
$requiredCheckContexts = if ($null -ne $protection) {
    @($protection.required_status_checks.contexts | ForEach-Object { [string]$_ } | Sort-Object -Unique)
}
else { @() }
$requiredChecksEnforced = $null -ne $protection -and
    [bool]$protection.required_status_checks.strict -and
    $requiredCheckContexts.Count -eq $expectedRequiredChecks.Count -and
    @($expectedRequiredChecks | Where-Object { $requiredCheckContexts -notcontains $_ }).Count -eq 0
$pullRequestProtectionEnforced = $null -ne $protection -and
    [bool]$protection.enforce_admins.enabled -and
    [int]$protection.required_pull_request_reviews.required_approving_review_count -eq 1 -and
    [bool]$protection.required_pull_request_reviews.dismiss_stale_reviews -and
    [bool]$protection.required_pull_request_reviews.require_code_owner_reviews -and
    [bool]$protection.required_pull_request_reviews.require_last_push_approval
$mutationProtectionEnforced = $null -ne $protection -and
    -not [bool]$protection.allow_force_pushes.enabled -and
    -not [bool]$protection.allow_deletions.enabled -and
    [bool]$protection.required_linear_history.enabled -and
    [bool]$protection.required_conversation_resolution.enabled
$branchProtectionContractSatisfied = $branchProtected -and $requiredChecksEnforced -and
    $pullRequestProtectionEnforced -and $mutationProtectionEnforced
$runnerRecords = if ($results.runners.status -eq 200) { @($results.runners.body.runners) } else { @() }
$matchingUeRunners = @($runnerRecords | Where-Object {
    $labels = @($_.labels.name)
    [string]$_.os -eq 'windows' -and
    $labels -contains 'tmxy-ue58' -and $labels -contains 'tmxy-ephemeral'
})
$collaboratorCount = if ($results.collaborators.status -eq 200) {
    @($results.collaborators.body).Count
}
else { 0 }
$workflowCount = if ($results.workflows.status -eq 200) {
    @($results.workflows.body.workflows).Count
}
else { 0 }
$p0ReleaseEnvironment = if ($results.p0_release_environment.status -eq 200) {
    $results.p0_release_environment.body
}
else { $null }
$p0ReleaseEnvironmentProtected = $null -ne $p0ReleaseEnvironment -and
    [bool]$p0ReleaseEnvironment.deployment_branch_policy.protected_branches -and
    -not [bool]$p0ReleaseEnvironment.deployment_branch_policy.custom_branch_policies -and
    @($p0ReleaseEnvironment.protection_rules | Where-Object {
            [string]$_.type -eq 'branch_policy'
        }).Count -eq 1
$artifactRetentionDays = if ($results.artifact_retention.status -eq 200) {
    [int]$results.artifact_retention.body.days
}
else { 0 }
$maximumArtifactRetentionDays = if ($results.artifact_retention.status -eq 200) {
    [int]$results.artifact_retention.body.maximum_allowed_days
}
else { 0 }
$minimumRetentionSatisfied = $artifactRetentionDays -ge 365 -and
    $maximumArtifactRetentionDays -ge 365
$blockers = [System.Collections.Generic.List[string]]::new()
if (-not $branchProtected) { $blockers.Add('main_unprotected') }
if ($results.protection.status -ne 200) { $blockers.Add('branch_protection_api_unavailable') }
if ($results.protection.status -eq 200 -and -not $branchProtectionContractSatisfied) {
    $blockers.Add('branch_protection_contract_mismatch')
}
if ($collaboratorCount -lt 2) { $blockers.Add('independent_reviewer_unavailable') }
if ($collaboratorCount -lt 3) { $blockers.Add('two_sensitive_reviewers_unavailable') }
if ($matchingUeRunners.Count -eq 0) { $blockers.Add('ue58_ephemeral_runner_unavailable') }
if ($workflowCount -eq 0) { $blockers.Add('hosted_workflows_not_on_default_branch') }
if ($repositoryPublic -and -not $forkApprovalPolicySatisfied) {
    $blockers.Add('public_fork_workflow_approval_not_all_external_contributors')
}
if (-not $p0ReleaseEnvironmentProtected) {
    $blockers.Add('p0_release_environment_missing_or_unprotected')
}
$blockers.Add('locked_builder_not_verified_in_ghcr')
$blockers.Add('hosted_vulnerability_and_license_authority_missing')
$blockers.Add('signed_provenance_and_oci_attestation_missing')
if (-not $minimumRetentionSatisfied) {
    $blockers.Add('minimum_365_day_immutable_retention_missing')
}

$report = [pscustomobject][ordered]@{
    schema_version = 4
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = 'BLOCKED_EXTERNAL_AUTHORITY'
    completion_criteria_satisfied = $false
    release_authority = $false
    provider = [pscustomobject][ordered]@{
        name = 'github'
        repository = $Repository
        visibility = [string]$results.repository.body.visibility
        default_branch = [string]$results.repository.body.default_branch
        viewer_permission = Get-ViewerPermission -Permissions $results.repository.body.permissions
        remote_name = $RemoteName
        remote_url = $remoteUrl
    }
    source = [pscustomobject][ordered]@{
        revision = $head
        branch = $branchName
    }
    branch_authority = [pscustomobject][ordered]@{
        protected = $branchProtected
        protection_api_status = $results.protection.status
        protection_api_message = $results.protection.message
        rulesets_api_status = $results.rulesets.status
        rulesets_api_message = $results.rulesets.message
        contract_satisfied = $branchProtectionContractSatisfied
        required_checks_enforced = $requiredChecksEnforced
        required_status_checks_strict = if ($null -ne $protection) {
            [bool]$protection.required_status_checks.strict
        }
        else { $false }
        required_check_contexts = @($requiredCheckContexts)
        expected_required_check_contexts = @($expectedRequiredChecks)
        pull_request_protection_enforced = $pullRequestProtectionEnforced
        administrator_bypass_forbidden = if ($null -ne $protection) {
            [bool]$protection.enforce_admins.enabled
        }
        else { $false }
        required_approvals = if ($null -ne $protection) {
            [int]$protection.required_pull_request_reviews.required_approving_review_count
        }
        else { 0 }
        dismiss_stale_approvals = if ($null -ne $protection) {
            [bool]$protection.required_pull_request_reviews.dismiss_stale_reviews
        }
        else { $false }
        require_code_owner_review = if ($null -ne $protection) {
            [bool]$protection.required_pull_request_reviews.require_code_owner_reviews
        }
        else { $false }
        require_last_push_approval = if ($null -ne $protection) {
            [bool]$protection.required_pull_request_reviews.require_last_push_approval
        }
        else { $false }
        mutation_protection_enforced = $mutationProtectionEnforced
        force_push_forbidden = if ($null -ne $protection) {
            -not [bool]$protection.allow_force_pushes.enabled
        }
        else { $false }
        deletion_forbidden = if ($null -ne $protection) {
            -not [bool]$protection.allow_deletions.enabled
        }
        else { $false }
        linear_history_required = if ($null -ne $protection) {
            [bool]$protection.required_linear_history.enabled
        }
        else { $false }
        conversation_resolution_required = if ($null -ne $protection) {
            [bool]$protection.required_conversation_resolution.enabled
        }
        else { $false }
    }
    review_authority = [pscustomobject][ordered]@{
        direct_collaborator_count = $collaboratorCount
        one_non_author_approval_possible = $collaboratorCount -ge 2
        two_non_author_approvals_possible = $collaboratorCount -ge 3
        code_owner_file_present = Test-Path -LiteralPath (Join-Path $root '.github/CODEOWNERS')
    }
    actions = [pscustomobject][ordered]@{
        enabled = if ($results.actions_permissions.status -eq 200) {
            [bool]$results.actions_permissions.body.enabled
        }
        else { $false }
        allowed_actions = if ($results.actions_permissions.status -eq 200) {
            [string]$results.actions_permissions.body.allowed_actions
        }
        else { 'unknown' }
        default_workflow_permissions = if ($results.workflow_permissions.status -eq 200) {
            [string]$results.workflow_permissions.body.default_workflow_permissions
        }
        else { 'unknown' }
        fork_pr_contributor_approval_api_status = $results.fork_pr_contributor_approval.status
        fork_pr_contributor_approval_policy = $forkApprovalPolicy
        fork_pr_contributor_approval_policy_satisfied = $forkApprovalPolicySatisfied
        public_repository_runner_registration_authorized = $false
        workflow_count_on_default_branch = $workflowCount
        repository_secret_count = if ($results.secrets.status -eq 200) {
            @($results.secrets.body.secrets).Count
        }
        else { -1 }
        repository_variable_count = if ($results.variables.status -eq 200) {
            @($results.variables.body.variables).Count
        }
        else { -1 }
        artifact_count = if ($results.artifacts.status -eq 200) {
            @($results.artifacts.body.artifacts).Count
        }
        else { -1 }
    }
    runners = [pscustomobject][ordered]@{
        self_hosted_count = @($runnerRecords).Count
        matching_ephemeral_ue58_count = @($matchingUeRunners).Count
    }
    release_environment = [pscustomobject][ordered]@{
        name = 'p0-release'
        api_status = $results.p0_release_environment.status
        present = $null -ne $p0ReleaseEnvironment
        protected_branch_deployments_only = $p0ReleaseEnvironmentProtected
        required_reviewer_count = if ($null -ne $p0ReleaseEnvironment) {
            @($p0ReleaseEnvironment.protection_rules |
                Where-Object { [string]$_.type -eq 'required_reviewers' } |
                ForEach-Object { @($_.reviewers) }).Count
        }
        else { 0 }
    }
    artifact_retention = [pscustomobject][ordered]@{
        api_status = $results.artifact_retention.status
        configured_days = $artifactRetentionDays
        maximum_allowed_days = $maximumArtifactRetentionDays
        minimum_required_days = 365
        requirement_satisfied = $minimumRetentionSatisfied
    }
    local_workflow_binding = [pscustomobject][ordered]@{
        required_checks_workflow_present = Test-Path -LiteralPath (
            Join-Path $root '.github/workflows/p0-required-checks.yml')
        release_provenance_workflow_present = Test-Path -LiteralPath (
            Join-Path $root '.github/workflows/p0-release-provenance.yml')
        diagnostic_artifact_retention_days = 90
        minimum_required_retention_days = 365
    }
    blocker_count = $blockers.Count
    blockers = @($blockers)
}
$json = ($report | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n")
$fullOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $fullOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText(
    $fullOutputPath,
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
