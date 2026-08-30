# G2 Static-Mesh Payload-Section Prefix Evidence

P2-20A.12 is a source-derived diagnostic overlay on P2-20A.4, A.7, and A.8. It does not alter the
authoritative asset-binding workset.

## Frozen scope

- Family: `sm`
- A.7 strict failure: one target, two distinct candidate edges
- Strict error: `material_slot_mismatch`
- Diagnostic API: `bind_static_mesh_with_payload_section_prefix`
- Recovery label: `sm_payload_section_prefix`
- Basis: `payload_section_prefix_contract`

The ignored JSONL contains one anonymous target record and two anonymous candidate records. Every
candidate binds package, body, descriptor-semantic, strict-semantic, and prefix-semantic SHA-256
values. Names, legacy paths, source lines, decoded confidential payloads, and exact primary keys are
excluded from tracked evidence.

## Relation contract

Both candidates must independently prove all of the following:

1. The strict production binder rejects with `material_slot_mismatch`.
2. The explicit prefix API passes.
3. The descriptor has exactly two dense material slots.
4. The payload has exactly one section and that section has at least one triangle.
5. Exactly one trailing descriptor slot is ignored by the explicit API.
6. Body, descriptor-semantic, strict-semantic, and prefix-semantic projections each have one variant
   across the two candidates.

The prefix semantic digest binds the complete asset content digest, candidate body digest,
descriptor semantic digest, strict semantic digest, basis, and all four material/section counts.

## Source provenance

Seven legacy source roles are bound by SHA-256. The generator verifies closed facts from their bytes:
exporter material/section ordinal alignment, factory omission of zero-face sections, programmable and
fixed render loops bounded by payload section count, same-index material lookup, non-consumption of a
trailing material slot, and payload section order preservation. Only the role and digest appear in
the tracked report. This is `SOURCE_DERIVED`; no legacy binary is executed and runtime parity is not
claimed.

## Authority boundary

`PASS_DIAGNOSTIC` means only that the frozen relation was reproduced under the locked sources and
production API. It is not an adapter application, recovery, candidate selection, content disposition,
repair, deletion, no-reference decision, owner approval, or verified resolution. A.4 remains the
sole authority. A.12 hash-binds and reconciles the current A.4/A.7/A.8 effective state while requiring
the same one SM target / two candidate edges to remain unresolved. The current post-A.13 chain retains
189 targets / 546 edges ambiguous and 6 targets / 9 edges unresolved, but these global values are
derived from the bound upstream reports rather than duplicated as A.12 policy constants. G2-06 and P3
remain blocked.
