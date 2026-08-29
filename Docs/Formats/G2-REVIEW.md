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

G2-06 now has a hash-bound monotonic core-resource scope and explicit reference,
asset-binding, conditional-required, and structure metrics. P2-20A.4 separately
revalidates 3,651 high-risk targets and 12,764 exact candidate edges through full
semantic signatures and production binders. Its reconciliation supersedes the
coarse descriptor counts for the G2 decision: the complete 21,494-target workset
contains 21,460 resolved, 15 ambiguous, and 19 unresolved targets. The frozen
coarse workset remains the audit baseline, and no candidate is selected. P2-20A.3 also
hash-binds all 212 auxiliary configuration instances and their lexical
candidates: 171 remain candidate-only, 35 editor-undecided, and 6
malformed-blocked; approved semantic adapters, no-reference dispositions, and
roots are all zero. The scoped queues remain nonzero, so the exit still fails
closed. Lexical candidates are not semantic approvals. Core foreign-key
dangling count zero is a narrower integrity fact and cannot replace these
resource-closure facts.

P2-20A.6 independently joins all 15 A.4 ambiguous targets and 30 candidate edges
to P2-03 identity hashes. Thirteen targets and 26 edges collide under ASCII-lower
identity grouping, while the remaining 2/4 do not; strict descriptor and full
semantic equivalence are both zero. A.6 therefore selects no candidate and
retains all 15/30 ambiguous plus 19/24 unresolved states. Identity grouping is
not runtime-selection or semantic-equivalence authority.

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
