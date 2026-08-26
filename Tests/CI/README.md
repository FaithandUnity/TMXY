# CI gate entry points

`Invoke-LocalQualityGates.ps1` is the platform-neutral rehearsal entry point.
It executes repository, Secret, golden-metadata, backend format/tidy, diagnostic
Linux build/CTest, and optional UE Automation checks, then emits one JSON report.

```powershell
pwsh -NoProfile -File .\Tests\CI\Invoke-LocalQualityGates.ps1 `
  -VerifyLegacyGoldenSources `
  -RunUEAutomation
```

A hosted merge/release job must execute the digest-locked Clang 21 build (the
local aggregate already verifies its qualification evidence), publish immutable
logs, enforce the locked-image vulnerability/license policy, and issue signed
provenance. A `PASS_DIAGNOSTIC` report is never release authority.

`Data/Governance/p0-hosted-ci-contract.json` freezes provider-neutral check
names, protected-branch rules, trust/cache boundaries, locked digests, and final
evidence fields. It remains unbound until the project owner authorizes a hosted
provider and repository.
