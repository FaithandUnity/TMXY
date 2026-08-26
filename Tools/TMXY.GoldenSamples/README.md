# TMXY.GoldenSamples

`New-GoldenSampleBaseline.ps1` validates the reviewed P0 sample selection
against the frozen client Manifest and the read-only legacy client. It writes
portable metadata only; it never copies source assets.

```powershell
pwsh -NoProfile -File .\Tools\TMXY.GoldenSamples\New-GoldenSampleBaseline.ps1
```

The command verifies every selected file by size and SHA-256, classifies the
observed Package headers, records the complete Package-version distribution,
and generates `Data/GoldenSamples/p0-golden-samples.json`.
