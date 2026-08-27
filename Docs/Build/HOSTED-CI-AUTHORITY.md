# GitHub hosted CI and release-authority binding

## Current state

GitHub is now the selected provider and `FaithandUnity/TMXY` is the authorized
public repository. The local `origin`, configured identity, `main`, and remote
head are real. The provider-neutral contract has therefore
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

## Verified hosted state on 2026-08-28

- `main` is protected and the protection API returns HTTP 200. Strict status
  checks contain exactly the eight frozen contexts.
- Pull requests, CODEOWNERS, stale-review dismissal, last-push approval, one
  approval, administrator enforcement, linear history, and conversation
  resolution are enabled. Force pushes and deletion are disabled.
- The repository has one direct collaborator, so neither one non-author approval
  nor two sensitive-change approvals can currently be satisfied.
- No self-hosted runner exists; the required ephemeral Windows x64 UE 5.8.2
  runner is unavailable.
- Public fork workflow approval is `all_external_contributors`, satisfying the
  source-side policy required before any future isolated runner path.
- The locked Clang 21 builder has not been verified at the frozen digest in
  GHCR, so hosted backend jobs fail closed instead of rebuilding another image.
- A source-built PostgreSQL 18.6 candidate with gosu 1.19/Go 1.26.7 is locally
  qualified at image ID
  `sha256:cf86acb2941d1703c8b21cc51722d200b7d6b0cf01398a45b01d58f649f5ae5b`:
  direct-image and final-filesystem SBOM scans each report zero
  HIGH/CRITICAL findings, `govulncheck` reports zero reachable findings, and
  the real migration passes. It is not release authority until the exact
  manifest is published and verified in the protected registry path.
- The `p0-release` environment is protected so only protected branches may
  deploy. GitHub Actions retention is configured at the provider/account
  maximum of 90 days; GitHub rejected 365 days with HTTP 409, so hosted
  vulnerability/license authority, signed provenance, OCI attestation, and an
  external immutable evidence store covering at least 365 days remain missing.
- The default branch exposes the required workflow, but the current protected
  checks cannot all pass until the remaining infrastructure and policy blockers
  are resolved.

## Trust and cache behavior

Pull requests receive no configured repository Secret and no release write
permissions. The merge workflow grants only read access to source, pull-request
metadata, and the locked GHCR package; checkout credentials are not persisted.
Backend caches use a key containing OS, architecture, preset, toolchain lock
hash, dependency lock hash when present, and source revision. Pull requests may
restore a trusted cache, but only an API-confirmed protected `main` push may save
it. Every hit still reconfigures, builds, analyzes, scans, and tests.

The UE execution job requires the labels
`self-hosted/Windows/X64/tmxy-ue58/tmxy-ephemeral`. Fork pull requests skip that
execution before runner scheduling, while a separate GitHub-hosted stable check
fails closed rather than reporting untested success. No compatible runner
currently exists. This workflow guard is defense in depth only because a pull
request can modify workflow source; it does not authorize registering a runner.
The mandatory isolation contract is
`Docs/Build/PUBLIC-SELF-HOSTED-RUNNER-SECURITY.md`.

## Authorized completion sequence

Repository visibility, the exact `main` protection contract, strict fork
approval, protected release environment, registry publication/signing work,
and 365-day evidence retention were explicitly authorized on 2026-08-28. Fork
approval and the release environment were applied. The remaining work now
depends on identities, infrastructure, credential scope, or provider features
that authorization alone cannot create:

1. add enough independent reviewers to satisfy ordinary and sensitive-change
   review policy;
2. provision a disposable-per-job UE 5.8.2 Windows x64 execution boundary that
   satisfies the public-runner security contract;
3. provide a credential with `write:packages`, publish the already-qualified
   builder and PostgreSQL manifests to GHCR without rebuilding, and verify their
   exact digests;
4. approve the vulnerability database and component-specific license policy;
5. run signed provenance/OCI attestation through the protected `p0-release`
   environment and provide external immutable evidence storage for at least
   365 days;
6. record provider-generated run, artifact, database, policy, and
   provenance identities, rerun local gates, and regenerate P0 readiness.

Because the repository is public, no self-hosted runner may be registered until
its ephemeral isolation and fork-pull-request threat controls are reviewed.

No Secret value, registry credential, signing material, or TBL key may enter a
command line, workflow source, report, cache, artifact name, or Git history.
Local `PASS_DIAGNOSTIC`, a queued job, a screenshot, or manually edited JSON is
never accepted as hosted authority.
