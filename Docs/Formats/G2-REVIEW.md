# G2 review evidence format

P2-20 produces a deterministic, fail-closed review of the nine G2 data exit
criteria. The machine report is
`Data/Reports/p2-20-g2-review-report.json`; its human-readable projection is
`Data/Reports/p2-20-g2-review-report.md`; and the tracked task evidence is
`Data/Inventory/p2-20-g2-review.json`.

## Required status versus observed status

Every policy criterion has `required_status: SATISFIED`. This is the exit
condition and must never be weakened to describe the current repository.
Each report criterion separately records `observed_status`. The current review
has seven `SATISFIED` observations and two `BLOCKED` observations.

`review_execution_result: PASS` means only that evidence binding, evaluation,
Schema validation, and rendering completed. The decision fields remain:

- `result: BLOCKED`
- `task_status: BLOCKED`
- `completion_criteria_satisfied: false`
- `gate_decision: BLOCKED`
- `g2_approved: false`
- `p3_authorized: false`

No consumer may reinterpret successful review execution as a gate pass.

## Current blocking evidence

G2-06 is blocked because the evidence does not define and hash-bind a scoped
core-resource reference set or publish its explicit unresolved, ambiguous, and
heuristic-selection metrics. Those three core metrics must all be zero. The
non-core/global package and nullable table-object queues are risk context, not
the core exit threshold, so future non-zero global queues do not permanently
block G2-06. Core foreign-key dangling count zero is a narrower integrity fact
and cannot replace the missing core-resource proof.

G2-07 is blocked because diff, canonical-ID, fixed-limit, and shared uint64
code-generation audits do not constitute a complete reviewed registry of
migration decisions. The registry must cover ID, width, old-to-new Schema, and
legacy fixed-limit risks.

## Budget semantics

The manual-content rate uses the complete asset population: 800 / 40,090,
floor-rounded to 19,955 parts per million (1.9955%). P2-19 planning hours,
machine projections, and storage figures are planning inputs with explicit
assumptions and reserves. They are not measured delivery time, a financial
total cost, a quote, or a delivery commitment.

## Deterministic reproduction

Run:

```powershell
pwsh -NoProfile -File Tools/TMXY.G2Review/New-G2Review.ps1
pwsh -NoProfile -File Tools/TMXY.G2Review/New-G2Review.ps1 -Check
```

The wrapper verifies the locked non-root builder and runs with a read-only
repository mount, no network, all Linux capabilities dropped, and
`no-new-privileges`. Formal output is written only under `Rebuild`; temporary
generation occurs under the ignored `Data/Local/P2-20` tree and is cleaned.

The JSON Schema is closed at every object level. The report hash-binds P2-01
through P2-19 plus the current local-quality aggregate. It intentionally emits
no private source paths, exact primary keys or observed extrema, raw table rows,
decoded confidential payloads, or legacy source lines.
