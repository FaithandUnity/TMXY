# TMXY.Package

Owner: P1 Package/TBL proof workstream.

This offline, pure C++20 module reconstructs legacy Package formats from
evidence. It depends only on `TMXY.FormatCore`; it never links the legacy client,
D3D, MFC, UE, compression, encryption, or runtime service code.

The implemented contracts are the Package 1.0, Package 2.0, and Package 3.0
header readers.
They preserve name and class bytes without guessing their encoding, validate
every count and object range, reject ambiguous duplicate names, and never
deserialize legacy object bodies. The Package 2.0 reader also performs the
evidence-backed directory transform and maps decoded failures back to encoded
file offsets. File I/O remains at CLI/test boundaries; the library accepts a
caller-owned byte span.

Format evidence and field levels are documented in
`Docs/Formats/PACKAGE-V1-FORMAT.md`, `Docs/Formats/PACKAGE-V2-BASELINE.md`,
`Docs/Formats/PACKAGE-V3-BASELINE.md`, and
`Docs/Formats/PACKAGE-DIRECTORY-PIPELINE.md`. The deterministic normalized JSON
tree and its explicit unparsed/unknown boundaries are documented in
`Docs/Formats/PACKAGE-NORMALIZED-TREE.md`.
