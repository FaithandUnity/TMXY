# TMXY.G2QtxDeclaredMipPayloadPrefix

P2-20A.13 freezes six single-candidate QTX edges from A.7. Each descriptor explicitly stores one
mip, while the input payload ends on a larger natural mip boundary. The production default remains
strict and rejects all six complete inputs with `payload_size_mismatch`; only the explicitly named
`QtxReader::parse_with_declared_mip_payload_prefix` API may consume the declared one-mip prefix.

Prepare derives the probe scope directly from the frozen policy, tracked anonymous 21-row base-plan
contract, P2-12 catalog, and P2-03 package graph. It does not require the ignored A.8 attempt TSV and
does not read current A.4/A.7/A.8/Core effective-state reports. Finalize then
revalidates those post-application reports and hashes, compares decoded mip zero against a strict
parse of the isolated prefix, and proves that DDS output contains exactly its 128-byte header plus
that prefix. Ignored bytes are neither decoded nor exported; only their byte count and SHA-256 are
recorded. The three DXT5 inputs stop at boundary 7 of maximum 9, so this module deliberately uses
“complete payload boundary,” never “complete natural chain,” for the common relation.

Four remaining QTX targets / six candidate edges are frozen as exclusions. The module also derives
a 21-row effective recovery plan from the tracked base-plan contract by changing only the six selected
`recovery_kind` cells. It never selects a candidate or mutates A.4 authority.

After regenerating the independently reproducible P2-03 and P2-12 exports, publish only the
effective plan without reading the ignored A.4/A.7/A.8/Core chain:

```powershell
.\Tools\TMXY.G2QtxDeclaredMipPayloadPrefix\New-G2QtxDeclaredMipPayloadPrefix.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -Mode Prepare
```

After A.4, A.7, A.8 Finalize, and Core have been regenerated, publish the final POST report:

```powershell
.\Tools\TMXY.G2QtxDeclaredMipPayloadPrefix\New-G2QtxDeclaredMipPayloadPrefix.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游 `
  -LegacyClientSourceRoot E:\QQXYCodeDev\ClientCode `
  -Mode Finalize
```

Verify byte-for-byte regeneration while preserving the captured timestamp:

```powershell
.\Tools\TMXY.G2QtxDeclaredMipPayloadPrefix\New-G2QtxDeclaredMipPayloadPrefix.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacyClientRoot E:\QQXYCodeDev\天命西游 `
  -LegacyClientSourceRoot E:\QQXYCodeDev\ClientCode `
  -Mode Finalize `
  -Check
```

The wrapper uses the qualified non-root Clang 21 container with networking disabled, a read-only
container filesystem, read-only repository/legacy mounts, and individually hash-resolved read-only
legacy source files. The result is `PASS_DIAGNOSTIC` / `BLOCKED`, `SOURCE_DERIVED`, with legacy
binary/runtime parity false and selection, disposition, repair, recovery application, authority
change, G2-06, and P3 all false. Final tracked evidence accepts only `POST_APPLICATION` with exact
6 resolved targets / 6 passing edges / 6 applied recovery edges; Prepare remains plan-only.
