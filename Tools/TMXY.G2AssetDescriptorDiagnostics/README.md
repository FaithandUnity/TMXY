# TMXY.G2AssetDescriptorDiagnostics

P2-20A.4 revalidates the 3,651 highest-risk package-to-asset descriptor obligations
against the exact P2-03/P2-12/P2-13 identity sets and the production asset binders.

Run from PowerShell:

```powershell
.\Tools\TMXY.G2AssetDescriptorDiagnostics\New-G2AssetDescriptorDiagnostics.ps1
.\Tools\TMXY.G2AssetDescriptorDiagnostics\New-G2AssetDescriptorDiagnostics.ps1 -Check
```

The legacy client tree is mounted read-only. Preparation TSVs, probe output, and the
full anonymous diagnostic workset remain under ignored `Data/Local` or `Data/Exports`.
Tracked outputs contain aggregate, disclosure-safe evidence only. A successful
diagnostic run does not select a candidate and does not authorize G2 or P3.

Every parsed candidate now carries separate exact descriptor, exact identity-plus-
descriptor, and ASCII-lower identity diagnostic hashes. Animation candidates also
record whether the mirrored skeletal-mesh identity has the same ASCII-lower value;
only that mirrored identity field is lower-cased for the normalized diagnostic.
These hashes are inputs to the separate P2-20A.6 safety audit. They never alter the
A.4 exact-semantic classification or imply candidate equivalence or selection.
