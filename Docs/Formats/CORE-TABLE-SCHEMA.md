# P2-07 core-table schema

## Scope and authority

P2-07 freezes an executable import contract for twelve gameplay-critical tables from
the `qy-3.0.0.413` source build: item, skill, level, profession progression, unit class,
unit property, state, suit, quest, crafting formula, waypoint and transfer point. The
selection covers the definitions needed by the login-to-first-playable-slice path and
is not a claim that the other 213 active tables are unimportant.

`Data/Schemas/core-table-registry-v1.json` is authoritative only for importing this
frozen source build. It is not authority for runtime ownership or hot-reload policy;
those remain P2-08 decisions. A later source build, a wider observed range, a longer
UTF-8 value or a semantic type change requires a registry version bump and full
revalidation. The contract must never silently widen itself in production.

## Inputs and outputs

`Tools/TMXY.Table/New-CoreTableSchema.ps1` consumes the ignored P2-06
`normalized.jsonl` and `schema.yaml` files. It does not decrypt TBL files and has no
Secret input. The tracked outputs are:

- `Contracts/data-schema/core-table-policy-v1.json`: reviewed table, key and reference
  decisions expressed with stable column IDs;
- `Contracts/data-schema/core-table-registry-v1.schema.json`: JSON Schema for the
  generated registry;
- `Data/Schemas/core-table-registry-v1.json`: source column names, authoritative import
  types, nullability and closed observed bounds;
- `Data/Inventory/p2-07-core-table-schema.json`: hashes and aggregate validation evidence
  without raw rows or field values.

Run the generator once to create the registry and evidence, then use `-Check` to rebuild
both in memory and require byte-identical tracked outputs:

```powershell
& .\Tools\TMXY.Table\New-CoreTableSchema.ps1
& .\Tools\TMXY.Table\New-CoreTableSchema.ps1 -Check
& .\Tests\Contract\Test-CoreTableSchema.ps1 -RequireLocalExports
```

Hosted CI can validate the tracked contract without possessing ignored plaintext
exports. A release-authority machine must additionally run the local-export check.

## Keys and duplicate policy

Eleven tables reject duplicate primary keys. `Profession_lvl.tbl` uses the composite
`Profession + level` key and contains 800 duplicate physical occurrences across 700
key groups. Full normalized-row comparison proves every such group is identical. The
canonical import therefore collapses identical duplicates from 16,000 physical rows
to 15,200 canonical rows and rejects any divergent duplicate.

`skill_table.tbl` uses `guid + level`; `unit_prop.tbl` uses `name + cl_name`; and
`waypoint.tbl` uses `way_id + index_id`. The remaining core tables have a single-column
primary key. The registry retains stable `cNNNN` IDs beside the source names so later
code generation does not depend on ambiguous or blank headers.

## Types, ranges and references

All 355 core columns have exactly one import type and validation rule. Numeric values
use inclusive observed minimum/maximum bounds, strings use inclusive UTF-8 byte-length
bounds, booleans use the boolean domain, and an all-null column is explicitly marked as
having no observed non-null value. Empty or physically missing source fields remain
`null`.

Fourteen strict references cover item-to-skill identity, quest, suit and level; skill
prerequisites; profession and transfer-point levels; and all six crafting materials
plus crafting output. A skill identity reference deliberately targets the distinct
skill-ID domain because individual skill rows are keyed by ID and level. Null, zero and
minus-one are inactive sentinels only when every component is inactive. Every active
declared reference resolves, and target/source types match.

Three plausible relations are deliberately deferred instead of weakened: required
skill item has one current dangling row, required skill level extends beyond the
current level table, and quest level carries special non-level codes. P2-13 must close
or explicitly map those semantics before broad reference closure can be claimed.

## Acceptance evidence

The frozen population contains 87,844 physical rows, 87,044 canonical rows, 355 columns,
12 primary keys and 14 strict foreign keys. Validation requires zero type, range, key,
divergent-duplicate and dangling-reference violations. The generator, policy, contract,
P2-06 evidence and P2-06 content-set hashes are all bound into the tracked evidence.
