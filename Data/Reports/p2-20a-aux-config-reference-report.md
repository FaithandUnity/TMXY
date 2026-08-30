# P2-20A.3 Auxiliary-Config Reference Evidence

- Review execution: `PASS`
- Closure result: `BLOCKED`
- G2-06 satisfied: `false`
- P3 authorized: `false`

## Measured lexical facts

- File instances: 212 (196 unique bodies)
- Parsed / malformed: 206 / 6
- Scalar positions / non-empty: 39522 / 39498
- Exact asset occurrences: 3043
- Exact Package occurrences: 638 (218 unique, 420 ambiguous)
- Retained ambiguous Package candidate edges: 1136
- Exact config-to-config lexical edges: 8

These are complete-scalar lexical observations only. They do not approve a semantic adapter or a traversal root.

## Adapter state

- Candidate-only: 171
- Malformed-blocked: 6
- No-reference undecided: 35
- Semantic-approved / no-ref-approved: 0 / 0
- Approved roots: 0

Every file instance is retained, including duplicate bodies. ECF repeated assignments preserve source order; no first/last winner is selected. XML DTDs and external resolution are disabled. Substring, basename, extension-only and first-candidate matching are prohibited.

## Blocking boundary

All 212 instances still need an authority-backed terminal disposition. The six malformed XML instances need explicit safe handling. Semantic resolution and configuration closure cannot be calculated from lexical candidates until adapters and roots are approved.

This evidence does not establish a complete playable version, approve G2, authorize P3, or grant release authority.

## Reproduction

Run `Tools/TMXY.G2AuxConfigClosure/New-G2AuxiliaryConfigClosure.ps1`; add `-Check` to compare deterministic outputs. Deep contract verification additionally reads the ignored anonymous candidate export.
