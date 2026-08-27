# TMXY.SupplyChain

`Test-LocalImageEvidence.ps1` validates the locally locked PostgreSQL and Linux
backend-builder images plus both CycloneDX SBOMs without mutating registries or
credentials. The current SBOMs contain 77 and 314 components respectively; the
builder SBOM hash and component count are bound to `toolchain.lock.json`.

`New-LicenseEvidence.ps1` verifies both locked local image IDs, hashes the
installed Debian/APK copyright or Python metadata for scanner gaps, verifies
version-pinned upstream license files, and writes the component-complete
`p0-12-license-evidence.json`. The manifest covers 77/77 PostgreSQL and 314/314
builder components, is bound by the hosted contract, and explicitly does not
claim release authority.

`New-HostedVulnerabilitySummary.ps1` reduces the hosted Trivy JSON to a
reviewable, secret-free finding inventory while preserving hashes of both raw
reports, the exact source revision and GitHub run, and the database identity.
It fails closed unless the identity includes scanner/database versions plus
`UpdatedAt` and `DownloadedAt`; the raw reports remain short-lived artifacts.

`Test-PostgresRefreshPreflight.ps1` performs one read-only HTTPS observation of
the exact official `postgres:18.6-alpine` Docker Hub tag, validates the response,
and compares its index digest with the disposition, toolchain lock, and compose
binding. It never pulls, changes a lock, or grants release authority. A changed
tag is reported only as a candidate that still requires SBOM, hosted
vulnerability, migration, and review qualification. The offline regression
test covers unchanged, byte-identical repeat, changed, and malformed upstream
responses. A byte-identical repeat preserves the existing report bytes so a
time-only rewrite cannot invalidate downstream candidate and waiver bindings.

`Test-PostgresOfficialCandidate.ps1` qualifies a separately tagged official
PostgreSQL candidate far enough to reject obvious non-remediations without
changing the lock. It binds the Docker Hub index and linux/amd64 manifest,
runs isolated probes of both immutable local images, and compares the affected
`gosu` binary by SHA-256. Byte-identical candidates inherit the recorded hosted
blocker without being misrepresented as a new vulnerability scan. Changed bytes
still require SBOM, hosted scanning, migration tests, full gates, and review.
Its offline regression covers identical, changed, and malformed probe evidence.

`New-PostgresGosuReachabilityReview.ps1` binds the exact locked `gosu` bytes and
Go build metadata to an official `govulncheck v1.7.0` binary-mode SARIF scan,
the official `GO-2026-4970` OSV package/symbol record, the PostgreSQL entrypoint,
and the tagged `gosu` source. The current review maps all 22 hosted blockers:
0 symbol-reachable, 1 package-only, and 21 module-only. This reduces the assessed
reachability but deliberately keeps the hosted policy blocking; it cannot create
a waiver, owner approval, lock update, merge authority, or release authority.
Its offline regression also proves that a reachable symbol stays blocking and a
missing mapped result fails closed.

Hosted Trivy evidence is the vulnerability-policy input. The recorded
PostgreSQL result remains blocked on 22 HIGH/CRITICAL findings; a new hosted run
must verify the 314-component builder after build-only pip/setuptools removal.
Local Docker Scout still requires authentication, so the tools never perform
`docker login` or upgrade local diagnostics to release authority. Application
Conan profile lockfiles are created in P4 when a real external C++ dependency
first exists, rather than inventing an empty P0 lock.
