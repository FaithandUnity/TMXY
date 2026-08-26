# ADR-004: Reconstruct qtx from Package metadata plus raw mip payload

- Status: Accepted
- Date: 2026-08-26
- Decision owner: P1 format proof workstream

## Context

Legacy `.qtx` files have no magic or descriptor. The D3D9 renderer reads the
entire file and copies calculated byte ranges into a texture created from the
associated `QTexture` object's `format`, `uSize`, `vSize`, and `mipLevel`.
Treating `.qtx` as self-describing would make multiple valid interpretations of
the same byte length possible and would turn guesses into migration data.

## Decision

Create the platform-neutral C++20 `TMXY.Texture` module. It consumes a validated
legacy Package object body and its external qtx payload, applies legacy default
property values, validates the complete mip layout, decodes mip zero for Alpha
analysis, and produces deterministic DDS, PNG, TGA, and JSON intermediates.

DDS preserves the original format and mip bytes. PNG/TGA are normalized RGBA8
previews and are not the authoritative source for float or compressed payloads.
Format alpha capability and observed pixel alpha coverage are separate fields.
No D3D, UE, image SDK, legacy runtime, or guessed descriptor is linked.

## Consequences

- A qtx conversion cannot proceed without the matching Package object.
- Corruption and descriptor/payload disagreement fail before any output is
  committed.
- Output is deterministic and testable in the locked Linux Clang 21 builder.
- UE import can later select texture compression and material behavior using
  explicit metadata rather than filename heuristics.
