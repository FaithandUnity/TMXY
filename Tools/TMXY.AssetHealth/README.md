# TMXY.AssetHealth

P2-14 consumes the P2-12 full asset catalog and P2-13 reference closure. It
creates two independent classifications:

- exact byte duplicates from the complete source SHA-256;
- root reachability and unlinked review states from evidence-backed graph edges.

Assets with matching parser metrics but different hashes are emitted only as
structural review candidates. They are not claimed to be semantically equal.
No classification authorizes deletion, repair, or candidate selection.

```powershell
.\Tools\TMXY.AssetHealth\New-AssetHealthReport.ps1
.\Tools\TMXY.AssetHealth\New-AssetHealthReport.ps1 -Check
.\Tools\TMXY.AssetHealth\Find-AssetHealth.ps1 -ReferenceState unlinked_identity_rule_no_match
```

The per-asset report remains under ignored `Data/Exports/P2-14`. Git tracks only
the generator, policy, contract, documentation, tests, and aggregate evidence.
