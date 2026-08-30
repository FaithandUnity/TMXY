# TMXY.G2StaticMeshPayloadSectionPrefix

P2-20A.12 freezes the single static-mesh target and its two candidate edges from A.7. The probe
revalidates the asset, package, body, descriptor, and semantic hashes; confirms that the strict
production binder still rejects both edges with `material_slot_mismatch`; and exercises only the
explicit `bind_static_mesh_with_payload_section_prefix` API.

The observed relation is identical on both edges: two dense descriptor material slots, one nonempty
payload section, and one ignored trailing descriptor slot. Seven hash-locked legacy source roles are
also checked for the exporter, factory, renderer, and payload-order facts that support this bounded
interpretation. Tracked output contains role names and hashes only, never legacy paths or lines.

Generate the ignored anonymous detail and tracked report, Markdown, and inventory:

```powershell
.\Tools\TMXY.G2StaticMeshPayloadSectionPrefix\New-G2StaticMeshPayloadSectionPrefix.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游 `
  -LegacyClientSourceRoot E:\QQXYCodeDev\ClientCode `
  -LegacyToolSourceRoot E:\QQXYCodeDev\ToolCode
```

Verify byte-for-byte regeneration while preserving the captured timestamp:

```powershell
.\Tools\TMXY.G2StaticMeshPayloadSectionPrefix\New-G2StaticMeshPayloadSectionPrefix.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游 `
  -LegacyClientSourceRoot E:\QQXYCodeDev\ClientCode `
  -LegacyToolSourceRoot E:\QQXYCodeDev\ToolCode `
  -Check
```

The wrapper requires the qualified non-root Clang 21 container. It disables networking, makes the
container filesystem read-only, mounts the repository and legacy assets read-only, and mounts each
resolved legacy source role as a read-only file. Finalization hash-binds A.4, A.7, and A.8 and
requires their current effective counts to reconcile before publishing the A.7 blocker object. The
result is `PASS_DIAGNOSTIC` with task status `BLOCKED`: A.4 remains authoritative, the same one SM
target / two edges remain unresolved, no adapter or recovery is applied, and G2-06 and P3 remain
false. In the current post-A.13 chain the global effective remainder is 6 targets / 9 edges; those
counts are derived from the bound upstream evidence rather than frozen in the A.12 policy.
