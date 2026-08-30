# P0/G0 readiness review

## Decision

Current result: **NOT READY**. P0 has 17/19 completed items and 10/11 machine
readiness checks pass. P0-16 must not be
marked complete and G0 must not pass until the machine-readable review reports
zero blockers.

The review generator is `Tests/Review/New-P0ReadinessReport.ps1`; evidence is
`Data/BuildBaseline/p0-readiness.json`. Local source, security, migration,
locked Clang 21 builder, static-analysis, backend, golden-source, and UE
Automation checks are passing. Local success is not hosted release authority.

## Open decisions and external actions

1. P0-12: GitHub and `FaithandUnity/TMXY` are now authorized and the eight
   required workflow names, CODEOWNERS, cache trust boundary, locked builder,
   PostgreSQL, SBOM scan, UE runner labels, and provenance workflow exist in
   source. Public visibility and the exact protected-`main` contract are now
   API-verified. Fork approval is now strict for all external contributors and
   `p0-release` accepts protected branches only. A derived PostgreSQL 18.6
   candidate is locally qualified with zero direct-image/SBOM HIGH or CRITICAL
   findings, zero reachable `govulncheck` findings, and a passing real
   migration. The remaining external actions are to add enough independent
   reviewers, register an ephemeral UE 5.8.2 runner, provide a
   `write:packages` credential and publish the unchanged builder and derived
   PostgreSQL manifests to GHCR, approve hosted vulnerability/license evidence,
   issue signed provenance/OCI attestation, and retain immutable evidence for
   365 days outside the account's observed 90-day maximum.
2. P0-16/G0: after that authority check passes, record the final review
   decision against the already frozen P1 execution charter.

The real `origin` and developer identity were verified and a conforming P0-12
feature branch is in use. The project owner changed the repository to public
and explicitly authorized the exact branch protection and remaining hosted
authority work. The main rule, strict fork approval, and protected release
environment were applied and verified. The current credential cannot publish
packages, GitHub rejected 365-day retention because the account maximum is 90,
and no collaborator, runner, Secret, registry package, or signed release was
fabricated. TLS was not disabled and no unknown mirror or image was substituted.
The sanitized API evidence is
`Data/Governance/p0-github-hosting-status.json`.

## Evidence already accepted by the generator

- copyright/read-only boundary and frozen input Manifest;
- final architecture and engineering standard;
- UE 5.8.2 build/module/Automation baseline;
- source-bound UE 5.8.2 MSVC 14.51 Development/Shipping packaging waiver;
- official Debian digest, exact Clang 21 revision, immutable backend builder,
  clean-builder reproduction, 2/2 CTest and 314-component SBOM;
- 42 reference-only golden samples;
- frozen client/backend performance and recovery budget;
- Git root constrained to `Rebuild`;
- GitHub provider/remote binding and source-side mapping of all eight stable
  checks, while current hosted authority accurately remains false;
- PostgreSQL 18.6 empty-database V0001 migration test;
- locally qualified PostgreSQL 18.6/gosu 1.19 candidate, final-filesystem
  CycloneDX SBOM, direct/SBOM Trivy scans with zero HIGH/CRITICAL findings,
  zero-result `govulncheck`, real migration, and verified local image archive;
- operating-system-keychain Secret Store rotation/revocation drill;
- local Secret scan, format/tidy, diagnostic Linux build, CTest, SBOM, and UE
  aggregate gates.
