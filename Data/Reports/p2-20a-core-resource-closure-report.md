# P2-20A G2-06 Core Resource Closure

- Review execution: `PASS`
- Criterion decision: `BLOCKED`
- Completion criteria satisfied: `false`
- G2 approved: `false`
- P3 authorized: `false`

The review computes a monotonic union fixed before observing the result. It does not select a favorable playable sample or filter by client/server ownership.

## Scope

All 24465 declared character, scene, and skill roots are included. All 16 resource-bearing core-table rules are included for every emitted non-sentinel canonical-row reference.

Auxiliary lexical evidence is SHA-256 bound for all 212 file instances. It records 171 candidate-only, 35 editor-undecided, and 6 malformed-blocked states; approved adapters, no-reference dispositions, and roots remain zero. Package-to-asset bindings are explicitly classified, but ambiguous and unresolved states remain blocking.

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
| Asset binding targets resolved | 21293 |
| Asset binding targets ambiguous | 189 |
| Asset binding targets unresolved | 12 |
| Asset binding targets unknown | 0 |
| Reachable asset structure unresolved | 18 |
| Reachable asset structure fail | 0 |

Core foreign-key dangling zero remains a distinct table-integrity fact and is not substituted for these resource-reference metrics. The conditional-required missing count is retained even though missing values produce no table-to-Package edge. Ambiguous edges retain every candidate; no first candidate is selected.

The 29-member conditional-required workset is exported only in the ignored evidence area and bound by SHA-256 `90bf56294f616036d1f238e445f62ffce58e17c3f9aba6008750939246389b9d`. Each record contains only an anonymous member hash, a frozen rule ID, and a closed reason. No value, primary key, source row, or source path is disclosed.

The 21494-member asset binding workset is also ignored and SHA-256 bound as `432254a7a6160c746c03cbeb454a7833ab92e503bae299be6f1c783acbbdd753`. Explicit status does not mean resolved: every ambiguous or unresolved target remains a zero-threshold blocker, and no candidate is selected.

## Blocking work

- `G2-06-CONFIG-SCOPE`: Auxiliary configuration lexical candidates are measured and hash-bound, but all 212 file instances remain nonterminal and no semantic adapter, no-reference disposition, or root is approved. Define reviewed semantic adapters or explicit no-reference dispositions for all file instances, dispose every malformed XML input, and add only approved roots by union.
- `G2-06-ASSET-BINDING`: All reachable Package-to-asset bindings now have explicit evidence states, but divergent or invalid descriptor sets remain ambiguous or unresolved. Resolve every divergent descriptor set and failed descriptor validation through qualified evidence while preserving all candidates and without first-candidate selection.
- `G2-06-CONDITIONAL-REQUIRED`: P2-13 reports conditionally required resource fields with missing values; such rows may emit no table-to-Package edge and cannot disappear from review. Use the complete hashed member workset for authorized remediation, resolve every missing required value, retain the P2-06 and P2-13 source bindings, and reach the independent zero threshold.
- `G2-06-LOGICAL-GAPS`: The monotonic core closure contains unresolved and ambiguous table or Package references. Resolve each hashed work item through reviewed aliases, equivalent-candidate proof, source recovery, or an explicit versioned scope decision.
- `G2-06-ASSET-STRUCTURE`: Some reachable assets remain structurally unresolved. Recover qualified descriptors or provide reviewed replacements while retaining source hashes and audit history.

## Reproduction

Run `pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1`, then rerun with `-Check`. The generator runs as the locked non-root builder with a read-only repository mount, no network, no Linux capabilities, and no-new-privileges.

The detailed hashed start, reachable, logical-gap, and asset-structure sets remain in the ignored `Data/Exports/P2-20` directory. Tracked evidence contains only aggregate counts and SHA-256 bindings.
