# P2-20A.3 G2-06 core-resource closure

P2-20A turns the missing G2-06 proof into a reproducible blocked evidence set.
It does not approve G2. The scope is frozen independently of the observed
counts and is the monotonic union of:

1. every character, scene, and skill root already declared by P2-13; and
2. every emitted non-sentinel canonical-row reference from all P2-13 resource
   rules that exactly match a PASS core column in the P2-08 ownership registry.

P2-13 conditionally required resource fields are an independent obligation.
A required field with no value may emit no `table_package_edge`, but it remains
in G2-06 and must satisfy `conditional_required_missing = 0`.

Client/server ownership controls runtime trust. It never removes a resource
field from this scope. Current-consumer observations and the desired outcome
also cannot filter roots, rows, fields, edge kinds, or candidates.

## Fixed-point traversal

The generator follows `table_fk_edge`, `table_domain_edge`,
`table_package_edge`, `package_edge`, and `package_asset_edge` until no new
hashed node is discovered. Ambiguous references retain every candidate.
`scoped-terminal` is accepted only for the Package edge kinds already frozen by
P2-13; it is neither reported as missing nor resolved to a guessed global node.

The tracked report separates table and Package unresolved/ambiguous counts,
heuristic selections, reachable asset structure gaps, unknown records, and
unknown resolution states. Core foreign-key dangling zero is preserved as a
different table-integrity fact and cannot satisfy G2-06.

The current P2-13 aggregate records 5,993 runtime-assert rows, 29 missing
conditionally required values, and zero unresolved nonempty values. The 29
missing values are an independent blocker, not part of the edge-derived logical
gap set. P2-20A independently reproduces them from the exact-hash-bound P2-06
normalized source, the qualified core primary key, and the frozen P2-13 rule.
Its ignored workset contains exactly three closed fields per member:
`member_sha256`, `rule_id`, and `reason`. The tracked report records only the
member count and set SHA-256; no value, primary key, row, or source path is
published.

## Explicit asset-binding states

P2-20A independently reconciles every reachable P2-13 asset node to the
P2-12 catalog and every observed Package candidate. The ignored anonymous
workset contains exactly 21,494 unique asset records covering 39,351 candidate
edges. Every record publishes a closed `RESOLVED`, `AMBIGUOUS`, or `UNRESOLVED`
state, its evidence basis, candidate-set SHA-256, counts, family, structure, and
`heuristic_selection=false`; it never publishes a selected candidate.

Explicit coverage is not successful resolution. The current evidence contains
21,299 resolved targets, 189 ambiguous targets, and 6 unresolved targets
(38,796, 546, and 9 candidate edges respectively). These effective states bind the
P2-20A.4 production diagnostic and the P2-20A.7/A.8 recovery cross-proof. Equivalent candidate sets
retain all members, identical payloads do not prove descriptor equivalence,
and both ambiguous and unresolved counts have independent zero thresholds.

## Incomplete scope

The current report deliberately records the first two fields as false and the
third as true:

- `scope_complete`;
- `auxiliary_config_reference_scope_complete`;
- `asset_binding_resolution_explicit` (true only because every binding now has
  an explicit state; this does not mean every state is resolved).

P2-20A.3 SHA-binds the separate auxiliary reference report and its policy and
Schema. It preserves all 212 file instances/196 unique content bodies and the
measured 3,043 asset, 638 Package, and 8 configuration lexical occurrences. The
states remain 171 candidate-only, 35 editor-undecided, and 6 malformed-blocked;
approved semantic adapters, no-reference dispositions, and roots are all zero.
Lexical candidates are not semantic approvals, and later approved roots may only
enlarge the union. The asset-binding contract is also explicit, but its 189
ambiguous and 6 unresolved targets remain fail-closed.

Consequently, even a future zero logical queue would remain blocked until both
coverage gaps close and conditionally required missing values reach their
independent zero threshold with member-level evidence. Unlinked or duplicate
assets are retained and are not automatic deletion authority.

## Evidence and reproduction

The detailed hashed start, reachable, logical-gap, asset-structure,
conditional-required, and asset-binding member records are regenerated under ignored
`Data/Exports/P2-20`. The tracked report and task evidence contain only counts
and SHA-256 bindings; they contain no exact primary keys, table rows, decoded
confidential data, private source paths, or legacy source lines.

```powershell
pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1
pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1 -Check
pwsh -NoProfile -File Tests/Contract/Test-G2CoreResourceClosure.ps1 -VerifyDerivedSources
```

All generation runs in the locked non-root builder with a read-only repository
mount, no network, no capabilities, and no-new-privileges. Successful execution
means that the blocked decision was reproduced; it is not a G2 pass, P3
authorization, playability proof, or release authority.
