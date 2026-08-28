# P2-14 asset duplicate and orphan review

P2-14 classifies every P2-12 asset against exact source identity and the P2-13
character, scene, and skill closure. It produces evidence and review queues; it
does not delete, move, repair, merge, or select any asset.

The full local report is
`Data/Exports/P2-14/p2-14-asset-health.jsonl`. It contains 42,356 deterministic
JSONL records, is 23,686,877 bytes, and has SHA-256
`9a0db19c7809da06e7225ec900864f0854c8b61af224366aac746be312880b9f`.
It is Git-ignored because its 40,090 per-asset rows contain source paths and
hashes. Tracked evidence contains aggregate counts and input/output hashes only.

## Duplicate semantics

Two or more files are an exact duplicate group only when their complete source
SHA-256 is identical. The frozen client contains 1,743 such groups spanning
9,102 files. Keeping one copy per group would represent 7,359 redundant copies
and 1,286,887,829 bytes, but these are capacity facts, not deletion instructions.
There are no cross-family exact groups.

The parser also found 523 groups/33,629 files with the same family, byte length,
format contract, and structural metrics but different source hashes. These are
only structural review candidates. Coarse metrics—especially terrain dimensions
and texture dimensions/format—cannot prove equal runtime content. P2-14 therefore
reports zero proven semantic-equivalence groups and zero deletion recommendations.
A future semantic proof must use a format-qualified normalized-payload digest.

| Family | Exact groups | Exact files | Redundant copies | Redundant bytes | Structural review groups/files |
|---|---:|---:|---:|---:|---:|
| ANIM | 155 | 471 | 316 | 203,970,664 | 47 / 268 |
| MP3 | 3 | 6 | 3 | 5,726,390 | 0 / 0 |
| QTX | 1,326 | 2,880 | 1,554 | 242,876,664 | 272 / 23,905 |
| SKEM | 76 | 154 | 78 | 39,406,874 | 41 / 132 |
| SM | 64 | 162 | 98 | 17,505,262 | 98 / 252 |
| TER | 81 | 5,325 | 5,244 | 773,494,744 | 9 / 8,876 |
| WAV | 24 | 55 | 31 | 3,822,950 | 44 / 162 |
| ZIF | 14 | 49 | 35 | 84,281 | 12 / 34 |

## Reachability and “orphan” semantics

The union of 24,465 declared character, scene, and skill roots reaches 60,512
graph nodes and 14,058 assets. The remaining assets are partitioned without
claiming they are unused:

- 24,119 have Package links but are outside the current declared root slice;
- 1,008 belong to a family with an identity rule but have no matching Package;
- 905 are MP3 or ZIF files for which P2-13 has no evidence-backed identity rule.

“Outside the current roots” means only that P2-13's first-slice roots did not
reach the asset. It does not account for UI-only, editor-only, dynamically named,
event, patch, or future content. “No identity rule” is a coverage gap, not an
orphan finding. Every report row therefore has `delete_eligible=false`.

Local queries may expose source paths for engineering review but not payloads or
per-asset hashes:

```powershell
.\Tools\TMXY.AssetHealth\Find-AssetHealth.ps1 -ReferenceState root_reachable
.\Tools\TMXY.AssetHealth\Find-AssetHealth.ps1 -ReferenceState unlinked_identity_rule_no_match -Family qtx
.\Tools\TMXY.AssetHealth\Find-AssetHealth.ps1 -GroupId <lowercase-group-sha256>
```

Generation runs in the qualified non-root builder with no network, a read-only
workspace and container filesystem, no capabilities, and no new privileges.
`-Check` requires byte-identical report and tracked evidence regeneration.
