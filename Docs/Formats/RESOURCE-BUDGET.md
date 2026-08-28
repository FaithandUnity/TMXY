# P2-19 resource-budget contract

P2-19 replaces the original rough intervals with a reproducible conditional
model while preserving every remaining measurement gap. Its output is a
planning baseline, not a commitment.

## Evidence and basis

The generator reads only the resource-budget policy, P2-15 aggregate routing
evidence, P2-18 aggregate health evidence, and the sanitized P2-19 pilot. It
verifies the three file hashes, the P2-18-to-P2-15 binding, and the
pilot-to-P2-15 binding. The report records a deterministic aggregate digest.

Every reported quantity references one or more basis IDs. The five required
categories are:

1. `measured_fact`: inventories, the selected-case pilot observations, and the
   pilot-time host/storage snapshot;
2. `planning_coefficient`: P2-15 effort or fallback machine coefficients and
   the original P3-P8 phase ranges;
3. `assumption`: linear pilot extrapolation, team productivity, storage
   multipliers, overlap, and scenario staffing;
4. `risk_reserve`: increments shown separately from their bases;
5. `missing_measurement`: facts that still prevent price, capacity, or schedule
   authority.

The pilot records five elapsed-time series and stable output hashes. Those
selected-case measurements do not establish population throughput. P2-19 uses
an explicit assumption that p80 time and output ratio scale linearly with
alias-excluded ready conversion-job bytes. The report never labels an
extrapolated total as a measured fact.

## Human model

For each P2-15 route:

```text
reserve_hours = base_planning_hours * route_reserve_basis_points / 10,000
risk_adjusted_hours = base_planning_hours + reserve_hours
```

All arithmetic uses `Decimal`; JSON numbers are rounded only at the output
boundary. Measured human time is zero. The 2/3/4-content-specialist scenarios
divide base and reserve independently by 28 productive hours per FTE-week.
These FTE values, skills, and productive hours are assumptions.

No currency or approved labor, machine, storage, license, or vendor rates are
available. The monetary budget therefore remains `estimated=false`, with null
currency and amount.

## Machine model

QTX, SM, SKEM, ANIM, and TER use the selected pilot case for their family:

```text
family_p80_seconds = pilot_p80_seconds
                     * family_ready_unique_job_bytes
                     / pilot_input_bytes
```

The automatic interchange route is the sum of these assumed byte-linear p80
projections. Audio and ZIF retain P2-15 sequential planning coefficients;
manual routes remain zero-machine placeholders pending intervention. A separate
5,000-basis-point reserve applies to every route base.

The result is sequential machine time. It cannot be divided by the visible CPU
count to obtain wall time. CPU time, peak RSS, peak temporary disk, I/O
saturation, verified cache-hit rate, and parallel scaling are all missing.

## Storage model

The model never subtracts the 1,286,887,829 review-only duplicate bytes. Safe
aliases are excluded before ready-job input bytes enter a projection, so the
same conversion output is not budgeted twice.

For the five pilot families, selected-case output ratios are byte-linearly
extrapolated. Audio, ZIF, and manual routes use policy assumptions. UE content
and build cache use separate policy multipliers. One complete copy contains
retained source, measured metadata, intermediate output, UE content, and build
cache. Two additional durable recovery copies are budgeted, followed by a
separate 3,500-basis-point reserve.

Incremental required bytes are compared with the pilot-time free bytes on the
workspace volume:

```text
capacity_gap_bytes = max(0, incremental_required_bytes - disk_free_bytes)
```

Existing workspace occupancy is reported separately because current free space
already reflects it. A zero capacity gap would not prove I/O or temporary-space
adequacy.

## Program and authority boundary

P3-P8 retain their original minimum/maximum ranges. Each constrained,
recommended, or accelerated scenario applies its phase-overlap coefficient,
then reports calendar reserve as a separate range. Team sizes and skill mix are
assumptions.

G2 blocking delay is `null` and `unbounded`; it is excluded from every P3-P8
range. Consequently the report supplies no delivery date. G2 approval,
playability, money estimation, schedule commitment, and release authority all
remain false. The PostgreSQL `gosu` waiver status is outside this calculation
and remains governed by its independent approval boundary.
