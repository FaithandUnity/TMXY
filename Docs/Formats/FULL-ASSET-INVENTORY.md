# Full installed-client asset inventory

Status: P2-12 complete for frozen client `qy-3.0.0.413`.

## Scope and result

The inventory covers every installed `.qtx`, `.sm`, `.skem`, `.anim`, `.ter`, `.zif`, `.wav`,
and `.mp3` file selected from the frozen client Manifest. It accounts for 40,090 files,
8,882,019,027 bytes, and all eight required families. The scanner reads the client through a
read-only mount in the qualified Clang 21 container with networking and capabilities disabled.

| Family | Files | Bytes | PASS | UNRESOLVED | FAIL |
|---|---:|---:|---:|---:|---:|
| QTX | 24,798 | 3,910,277,648 | 24,042 | 756 | 0 |
| SM | 2,924 | 2,307,762,148 | 2,912 | 0 | 12 |
| SKEM | 1,068 | 515,443,174 | 1,066 | 0 | 2 |
| ANIM | 1,069 | 655,802,200 | 1,039 | 30 | 0 |
| TER | 8,876 | 1,309,215,704 | 8,876 | 0 | 0 |
| ZIF | 841 | 4,565,902 | 841 | 0 | 0 |
| WAV | 450 | 54,949,730 | 450 | 0 | 0 |
| MP3 | 64 | 124,002,521 | 64 | 0 | 0 |

`PASS` means the applicable production reader consumed the complete structure. `UNRESOLVED`
means a headerless QTX or ANIM payload lacks a Package descriptor or disagrees with every exact
logical-name descriptor candidate. It is not mislabeled as corruption because descriptor and
payload evidence cannot identify which side is stale. `FAIL` is reserved for self-contained
payloads rejected independently of Package metadata: 12 SM and 2 SKEM files. Those 14 files are
retained, hashed, and routed for later recovery or replacement; this stage deletes or repairs
nothing.

## Package ambiguity

Every Package object candidate is retained. Historical `tempfile` copies create equivalent and
divergent descriptor sets: QTX has 3,517 equivalent and 391 divergent multi-candidate paths; SM
has 506/2, SKEM 106/2, and ANIM 100/8. The inventory accepts a payload if at least one exact
logical-name descriptor variant validates it but records the ambiguity for P2-13/P2-16. It never
selects the newest timestamp or silently treats a temporary Package as authoritative.

## Evidence boundary

The complete 40,090-line catalog is deterministic and Git-ignored at
`Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl`. Each row contains only path, frozen source
SHA-256, byte count, format contract, parse state, Package-candidate state, stable error/offset,
and structural counts. It contains no asset payload, decoded image, geometry, audio, object name,
or Package name. The tracked evidence at `Data/Inventory/p2-12-full-asset-inventory.json` binds
the full catalog hash, input set, parser sources, P1 readers, locked builder, and isolation.

## Completion semantics and next work

P2-12 is complete because every target file is accounted for and classified, not because every
legacy file is conversion-ready. P2-13 builds the reference closure and distinguishes required
from orphaned failures. P2-14 analyzes duplicates without deleting them. P2-15 assigns automatic,
semi-automatic, or manual routes. P2-16 defines content-addressed cache invalidation.
