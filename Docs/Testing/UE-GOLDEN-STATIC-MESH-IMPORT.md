# UE golden static mesh import

Status: P1-23 accepted local contract. Owner: `TMXYImporter` Editor plugin.

## Scope

P1-23 adds the production `khronos.gltf-json` Handler. It consumes the authoritative
glTF 2.0 JSON and external BIN artifacts from a `tmxy.asset.interchange` 1.0.0 bundle,
then creates or updates only `UStaticMesh` packages below
`/Game/TMXY/Golden/StaticMeshes`.

Before package mutation, the Handler verifies every source and artifact byte count and
SHA-256, safe relative paths, the Manifest asset kind and UE extension, the companion
metadata, and a bounded producer-owned glTF subset. It accepts only `SingleFixture` mode.
Unknown glTF features, a wrong hash, inconsistent counts, unsafe paths, or a target outside
the Golden root fail before asset creation.

## Coordinate and geometry contract

The offline SM exporter writes standard right-handed glTF meters with the cyclic mapping
`legacy(x,y,z) -> glTF(y,z,x)`. The UE Handler maps this back to
`UE(x,y,z) = (glTF.z, glTF.x, glTF.y) * 100`, a positive-determinant transform, so triangle
winding is preserved. Normals use the same cyclic mapping and are normalized; UV values are
preserved. The importer retains source normals, asks UE 5.8.2 to recompute MikkTSpace
tangents, disables generated light-map UVs, and selects UV1 only when the legacy metadata
declares a light map.

The Manifest records render bounds derived from the glTF POSITION accessor separately from
the effective legacy bounds in `mesh.json`. This distinction is required because the legacy
reader intentionally reports collision bounds when collision vertices exist, while the UE
asset bounds describe render geometry.

## Golden fixtures and assets

`Apps/UEClient/Scripts/CreateStaticMeshGoldenFixtures.ps1` deterministically generates two
reviewable bundles from exact read-only Package/SM pairs in the locked non-root Clang 21
container:

- `particle.ZFH_O_S_Tianpian100`: 4 source vertices, 2 triangles, 1 section, 1 UV channel;
- `scene09.GT_B_S_BangPai05`: 11,847 source vertices, 6,511 triangles, 43 sections, 2 UV channels.

Only deterministic derivatives and source path/hash provenance enter `Rebuild`; original
Packages and SM payloads are not copied. The approved assets are
`SM_Golden_Minimum_Real` and `SM_Golden_MultiSection_Real`.

UE tangent/material splitting produces 11,851 render vertices for the second fixture. This
does not alter its retained 11,847-vertex MeshDescription source topology; both counts are
recorded and tested explicitly.

## Automation and reimport

`TMXY.Importer.StaticMesh` proves invalid-hash rejection without package creation, exact
coordinate/normal/UV/index decoding, source and render counts, triangle/section counts,
material-slot order, two-sided metadata, render bounds, and light-map channel selection.
Reimport compares the Manifest hash, importer version, retained source topology, render
properties, material slots, UV count, light-map index, and bounds. An exact match is a
content-addressed no-op, and Automation proves the `.uasset` bytes remain unchanged.

The generated report is validated by
`Contracts/data-schema/ue-static-mesh-import-report-v1.schema.json`. Development and
Shipping packaging remain the authority for target-platform cook and serialization.
