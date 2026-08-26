# UE Golden Automation Host

P1-20 establishes a real UE 5.8.2 Editor automation host without importing legacy assets. The fixed content root is
`/Game/TMXY/Golden`; the only P1-20 package is
`/Game/TMXY/Golden/Maps/TMXYGoldenTestMap`.

## Runtime boundary

`TMXYGoldenTests` is an Editor module loaded at `PostEngineInit`. It owns `TMXY.Golden.Host`, which checks the fixed
root, resolves and loads the Map package, confirms that it contains a `UWorld` with a persistent level, and rejects
World Partition for this minimal fixture. The module is absent from the Windows client target and adds no runtime
dependency.

P1-20 must contain exactly one `.umap` and no `.uasset`. Raw Package files, bulk exports, cooked content, DDC and
assets copied from the installed client are forbidden. `TMXYImporter` is intentionally not created until P1-21 has
its first executable import path.

## Deterministic host generation

`Apps/UEClient/Scripts/CreateGoldenHostMap.py` targets exactly the fixed Map. It may be run only with the locked UE
5.8.2 editor; `PythonScriptPlugin` is enabled for that command only and is not added to the project descriptor:

```powershell
& 'C:\Program Files\Epic Games\UE_5.8\Engine\Binaries\Win64\UnrealEditor-Cmd.exe' `
  'E:\QQXYCodeDev\Rebuild\Apps\UEClient\TMXY.uproject' `
  -run=PythonScript `
  '-Script=E:\QQXYCodeDev\Rebuild\Apps\UEClient\Scripts\CreateGoldenHostMap.py' `
  -EnablePlugins=PythonScriptPlugin -Unattended -NoP4 -NullRHI -NoSound
```

Regeneration changes a binary package and therefore requires the P1-20 contract, headless Automation and LFS pointer
review before acceptance. The contract locks the current Map SHA-256 and Unreal package tag.

## Before and after report

`ue-golden-import-report-v1.schema.json` is the stable hand-off to P1-21. Every importer run records package snapshots
before and after execution, the fixed root and Map, its interchange manifest, import mode, outcome, warnings and
errors. Package names outside the golden root, absolute manifest paths and unknown root properties are rejected.

The P1-20 example is deliberately `validate-only`: before and after inventories are identical, status is `not-run`,
and the imported asset count is zero. A later `single-fixture` or explicitly reviewed `batch` run may change the
inventory, but it must still emit the same versioned report contract.

## Headless entry

Run all project automation, including the golden host, with:

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tests\Contract\Test-UEProjectBaseline.ps1' -RunAutomation
```

Acceptance requires both `TMXY.Core.BuildInfo` and `TMXY.Golden.Host` to report `Success`. The P1-20 contract also
checks the Editor-only module descriptor, generation-script scope, report Schema, exact content inventory and the
current UE evidence hash.
