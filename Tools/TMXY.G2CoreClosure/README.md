# TMXY.G2CoreClosure P2-20A.1

This module computes the fail-closed P2-20A remediation evidence for G2-06.
It takes the monotonic union of every P2-13 declared root and every emitted
reference from all P2-08-owned core resource fields, then traverses all five
evidence-backed P2-13 edge records to a fixed point.

The detailed hashed sets remain under ignored `Data/Exports/P2-20`. Tracked
outputs contain aggregate counts and exact SHA-256 bindings only. A successful
execution remains `BLOCKED` because configuration reference coverage and
Package-to-asset resolution are incomplete, conditionally required values are
missing, and measured logical gaps are open. Missing conditional values may
emit no edge, so their P2-13-bound aggregate is independently reproduced from
the P2-06 normalized source into an ignored three-field anonymous workset. Only
its count and set SHA-256 enter tracked evidence.

```powershell
pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1
pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1 -Check
pwsh -NoProfile -File Tests/Contract/Test-G2CoreResourceClosure.ps1
```
