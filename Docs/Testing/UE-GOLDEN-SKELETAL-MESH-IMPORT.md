# UE golden skeletal mesh import

Status: P1-24 accepted local contract. Owner: `TMXYImporter` Editor plugin.

## Scope

P1-24 extends the production `khronos.gltf-json` Handler with an asset-kind router for
skeletal meshes. It consumes authoritative glTF 2.0 JSON and external BIN skinning data
from a `tmxy.asset.interchange` 1.0.0 bundle and creates exactly one `USkeletalMesh` below
`/Game/TMXY/Golden/SkeletalMeshes` plus one `USkeleton` below
`/Game/TMXY/Golden/Skeletons`.

Before package mutation, the Handler verifies every source and artifact byte count and
SHA-256, safe relative paths, asset kind, target roots, companion metadata, and a bounded
producer-owned glTF subset. The subset requires POSITION, NORMAL, TEXCOORD_0, JOINTS_0,
WEIGHTS_0, uint32 triangle indices, one skin, inverse bind matrices, a single-root bone
tree, normalized quaternions, finite transforms, and one to four normalized influences per
vertex. Unknown features or a mismatch fail before either output package is created.

## Golden source and coordinate contract

`Apps/UEClient/Scripts/CreateSkeletalMeshGoldenFixtures.ps1` deterministically derives the
`boy01-default-real` fixture from the exact read-only `skchar` Package and `Boy01.skem`
payload. Only the selected default visible parts and source path/hash provenance enter
`Rebuild`; the 95.7 MB original payload is not copied.

The fixture contains 10,338 source vertices, 8,757 triangles, seven material sections,
80 bones, one `Bip01` root, and at most four active influences. It has no legacy
all-unweighted sentinel vertices. The offline exporter maps legacy
`(x,y,z)` to glTF `(y,z,x)` in meters; the UE decoder maps this back to UE centimeters.
The cyclic basis has positive determinant, so index winding is preserved. Every inverse
bind matrix is finite and must have a positive unit rotational determinant.

## Bind pose, weights, and attachments

The importer retains the source MeshDescription, skin weights, bone names, parent indices,
and local bind transforms. UE builds render data and tangents from this source; render
vertex count may therefore differ from source vertex count. Automation compares every bone
name, parent, local translation, and quaternion with decoded authority, evaluates the full
component-space bind pose, rejects NaN or extreme translations, and proves positive
orientation throughout the hierarchy.

Every retained source vertex must have one to four valid influences whose normalized sum
differs from one by no more than `0.0001`. The legacy format exposes attachment points only
as bone-name candidates. P1-24 therefore proves the head and both hand candidates exist and
creates no invented UE sockets.

## Automation and reimport

`TMXY.Importer.SkeletalMesh` proves wrong-hash rejection is atomic, imports and loads both
assets, verifies geometry, materials, skeleton, bind pose, weights, bounds, orientation,
and attachment policy, then repeats the same import. Matching Manifest hash, importer
version, source topology, sections, bounds, and skeleton make reimport a content-addressed
no-op; Automation proves both `.uasset` files remain byte-identical.

The generated report is validated by
`Contracts/data-schema/ue-skeletal-mesh-import-report-v1.schema.json`. Development and
Shipping BuildCookRun remain the authority for target-platform cook and serialization.
