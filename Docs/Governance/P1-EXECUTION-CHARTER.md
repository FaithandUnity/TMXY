# P1 execution charter

## Ownership and duration

Codex is the engineering execution owner for P1. The project lead remains the
acceptance and scope owner. The frozen duration is 4–8 weeks, matching the
implementation plan; evidence is reviewed weekly and the phase closes only at
P1-28/G1.

The machine authority is `Data/Governance/p1-resourcing.json`. It assigns every
P1 task to one of four real workstreams: bounded binary foundation, Package/TBL
proof, five resource-format proofs, and the UE golden-test host.

## Experiment boundaries

P1 may read authorized legacy inputs but cannot write them, copy bulk payloads
into Git, place Secrets in source/logs/reports, introduce legacy runtime
dependencies, or begin bulk UE import. Parsers must enforce bounds, preserve
unknown fields, attach evidence levels, and reproduce results from frozen sample
hashes.

Work stops immediately on source-integrity mismatch, security/rights boundary
violation, out-of-bounds acceptance, irreproducible sample results, or attempted
bulk import before G1. A stop condition is investigated and reviewed; it is not
silently waived.

## Start gate

This charter prepares resources only. P1 implementation starts after the
machine readiness report reaches `READY_FOR_G0_REVIEW` and P0-16 records the G0
decision.

The project lead's 2026-08-26 instruction to defer Git/hosted CI and continue
development is recorded as the time-bounded local-only waiver `WVR-0001`.
While it is active, P1-01 through P1-27 may produce local source, tests, evidence,
and verified backups when their other dependencies are satisfied. It cannot
complete P0-12/P0-16, approve G0/G1, authorize remote operations, or create
release authority. P1-28 remains gated by the normal start condition.

On 2026-08-28 the project lead separately authorized P1-28 and the G1 technical
format-gate decision after P1-01 through P1-27 completed. The bounded machine
record is `Data/Governance/p1-g1-stage-authorization.json`. It supersedes
WVR-0001 only for P1-28/G1 and does not approve G0, complete P0-12/P0-16, create
release authority, loosen Secret handling, or permit writes to legacy inputs.
