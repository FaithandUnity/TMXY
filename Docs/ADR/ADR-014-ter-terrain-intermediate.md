# ADR-014: Preserve TER tiles as lossless sample planes

- Status: Accepted for P1-17
- Date: 2026-08-26

## Decision

Keep the parsed terrain tile as a row-major 64×64 set of source vertex records. Export exact
float32 heights, exact four-channel layer alpha, deterministic metadata JSON, and complete edge
CSV. Preserve optional legacy water color as absent or present. Do not weld neighboring edges,
renormalize normals, reinterpret layer indices, or infer physical scale during parsing.

## Rationale

The source file is a tile-local sample plane, while physical scale and layer resources live in
level/package metadata. The installed client also contains small differences across some shared
edges. Lossless intermediate data keeps those facts observable and allows the UE import decision
to choose an explicit seam and scaling policy later.

## Consequences

- Corrupt sizes, non-finite values, invalid booleans, and invalid layer tails fail closed.
- Height and layer payloads remain suitable for later lossless import or comparison.
- Adjacency diagnostics can distinguish source seams from importer-created seams.
- This ADR does not choose Unreal Landscape versus a custom terrain renderer.
