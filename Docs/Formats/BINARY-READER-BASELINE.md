# P1-01 bounded binary reader baseline

## Scope

`Tools/TMXY.FormatCore` is the shared, format-neutral foundation for offline
Package, table, and asset reconstruction. It is pure C++20 and has no legacy,
platform, renderer, UE, compression, encryption, or file-system dependency.

The current API provides:

- explicit little- and big-endian unsigned/signed 8/16/32/64-bit and IEEE-754
  32/64-bit floating-point reads;
- bounded byte views, skip, seek, size, cursor, remaining bytes, and absolute
  source offsets;
- stable error schema version 1 with `out_of_bounds`, `invalid_seek`, and
  `offset_overflow` codes;
- caller-supplied semantic context such as `package.header.magic`;
- failure atomicity: failed reads and seeks never advance the cursor.

The reader does not infer format semantics. Format-specific readers must assign
their own evidence levels, preserve unknown fields, and translate read failures
without dropping the absolute offset or stable code.

## Verification

`Tests/Contract/Test-FormatCoreBaseline.ps1` verifies the qualified builder
digest and non-root user, scans forbidden platform/legacy dependencies, then
runs Clang 21 format, CMake build with warnings as errors, clang-tidy 21, and
CTest inside a networkless, capability-free, read-only container. The repository
is mounted read-only; all build output uses ephemeral tmpfs.

Machine evidence is `Data/BuildBaseline/p1-01-format-core.json`. Unit coverage
includes both byte orders, sequential and exact-boundary reads, truncation,
absolute/context diagnostics, invalid seek, zero-length views, failed-operation
cursor stability, and absolute-offset overflow.
