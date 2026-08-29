# TMXY.G2AssetIdentityNormalization

This module implements the P2-20A.6 / G2-06 identity-normalization safety audit. It consumes the
P2-20A.4 descriptor diagnostic and the P2-03 package graph as hash-bound inputs. It never selects a
candidate and treats P2-03 ASCII-lower identity grouping as an observation, not semantic equivalence.

Generate the tracked aggregate report, ignored anonymous detail, and machine evidence from the
frozen A.4 capture timestamp; use `-Check` for byte-identical regeneration:

```powershell
.\Tools\TMXY.G2AssetIdentityNormalization\New-G2AssetIdentityNormalization.ps1
.\Tools\TMXY.G2AssetIdentityNormalization\New-G2AssetIdentityNormalization.ps1 -Check
```

The wrapper requires the repository's locked, non-root builder image and runs with no network,
read-only workspace access, dropped capabilities, and no-new-privileges. The detailed JSONL output
contains anonymous identifiers and hashes only and must remain ignored. The tracked report interface
is defined by `Contracts/data-schema/g2-asset-identity-normalization-v1.schema.json`; the complete
machine evidence is `Data/Inventory/p2-20a-asset-identity-normalization.json`.

The verified expected result is `PASS_DIAGNOSTIC` for execution and `BLOCKED` for G2-06: 13 of 15
ambiguous targets are ASCII-case-fold identity collisions, but zero targets are equivalent under the
strict production descriptor and full-semantic signatures. All 15 targets therefore remain ambiguous.
