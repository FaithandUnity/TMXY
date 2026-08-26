# CI gate entry points

`Invoke-LocalQualityGates.ps1` is the platform-neutral rehearsal entry point.
It executes repository, Secret, golden-metadata, backend format/tidy, diagnostic
Linux build/CTest, and optional UE Automation checks, then emits one JSON report.

```powershell
pwsh -NoProfile -File .\Tests\CI\Invoke-LocalQualityGates.ps1 `
  -VerifyLegacyGoldenSources `
  -RunUEAutomation
```

A GitHub merge workflow now maps the eight frozen check names. It uses a
digest-addressed GHCR builder reference, protected-main-only cache writes,
networkless/read-only builder execution, a real PostgreSQL 18 migration,
fail-closed SBOM vulnerability/license policy, and an ephemeral UE 5.8.2 runner
label. The separate protected release workflow issues GitHub signed provenance
and an OCI registry attestation only after the external authority prerequisites
exist. A `PASS_DIAGNOSTIC` report is never release authority.

`Data/Governance/p0-hosted-ci-contract.json` freezes the GitHub binding, check
names, protected-branch rules, trust/cache boundaries, locked digests, and final
evidence fields. `Data/Governance/p0-github-hosting-status.json` records the
current external blockers without storing credentials.
