# Public-repository self-hosted UE runner security

## Decision

Repository-level self-hosted runner registration is **not authorized** while
`FaithandUnity/TMXY` is public. GitHub warns that a public fork can propose and
run dangerous workflow code on a self-hosted machine. The current absence of a
runner is therefore a safety control, not merely missing capacity.

The base required-check workflow now applies defense in depth:

- a fork pull request cannot schedule `client/ue58-execution`;
- the GitHub-hosted `client/ue58-build-automation` check still runs and fails
  closed for that fork instead of remaining pending or reporting an untested
  success;
- a same-repository pull request must receive a successful isolated UE result;
- a missing, cancelled, skipped, or failed UE result fails the stable check.

A pull request can modify its own workflow definition. Consequently this base
workflow guard is **not registration authority** and must never be used as the
sole reason to attach a persistent machine to the public repository.

## Required evidence before any registration

All conditions below require a separate owner authorization and machine-readable
evidence before `Get-GitHubHostedCIStatus.ps1` may stop blocking the runner:

1. GitHub fork workflow approval is `all_external_contributors`; approval of a
   run is never delegated to code from the pull request.
2. Every job receives a newly created disposable VM and teardown is verified.
   A developer workstation, long-lived VM, or reused runner is prohibited.
3. The VM contains no persistent Secret, SSH key, registry credential, browser
   session, signing key, source outside this repository, or reusable token.
4. Network policy denies internal services, cloud metadata, developer LANs,
   private registries, and all destinations not required by the reviewed job.
5. The runner has no writable shared DDC/cache or host mount. Inputs are
   immutable; outputs are isolated and treated as untrusted until verified.
6. `GITHUB_TOKEN` remains least-privilege read-only, checkout credentials are
   not persisted, and no repository/environment Secret is injected.
7. The runner is dedicated to this repository and the reviewed workflow; an
   organization/enterprise runner group must restrict both where available.
8. Creation, registration, single-job execution, teardown, disk destruction,
   network policy, source SHA, workflow SHA, and result are recorded without
   credentials and retained under the release evidence policy.

If those controls cannot be proved, use a GitHub-hosted or separately brokered
disposable build service, or obtain explicit authorization for a different
repository visibility/hosting design. Do not weaken the required check.

## Current external observation

The authenticated API currently reports:

- repository visibility: public;
- fork workflow approval: `first_time_contributors`;
- matching UE runner count: zero;
- public runner registration authorization: false.

Therefore `public_fork_workflow_approval_not_all_external_contributors` and
`ue58_ephemeral_runner_unavailable` remain explicit hosted-authority blockers.

Primary references:

- <https://docs.github.com/en/actions/reference/security/secure-use>
- <https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners>
- <https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks>
