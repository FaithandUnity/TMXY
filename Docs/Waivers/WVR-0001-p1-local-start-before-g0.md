# WVR-0001: P1 local development before G0

> Status: Active, time bounded  
> Approved: 2026-08-26 07:30 Asia/Shanghai  
> Expires: 2026-09-25 23:59:59 Asia/Shanghai  
> Approver: Project lead  
> Execution owner: Codex

## Decision

The project lead explicitly directed development to continue without waiting
for Git identity, a remote repository, or hosted CI, with progress protected by
verified local backups. This waiver permits P1-01 through P1-27 to produce local
source, tests, evidence, and small golden outputs whose other prerequisites are
satisfied.

The normal start gate remains `G0_READY_AND_P0_16_APPROVED`. This waiver does
not complete P0-12/P0-16, approve G0 or G1, authorize a remote/push/login, or
turn local diagnostics into release authority. P1-28 and the G1 decision remain
outside its scope.

## Hard boundaries

- Legacy directories remain read-only; only evidence-based reads are allowed.
- All code, reports, tests, and backups stay under `Rebuild`, except the two
  authorized root implementation-plan documents.
- Parsers must reject truncation and out-of-bounds access deterministically.
- Secret, rights, evidence-level, unknown-field, and no-bulk-import rules remain
  mandatory.
- No bulk UE import may begin before G1.
- Local backups must carry file hashes and archive verification.

The machine contract is `Data/Governance/p1-local-start-waiver.json` and is
validated by `Tests/Contract/Test-P1ExecutionCharter.ps1`. Expiry or any listed
invalidation condition stops the local-start authorization automatically.

## 2026-08-27 clarification

The project lead subsequently authorized the existing GitHub repository,
configured identity, safe fetch, a P0-12 feature branch, workflow commits, push,
and pull-request evidence for `FaithandUnity/TMXY`. That later authorization
supersedes this waiver's remote/login prohibition only for P0-12 GitHub CI
onboarding. It does not extend the P1 scope, disclose a Secret, authorize branch
protection/plan/publicity/runner/signing changes, or approve G0/G1.
