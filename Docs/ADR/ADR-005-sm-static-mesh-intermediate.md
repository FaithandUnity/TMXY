# ADR-005: Bind Package QStaticMesh metadata to bounded SM geometry

- Status: Accepted
- Date: 2026-08-26
- Last amended: 2026-08-30
- Decision owner: P1 format proof workstream

## Context

Legacy `.sm` files are headerless serialized runtime arrays. Their section
materials and declared bounds live in a separate Package `QStaticMesh` object,
and optional arrays are identified only by their position at the end of the
payload. Treating either file as sufficient would require guessing material
slots, bounds, or tail meaning. Real evidence also shows that Package bounds
may contain the effective mesh bounds or may be stale after an external SM
replacement.

## Decision

Create the platform-neutral C++20 `TMXY.StaticMesh` module. It parses all
documented render, shadow, collision, section, octree, emitter, and UV arrays
with explicit limits and stable errors. It independently reads the Package
descriptor and keeps `bind_static_mesh` as the strict, non-zero one-to-one
material-slot/section policy. A separately named
`bind_static_mesh_with_payload_section_prefix` policy may consume only the
leading Package material prefix when a non-empty SM payload has fewer sections
than declared slots. It never accepts fewer Package slots, invents materials,
or removes the ignored descriptor tail. Each success records declared,
effective, and ignored counts plus the exact resolution basis. The module also
calculates render and collision bounds and reports the declared/effective
bounds relation without silently rewriting evidence.

Keep the in-memory mesh in legacy runtime coordinates. Emit deterministic JSON
metadata plus an OBJ review preview transformed through the frozen
`TMXY.Transform` contract into Unreal centimeters. Following ADR-015, emit
authoritative glTF 2.0 JSON and an independently hashed external BIN. The
handedness-preserving cyclic mapping `(legacy.y, legacy.z, legacy.x)` converts
to glTF coordinates without changing triangle or material-section order. OBJ
remains a diagnostic intermediate.

## Consequences

- Static-mesh conversion requires the matching Package object and SM payload.
- The strict API remains exact-by-default; prefix recovery requires the
  explicit API, a non-zero section count, and sufficient declared slots.
- JSON discloses material-slot resolution counts and basis; OBJ and glTF emit
  only the effective section prefix while preserving the full descriptor.
- Corrupt counts, indices, sections, booleans, octree references, non-finite
  values, and trailing bytes fail before outputs are committed.
- Internal octree face values are preserved without misclassifying them as leaf
  spans; leaf ranges remain strictly validated.
- A stale Package AABB is visible as `mismatch` metadata instead of being
  treated as geometry corruption or silently normalized.
- The locked Linux Clang 21 builder can reproduce parser, real-sample, JSON,
  OBJ, glTF and BIN signatures without D3D, Unreal, or legacy runtime dependencies.
