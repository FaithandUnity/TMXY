# TMXY.SkeletalMesh

Offline, bounded reconstruction of the legacy `QSkelMesh` Package descriptor
and its companion headerless `.skem` payload. The module validates the bone
graph, local bind pose, per-vertex weights and bone indices, group/material
binding, default submesh selections, shadow indices, sections, and face
adjacency. It emits deterministic JSON metadata plus authoritative glTF 2.0
JSON/external BIN skinning artifacts for the Package-selected default variants.
A UE-centimeter OBJ remains available only for visual review.

The old client is evidence only and is never linked into this module. Animation
payload decoding remains the separate responsibility of P1-16.
