# P2-20A.13 QTX Declared-Mip Payload-Prefix Source Proof

- Execution: `PASS_DIAGNOSTIC`; task: `BLOCKED`
- Upstream effective phase: `POST_APPLICATION`
- Frozen scope: 6 targets / 6 unique candidate edges; excluded: 4 targets / 6 edges
- DXT1: 3 x 512x512, boundary 10 / max 10, 174776 = 131072 + 43704 bytes
- DXT5: 3 x 256x256, boundary 7 / max 9, 87376 = 65536 + 21840 bytes
- Default strict parser: 6 payload-size rejections; explicit prefix API: 6 passes
- Effective plan: 21 rows, exactly 6 recovery-kind cells changed
- Preserved effective unresolved: 6 targets / 9 edges

This hash-locked `SOURCE_DERIVED` diagnostic executes no legacy binary and proves no runtime parity. It makes no selection, disposition, repair, recovery application, or authority change; G2-06 and P3 remain blocked.
