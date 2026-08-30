# P2-17 Data/Protocol code generation

`Contracts/data-schema/core-data-model-v1.json` is the single generated source
model for the first playable slice. It is derived only from the frozen P2-07
registry and P2-11 width audit and contains table/field types, nullability, and
identity roles, never row values, exact extrema, or legacy source lines.

`TMXY.ProtocolGen` produces a portable C++20 header for the Linux backend and a
UE 5.8 C++20 header for TMXYCore. Both targets receive domain-specific ID
structs and typed records. Numeric ID components use 64-bit unsigned storage,
string IDs remain strings, composite IDs preserve component order, nullable
values use explicit optionals, and cross-domain implicit conversion is absent.

Generated files under `Contracts/generated` must not be edited by hand. Change
the authoritative registry/audit/policy, regenerate, run the P2-17 contract,
then compile both backend and UE targets.
