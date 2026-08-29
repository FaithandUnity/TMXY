# TMXY.G2AssetBindingFailureDiagnostics

P2-20A.7 reproduces the 19 unresolved A.4 asset bindings and captures the family-typed error object
returned by the same production qtx, static-mesh, and animation binders. It hashes error contexts and
never emits names, paths, offsets, payload values, or raw context strings.

Generate the tracked report, Markdown, inventory evidence, and ignored anonymous detail:

```powershell
.\Tools\TMXY.G2AssetBindingFailureDiagnostics\New-G2AssetBindingFailureDiagnostics.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游
```

Verify byte-for-byte deterministic regeneration without replacing outputs:

```powershell
.\Tools\TMXY.G2AssetBindingFailureDiagnostics\New-G2AssetBindingFailureDiagnostics.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游 `
  -Check
```

The wrapper uses the locked non-root builder with no network, a read-only repository mount, a
read-only legacy-client mount, dropped capabilities, and no-new-privileges. If any binder now passes,
the probe fails with `a4_binding_pass_requires_rerun`; it does not silently reduce the upstream
unresolved set.

The expected result is `PASS_DIAGNOSTIC` for execution and `BLOCKED` for the task: all 24 rejected
candidate edges receive typed error codes, while all 19 targets remain unresolved and have no
candidate selection, automatic resolution, or owner disposition.
