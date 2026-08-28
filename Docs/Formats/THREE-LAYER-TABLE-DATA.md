# Three-layer table data

P2-06 turns every active table in the frozen P2-04 inventory into a deterministic
three-layer representation under the Git-ignored `Data/Exports/P2-06` tree. The
tracked, value-free evidence is `Data/Inventory/p2-06-three-layer-data.json`.

## Per-table output

Each of the 225 active tables has a directory matching its source path without
the `.tbl` suffix and containing:

- `raw.csv`: the decoded payload bytes, byte-identical to the input of the legacy
  parser, retaining source encoding and CRLF line endings;
- `normalized.jsonl`: UTF-8 without BOM, one object per nonempty data row, stable
  `c0001`-style column IDs, empty or physically missing fields represented as
  JSON `null`, and conservative observed-value types;
- `schema.yaml`: a JSON-syntax YAML 1.2 document conforming to
  `Contracts/data-schema/table-schema-v1.schema.json`. It records source names,
  the old-to-new column mapping, provisional types, candidate keys, ownership,
  references, loading/hot-update/release metadata, and evidence levels.

JSON syntax is intentionally used for YAML so PowerShell and CI can parse every
schema without an extra YAML package. The file remains valid YAML 1.2.

Delimiter selection scans every nonempty line instead of assuming the P2-04
comma probe is semantic. The frozen result is 222 comma-delimited tables, two
single-column tables, and one 78-column asterisk-delimited compatibility table
(`Table/quest_table.tbl`). Candidate tab, pipe, and semicolon delimiters remain
supported. A header may declare more columns than the modal data row, as
observed in the compatibility data. The quest table has 5,942 data rows at its
78-column header width and one nonempty 79-column row; normalization preserves
that overflow as `c0079` instead of truncating or guessing its meaning.

The 113 historical shadows do not receive fabricated exports: their active
runtime key does not decode them. Evidence records their verified newer active
replacement instead.

## Semantic boundary

P2-06 makes only structural claims. A column becomes `int64`, `decimal`, or
`boolean` only when every non-null observed value passes a canonical and
culture-invariant parser; mixed or ambiguous columns remain `string`. This is
not an authoritative product type decision. Primary keys remain P2-04
candidates, ownership/loading policy is explicitly `pending-p2-08`, and ranges,
enums, defaults, units, localization, and foreign keys remain unresolved for
P2-07/P2-08. Raw bytes make every normalization decision auditable and reversible.

## Security and storage

The generator reads the 16-byte key only from the Windows credential store,
checks the approved fingerprint and source hashes, never accepts the key through
arguments or environment variables, and clears key/decryption buffers. Bulk
plaintext and source field names stay in `Data/Exports`, which policy excludes
from Git and Git LFS. The committed evidence contains only relative paths,
hashes, sizes, counts, classifications, and stable column IDs.

## Reproduction and verification

Run twice to establish a same-input deterministic match, then execute the
contract with local exports required:

```powershell
pwsh -NoProfile -File Tools/TMXY.Table/New-ThreeLayerTableData.ps1
pwsh -NoProfile -File Tools/TMXY.Table/New-ThreeLayerTableData.ps1
pwsh -NoProfile -File Tests/Contract/Test-ThreeLayerTableData.ps1 -RequireLocalExports
```

The second generation compares the previous and current content-set SHA-256.
The contract checks the committed evidence without a Secret in hosted CI and,
when the ignored export is present, verifies all file hashes, JSONL row counts,
schema structure, UTF-8/BOM rules, and the exact 225 × 3 coverage.
