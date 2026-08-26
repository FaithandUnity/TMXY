# TMXY.Transform

Owner: P1 resource-reconstruction workstream.

This pure C++20 library is the single offline boundary for converting decoded
legacy spatial values to Unreal Engine conventions. It owns the meter-to-
centimeter scale, legacy angle-unit conversion, row-vector affine matrices,
serialized UV semantics, normal validation, and triangle winding policy.

The library does not read legacy files, include legacy/UE/D3D headers, create
`.uasset` files, or mutate source evidence. Parsers must first preserve raw
values in their intermediate model and call this library only when producing a
UE-facing representation.

The frozen convention and evidence are documented in
`Docs/Formats/LEGACY-TO-UE-TRANSFORM.md`. Invalid external numeric input returns
a stable `TransformError`; it never silently emits NaN, infinity, a zero normal,
or a projective matrix.
