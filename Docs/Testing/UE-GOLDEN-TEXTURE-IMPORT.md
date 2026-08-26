# UE golden texture import

Status: P1-22 accepted local contract. Owner: `TMXYImporter` Editor plugin.

## Scope

P1-22 adds the first production format handler, `microsoft.dds`. It consumes the
authoritative DDS artifact from a `tmxy.asset.interchange` 1.0.0 bundle and creates or
updates only `UTexture2D` packages below `/Game/TMXY/Golden/Textures`.

The handler verifies every artifact byte count and SHA-256 before it changes a package.
It accepts `SingleFixture` mode only; bulk mutation remains disabled. A wrong artifact
hash, unsupported DDS format, unsafe path, mismatched dimensions, or target outside the
Golden root fails before asset creation.

## DDS boundary

UE 5.8.2's generic image import path rejects the validated legacy BC1/BC3 DDS samples.
The plugin therefore owns a bounded DDS reader for the P1-22 sample slice:

- classic 128-byte DDS header only;
- 2D DXT1/BC1 and DXT5/BC3 only;
- maximum 16,384 pixels per axis and 15 mips;
- exact payload-length validation;
- complete mip-by-mip decode to `TSF_BGRA8`;
- UE target compression selected by Alpha policy (`CompressionNoAlpha`).

RGBA8, RGBA16F, R32F, DXT1a, and DXT3 remain stable unsupported inputs until a later
fixture proves their UE mapping. PNG/TGA previews are never import authority.

## Golden fixtures and assets

Two tiny persisted fixtures are generated from real read-only Package/QTX pairs by
`Apps/UEClient/Scripts/CreateTextureGoldenFixtures.ps1` in the locked non-root Clang 21
container:

- 8x8 DXT1 opaque (`texstone.WHZ_S_Dimian20_D`);
- 16x16 DXT5 transparent (`texparticle.FXH_T_toumingtu`).

A synthetic 8x8 DXT1 fixture with four complete mips tests the mip-chain boundary
without copying the 22 MB legacy maximum sample. The three approved packages are:

- `/Game/TMXY/Golden/Textures/T_Golden_Opaque_DXT1`;
- `/Game/TMXY/Golden/Textures/T_Golden_Transparent_DXT5`;
- `/Game/TMXY/Golden/Textures/T_Golden_MultiMip_DXT1`.

No original Package or qtx file is copied into `Rebuild`; each real fixture carries only
source path, byte count, and SHA-256 provenance plus its small deterministic derivatives.

## Automation and reimport

`TMXY.Importer.Texture` first submits a schema-valid Manifest with an intentionally wrong
DDS hash and proves that no target package is created. It then imports all three fixtures,
checks dimensions, sRGB, Alpha compression policy, decoded Source format, and the four-mip
chain, and reimports the transparent texture through the registered Handler. Reimport first
compares every decoded BGRA8 mip and all controlled import settings. An exact match is a
content-addressed no-op: it neither dirties nor saves the package. Automation proves the
transparent `.uasset` bytes remain identical across that reimport. The generated report is
validated against `ue-texture-import-report-v1.schema.json`.

Development and Shipping packaging remain the authority for successful target-platform
texture build/cook. The Editor NullRHI test does not claim that an immediate platform-data
pixel format is available.
