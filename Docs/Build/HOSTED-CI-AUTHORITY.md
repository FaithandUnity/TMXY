# GitHub hosted CI and release-authority binding

## Current state

GitHub is now the selected provider and `FaithandUnity/TMXY` is the authorized
private repository. The local `origin`, configured identity, `main`, and remote
head are real and synchronized. The provider-neutral contract has therefore
advanced to `github_workflows_prepared_pending_external_authority` in
`Data/Governance/p0-hosted-ci-contract.json`.

The repository now contains two real workflows:

- `.github/workflows/p0-required-checks.yml` maps all eight stable merge checks;
- `.github/workflows/p0-release-provenance.yml` is a protected, explicitly
  dispatched signing and OCI-attestation workflow.

`Tests/CI/Test-HostedWorkflowContract.ps1` enforces the mapping, immutable action
revisions, locked builder digest, untrusted-change permissions, protected-only
cache writes, ephemeral UE runner labels, and release signing boundary.
`Tools/TMXY.GitHub/Get-GitHubHostedCIStatus.ps1` performs a read-only GitHub API
audit and writes the sanitized result to
`Data/Governance/p0-github-hosting-status.json`.

This is real source-side onboarding, not hosted release authority. The current
GitHub observation is `BLOCKED_EXTERNAL_AUTHORITY` and must remain so while any
condition below is missing.

## Verified external blockers on 2026-08-27

- `main` is not protected and required checks are not enforced.
- GitHub returns HTTP 403 with “Upgrade to GitHub Pro or make this repository
  public to enable this feature” for both branch protection and rulesets.
- The repository has one direct collaborator, so neither one non-author approval
  nor two sensitive-change approvals can currently be satisfied.
- No self-hosted runner exists; the required ephemeral Windows x64 UE 5.8.2
  runner is unavailable.
- The locked Clang 21 builder has not been verified at the frozen digest in
  GHCR, so hosted backend jobs fail closed instead of rebuilding another image.
- Hosted vulnerability/license authority, signed provenance, OCI attestation,
  and immutable 365-day evidence retention do not yet exist.
- The default branch has no workflows until this feature branch is reviewed and
  merged; local YAML or a feature-branch run cannot replace protected-main
  evidence.

## Trust and cache behavior

Pull requests receive no configured repository Secret and no release write
permissions. Checkout credentials are not persisted. Backend caches use a key
containing OS, architecture, preset, toolchain lock hash, dependency lock hash
when present, and source revision. Pull requests may restore a trusted cache,
but only an API-confirmed protected `main` push may save it. Every hit still
reconfigures, builds, analyzes, scans, and tests.

The UE job requires the labels
`self-hosted/Windows/X64/tmxy-ue58/tmxy-ephemeral`; this deliberately prevents an
untrusted change from running on a persistent developer workstation or writing
a shared DDC. No compatible runner currently exists.

## Authorized completion sequence

The following operations change online governance or release authority and
require project-owner confirmation before execution:

1. upgrade the GitHub plan or approve making the repository public;
2. add enough independent reviewers and configure `main` protection/rulesets
   with the frozen eight checks, Code Owner review, stale-approval dismissal,
   no administrator bypass, and no force push/deletion;
3. register an ephemeral UE 5.8.2 Windows x64 runner;
4. publish the already-qualified builder manifest to GHCR without rebuilding,
   and verify the exact digest;
5. approve the vulnerability database and component-specific license policy;
6. protect the `p0-release` environment, run signed provenance/OCI attestation,
   and provide immutable evidence storage for at least 365 days;
7. record provider-generated rule, run, artifact, database, policy, and
   provenance identities, rerun local gates, and regenerate P0 readiness.

No Secret value, registry credential, signing material, or TBL key may enter a
command line, workflow source, report, cache, artifact name, or Git history.
Local `PASS_DIAGNOSTIC`, a queued job, a screenshot, or manually edited JSON is
never accepted as hosted authority.
