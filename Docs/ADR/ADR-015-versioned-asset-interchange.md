# ADR-015: Use versioned manifests with standard asset payloads

- Status: Accepted
- Date: 2026-08-26
- Decision owners: Asset pipeline and UE importer owners

## Context

P1 format tools produce deterministic evidence and review outputs, but OBJ, PNG/TGA, CSV and
summary JSON cannot represent every source semantic. A single custom binary package would add a
second archive system, hide payload-level hashes, and bind offline tools to an unnecessary codec.
P1-20 onward needs a stable boundary that can evolve without losing unknown legacy fields.

## Decision

Use a directory bundle with a versioned JSON `manifest.json` and separately hashed artifacts.
Choose standard payloads where they preserve the required data: DDS for complete texture mip
chains, glTF 2.0 JSON plus external BIN for portable mesh/skeleton/animation content, RIFF/WAVE
PCM for approved audio, and explicit typed little-endian planes for terrain. Keep legacy-only
semantics in a registered metadata JSON artifact.

Every unknown field is retained as an exact source span, opaque sidecar, or namespaced extension.
The registry controls which artifacts are import authority; OBJ, PNG, TGA and CSV remain review
outputs. Semantic version rules require readers to reject unknown major versions and unsupported
minor features. Published registry entries are immutable.

## Consequences

- Artifacts are independently hashable, streamable and replaceable.
- UE Editor import does not link legacy runtime code or parse files from read-only source roots.
- glTF/DDS consumers cannot silently discard legacy extras because the manifest lists them.
- Producers must add final bundle output during P1-22 through P1-26; existing review outputs stay
  valid diagnostics but are not promoted by renaming.
- A future incompatible representation receives a new format/version and explicit upgrader.

## Rejected alternatives

- One private monolithic container: duplicates archive/version work and weakens artifact hashing.
- JSON arrays for all numeric data: excessive size and float/byte ambiguity.
- Direct UE `.uasset` as interchange: engine-version-bound, hard to diff, and unsuitable as the
  only preservation record.
- Treating OBJ/PNG/CSV as authority: known loss of mips, precision, skinning and legacy semantics.
