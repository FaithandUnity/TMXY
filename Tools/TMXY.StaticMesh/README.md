# TMXY.StaticMesh

`TMXY.StaticMesh` is the bounded, offline reader for legacy `.sm` static-mesh payloads. It
preserves the original runtime geometry, validates Package `QStaticMesh` material references and
declared bounds, and emits deterministic metadata, glTF 2.0 JSON with an external BIN, plus a
UE-centimeter OBJ preview. The glTF pair is the P1-19 authoritative render-geometry interchange;
the OBJ remains review-only.

The module does not link the legacy runtime or import assets into Unreal. It maps legacy
`(x,y,z)` to the handedness-preserving glTF cyclic permutation `(y,z,x)`, preserves triangle and
material-section order, normalizes normals, and retains one or two UV channels.
