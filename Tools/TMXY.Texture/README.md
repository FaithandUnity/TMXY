# TMXY.Texture

Owner: P1-13 qtx format proof workstream.

This offline C++20 module reads the six evidence-backed `QTextureBase`
properties from a Package object body, validates the external headerless qtx mip
payload, reports Alpha encoding and decoded coverage, and emits deterministic
DDS/PNG/TGA/JSON intermediates.

It depends only on `TMXY.FormatCore` and `TMXY.Package`. It does not link D3D,
UE, the legacy client, or an image SDK. Original evidence is always caller-owned
and read-only. See `Docs/Formats/QTX-FORMAT.md` and ADR-004.

The CLI contract is:

```text
tmxy_qtx_export <package-file> <full-object-name> <qtx-file> <output-stem>
```

It writes `<output-stem>.dds`, `.png`, `.tga`, and `.json` only after both
inputs validate.
