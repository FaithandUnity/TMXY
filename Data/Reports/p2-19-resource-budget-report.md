# P2-19 Resource Budget

Result: `PASS_WITH_OPEN_MEASUREMENT_GAPS`; status: `CONDITIONAL_PLANNING_BASELINE`.

This is a conditional, non-price planning baseline. It is not a delivery commitment, playable-build claim, G2 approval, or release authority.

## Input bindings

| Input | Task | SHA-256 |
|---|---|---|
| conversion_routing | P2-15 | `c0cf266aff9c043f91839f1540500dcf0e23b82fffb13ea5f6d2f13c0030be54` |
| content_health | P2-18 | `afb00c48630ed7cc9047beb2eee73b0118bd85baba2ae8a9d6fd34c0d780d829` |
| conversion_pilot | P2-19-PILOT | `e693119bd8bb6c9200a441f73207ad4616c3cf380da0bac31de7131d7b715ff2` |

## Human budget

Measured human hours: **0**. Route values remain P2-15 planning coefficients plus separate reserves.

| Route | Base h | Reserve bp | Reserve h | Risk-adjusted h |
|---|---:|---:|---:|---:|
| automatic-qualified-interchange | 392.25 | 2,500 | 98.062 | 490.312 |
| automatic-standard-audio | 33.77 | 2,500 | 8.443 | 42.212 |
| semi-automatic-navigation-adaptation | 361.675 | 4,000 | 144.67 | 506.345 |
| manual-descriptor-recovery | 473 | 5,000 | 236.5 | 709.5 |
| manual-repair-or-replace | 144 | 7,500 | 108 | 252 |

Total: 1,404.695 base h + 595.675 reserve h = 2,000.37 planning h.

| Content specialists | Productive h/FTE-week | Base weeks | Reserve weeks | Risk-adjusted weeks |
|---:|---:|---:|---:|---:|
| 2 | 28 | 25.084 | 10.637 | 35.721 |
| 3 | 28 | 16.723 | 7.091 | 23.814 |
| 4 | 28 | 12.542 | 5.319 | 17.86 |

Money budget: **not estimated**; currency and all required rate cards are missing.

## Machine budget

Projection status: `PARTIALLY_PILOT_CALIBRATED`. Sequential seconds do not establish wall time or fleet size.

| Route | Pilot runs | Base s | Reserve s | Total s |
|---|---:|---:|---:|---:|
| automatic-qualified-interchange | 25 | 151.423 | 75.712 | 227.135 |
| automatic-standard-audio | 0 | 2,400 | 1,200 | 3,600 |
| semi-automatic-navigation-adaptation | 0 | 8,060 | 4,030 | 12,090 |
| manual-descriptor-recovery | 0 | 0 | 0 | 0 |
| manual-repair-or-replace | 0 | 0 | 0 | 0 |

Total: 10,611.423 base s + 5,305.712 reserve s = 15,917.135 sequential s.

Five interchange families use a **planning assumption** that selected-case p80 scales linearly with alias-excluded ready-job bytes. Audio/navigation retain planning coefficients. CPU time, peak RSS/temp, I/O, cache hits, and parallel scaling are missing.

## Storage budget

Pilot output ratios are also **planning-assumption byte-linear extrapolations**. Review-only duplicate bytes are not deducted.

| Item | Bytes |
|---|---:|
| Existing workspace | 46,581,322,601 |
| Source retained | 8,882,019,027 |
| Intermediate | 15,256,368,337 |
| UE content | 22,884,552,506 |
| Build cache | 45,769,105,012 |
| Two recovery copies | 186,408,712,246 |
| Storage reserve | 94,611,558,336 |
| Incremental required | 364,930,296,437 |
| Current volume free | 199,823,572,992 |
| Capacity gap | 165,106,723,445 |

## Conditional P3-P8 scenarios

G2 blocking delay is **unbounded** and `null`; every range excludes it.

| Scenario | Core/shared FTE | Base weeks | Reserve weeks | Conditional total |
|---|---:|---:|---:|---:|
| constrained | 8/1 | 52.7–103.7 | 15.81–31.11 | 68.51–134.81 |
| recommended | 10/1.5 | 43.4–85.4 | 10.85–21.35 | 54.25–106.75 |
| accelerated | 12/2 | 37.2–73.2 | 7.44–14.64 | 44.64–87.84 |

Team composition, productive hours, overlap, and reserve are assumptions.

## Open measurements

- `MIS-001`: Measured human handling time is zero across all routes. Next: Run role-tagged time studies for review, adaptation, recovery, and repair.
- `MIS-002`: The pilot has one deterministic case per measured family. Next: Run deterministic family and size-stratified pilots.
- `MIS-003`: CPU time is not measured. Next: Capture process CPU seconds for cold and warm runs.
- `MIS-004`: Peak RSS is not measured. Next: Capture process and aggregate peak resident memory.
- `MIS-005`: Peak temporary storage is not measured. Next: Measure per-family temporary-space high-water marks.
- `MIS-006`: I/O throughput and saturation are not measured. Next: Measure bytes read/written and fixed-worker scaling.
- `MIS-007`: Cold/warm cache hit rates are not measured. Next: Replay unchanged and controlled-mutation verified-cache workloads.
- `MIS-008`: Parallel scaling efficiency is not measured. Next: Benchmark 1, 2, 4, and 8 workers.
- `MIS-009`: Audio, navigation, manual, UE, and build-cache ratios are assumptions. Next: Measure outputs and temporary bytes for missing routes.
- `MIS-010`: Currency and labor, machine, storage, license, and vendor rates are absent. Next: Supply approved currency and dated rate cards.
- `MIS-011`: G2 blocker resolution duration is unbounded. Next: Resolve P2-20 evidence queues and approve G2.

## Decision boundary

Budget accounting supports a conditional baseline only. Price, G2, playability, schedule commitment, and release authority remain unavailable.
