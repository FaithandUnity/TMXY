# P2-09 legacy/current table difference

P2-09 compares the read-only, already-decrypted DevDoc CSV snapshot with the
current P2-06 active CLSVShare data. The 52 legacy files share a narrow 2012
filesystem timestamp window, but no trustworthy build identifier is present.
The snapshot is therefore identified by a complete file manifest hash and its
build remains `unknown-not-inferred`.

All 52 legacy basenames pair ASCII-case-insensitively with one of 113 current
active CLSVShare tables. The legacy inputs total 8,609,196 bytes: 19 are strict
UTF-8 and 33 require strict GB18030. No legacy payload is copied into Rebuild.

The full local report is
`Data/Exports/P2-09/p2-09-legacy-current-diff.jsonl`: 52 records, 41,759 bytes,
SHA-256
`c6fb188d97db18e1dd87201871a36bad77229f5f53e24d2650871a032bcf2667`.
It is Git-ignored. Tracked evidence contains no headers, row values, or primary
keys.

## Schema and row differences

Forty tables have byte-equivalent decoded header arrays. Across all paired
tables there are 608 shared column identities, 18 legacy-only columns, and 66
current-only columns. Shared columns have 59 observed inference changes among
`empty/int64/decimal/string` and 179 changes to the hashed modal-value candidate.
The latter is only an observed distribution hint; P2-09 makes zero authoritative
default-value claims.

The legacy snapshot has 73,602 data rows and the current paired tables have
149,472. Canonical row-array multiset comparison finds 44,500 exact shared rows,
29,102 legacy-only occurrences, and 104,972 current-only occurrences. This is a
lossless occurrence count, including duplicates; it is not a deletion policy.

Ten paired tables fall under the P2-07 primary-key contract, enabling old-only,
shared, and current-only key-domain queries without exposing the key values.
Twelve P2-07 foreign-key rules have both source and target columns in the legacy
snapshot. They cover 19,599 active legacy and 39,361 active current references;
both snapshots have zero dangling references. All 12 activity counts changed.

```powershell
.\Tools\TMXY.TableDiff\Find-LegacyCurrentDiff.ps1 -Table item_table
.\Tools\TMXY.TableDiff\Find-LegacyCurrentDiff.ps1 -State paired
```

Generation runs with both the legacy source and Rebuild mounted read-only in the
qualified non-root builder, with no network or capabilities. `-Check` requires
byte-identical report and evidence regeneration.
