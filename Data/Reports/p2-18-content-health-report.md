# P2-18 Full Content Health Report

Result: `PASS_WITH_OPEN_CONTENT_RISKS`. This proves complete accounting, not a playable or release-ready build.

## Coverage

| Population | Complete/valid | Total | Rate |
|---|---:|---:|---:|
| Recognized Packages | 163 | 163 | 100.00% |
| Core Packages | 12 | 12 | 100.00% |
| Active tables | 225 | 225 | 100.00% |
| Classified assets | 40,090 | 40,090 | 100.00% |
| Structurally valid assets | 39,290 | 40,090 | 98.00% |
| Assets with ready conversion key | 39,290 | 40,090 | 98.00% |

## Integrity and unresolved work

- Damaged or isolated source artifacts: 20 (14 corrupt assets and 6 isolated XML files).
- Opaque Package object payloads: 121,715; these are preserved spans, not parse failures.
- Package references: 1,076 unresolved and 21,146 ambiguous of 147,349.
- Core foreign-key dangling references: 0 of 54,561 canonical edges.
- Optional table-object references: 5,161 unresolved and 6,945 ambiguous of 113,484.
- Manual conversion assets: 800; blocked cache jobs: 800.
- Planning coefficient: 1,404.695 human hours and 108,005 machine seconds; this is not a schedule commitment.

## Risk register

| ID | Severity | State | Count | Unit | Next task |
|---|---|---|---:|---|---|
| CHR-001 | high | open | 1,076 | package edges | P2-20 |
| CHR-002 | high | open | 21,146 | package edges | P2-20 |
| CHR-003 | high | open | 786 | assets | P3-04 |
| CHR-004 | high | open | 14 | assets | P3-04 |
| CHR-005 | medium | controlled-open | 121,715 | Package object payloads | P4-01 |
| CHR-006 | medium | open | 5,161 | nullable table-object references | P2-20 |
| CHR-007 | medium | open | 6,945 | nullable table-object references | P2-20 |
| CHR-008 | medium | review-only | 1,008 | assets | P2-20 |
| CHR-009 | medium | review-only | 905 | assets | P2-20 |
| CHR-010 | high | open | 800 | assets | P3-04 |
| CHR-011 | high | controlled-open | 5 | ID components | P4-22 |
| CHR-012 | medium | review-only | 6 | XML files | P3-03 |
| CHR-013 | low | review-only | 33,629 | assets | P3-04 |

## Decision boundary

P2-18 is complete because every upstream population and risk is accounted for and hash-bound. G2 remains unapproved, all-content conversion remains incomplete, automatic repair or deletion remains forbidden, and no playable experience or release authority is claimed.

Input binding SHA-256: `93617e5c9455bd035a83eefcaefd9a41c895547d312ae96bdf67e6526c939b0b`.
