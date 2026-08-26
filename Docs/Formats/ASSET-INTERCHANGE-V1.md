# TMXY asset interchange bundle v1

Status: P1-19 accepted contract. Manifest version: `1.0.0`; schema version: `1`.

## Purpose

One asset conversion produces a directory bundle whose root file is `manifest.json`. The
manifest provides provenance, versions, hashes, roles, dependencies, unit/coordinate contracts,
and explicit unknown-field preservation. Standard payloads remain separate files so each can be
hashed, streamed, diffed, regenerated, and consumed without inventing a monolithic container.

The normative sources are:

- `Contracts/data-schema/asset-interchange-v1.schema.json`;
- `Contracts/interchange/format-registry-v1.json`;
- `Contracts/examples/asset-interchange-v1.example.json`.

## Deterministic bundle rules

- all manifest and artifact paths are relative, `/`-separated, and may not contain `..`;
- manifests are UTF-8 without BOM and LF; absolute host paths and timestamps are forbidden;
- source inputs remain `reference-only` and are identified by byte size plus lowercase SHA-256;
- every artifact has its own byte size, SHA-256, format/version, authority, dependencies,
  coordinate contract, and unit contract;
- producers use stable ordering and deterministic float/text serialization;
- the manifest does not hash itself; archive or publication layers hash the complete bundle.

## Format ownership

| Asset | Authoritative interchange | Adjacent semantics | Review only |
|---|---|---|---|
| Package tree | `tmxy.package.tree-json` | source-span unknown bodies | none |
| Texture/UI texture | DDS with complete mip chain | asset metadata JSON | mip-zero PNG/TGA |
| Static mesh | glTF 2.0 JSON + external BIN | material, collision, shadow, emitter, AABB and unknown metadata JSON | OBJ |
| Skeletal mesh | glTF 2.0 JSON + external BIN | variants, legacy sentinels, attachments and unknown metadata JSON | default-selection OBJ |
| Animation set | glTF 2.0 JSON + external BIN | legacy loop period, notify and Root Motion policy metadata JSON | root-track CSV |
| Terrain tile | little-endian float32 height and RGBA8 layer planes | water, layer refs, edge/scale metadata JSON | edge CSV |
| Audio | reviewed RIFF/WAVE PCM | loop, attenuation, loudness, rights and source provenance metadata | none |
| Navigation | versioned graph JSON | exact `.zif`/`.path` references and source disconnections | optional diagnostics |
| Material | metadata JSON bound to texture artifacts | preserved legacy properties and mapping state | golden render |

`OBJ`, `PNG`, `TGA`, and `CSV` are never import authority. They omit material, mip, skin,
collision, animation, precision, or legacy semantics. An importer must select only registry
entries with `import_authority: true` and must verify hashes before parsing.

## JSON, BIN, glTF, and DDS boundaries

JSON carries descriptive semantics and provenance. Large numeric planes, indices, vertices,
weights, and keys do not become giant JSON arrays: glTF external BIN or an explicitly registered
typed plane owns those bytes. The format registry freezes media type, byte order, version, role,
and allowed asset kinds for each artifact.

glTF output follows the glTF 2.0 coordinate/unit contract recorded on its artifacts. It carries
portable render geometry, skeletons, skins, and animations. Semantics that glTF cannot represent
without guessing stay in the adjacent metadata artifact. The UE importer owns the tested
glTF-to-UE conversion; it must not assume the legacy-runtime coordinate contract.

DDS is the texture authority because the current QTX converter preserves the complete validated
mip chain and original supported format. PNG/TGA are normalized RGBA8 previews only.

Terrain planes retain their P1-17 byte contracts. Physical scale is still not inferred without
Level metadata.

## Unknown fields and extensions

An unknown or unsupported field may never disappear silently. Every entry in `unknown_fields`
uses exactly one preservation mode:

- `source-span`: source input ID plus exact offset and size;
- `opaque-sidecar`: an artifact ID containing the retained bytes;
- `namespaced-extension`: a dotted extension key whose value is present under `extensions`.

Extension keys must be namespaced, such as `org.tmxy.legacy-octree`. Normal manifest fields reject
undeclared properties; experimentation is isolated to extensions. Readers must retain unknown
extension values byte-semantically when rewriting a manifest.

## Version compatibility

`format_version` uses semantic `major.minor.patch` form and is independent of the integer JSON
Schema revision. A reader rejects an unknown major version. A newer minor version is accepted
only if every `required_features` item is supported; otherwise it fails without partial import.
A patch version may clarify or correct behavior without changing the represented semantics.

Published registry entries are immutable. New meanings, layouts, byte orders, or incompatible
field requirements receive a new version or format ID. Upgrades are explicit read-old/write-new
operations; producers never rewrite source evidence, and downgrade is rejected if it would lose
fields, artifacts, or extensions.

## Importer obligations

Before asset creation, the later Editor-only importer must:

1. validate the manifest and supported major version;
2. reject unsafe paths, duplicate IDs, missing dependencies, and unsupported required features;
3. verify every referenced artifact byte size and SHA-256;
4. preserve or report every unknown field and extension;
5. apply the named coordinate/unit contract exactly once;
6. record source hashes, producer version, manifest version, importer version, and output identity;
7. write a deterministic report and fail atomically before modifying existing assets.

P1-19 defines this interchange contract but does not create UE assets or claim that the current
OBJ/JSON review exporters already emit final glTF bundles. P1-20/P1-21 establish the automation
host and Editor-only importer; P1-22 through P1-26 implement each producer/consumer slice.
