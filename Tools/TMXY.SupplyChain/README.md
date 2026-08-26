# TMXY.SupplyChain

`Test-LocalImageEvidence.ps1` validates the locally locked PostgreSQL and Linux
backend-builder images plus both CycloneDX SBOMs without mutating registries or
credentials. The current SBOMs contain 77 and 316 components respectively; the
builder SBOM hash and component count are bound to `toolchain.lock.json`.

Vulnerability analysis is deliberately reported as pending because Docker Scout
requires an authenticated vulnerability database session on this host. The tool
never performs `docker login` and never upgrades diagnostic evidence to release
authority. Application Conan profile lockfiles are created in P4 when a real
external C++ dependency first exists, rather than inventing an empty P0 lock.
