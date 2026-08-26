# ADR-006: Bind Package QSkelMesh skeleton metadata to bounded SKEM variants

- Status: Accepted
- Date: 2026-08-26
- Decision owner: P1 format proof workstream

## Context

Legacy `.skem` files contain no magic, version, skeleton or material names.
Their selectable geometry groups and skin streams depend on a separate Package
`QSkelMesh` body for bones, bind poses, materials and default variants. Bone
indices are persisted as one-based floats, and the largest golden sample has
two exact legacy unweighted sentinel vertices. Treating SKEM as a standalone
modern skeletal asset would require guessing all of these semantics.

The old object has no socket collection. Runtime attachments search the
skeleton by bone name. Animation object references are present in the Package,
but their `.anim` payload is a separate ordered stream and belongs to P1-16.

## Decision

Create the platform-neutral C++20 `TMXY.SkeletalMesh` module. Parse the complete
SKEM group/submesh payload with explicit limits and stable errors. Parse the
Package `QSkelMesh` property body independently, validate the skeleton graph
and local bind pose, and then require exact group/material/default-selection
binding. Interpret positive bone indices as one-based only after finite,
integral and active-range checks.

Preserve the exact `[-1,-1,-1,-1]` weight plus `[0,0,0,0]` bone-index sentinel
as reported evidence; do not normalize or repair it. Emit deterministic JSON
for hierarchy, bind pose, weights, material/variant selections and bone-name
attachment candidates. Emit authoritative glTF 2.0 JSON/external BIN skinning
data for the default variants, with validated zero-based joints and inverse bind
matrices. Reject an authoritative selection that contains the legacy sentinel.
Emit a UE-centimeter OBJ only as a visual review artifact. P1-19 wraps these
outputs in the final versioned asset container.

## Consequences

- Product conversion requires the matching Package object and SKEM payload;
  payload-only parsing is limited to structural audit evidence.
- Counts, attribute parity, topology, sections, shadow references, adjacency,
  weights, one-based bone indices, skeleton parents and cycles fail closed.
- The two Girl01 sentinel vertices remain visible and reproducible rather than
  being silently changed or causing the entire proven file to be unreadable.
- Bone names are explicit attachment candidates, not automatically created UE
  sockets.
- The default-selection glTF carries positions, normals, UV0, joints, weights,
  triangle sections, the bone tree, and inverse bind matrices without linking
  the old runtime.
- Animation references remain opaque names until P1-16 decodes their payload.
- The locked non-root Linux Clang 21 builder reproduces real-sample and CLI
  signatures without legacy, D3D or Unreal dependencies.
