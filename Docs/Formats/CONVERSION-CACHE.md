# P2-16 content-addressed conversion cache

P2-16 defines deterministic incremental conversion keys for every P2-15 plan
row. It does not claim that converted outputs already exist and it does not
authorize shared-cache writes. A cache hit requires both a matching key and a
locally verified output byte length and SHA-256.

The full local plan is
`Data/Exports/P2-16/p2-16-conversion-cache-plan.jsonl`. It contains 40,090
records, is 28,389,045 bytes, and has SHA-256
`eb7991ca638edbb0029fb20b34b2f794380d6ff202413734e7abd46e78ff4afb`.
It remains Git-ignored because rows contain paths, source hashes, descriptor
scope hashes, and content keys. Tracked evidence contains only aggregates and
input hashes.

## Key material

Every ready key is SHA-256 over canonical compact UTF-8 JSON containing:

- namespace and stable asset ID;
- family and P2-15 route;
- complete source payload SHA-256;
- SHA-256 of the complete interpreted P2-12 row;
- descriptor scope SHA-256;
- family converter and P1-19 interchange source SHA-256;
- P2-15 routing-policy SHA-256;
- target UE/import profile SHA-256.

File timestamps and absolute paths are excluded. QTX, SM, SKEM, ANIM, and TER
depend on Package descriptors, so their keys bind the complete P2-03 descriptor
graph SHA-256. This is deliberately safe and coarse: any graph change
invalidates all 32,515 ready qualified-interchange jobs until a future proven
per-object descriptor digest can narrow the scope.

## Coverage and fail-closed states

There are 33,801 ready conversion jobs with 33,801 distinct keys. Another 5,489
source-path aliases share their explicitly selected representative key, giving
39,290 assets a ready key assignment. The remaining 800 jobs are manual:
756 QTX and 30 ANIM descriptor recoveries plus 12 SM and 2 SKEM repairs. They
remain `blocked-manual-input`; P2-16 forbids a final cache key until a reviewed
intervention digest is supplied.

| Family | Files | Jobs | Aliases | Ready jobs | Blocked jobs |
|---|---:|---:|---:|---:|---:|
| ANIM | 1,069 | 1,069 | 0 | 1,039 | 30 |
| MP3 | 64 | 61 | 3 | 61 | 0 |
| QTX | 24,798 | 24,798 | 0 | 24,042 | 756 |
| SKEM | 1,068 | 990 | 78 | 988 | 2 |
| SM | 2,924 | 2,826 | 98 | 2,814 | 12 |
| TER | 8,876 | 3,632 | 5,244 | 3,632 | 0 |
| WAV | 450 | 419 | 31 | 419 | 0 |
| ZIF | 841 | 806 | 35 | 806 | 0 |

Full-data mutation proofs freeze the invalidation boundary. An unchanged rebuild
keeps all 33,801 ready keys. Mutating one source changes exactly one pre-reroute
job key. Routing-policy or target-profile mutation changes all 33,801 keys.
Descriptor-graph mutation changes 32,515 keys. Family converter mutations change
ANIM/MP3/QTX/SKEM/SM/TER/WAV/ZIF keys by
1,039/61/24,042/988/2,814/3,632/419/806 respectively.

The resolver treats a missing manifest entry, missing artifact, unsafe path,
byte-length mismatch, SHA-256 mismatch, or duplicate manifest key as a miss or
corrupt failure. A manifest is never trusted by itself.

```powershell
.\Tools\TMXY.ConversionCache\Find-ConversionCachePlan.ps1 -State ready -Family qtx
.\Tools\TMXY.ConversionCache\Find-ConversionCachePlan.ps1 -State blocked-manual-input
.\Tools\TMXY.ConversionCache\Test-ConversionCacheEntry.ps1 -PlanPath <plan> -ManifestPath <manifest> -ArtifactRoot <root>
```

Generation runs in the qualified non-root builder with no network, a read-only
workspace and container filesystem, no capabilities, and no new privileges.
`-Check` requires byte-identical plan and evidence regeneration.
