# TMXY.G2CoreClosure P2-20A.3

This module computes the fail-closed P2-20A remediation evidence for G2-06.
It takes the monotonic union of every P2-13 declared root and every emitted
reference from all P2-08-owned core resource fields, then traverses all five
evidence-backed P2-13 edge records to a fixed point.

The detailed hashed sets remain under ignored `Data/Exports/P2-20`. Tracked
outputs contain aggregate counts and exact SHA-256 bindings only. A successful
execution remains `BLOCKED` because the hash-bound auxiliary evidence keeps all
212 file instances nonterminal (171 candidate-only, 35 editor-undecided, and 6
malformed-blocked), with zero approved semantic adapters, no-reference
dispositions, or roots. A.4/A.7/A.8-bound effective Package-to-asset states still include 189
ambiguous and 12 unresolved targets, conditionally required values are missing, and measured
logical gaps are open. Missing conditional values may
emit no edge, so their P2-13-bound aggregate is independently reproduced from
the P2-06 normalized source into an ignored three-field anonymous workset. Only
its count and set SHA-256 enter tracked evidence. A second ignored anonymous
workset covers all 21,494 reachable asset targets and 39,351 candidate edges;
tracked evidence retains only aggregate resolution counts and its SHA-256.
Explicit state coverage never substitutes for the independent ambiguity and
unresolved zero thresholds, and no first candidate is selected.

```powershell
pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1
pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1 -Check
pwsh -NoProfile -File Tests/Contract/Test-G2CoreResourceClosure.ps1
```
