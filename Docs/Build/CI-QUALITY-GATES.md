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

GitHub provider selection and workflow source are no longer pending. Protected
branch enforcement, sufficient independent reviewers, an ephemeral UE 5.8.2
runner, publication of the exact locked builder manifest, approved vulnerability
results, signed provenance/OCI attestation, and 365-day immutable
retention remain blocking P0-12 items. PostgreSQL
Migration is integrated and the source-bound MSVC 14.51 waiver is checked on
every local aggregate run. Local GCC, host clang-tidy, and UE evidence are
valuable diagnostics but cannot close release-authority requirements.

The current private repository plan does not expose branch protection/rulesets;
the read-only API returns HTTP 403 and requires GitHub Pro or a public repository.
The repository also has only one collaborator and zero self-hosted runners.
These facts are captured without credentials in
`Data/Governance/p0-github-hosting-status.json`.

The digest-locked PostgreSQL 18.6 development image now has a local CycloneDX
1.5 SBOM with 77 components: 70 carry embedded license data and the remaining
7 are bound to exact APK or version-pinned upstream evidence. Docker Scout CVE
analysis requires an authenticated database session on this host, so no login
was performed and vulnerability status remains pending. The final builder image
has a local CycloneDX 1.5 SBOM with 343 components: 275 carry embedded license
data and all 51 scanner gaps are bound to hashed copyright/METADATA sources.
`p0-12-license-evidence.json` is therefore component-complete but remains
non-authoritative until the hosted check succeeds. Hosted vulnerability policy
and signed provenance still require the selected CI authority. Application Conan
profile lockfiles begin in P4 with the first real external C++ dependency; an
empty placeholder lock is prohibited.

Private pull-request runs retain the fixed Trivy JSON and database-identity
files for seven days even when vulnerability or license policy fails. This
short-lived diagnostic artifact contains no configured Secret and is evidence
for remediation only; it is not the required 365-day immutable release record.
The identity is generated from the exact cache used by both scans and must
carry Trivy 0.74.0 plus a vulnerability-database `UpdatedAt` no older than 48
hours. A tool-only version string is rejected as incomplete evidence.
