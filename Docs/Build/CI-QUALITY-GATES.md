# CI quality gates and cache contract

## Required merge gates

Every merge candidate runs repository boundaries, UTF-8/LF and size limits,
Secret working-tree/history scanning, golden metadata integrity, format,
clang-tidy, Linux Clang 21 configure/build/CTest, PostgreSQL integration,
contract/architecture tests, dependency/license/vulnerability scanning, SBOM,
UE build/Automation for client-impacting changes, and validity of any active
toolchain waiver. Release jobs additionally require immutable OCI digests and
signed provenance.

`Tests/CI/Invoke-LocalQualityGates.ps1` rehearses all currently executable gates
and deliberately reports `PASS_DIAGNOSTIC`. GitHub and
`FaithandUnity/TMXY` are now bound, and `.github/workflows/p0-required-checks.yml`
maps every frozen check name. The source contract is validated by
`Tests/CI/Test-HostedWorkflowContract.ps1`; only a successful protected hosted
run may issue release evidence.

## Cache keys and trust boundary

Cache keys include operating system, architecture, compiler identity, CMake
preset, `toolchain.lock.json` SHA-256, dependency lock SHA-256, and source
revision. A restore-key prefix may omit only the source revision. Cache hits
must never bypass configure, dependency verification, tests, or scanning.

- Untrusted pull requests receive read-only or isolated caches and cannot write
  release caches.
- Secret files, `.env`, logs, test credentials, signing material, reports with
  sensitive inputs, and container auth never enter a cache.
- CMake/Ninja outputs and dependency downloads may be cached after integrity
  validation.
- UE DDC may use a separate access-controlled cache keyed by engine changelist,
  target platform, RHI, content/tool version, and source hash; DDC never enters
  Git or Git LFS.
- Cache corruption causes a clean rebuild, not a waiver.

## Pending authority

GitHub provider selection, workflow source, public visibility, and the exact
protected-`main` contract are no longer pending. Sufficient independent
reviewers, an ephemeral UE 5.8.2 runner, publication of the exact locked builder
and locally qualified PostgreSQL manifests, hosted approval of their
vulnerability results, signed provenance/OCI attestation, and external
365-day immutable retention remain blocking P0-12 items. PostgreSQL
Migration is integrated and the source-bound MSVC 14.51 waiver is checked on
every local aggregate run. Local GCC, host clang-tidy, and UE evidence are
valuable diagnostics but cannot close release-authority requirements.

The repository is public and the read-only API now proves HTTP 200 branch
protection with all eight strict checks, PR/CODEOWNERS review, stale-review
dismissal, last-push approval, administrator enforcement, and force-push/delete
prohibition. It still has only one collaborator and zero self-hosted runners.
Fork workflow approval is now `all_external_contributors`. The disposable
isolation contract must still be proven before runner registration. The base workflow prevents fork
PRs from scheduling UE execution and makes the stable hosted check fail closed,
but that guard is not sufficient registration authority because PR workflow
source is attacker-controlled.
These facts are captured without credentials in
`Data/Governance/p0-github-hosting-status.json`.

The digest-locked PostgreSQL 18.6 development image now has a local CycloneDX
1.5 SBOM with 77 components: 70 carry embedded license data and the remaining
7 are bound to exact APK or version-pinned upstream evidence. Hosted Trivy
evidence currently blocks the PostgreSQL image on 22 HIGH/CRITICAL findings.
The exact Docker Hub tag refresh preflight is byte-stable when the normalized
upstream observation and its bound inputs are unchanged. This prevents a
timestamp-only rewrite from invalidating the downstream official-candidate,
reachability, and waiver hashes; changed upstream semantics still produce new
evidence and require full qualification.
The explicitly authorized derived image retains that exact base, rebuilds gosu
1.19 from a SHA-256-bound source archive using Go 1.26.7, and pins Alpine
`libcrypto3`/`libssl3` to 3.5.8-r0. Its local OCI ID is
`sha256:cf86acb2941d1703c8b21cc51722d200b7d6b0cf01398a45b01d58f649f5ae5b`.
Direct-image and final-filesystem-SBOM Trivy 0.74.0 scans both report zero
HIGH/CRITICAL findings, `govulncheck` reports zero results, and PostgreSQL 18.6
migration validation passes. This is a locally qualified candidate, not release
authority: the exact manifest must still be published and hosted-qualified
before the lock or Compose reference changes.
The locked `gosu` binary now also has a source- and binary-bound reachability
review. Official `govulncheck v1.7.0` binary-mode SARIF maps all 22 blockers:
zero symbol-reachable, one package-only, and 21 module-only results. The one
package-only result is `GO-2026-4970` in `os`; its official OSV symbol set, the
root-only PostgreSQL entrypoint invocation, and the tagged `gosu` source are
bound by SHA-256. This lowers the assessed reachability but does not prove
absence, waive the hosted severity policy, update the image lock, or grant merge
or release authority. A component waiver still requires explicit owner approval
and a time bound after this review.

`WVR-0002` packages that possible component-only decision without approving it.
`Test-PostgresGosuWaiverDecision.ps1` binds the exact request bytes to the locked
image, `gosu` binary, all 22 hosted findings, reachability evidence, candidate
evaluation, toolchain lock, and Compose file. The checked-in request remains a
non-effective draft. Activation requires a current interval of at most 30 days
and an authenticated GitHub read of the exact PR HEAD with at least two unique
non-author approvals. An owner-authored PR requires explicit owner intent in
the exact request plus two other reviewers; otherwise the owner must be one of
the current-HEAD reviewers. Stale approvals fail closed.
Offline fixtures can validate structure but can never activate the exception,
and no waiver result grants merge, gate, or release authority.
The final builder image has a local CycloneDX 1.5 SBOM with 314 components: 266
carry embedded license data and all 48 scanner gaps are bound to hashed
copyright/METADATA sources. pip and setuptools are build-only bootstrap tools
and are removed after Conan installation so their vendored packages do not ship.
`p0-12-license-evidence.json` is therefore component-complete but remains
non-authoritative until the hosted check succeeds. Hosted vulnerability policy
and signed provenance still require the selected CI authority. Application Conan
profile lockfiles begin in P4 with the first real external C++ dependency; an
empty placeholder lock is prohibited.

Pull-request runs retain the fixed Trivy JSON and database-identity
files for seven days even when vulnerability or license policy fails. This
short-lived diagnostic artifact contains no configured Secret and is evidence
for remediation only; it is not the required 365-day immutable release record.
The identity is generated from the exact cache used by both scans and must
carry Trivy 0.74.0 plus a vulnerability-database `UpdatedAt` no older than 48
hours, plus the corresponding `DownloadedAt`. A tool-only version string is
rejected as incomplete evidence.
The repository retention API reports 90 configured days and a 90-day account
maximum; GitHub rejected the authorized 365-day request with HTTP 409. The
protected `p0-release` environment now exists and accepts deployments only from
protected branches, but 365-day authority evidence therefore requires a
separate immutable evidence store or an account capability change.
