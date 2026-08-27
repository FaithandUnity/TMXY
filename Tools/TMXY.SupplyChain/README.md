# TMXY.SupplyChain

`Test-LocalImageEvidence.ps1` validates the locally locked PostgreSQL and Linux
backend-builder images plus both CycloneDX SBOMs without mutating registries or
credentials. The current SBOMs contain 77 and 343 components respectively; the
builder SBOM hash and component count are bound to `toolchain.lock.json`.

`New-LicenseEvidence.ps1` verifies both locked local image IDs, hashes the
installed Debian/APK copyright or Python metadata for scanner gaps, verifies
version-pinned upstream license files, and writes the component-complete
`p0-12-license-evidence.json`. The manifest covers 77/77 PostgreSQL and 343/343
builder components, is bound by the hosted contract, and explicitly does not
claim release authority.

`New-HostedVulnerabilitySummary.ps1` reduces the hosted Trivy JSON to a
reviewable, secret-free finding inventory while preserving hashes of both raw
reports, the exact source revision and GitHub run, and the database identity.
It fails closed unless the identity includes scanner/database versions plus
`UpdatedAt` and `DownloadedAt`; the raw reports remain short-lived artifacts.

Vulnerability analysis is deliberately reported as pending because Docker Scout
requires an authenticated vulnerability database session on this host. The tool
never performs `docker login` and never upgrades diagnostic evidence to release
authority. Application Conan profile lockfiles are created in P4 when a real
external C++ dependency first exists, rather than inventing an empty P0 lock.
