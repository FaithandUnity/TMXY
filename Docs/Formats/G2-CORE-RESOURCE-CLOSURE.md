# P2-20A G2-06 core-resource closure

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
gap set. P2-13 is exact-hash bound. Because its current graph has no member
records for missing values, P2-20A reports `member_set_exported = false` and a
null member-set hash; that evidence gap cannot be interpreted as a zero count.

## Incomplete scope

The current report deliberately records all three fields below as false:

- `scope_complete`;
- `auxiliary_config_reference_scope_complete`;
- `asset_binding_resolution_explicit`.

P2-05 classifies every auxiliary configuration file but does not provide a
complete semantic resource-reference adapter set. Later configuration-derived
roots may only enlarge the union. Package-to-asset edges also need an explicit
versioned resolution contract; absence of a resolution field never means
unique.

Consequently, even a future zero logical queue would remain blocked until both
coverage gaps close and conditionally required missing values reach their
independent zero threshold with member-level evidence. Unlinked or duplicate
assets are retained and are not automatic deletion authority.

## Evidence and reproduction

The detailed hashed start, reachable, logical-gap, and asset-structure records
are regenerated under ignored `Data/Exports/P2-20`. The tracked report and task
evidence contain only counts and SHA-256 bindings; they contain no exact primary
keys, table rows, decoded confidential data, private source paths, or legacy
source lines.

```powershell
pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1
pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1 -Check
pwsh -NoProfile -File Tests/Contract/Test-G2CoreResourceClosure.ps1 -VerifyDerivedSources
```

All generation runs in the locked non-root builder with a read-only repository
mount, no network, no capabilities, and no-new-privileges. Successful execution
means that the blocked decision was reproduced; it is not a G2 pass, P3
authorization, playability proof, or release authority.
