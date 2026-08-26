# P0 golden sample baseline

## Purpose

P0-13 establishes a reproducible, reference-only corpus for later format
reconstruction. The corpus represents Package versions 1.0, 2.0, and 3.0;
table complexity boundaries; texture, static mesh, skeletal mesh, animation,
terrain, navigation, and audio boundaries; and deliberately damaged or empty
inputs.

No legacy payload is copied into `Rebuild`. Each entry is identified by a
portable client-relative path, byte size, and SHA-256 from the frozen
`client-3.0.0.413` Manifest. The generator independently hashes the read-only
source before it publishes the baseline.

## Evidence boundary

- L2 entries are confirmed by file inventory, size, hash, extension, or Package
  header evidence.
- L4 entries are explicit hypotheses for semantic coverage, such as
  transparency, multiple materials, or multiple bones.
- L4 candidates must be confirmed by P1 format analysis before they can become
  decode or rendering acceptance oracles.

This distinction prevents filenames and legacy namespaces from being treated
as decoded semantics.

## Source and generated records

- `Data/GoldenSamples/p0-golden-selection.json` is the reviewed, human-owned
  selection.
- `Data/GoldenSamples/p0-golden-samples.json` is generated evidence containing
  verified hashes, sizes, Package classifications, and summary counts.
- `Data/RawManifests/client-3.0.0.413.files.jsonl` remains the frozen inventory
  authority.

Regenerate and validate from the `Rebuild` root:

```powershell
pwsh -NoProfile -File .\Tools\TMXY.GoldenSamples\New-GoldenSampleBaseline.ps1
pwsh -NoProfile -File .\Tests\Contract\Test-GoldenSampleBaseline.ps1 -VerifySourceFiles
```

The client root is read-only. Generated metadata may be committed, but original
packages, raw assets, decrypted material, bulk exports, and DDC must remain
outside Git and Git LFS.
