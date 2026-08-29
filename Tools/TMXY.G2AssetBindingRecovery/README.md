# TMXY.G2AssetBindingRecovery

P2-20A.8 creates a hash-bound attempt scope from the frozen P2-20A.7 production-binding failures,
then cross-proves the recovery results emitted by a later full P2-20A.4 rerun. P2-20A.4 remains the
only authority for effective `RESOLVED`, `AMBIGUOUS`, and `UNRESOLVED` counts.

Prepare the ignored, headerless seven-column attempt TSV:

```powershell
.\Tools\TMXY.G2AssetBindingRecovery\New-G2AssetBindingRecovery.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild -Mode Prepare
```

The columns are `asset_id`, `candidate_id`, `body_sha256`, `source_sha256`, `family`,
`recovery_kind`, and `strict_error_code`, ordered by asset and candidate identity. The 21 rows are an
upper bound only: 16 QTX `payload_size_mismatch` edges and five ANIM `frame_count_mismatch` edges.
They are permission to attempt the explicit production recovery API, not evidence that recovery is
legal or successful.

After the A.4 probe has consumed that attempt TSV and regenerated its effective detail, finalize:

```powershell
.\Tools\TMXY.G2AssetBindingRecovery\New-G2AssetBindingRecovery.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild -Mode Finalize
```

Finalize accepts a success only when the edge is in the frozen attempt plan, its strict binding is
still `REJECTED`, its effective binding is `PASS`, `recovery_applied` is true, the recovery kind
matches, and a non-null effective semantic SHA-256 is present. It emits only aggregates and hashes to
tracked report/evidence; anonymous identities remain in ignored exports.

Run the contract:

```powershell
.\Tests\Contract\Test-G2AssetBindingRecovery.ps1 -RebuildRoot E:\QQXYCodeDev\Rebuild
```
