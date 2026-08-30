# P2-20A.10 ECF parser-parity diagnostic

Result: **BLOCKED** / diagnostic execution: **PASS**.

- Frozen P2-20A.5 history: 61/64 parity, 3 differences, and a net legacy-minus-A.3 pair-count delta of 4.
- Frozen A.3 output versus source-derived legacy reference: 51/64 parity and 13 differences.
- Correct plaintext, A.3 filter versus legacy pair parser: 63/64 parity and 4 legacy pair records absent from A.3.
- Both independent reference transform and pair-parser ports agree on all 64 instances; this is source-derived diagnostic parity only.
- Legacy runtime executed: no. Runtime binary parity claimed: no. A.3 outputs modified: no.
- Candidate projections are non-mutating and grant zero selections, roots, adapters, consumer contracts, semantic imports, or terminal states.

G2 remains 7/9 and BLOCKED; G2-06 is unsatisfied and P3 remains unauthorized.
