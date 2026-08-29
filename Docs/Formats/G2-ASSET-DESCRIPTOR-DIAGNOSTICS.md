# G2 asset descriptor diagnostics

P2-20A.4 is a fail-closed revalidation of package-to-asset descriptor ambiguity for
G2-06. It does not recover unavailable server behavior and is not a playability,
deletion, G2, P3, or release authority.

The scope is frozen from the P2-20A.3 anonymous binding workset: all 2,514
coarse-equivalent targets, 183 divergent targets, 19 zero-valid targets, and 935
unique SKEM targets. The exact 3,651 targets and 12,764 candidate edges are
reconciled to P2-03, P2-12, and P2-13 before probing. All 46,865 relevant package
objects must match their `(package, body offset, body size, class)` identity tuples.

Each candidate is parsed independently and passed through the production binder.
The versioned semantic digest includes the original object-name bytes and every
descriptor field retained for conversion, including ordered nested values, float
bit patterns, and unknown property name/value bytes. Storage offsets and sizes are
excluded from semantic equality.

Classification is conservative:

- zero production-compatible candidates is `UNRESOLVED`;
- one compatible semantic class with no unreadable candidate is `RESOLVED`;
- multiple compatible semantic classes is `AMBIGUOUS`;
- any unreadable candidate keeps an otherwise compatible target `AMBIGUOUS`.

No representative or first candidate is selected. The detailed anonymous workset
is Git-ignored; the tracked JSON and Markdown contain only aggregates and hashes.
Regenerate with:

```powershell
.\Tools\TMXY.G2AssetDescriptorDiagnostics\New-G2AssetDescriptorDiagnostics.ps1
.\Tools\TMXY.G2AssetDescriptorDiagnostics\New-G2AssetDescriptorDiagnostics.ps1 -Check
```
