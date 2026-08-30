# TMXY.G2AuxPackageContext

This P2-20A.9 tool cross-proves package-context selection for the 211 object references left ambiguous
by P2-20A.5. It verifies all 212 source instances, replays the 135 strict region instances through the
observed consumer fields, retains the complete frozen candidate sets, and accepts a selection only
when the production package prefix yields one order-invariant member.

Generate the ignored 135-record detail and the tracked report, Markdown, and inventory evidence:

```powershell
.\Tools\TMXY.G2AuxPackageContext\New-G2AuxPackageContext.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacySourceRoot E:\QQXYCodeDev
```

Verify deterministic regeneration without replacing outputs:

```powershell
.\Tools\TMXY.G2AuxPackageContext\New-G2AuxPackageContext.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild `
  -LegacySourceRoot E:\QQXYCodeDev `
  -Check
```

Run the contract after generation:

```powershell
.\Tests\Contract\Test-G2AuxPackageContext.ps1 `
  -RebuildRoot E:\QQXYCodeDev\Rebuild
```

The successful technical result is 211 singleton package-context matches and no remaining ambiguous
region object reference. One region resource remains unresolved. The task and G2-06 remain blocked:
P2-20A.9 grants no consumer-contract approval, no no-reference disposition, no root authority, and no
permission to collapse shadow instances or authorize P3.
