# P2-13 reference closure

P2-13 joins three already-qualified domains without copying legacy payloads:

- P2-03: 121,715 Package object nodes and 147,349 evidence-backed edges;
- P2-07: 87,044 canonical rows from 12 core tables and 14 authoritative foreign keys;
- P2-12: 40,090 asset files from eight format families.

The generated graph is `Data/Exports/P2-13/p2-13-reference-closure.jsonl`. It is
205,392,166 bytes, contains 683,355 deterministic JSONL records, and has SHA-256
`6d895d722d8a547c8c1c560a8c68750ae98b83b458e27836befac18cf496c9ed`.
It remains Git-ignored because it is reproducible from source-bound local exports.

## Roots and traversal

The graph exposes 1,096 character roots (`QSkelMesh`), 142 scene roots (`QLevel`
and `QTerrainInfo`), and 23,227 skill-level roots. The query tool traverses only
hashed identities and never emits decoded table values, primary keys, or Package
object names:

```powershell
.\Tools\TMXY.ReferenceClosure\Find-ReferenceClosure.ps1 -RootKind character
.\Tools\TMXY.ReferenceClosure\Find-ReferenceClosure.ps1 -RootKind scene
.\Tools\TMXY.ReferenceClosure\Find-ReferenceClosure.ps1 -RootKind skill
```

Package names and asset paths exist only in the ignored local graph so engineers
can locate source evidence. The tracked evidence stores counts and hashes only.

## Closure semantics

“Core dangling reference” has a deliberately narrow authoritative meaning: a
non-sentinel P2-07 foreign-key row whose canonical target row or declared distinct
domain does not exist. All 55,361 active and 129,154 inactive physical reference
rows were re-evaluated; the 55,361 active rows become 54,561 canonical edges after
the 800 already-approved duplicate physical rows are collapsed. Core dangling
references are zero.

Legacy `getFieldObj` columns are nullable presentation pointers, not server-trusted
foreign keys. Their 113,484 non-empty values are still fully retained as 101,378
unique, 6,945 ambiguous, and 5,161 unresolved links. No ambiguous candidate is
selected implicitly. Three scoped animation/bone token rules produce 631 terminal
links whose meaning depends on the owning skeleton rather than a global Package
object.

The old client contains 5,993 skill rows where its debug path expects a preparation
action. Twenty-nine have no value, while every non-empty value resolves to an
allowed action class. P2-13 records those 29 rows as a legacy runtime assertion
risk; it does not invent a default action or misreport them as authoritative table
foreign-key failures.

## Asset links

The closure preserves all 40,090 P2-12 assets and emits 61,511 Package-to-asset
candidate edges. QTX, SM, SKEM, ANIM, and WAV use the legacy ASCII-insensitive
logical-name rule. TER uses the observed level-package path segment rule. MP3 and
ZIF have no evidence-backed Package identity rule and therefore remain explicitly
unlinked for P2-14 analysis. “Unlinked” never means “delete”.

Regeneration is isolated in the qualified non-root builder with a read-only source
mount, no network, a read-only container filesystem, no capabilities, and no new
privileges. `-Check` requires byte-identical evidence and graph hashes.
