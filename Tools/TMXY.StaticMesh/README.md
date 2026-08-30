# TMXY.StaticMesh

`TMXY.StaticMesh` is the bounded, offline reader for legacy `.sm` static-mesh payloads. It
preserves the original runtime geometry, validates Package `QStaticMesh` material references and
declared bounds, and emits deterministic metadata, glTF 2.0 JSON with an external BIN, plus a
UE-centimeter OBJ preview. The glTF pair is the P1-19 authoritative render-geometry interchange;
the OBJ remains review-only.

The module does not link the legacy runtime or import assets into Unreal. It maps legacy
`(x,y,z)` to the handedness-preserving glTF cyclic permutation `(y,z,x)`, preserves triangle and
material-section order, normalizes normals, and retains one or two UV channels.

`bind_static_mesh` is the strict default: both counts must be non-zero and the Package material
slot count must exactly equal the SM section count. The explicitly named
`bind_static_mesh_with_payload_section_prefix` API also accepts an exact match, or a Package list
that is strictly longer than a non-empty SM section list. In the latter case, only the leading
section-sized material prefix is effective; trailing Package slots remain preserved descriptor
evidence and are not synthesized, deleted, or exported as sections. Fewer Package slots and
zero-section payloads are rejected under both APIs.

Every successful binding records `MaterialSlotResolution`: declared, effective, and ignored slot
counts plus a `package_descriptor` or `payload_section_prefix_contract` basis. The deterministic
metadata JSON exposes those four values, while OBJ and glTF consume only the effective section
prefix.
