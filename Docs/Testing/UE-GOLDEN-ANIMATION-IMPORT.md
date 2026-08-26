# UE golden animation import

P1-25 imports three behavior-boundary animations from the real `Boy01.anim` evidence into UE 5.8.2. The legacy file remains read-only. `CreateAnimationGoldenFixtures.ps1` runs the qualified non-root Clang 21 exporter and produces a deterministic glTF 2.0 JSON/external-BIN bundle under `Tests/Fixtures/UE/Animation/boy01-core-real`.

## Contract

- The manifest and every source/artifact entry are SHA-256 verified before a package can be written.
- The animation handler remains behind the existing `khronos.gltf-json` router; the production format-handler count stays two.
- All 80 ordered Boy01 tracks are bound to the existing P1-24 skeleton. The skeleton manifest hash is part of the animation manifest.
- Samples remain at 30/1 Hz. Translation maps from glTF `(x,y,z)` to UE `(z,x,y)` and meters become centimeters.
- Quaternion keys are normalized and adjacent keys must retain hemisphere continuity.
- Root tracks are preserved as ordinary bone tracks. The importer does not enable UE root-motion extraction.
- Legacy `self_loop=false` is retained as metadata; the importer does not invent a loop flag or synthesize an endpoint key.

The selected clips are `O_RoamIdle` (50 frames), `O_Run_Forward` (24 frames), and `SelectIdle` (60 frames). This set covers low-amplitude root drift, forward root motion, and a static-root selection pose. It is not permission to infer behavior for the other 269 clips.

## Verification

Run:

```powershell
pwsh -NoProfile -File E:\QQXYCodeDev\Rebuild\Tests\Contract\Test-UEAnimationImport.ps1 -RequireAutomationEvidence
```

`TMXY.Importer.Animation` rejects a valid-shape manifest with a corrupt artifact hash, checks every imported bone key against the authoritative glTF, checks timing and endpoint discontinuities, confirms the root/loop policies, and proves that reimport of all three packages is byte-identical. Its generated report is validated by `ue-animation-import-report-v1.schema.json`.

The checked-in `.uasset` files are golden test assets only. Bulk exported animations and legacy packages stay outside Git/LFS and remain read-only evidence or object-storage material.
