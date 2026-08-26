# Legacy SKEM skeletal-mesh contract

Status: P1-15 frozen evidence contract, schema version 1.

## 1. Scope and input pairing

A legacy skeletal mesh is split across a Package `QSkelMesh` object and a
matching `Resource/SkelMesh/<package>/<object>.skem` file. The Package body owns
the skeleton, local bind pose, animation references, material references and
default part selection. The headerless SKEM payload owns the selectable render
submeshes, skin weights, one-based bone indices, shadow indices and face
adjacency. A Package-bound conversion requires both inputs; a payload may be
parsed alone only for structural evidence such as the global minimum sample.

All scalars are little-endian. Every SKEM array begins with a signed 32-bit
element count. Strings use a little-endian `uint16` byte count followed by
opaque legacy name bytes. Counts are bounded before allocation; negative or
oversized counts, truncation, non-finite values, structural inconsistencies and
unconsumed trailing bytes are stable hard errors.

## 2. SKEM payload order

The file begins with `int32 group_count`. Each group then contains `int32 id`,
`int32 submesh_count`, followed by its submeshes. Every submesh has this exact
order:

| Order | Field | Element encoding |
|---:|---|---|
| 1 | section name | `uint16 byte_count` plus name bytes |
| 2 | global submesh index | `int32` |
| 3 | positions | array of `float32 x, y, z` |
| 4 | normals | array of `float32 x, y, z` |
| 5 | UV0 | array of `float32 u, v` |
| 6 | tangents | array of `float32 x, y, z` |
| 7 | binormals | array of `float32 x, y, z` |
| 8 | weights | array of four `float32` values |
| 9 | bone indices | array of four `float32` values |
| 10 | render indices | array of `uint16` |
| 11 | mesh sections | array of the 13-byte record below |
| 12 | shadow indices | array of `uint16` |
| 13 | adjacent faces | array of three raw `int32` values |

Position, normal, UV, tangent, binormal, weight and bone-index counts must be
equal. Render indices form triangles and reference the submesh vertex array.
Shadow indices reference the same vertices. Adjacent-face count equals render
triangle count; each of its three values is `-1` or a valid local face index.

A mesh-section record is `int32 triangle_count`, `int32 minimum_vertex_index`,
`int32 maximum_vertex_index`, then a one-byte boolean `two_sided`. Sections
cover the render index buffer exactly and each section's indices stay within
its declared vertex range. The global submesh index must be dense and equal the
submesh's order after flattening all groups; this is also asserted by the old
debug runtime.

## 3. Weights and bone-index semantics

The four bone indices are serialized as finite integral `float32` values even
though they are identifiers. A value of zero means no influence; positive
values are **one-based** legacy bone indices. The old CPU skinning path tests
both value and weight, then accesses `finalMat[index - 1]`. A Package-bound
reader therefore requires every positive-weight influence to have an index in
`1..bone_count`; UE-facing code must subtract one only after this validation.

Ordinary weights are in `[0,1]` and sum to one within `0.01`. One evidence-backed
exception is preserved rather than generalized: `Girl02_Body_Avter_010` has
exactly two render-referenced vertices whose four weights are all `-1` and four
bone indices are all zero. The legacy CPU path skips all four influences. The
parser recognizes only this byte-level sentinel shape, counts it explicitly as
`legacy_unweighted_sentinel_vertex_count`, and rejects other negative or
unnormalized combinations. It never silently repairs the two vertices.

## 4. Package QSkelMesh descriptor

The object body uses the legacy `QObject::serialize` envelope:

| Field | Encoding |
|---|---|
| record count | little-endian `uint16` |
| property name | `uint16` byte count plus name bytes |
| property size | little-endian `uint16` |
| property value | property-specific bytes |

Known property families are:

- `_skel` and `_skel[n]...`: bone count and flattened `QBone` records;
- `_anim` and `_anim[n]`: referenced `QSkelAnim` object names (payload decoding
  belongs to P1-16);
- `defaultAnim`: default animation name;
- `defaultSecs` and `defaultSecs[n]`: one selected global submesh index per
  group; `-1` hides that group;
- `skins` and `skins[n]`: one material object reference per group;
- `offset.{x,y,z}` and `rot.{pitch,yaw,roll}`: optional instance defaults;
- `bBox.min.{x,y,z}` and `bBox.max.{x,y,z}`: optional declared bounds.

Each bone contains `_ID` (`int32`), `_name` (length-prefixed bytes),
`_rotPose.{x,y,z,w}` (quaternion), `_tranPose.{x,y,z}` and an `_children` array
of `int32` bone IDs. Structural marker properties have zero-sized values.
Omitted numeric component properties retain the legacy property system's zero
default. Bone IDs must equal their dense array index. Child references derive
the parent table; multiple parents, self references, out-of-range references
and cycles are rejected. Roots are recorded explicitly. The serialized
rotation/translation pair is the local bind pose used by the old runtime to
build each bone's original inverse matrix.

Package `skins` and `defaultSecs` counts must both equal SKEM group count. A
non-negative default index must resolve inside the corresponding group. It is
not a per-submesh material array: one material belongs to each selectable part
group, while the hundreds of submeshes are alternative variants.

## 5. Attachment-point evidence

`QSkelMesh` contains no distinct socket record. The old runtime exposes
`findBone(name)` and attachment/effect code resolves a bone by name. The
intermediate output therefore labels every validated bone name as an
`attachment_point_candidate` and states this contract explicitly. It does not
invent UE sockets or infer special names. P1-24 preserves this bone-name lookup
policy and creates no UE sockets without separate authored evidence.

## 6. Coordinate and output policy

Parsed metadata remains in legacy runtime coordinates: X forward, Y right,
Z up, in meters. Deterministic JSON reports the complete skeleton hierarchy and
bind pose, material/default-selection bindings, weight statistics, legacy
sentinel count and aggregate geometry counts. The authoritative render output
is glTF 2.0 JSON plus an external BIN with positions, normals, UV0, JOINTS_0,
WEIGHTS_0, uint32 indices, the complete bone tree and inverse bind matrices.
The exporter maps legacy `(x,y,z)` to glTF `(y,z,x)` in meters and changes
one-based active bone indices to zero-based only after validation. It rejects an
authoritative selection containing the exact unweighted sentinel. A companion
UE-centimeter OBJ remains a visual review artifact and carries no skinning.

## 7. Defensive limits

Defaults allow 4,096 groups, 1,000,000 total submeshes, 4,000,000 vertices and
50,000,000 indices per submesh, 10,000,000 aggregate vertices and 100,000,000
aggregate indices. Package limits are 4,096 bones, 8,192 references and 16,384
property records. Callers may lower these values. The module links neither the
old runtime nor Unreal.

## 8. Frozen real samples

| Sample | Groups | Submeshes | Vertices | Indices | Bones | Boundary represented |
|---|---:|---:|---:|---:|---:|---|
| `particle/FXH_O_S_shizuo.skem` | 1 | 1 | 4 | 6 | unbound | 477-byte global minimum/orphan payload boundary |
| `skchar.Boy01` | 12 | 1,620 | 842,929 | 2,944,338 | 80 | canonical player, 272 animation refs |
| `skchar.Girl01` | 12 | 1,806 | 1,014,104 | 3,668,820 | 80 | global maximum, 270 animation refs, two exact legacy sentinels |

The three SKEM SHA-256 values are respectively
`a755d7c0a706895725b53d9ea0289fe42600841dd8ba725fae86f8c5034912d5`,
`409fedf015ae3949222241cd8d7cc1aea22bb6ef689b2cc0190a796fe7cf93b6`
and `6ada6140d6a615ba1e18b2e236548ed67972d81ab948d4884e20af77913606d9`.
The shared `Packages/SkelMesh/skchar` SHA-256 is
`0867a016dd0b2a75a35d453ffe2242ffeb5329d003de61ba9b121dcebdba10e7`.
`Tests/Contract/Test-SkemSkeletalMesh.ps1` rechecks these read-only inputs and
records the reproducible signatures in
`Data/BuildBaseline/p1-15-skem-skeletal-mesh.json`.

## 9. Explicit non-goals

P1-15 does not decode `.anim`, create UE assets or sockets, repair legacy
weights, choose gameplay equipment rules, or synthesize materials. P1-19 wraps
the deterministic outputs in the versioned interchange container; P1-24 owns
the bounded UE skeletal mesh import.
