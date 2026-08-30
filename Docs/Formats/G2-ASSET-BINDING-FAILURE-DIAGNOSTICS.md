# G2 production-binding failure diagnostics

## Purpose

P2-20A.7 explains the 19 unresolved asset targets retained by P2-20A.4. It reruns the exact
production qtx, static-mesh, and animation binders against all 24 candidate edges and records their
family-typed error codes. It does not select a candidate, modify legacy content, approve a repair, or
reduce a G2 threshold.

The inherited A.3 label `DESCRIPTOR_VALIDATION_FAILED` is not treated as the current technical
cause. A.4 proved that all 24 descriptors parse and that all 24 production bindings are rejected.
A.7 preserves the structured error object that A.4 intentionally reduced to a pass/reject boolean.

## Measured result

| Family and production error | Targets or edges |
| --- | ---: |
| Animation targets | 6 |
| `frame_count_mismatch` edges | 5 |
| `invalid_track_count` edges | 1 |
| QTX targets | 12 |
| `payload_size_mismatch` edges | 16 |
| Static-mesh targets | 1 |
| `material_slot_mismatch` edges | 2 |
| Total typed rejected edges | 24 |
| Unclassified edges | 0 |

The diagnostic result is `PASS_DIAGNOSTIC`, while the task result remains `BLOCKED`. All 19 targets
and 24 edges remain effectively unresolved. Candidate selections, automatic resolutions, owner
records, approved fixes, and verified resolutions are all zero.

An error code proves that the current production binder rejected a specific, hash-bound pairing. It
does not by itself prove that the legacy content is corrupt. A technical compatibility adapter must
be an explicit production API with complete contract evidence; it cannot be inferred from an error
code. Choosing a replacement candidate, changing content, accepting a compatibility exception, or
approving a no-reference disposition requires the appropriate owner or project authority and later
verification.

## Inputs and identity

The tracked report binds 15 ordered inputs by repository-relative path, tracked state, bytes, lines,
SHA-256, and aggregate SHA-256. These include A.4 report/detail/evidence/policy; P2-03 graph evidence
and ignored graph; P2-12 inventory evidence and ignored catalog; Core, A.5, A.6, and B.1 evidence;
and all three A.7 contracts.

The probe workset is joined only through anonymous SHA-256 identities. Asset bytes, candidate package
bodies, candidate-set identities, and legacy source files are rehashed before use. Any binder success
is treated as `a4_binding_pass_requires_rerun`; A.7 fails instead of silently updating the A.4 state.

## Anonymous output

The ignored detail export is
`Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl`. It has 19 target records and is
validated line-by-line against `g2-asset-binding-failure-detail-v1.schema.json`. Each record contains
anonymous asset and candidate identifiers, body and descriptor hashes, error schema/code, optional
stable read-error code, a hash of the error context, and a domain-separated failure identity.

Raw error contexts are never emitted because animation contexts can contain object references.
Absolute offsets, requested or available byte counts, file or object names, paths, payload values,
decoded content, primary keys, raw rows, and legacy source lines are also excluded.

## Reproduction

Generate outputs with the locked non-root builder and read-only inputs:

```powershell
.\Tools\TMXY.G2AssetBindingFailureDiagnostics\New-G2AssetBindingFailureDiagnostics.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游
```

Verify byte-for-byte deterministic regeneration:

```powershell
.\Tools\TMXY.G2AssetBindingFailureDiagnostics\New-G2AssetBindingFailureDiagnostics.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游 `
  -Check
```

Run positive, hash-binding, privacy, reconciliation, and negative contracts:

```powershell
.\Tests\Contract\Test-G2AssetBindingFailureDiagnostics.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游
```

## Gate boundary

A future G2 integration may project diagnostic coverage of 19 targets and 24 typed errors, but it
must also project 19/24 as effectively unresolved, zero dispositions, G2-06 false, and P3 false. A.7
does not change the A.6 15/30 ambiguity, A.5 212 nonterminal auxiliary instances, 29 conditional
missing values, B.1 1,359 pending decisions, or any other G2-06/G2-07 blocker.
