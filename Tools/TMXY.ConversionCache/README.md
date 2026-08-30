# TMXY.ConversionCache

P2-16 creates content-addressed conversion keys for the P2-15 plan. A ready key
binds payload SHA-256, interpreted P2-12 record, descriptor scope, family
converter source, interchange source, routing policy, and target profile.
Timestamps and absolute paths are never key material.

Manual descriptor recovery and repair remain blocked until a reviewed
intervention digest exists. A key match alone is not a cache hit: the resolver
must also verify the declared output size and SHA-256. Shared cache writes remain
unauthorized outside a trusted pipeline.

```powershell
.\Tools\TMXY.ConversionCache\New-ConversionCachePlan.ps1
.\Tools\TMXY.ConversionCache\New-ConversionCachePlan.ps1 -Check
.\Tools\TMXY.ConversionCache\Find-ConversionCachePlan.ps1 -State blocked-manual-input
```

The full plan remains in ignored `Data/Exports/P2-16`; Git tracks only policy,
implementation, tests, documentation, and aggregate evidence.
