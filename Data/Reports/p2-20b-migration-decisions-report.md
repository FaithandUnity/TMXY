# P2-20B G2-07 Migration Decision Registry

- Generation: `PASS`
- Registry result: `BLOCKED`
- G2-07 satisfied: `false`
- Enumerated units: 1359 / 1359
- Pending decisions: 1359
- Approved decisions: 0

The generator enumerated anonymous decision subjects. Every machine suggestion remains a suggestion; no decision or approval was inferred.

## Coverage

| Subject | Units |
| --- | ---: |
| Schema table | 52 |
| Schema reference | 12 |
| Canonical ID domain | 12 |
| ID component | 16 |
| Fixed-limit signal | 1267 |

Reference membership was deterministically enumerated from the frozen read-only legacy headers and the P2-09-bound core registry; names and paths are not emitted.

## Fail-closed status

Coverage complete: `true`. Decisions complete: `false`. Approvals complete: `false`.

G2-07 remains blocked until every active subject has a chosen action, migration and rollback evidence where required, and independently verifiable approval from the required role. Candidate text, a self-asserted approver field, or an aggregate count cannot close the gate.

## Hard boundaries

Numeric IDs may not be narrowed from uint64; string IDs may not be converted implicitly to numbers; observed modes are not authoritative defaults; Tombstones may not be reused; and legacy fixed limits may not be copied without classification and rationale.

This registry does not approve G2, authorize P3, grant release authority, or claim restoration of an unavailable official server implementation.
