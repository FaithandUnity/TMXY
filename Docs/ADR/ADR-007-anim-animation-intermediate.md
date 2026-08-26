# ADR-007: Bind ordered Package animation metadata to dense-prefix ANIM tracks

- Status: Accepted
- Date: 2026-08-26
- Decision owner: P1 format proof workstream

## Context

Legacy `.anim` files have no magic, names, skeleton identity, frame rate or
loop metadata. `QSkelMesh._anim` provides object order and each `QSkelAnim`
object provides metadata. Real Boy01 payloads use fewer tracks than the full
skeleton for some clips, while the old optimized player loops only over the
animation track array. Treating this as missing data or forcing an 80-track
equality check would reject valid evidence.

The old player also uses different wrap periods depending on `_selfLoop`, and
updates bone zero without a separate extraction path. A modern importer must
see these distinctions before choosing UE animation and Root Motion policy.

## Decision

Create the platform-neutral C++20 `TMXY.Animation` module. Bind the Package
`QSkelMesh` animation-reference order to validated `QSkelAnim` metadata and the
matching headerless ANIM stream. Model track IDs as a dense skeleton prefix,
require Package/payload frame equality, preserve every finite non-zero-
quaternion key, and parse only the evidence-backed optional emitter tail.

Report sampled duration and legacy loop period separately. Measure root-track
translation, rotation and maximum excursion without extracting or rewriting
the track. Emit deterministic JSON summaries and a complete root-track CSV.
Keep raw keys in the in-memory model for P1-19/P1-25, but do not serialize an
invented final binary format in this task.

## Consequences

- A usable conversion requires the Package, its QSkelMesh object and the
  matching `.anim`; a zero-animation file remains valid for structural proof.
- Partial Boy01 tracks remain valid and explicitly mean dense prefix coverage.
- Frame count, rate, key count, track order, looping and Root Motion are all
  independently reproducible.
- Notify references are preserved but never executed by offline tooling.
- Root Motion policy stays visible and deferred instead of being silently
  baked, removed or inferred.
- The module links neither legacy runtime nor Unreal and is validated in the
  locked non-root Linux Clang 21 environment.
