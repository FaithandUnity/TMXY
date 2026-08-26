# Legacy SM static-mesh contract

Status: P1-14 frozen evidence contract, schema version 1.

## 1. Scope and input pairing

A legacy static mesh is split across two files. A `QStaticMesh` object in a
Package contains material references, declared bounds, and an optional
`useLightMap` property. The matching
`Resource/StaticMesh/<package>/<object>.sm` file contains the geometry and
runtime acceleration data. Conversion requires both inputs; filename or byte
length is never used to invent missing Package metadata.

All scalar fields use little-endian encoding. Every serialized array begins
with a signed 32-bit count. Negative counts, configured-limit violations,
integer overflow, truncated values, non-finite floats, invalid indices, and
unconsumed bytes are hard errors with stable absolute offsets.

## 2. SM payload order

The payload has no magic or version header. Fields occur in this order:

| Order | Field | Element encoding |
|---:|---|---|
| 1 | render positions | `float32 x, y, z` |
| 2 | render normals | `float32 x, y, z` |
| 3 | UV channel 0 | `float32 u, v` |
| 4 | tangents | `float32 x, y, z` |
| 5 | binormals | `float32 x, y, z` |
| 6 | render indices | `uint16` |
| 7 | sections | record described below |
| 8 | shadow positions | `float32 x, y, z` |
| 9 | shadow normals | `float32 x, y, z` |
| 10 | shadow indices | `uint16` |
| 11 | collision positions | `float32 x, y, z` |
| 12 | collision indices | `uint16` |
| 13 | collision-octree selector | signed 32-bit boolean, only 0 or 1 |
| 14 | octree nodes | record described below |
| 15 | octree indices | `uint16`; present only when node count is non-zero |
| 16 | emitter points | optional array of `float32 x, y, z` |
| 17 | UV channel 1 | optional array of `float32 u, v` |

A section record is `int32 triangle_count`, `int32 minimum_vertex_index`,
`int32 maximum_vertex_index`, followed by a one-byte boolean `two_sided`.
Sections partition the render index buffer contiguously in Package material
slot order. Section triangle totals must cover the index buffer exactly, and
every referenced vertex must fall within that section's declared range.

An octree node stores maximum and minimum `Vec3`, signed 32-bit face count and
first-face values, then eight signed 32-bit child identifiers. `-1` means no
child. A node whose eight identifiers are all `-1` is a leaf, so its
first/count range is validated against the octree index array. The legacy
writer also persists face-range values on internal nodes, but those values are
not leaf index spans and are not rejected merely for exceeding the serialized
leaf array.

The optional tail has no presence flags. Remaining bytes after the octree
first encode emitter points, and any bytes after that encode UV1. This means a
file cannot encode UV1 while omitting the emitter array header; a zero-count
emitter array is the required placeholder.

## 3. Package descriptor

The `QStaticMesh` body uses the legacy `QObject::serialize` record envelope:

| Field | Encoding |
|---|---|
| item count | little-endian `uint16` |
| property name | little-endian `uint16` byte count followed by name bytes |
| property size | little-endian `uint16` |
| property bytes | property-specific payload |

Known properties are:

- `skins`: `uint16` material-slot count;
- `skins[n]`: length-prefixed material object name;
- `bBox.min.{x,y,z}` and `bBox.max.{x,y,z}`: finite `float32` components;
- `useLightMap`: one-byte boolean.

Material indices must be unique, dense from zero, and equal the number of SM
sections. Unknown properties are preserved as named byte spans. Some real
packages have a declared box that includes the origin, matches collision
geometry exactly, or is stale after external SM replacement. The reader
therefore records the relation as `absent`, `exact`, `contains`, or `mismatch`;
only an internally inverted declared box is corrupt.

## 4. Coordinate and intermediate policy

Parsed geometry remains in legacy runtime coordinates: X forward, Y right, Z
up, in meters. The deterministic JSON metadata preserves those bounds and also
reports centimeter-scaled bounds. The OBJ preview applies the frozen
`TMXY.Transform` contract: positions are converted to centimeters, normals are
validated and normalized, UVs preserve their orientation, and triangle winding
and section order are unchanged.

The authoritative render intermediate is glTF 2.0 JSON plus an external BIN.
Positions and normals use the handedness-preserving cyclic mapping
`(legacy.y, legacy.z, legacy.x)`, remain in meters, and preserve triangle and
material-section order. POSITION, normalized NORMAL, TEXCOORD_0, optional
TEXCOORD_1, unsigned-short indices, primitive-per-section material binding and
two-sided policy are explicit. OBJ remains a review/debug intermediate. It
cannot preserve the shadow mesh, collision mesh, octree, second UV channel, or
emitter-point semantics completely; the metadata JSON makes those omissions
explicit through counts and section/material bindings.

## 5. Defensive limits

The default reader limits are 4,000,000 vertices per vertex-like array,
50,000,000 indices per index array, 4,096 sections, 4,000,000 octree nodes, and
4,000,000 emitter points. Callers may lower these limits for a narrower import
job. The parser allocates only after validating each count and does not link or
execute legacy runtime code.

## 6. Frozen real samples

| Object | Render vertices | Indices | Sections | Boundary represented |
|---|---:|---:|---:|---|
| `particle.ZFH_O_S_Tianpian100` | 4 | 6 | 1 | minimum mesh/no optional runtime arrays |
| `newscenc.dy_bx_stl_005` | 157,638 | 157,638 | 1 | large mesh/shadow/octree/UV1 |
| `newscenc.dy_bx_bqg_006` | 47,964 | 250,614 | 1 | large shadow topology/stale declared bounds |
| `scene09.GT_B_S_BangPai05` | 11,847 | 19,533 | 43 | multi-section material binding/collision octree |

The authoritative SHA-256 values for these Package and SM files and the legacy
format evidence are enforced by `Tests/Contract/Test-SmStaticMesh.ps1` and
recorded in `Data/BuildBaseline/p1-14-sm-static-mesh.json`.

## 7. Explicit non-goals

The offline module does not create Unreal assets, synthesize materials, rebuild
collision, or reinterpret stale Package bounds. glTF/BIN carries authoritative
render geometry while legacy-only collision, octree, emitter, bounds and source
spans remain in metadata. The legacy client and tools remain read-only evidence
and never enter the new runtime.
