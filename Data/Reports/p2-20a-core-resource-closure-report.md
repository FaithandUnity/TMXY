# P2-20A G2-06 Core Resource Closure

- Review execution: `PASS`
- Criterion decision: `BLOCKED`
- Completion criteria satisfied: `false`
- G2 approved: `false`
- P3 authorized: `false`

The review computes a monotonic union fixed before observing the result. It does not select a favorable playable sample or filter by client/server ownership.

## Scope

All 24465 declared character, scene, and skill roots are included. All 16 resource-bearing core-table rules are included for every emitted non-sentinel canonical-row reference.

Auxiliary configuration reference adapters are absent and Package-to-asset edges lack explicit resolution states. Both omissions fail closed; later configuration roots may only enlarge the union.

## Measured closure

| Metric | Value |
| --- | ---: |
| Start nodes | 62256 |
| Reachable nodes | 127015 |
| Table unresolved | 5161 |
| Table ambiguous | 6945 |
| Package unresolved | 407 |
| Package ambiguous | 8511 |
| Scoped terminals (not gaps) | 22040 |
| Heuristic selections | 0 |
| Conditional-required rows | 5993 |
| Conditional-required missing | 29 |
| Conditional-required unresolved | 0 |
| Reachable asset structure unresolved | 18 |
| Reachable asset structure fail | 0 |

Core foreign-key dangling zero remains a distinct table-integrity fact and is not substituted for these resource-reference metrics. The conditional-required missing count is retained even though missing values produce no table-to-Package edge. Ambiguous edges retain every candidate; no first candidate is selected.

The conditional-required member set is not present in the current graph and is therefore not exported or assigned a fabricated set hash. Its aggregate is exact-hash bound to P2-13, but absence of member-level evidence cannot prove the required zero threshold.

## Blocking work

- `G2-06-CONFIG-SCOPE`: Auxiliary configuration reference adapters are absent, so configuration-derived roots are not proven complete. Define reviewed semantic adapters, including tolerant-parser coverage for isolated malformed XML, and add discovered roots by union.
- `G2-06-ASSET-BINDING`: Package-to-asset edges do not publish an explicit binding resolution state. Version the graph contract so every core package-to-asset binding records evidence-backed resolution without first-candidate selection.
- `G2-06-CONDITIONAL-REQUIRED`: P2-13 reports conditionally required resource fields with missing values; such rows may emit no table-to-Package edge and cannot disappear from review. Export a reviewed member-level work set, resolve every missing required value, retain the P2-13 source binding, and reach the independent zero threshold.
- `G2-06-LOGICAL-GAPS`: The monotonic core closure contains unresolved and ambiguous table or Package references. Resolve each hashed work item through reviewed aliases, equivalent-candidate proof, source recovery, or an explicit versioned scope decision.
- `G2-06-ASSET-STRUCTURE`: Some reachable assets remain structurally unresolved. Recover qualified descriptors or provide reviewed replacements while retaining source hashes and audit history.

## Reproduction

Run `pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1`, then rerun with `-Check`. The generator runs as the locked non-root builder with a read-only repository mount, no network, no Linux capabilities, and no-new-privileges.

The detailed hashed start, reachable, logical-gap, and asset-structure sets remain in the ignored `Data/Exports/P2-20` directory. Tracked evidence contains only aggregate counts and SHA-256 bindings.
