# TMXY.G2AuxEcfParserParity

This P2-20A.10 tool adds a non-mutating diagnostic overlay for the 64 frozen ECF instances. It
separates the immutable P2-20A.5 baseline, the actual frozen A.3 output, and a source-derived
reference built from the observed legacy transform and CRLF pair-parser contracts.

Generate the ignored 64-record anonymous detail and tracked report, Markdown, and inventory:

```powershell
.\Tools\TMXY.G2AuxEcfParserParity\New-G2AuxEcfParserParity.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacySourceRoot E:\QQXYCodeDev\ClientCode
```

Verify deterministic regeneration without replacing outputs:

```powershell
.\Tools\TMXY.G2AuxEcfParserParity\New-G2AuxEcfParserParity.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacySourceRoot E:\QQXYCodeDev\ClientCode `
  -Check
```

Run the contract after generation:

```powershell
.\Tests\Contract\Test-G2AuxEcfParserParity.ps1 -RebuildRoot E:\QQXYCodeDev\Rebuild
```

The two independent diagnostic ports agree for all 64 instances. That is source-derived diagnostic
self-consistency, not legacy runtime execution or compiled-binary parity. The overlay does not rewrite
A.3, approve the four additional pair records as valid semantic assignments, select candidates, approve
roots or adapters, satisfy G2-06, or authorize P3.
