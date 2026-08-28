# P2-15 conversion route classification

P2-15 turns the P2-14 health report into an explicit conversion route, execution
tier, delivery priority, duplicate-handling decision, and planning estimate for
every one of the 40,090 classified assets. It does not convert payloads, remove
aliases, repair sources, or authorize deletion.

The full local report is
`Data/Exports/P2-15/p2-15-conversion-routing.jsonl`. It contains 40,090
deterministic JSONL records, is 21,021,383 bytes, and has SHA-256
`77620c2db505d98a94f64e1bd9f7c5244fbb48fbad80900cb83d699add832559`.
It is Git-ignored because each row contains a source path and stable asset ID.
Tracked evidence contains only aggregate counts and input/output hashes.

## Routes and planning coefficients

Every asset has exactly one of five routes. The 1,404.695 total human hours are
a planning coefficient, not a benchmark or schedule commitment. P2-19 must
replace these coefficients with measured pilot throughput before a delivery
forecast is made. The 108,005 machine seconds are likewise a sequential batch
planning quantity, not elapsed-time evidence.

| Route | Tier | Files | Jobs | Reused aliases | Bytes | Fixed h | Item h | Planning h | Machine s |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Qualified interchange | Automatic | 37,935 | 32,515 | 5,420 | 8,534,384,165 | 40 | 352.25 | 392.25 | 97,545 |
| Standard audio | Automatic | 514 | 480 | 34 | 178,952,251 | 24 | 9.77 | 33.77 | 2,400 |
| Navigation adaptation | Semi-automatic | 841 | 806 | 35 | 4,565,902 | 160 | 201.675 | 361.675 | 8,060 |
| Descriptor recovery | Manual | 786 | 786 | 0 | 144,791,420 | 80 | 393 | 473 | 0 |
| Repair or replace | Manual | 14 | 14 | 0 | 19,325,289 | 32 | 112 | 144 | 0 |

The automatic tier covers 38,449 files and 32,995 conversion jobs, the
semi-automatic tier covers 841 files and 806 jobs, and the manual tier covers
800 files and 800 jobs. All 8,882,019,027 source bytes are classified and the
unclassified count is zero.

## Priority order

Priorities preserve the P2-14 reference-state distinction instead of treating
every unlinked file as disposable:

- `P0-first-playable-slice`: 14,058 files, 8,842 jobs, 5,216 aliases;
- `P1-linked-content`: 24,119 files, 24,025 jobs, 94 aliases;
- `P2-unlinked-review`: 1,008 files, 867 jobs, 141 aliases;
- `P3-identity-rule-gap`: 905 files, 867 jobs, 38 aliases.

P0 is the first playable content slice, not a claim that every P0 asset is
already importable. Manual descriptor recovery and repair findings remain
blocking work within their assigned priority.

## Exact-byte reuse boundary

P2-15 reduces 40,090 source paths to 34,601 conversion jobs without losing any
path identity. It selects 262 safe representatives and maps 5,489 aliases to
them only when complete source SHA-256 matches, parsing passed, and the family is
MP3, SM, SKEM, TER, WAV, or ZIF. Representative choice is deterministic: highest
priority first, then lowercase asset ID. Aliases are preserved in the output.

QTX and ANIM are descriptor-bound headerless formats. Their 3,351 exact-byte
duplicate rows remain `exact-duplicate-review-only`, because identical payload
bytes do not prove identical external descriptors. P2-15 records zero
descriptor-bound alias reuse and zero deletion recommendations.

Local review queries expose paths but never payloads or per-asset source hashes:

```powershell
.\Tools\TMXY.ConversionRouting\Find-ConversionRoute.ps1 -Priority P0-first-playable-slice
.\Tools\TMXY.ConversionRouting\Find-ConversionRoute.ps1 -Tier manual
.\Tools\TMXY.ConversionRouting\Find-ConversionRoute.ps1 -DuplicateHandling safe-reuse-alias
```

Generation runs in the qualified non-root builder with no network, a read-only
workspace and container filesystem, no capabilities, and no new privileges.
`-Check` requires byte-identical report and tracked evidence regeneration.
