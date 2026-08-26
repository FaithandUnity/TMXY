# TMXY.FormatCore

Owner: P1 binary-foundation workstream.

This pure C++20 library provides bounded, endian-explicit reads for offline
Package, table, and resource reconstruction. It owns stable read error codes,
absolute source offsets, and parser context. It does not own a file system,
compression, encryption, legacy runtime types, D3D, MFC, UE, or format-specific
semantics.

`BinaryReader` is a non-owning view. Returned byte spans remain valid only while
the caller-owned input storage remains alive. A failed read or seek never moves
the cursor. Construction detects an absolute-offset range that cannot be
represented and makes every read fail with `offset_overflow`.

Build and test from `Tools` with the CMake presets. The P1 contract test also
runs format, clang-tidy, compile, and CTest inside the locked Clang 21 builder
with the repository mounted read-only and networking disabled.
