# TMXY.G2AssetBindingRecovery

P2-20A.8 creates a hash-bound attempt scope from the frozen P2-20A.7 production-binding failures,
then cross-proves the recovery results emitted by a later full P2-20A.4 rerun. P2-20A.4 remains the
only authority for effective `RESOLVED`, `AMBIGUOUS`, and `UNRESOLVED` counts.

The repository carries a frozen, tracked, headerless 21-row anonymous base-plan contract at
`Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv`. Prepare regenerates the live
ignored seven-column TSV from A.7 and fails unless its bytes exactly equal that contract:

```powershell
.\Tools\TMXY.G2AssetBindingRecovery\New-G2AssetBindingRecovery.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild -Mode Prepare
```

The columns are `asset_id`, `candidate_id`, `body_sha256`, `source_sha256`, `family`,
`recovery_kind`, and `strict_error_code`, ordered by asset and candidate identity. The 21 rows are an
upper bound only: 16 QTX `payload_size_mismatch` edges and five ANIM `frame_count_mismatch` edges.
They are permission to attempt the explicit production recovery API, not evidence that recovery is
legal or successful.

After the independently reproducible P2-03 and P2-12 exports are available, P2-20A.13 can break the
A.4/A.7/A.8 recovery-cycle bootstrap directly from the tracked contract and derive a second 21-row
effective plan. It changes only the `recovery_kind` cell for its exact six source-proven QTX edges;
every identity, hash, family, error, and unselected row remains byte-for-byte equivalent by field.
After A.4 consumes the effective plan and regenerates its detail, finalize:

```powershell
.\Tools\TMXY.G2AssetBindingRecovery\New-G2AssetBindingRecovery.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild -Mode Finalize
```

Finalize accepts a success only when the edge is in the frozen attempt plan, its strict binding is
still `REJECTED`, its effective binding is `PASS`, `recovery_applied` is true, the recovery kind
matches, and a non-null effective semantic SHA-256 is present. Tracked evidence contains aggregates,
hash bindings, and the anonymous base-plan contract; it contains no raw names or private paths.

Run the contract:

```powershell
.\Tests\Contract\Test-G2AssetBindingRecovery.ps1 -RebuildRoot E:\QQXYCodeDev\Rebuild
```
