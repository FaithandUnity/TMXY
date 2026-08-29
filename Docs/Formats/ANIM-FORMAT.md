# Legacy ANIM skeletal-animation contract

Status: P1-16 frozen evidence contract, schema version 1.

## 1. Scope and binding

A character animation set is split across three ordered inputs:

1. Package `QSkelMesh._anim[n]` supplies the exact animation object order;
2. each referenced Package `QSkelAnim` supplies name, skeleton name, frame count,
   frame delta, self-loop flag and notify references;
3. the matching headerless `.anim` file supplies dense bone tracks and keys in
   that same order.

The parser binds all three. It never guesses an animation name from a file path
and never links the legacy runtime. All binary scalars are little-endian.

## 2. Package QSkelAnim metadata

The object body uses the same `uint16 record_count` and
`name_length/name/property_size/value` envelope as other Package objects.
Known fields are:

| Property | Encoding | Rule |
|---|---|---|
| `_animName` | length-prefixed opaque bytes | required |
| `_skeName` | length-prefixed opaque bytes | required |
| `_frame` | `int32` | required and positive |
| `_frameDelta` | `float32` seconds | required, finite and positive |
| `_selfLoop` | one-byte boolean | optional; omitted means false |
| `notify` | `uint16` count | optional; omitted means zero |
| `notify[n]` | length-prefixed object reference | dense and ordered |

Unknown properties are retained with their source value offset and bytes.
Notify object bodies are not executed; references are preserved for a later
versioned importer policy.

## 3. ANIM payload layout

The file begins with `int32 animation_count`. For every Package animation
reference, in order, it then contains:

| Field | Encoding |
|---|---|
| track count | `int32` |
| frame count | `int32` |
| keys | `track_count * frame_count` records |

One key is exactly 28 bytes: quaternion `x,y,z,w` followed by local translation
`x,y,z`, all `float32`. Storage order is bone-major, then frame-major.
Quaternion components are preserved as evidence; every component must be
finite and the quaternion norm must be non-zero.

Track IDs are the dense prefix `0..track_count-1` of the owning skeleton. This
is evidence-backed, not an inference: the old optimized update loops over
`QSkelAnim::_skeAnim.size()`, while Boy01 legitimately uses 22 through 80
tracks against an 80-bone skeleton. A smaller track count therefore leaves
the skeleton tail uncontrolled by that animation; it is not a corrupt file.
Track count must still be positive and no larger than the skeleton.

The default binder requires the payload frame count to exactly equal Package
`_frame`. The outer animation count must exactly equal `QSkelMesh._anim` count.

P2-20A.8 adds a separate explicit adapter for a hash-bound A.7
`frame_count_mismatch` edge. In that mode every clip retains the Package value
as `declared_frame_count`, records the payload value as
`observed_frame_count`/`effective_frame_count`, and records
`payload_observed_contract` as the basis. Recovery is accepted only when the
whole animation set closes: every positive count is within the existing limit,
every track and key is present and valid, all quaternions and emitter values
pass the original checks, and no unexplained tail remains. The default binder
continues to reject the mismatch, and invalid track counts or later payload
errors cannot be overridden by this adapter.

After all clips, an optional emitter-point tail may appear as `int32 count`
followed by `count` finite `float32 x,y,z` vectors. No other trailing bytes are
accepted. A four-byte zero animation count is the valid global-minimum file.

## 4. Duration and looping

Two values are reported deliberately:

- sampled duration: `(frame_count - 1) * frame_delta`;
- legacy loop period: `_selfLoop ? (frame_count - 1) : frame_count`, multiplied
  by `frame_delta`.

The distinction reproduces old playback behavior. `_selfLoop=true` means the
terminal key duplicates the first key, so the old runtime skips that duplicate
when wrapping. It does not mean that gameplay must automatically loop a clip.

## 5. Root Motion evidence

Bone track 0 is measured as the root track because the old runtime updates it
like every other dense track. The parser reports:

- first-to-last local translation delta in legacy meters and UE centimeters;
- first-to-last normalized quaternion angular delta;
- maximum translation excursion from the first key;
- a deterministic moving/static classification using 0.0001 m translation or
  0.01 degree rotation thresholds.

This is analysis, not extraction. P1-16 does not remove root transforms,
rewrite child tracks, choose in-place locomotion or invent a gameplay Root
Motion policy. Deterministic root-track CSV retains every root key for review.

## 6. Outputs and limits

Deterministic JSON contains Package metadata, declared/observed/effective frame
counts and their authority basis, tracks, key counts,
duration, looping, notify references and Root Motion summaries. Root CSV
contains every root key with legacy-meter and UE-centimeter translations plus
the original quaternion. Final UE quaternion basis conversion and asset
creation belong to P1-25; the P1-16 output is an evidence intermediate, while
P1-19 owns the final versioned interchange contract.

The default safety ceiling is 1,000,000 frames per descriptor, 50,000,000
total keys, 4,096 metadata records/notifies and 1,000,000 emitter points.
Negative counts, overflow, truncation, Package/payload mismatch, non-finite
keys, zero quaternions and unexplained bytes fail closed with stable errors.

## 7. Frozen real samples

| Sample | Bytes | Clips | Tracks | Keys | Frame range | Track range | Root-moving | Boundary |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `particle/ZFH_B_S_XALGF001.anim` | 4 | 0 | 0 | 0 | n/a | n/a | 0 | global minimum |
| `skchar/Boy01.anim` | 32,855,816 | 272 | 21,702 | 1,173,344 | 12–250 | 22–80 | 261 | partial-track prefix |
| `skchar/Girl01.anim` | 33,275,128 | 270 | 21,600 | 1,188,320 | 11–341 | 80 | 254 | largest canonical pair |

Boy01 and Girl01 use `0.033333335` seconds per frame, have no Package
`_selfLoop=true` clip among their referenced sets, contain 80 notify references
each and have no emitter tail. The shared skeletons each contain 80 bones.
The input SHA-256 values and deterministic JSON/CSV fingerprints are rechecked
by `Tests/Contract/Test-AnimAnimation.ps1` and recorded in
`Data/BuildBaseline/p1-16-anim-animation.json`.

## 8. Explicit non-goals

P1-16 does not execute notifies, retarget skeletons, resample or compress keys,
repair loops, extract Root Motion, create UE assets, or define the final asset
container. Those decisions remain with P1-19 and P1-25.
