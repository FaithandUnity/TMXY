# G2 asset identity-normalization safety audit

## Purpose and authority boundary

P2-20A.6 is a fail-closed diagnostic slice for G2-06. It asks whether P2-03 identity normalization
can safely remove any ambiguity retained by the P2-20A.4 production descriptor audit. It does not
choose a package candidate, grant G2 approval, authorize P3, or alter the P2-20A.4 workset.

`PASS_DIAGNOSTIC` means the audit ran completely and its bindings and contracts passed. The task
result remains `BLOCKED` because strict semantic equivalence was not demonstrated.

## Bound inputs

The report binds seven ordered inputs by repository-relative path, byte count, line count, SHA-256,
and an aggregate SHA-256:

1. the tracked P2-20A.4 report;
2. its ignored detail JSONL;
3. the tracked P2-20A.4 policy;
4. the tracked P2-03 evidence summary;
5. its ignored package graph JSONL;
6. the P2-20A.6 policy; and
7. the P2-20A.6 closed report schema.

Candidate membership is joined by the anonymous exact candidate identifier. Identity observations
come only from the P2-03 `logical_name_sha256` and `logical_name_ascii_lower_sha256` fields.

## Measured conclusion

The P2-20A.4 retained scope is 15 ambiguous targets and 30 candidate edges, with two candidates per
target. P2-03 identity evidence divides that scope as follows:

| Classification | Targets | Edges |
| --- | ---: | ---: |
| distinct exact identities that collide under ASCII lower | 13 | 26 |
| identity multiplicity not caused by ASCII case folding | 2 | 4 |
| strict production descriptor-semantic equivalence | 0 | 0 |
| strict full-semantic equivalence | 0 | 0 |
| effective ambiguity retained | 15 | 30 |

ASCII-lower identity grouping is not semantic equivalence. Strict signatures preserve nested
references, unknown property names and values, floating-point bits, and field order. The audit does
not apply Unicode case folding, locale-sensitive mapping, path normalization, descriptor-field
normalization, first-candidate selection, representative selection, or a coarse-equivalence proxy.

The identity-normalization slice retains all 15 / 30 targets and edges in its ambiguous diagnostic
scope. It separately binds the current P2-20A.4 reconciled full workset rather than projecting its
subset as the global result: 21,494 targets / 39,351 edges, with 21,299 / 38,796 resolved,
189 / 546 ambiguous, 6 / 9 unresolved, and zero unknown. G2 remains 7 of 9 criteria satisfied with
two blocked; P3 remains unauthorized.

## Output and disclosure contract

The closed tracked-report interface is
`Contracts/data-schema/g2-asset-identity-normalization-v1.schema.json`. The detailed JSONL advertises
`Data/Exports/P2-20/p2-20a-asset-identity-normalization.jsonl`, remains ignored, and contains only
anonymous identifiers, hashes, counts, booleans, and disposition tokens. Neither output may contain
raw names, private source paths, exact primary keys, raw table rows, legacy source lines, or decoded
confidential payloads.

## Reproduction and contracts

Generate the tracked outputs and machine evidence, or verify byte-identical regeneration:

```powershell
.\Tools\TMXY.G2AssetIdentityNormalization\New-G2AssetIdentityNormalization.ps1
.\Tools\TMXY.G2AssetIdentityNormalization\New-G2AssetIdentityNormalization.ps1 -Check
```

Run the complete positive, determinism, disclosure, hash-binding, and negative contract suite:

```powershell
.\Tests\Contract\Test-G2AssetIdentityNormalization.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild
```

Negative fixtures reject candidate selection, forced equivalence, missing and unknown fields, input
hash tampering, false G2/P3 states, Unicode or locale folding, nested-reference or unknown-property
omission, float normalization, field reordering, and coarse-equivalence substitution.

The tracked machine evidence is `Data/Inventory/p2-20a-asset-identity-normalization.json` and binds
the report, Markdown, ignored detail, contracts, implementation, locked builder, and isolation state.

## G2 integration point

G2 integration may consume only a schema-valid report whose seven input bindings recompute
exactly. It must project `g2_06_satisfied=false`, `p3_authorized=false`, 15 effective ambiguous
targets, 30 effective ambiguous edges, and zero candidate selections. Any other projection is a hard
contract failure, not an approval path.
