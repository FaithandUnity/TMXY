# G2 QTX Declared-Mip Payload-Prefix Evidence

## Contract

The default QTX parser owns the complete-input contract: the byte length must equal the exact sum of
the descriptor-declared mip levels. P2-20A.13 does not weaken that API. It adds evidence for one
explicit opt-in API whose input preconditions are all fail-closed:

1. `stored_mip_count` is nonzero and equals the normalized declared mip count.
2. The complete input ends exactly on a natural mip boundary strictly larger than the declaration.
3. The declared prefix has an overflow-safe exact extent and is strictly parseable on its own.
4. The explicit view retains the complete input size, consumed prefix size, ignored tail size, and
   `declared_mip_payload_prefix_contract` basis.
5. Decode and DDS writers accept the complete input only through this explicit view and restrict all
   reads to the consumed prefix.

An input that merely has extra bytes but does not end on a larger valid mip boundary is rejected.
An implicit/default mip declaration, a declaration that consumes the complete input, a truncated
prefix, a mismatched descriptor, or an unknown payload basis is rejected. No caller may silently
retry the explicit API after default strict failure.

## Frozen observed relation

| Count | Format | Dimensions | Stored / declared | Payload boundary / natural maximum | Input | Consumed | Ignored |
|---:|---|---:|---:|---:|---:|---:|---:|
| 3 | DXT1 | 512 x 512 | 1 / 1 | 10 / 10 | 174,776 | 131,072 | 43,704 |
| 3 | DXT5 | 256 x 256 | 1 / 1 | 7 / 9 | 87,376 | 65,536 | 21,840 |

Boundary 7 for the DXT5 group ends at the 4x4 block level. It is a complete payload boundary, not a
complete maximum natural chain. The six inputs have six distinct asset identities and six distinct
candidate identities. Four other unresolved QTX targets / six edges do not satisfy this frozen
relation and remain explicit negative/excluded scope.

## Output proof

For every selected edge the probe performs both paths:

- default strict parse of the complete input: `REJECTED / payload_size_mismatch`;
- explicit declared-mip prefix parse: `PASS`;
- default strict parse of the isolated consumed prefix: `PASS`;
- decoded mip-zero bytes from the explicit view equal the isolated-prefix decode byte-for-byte;
- DDS mip count is one and DDS bytes equal a 128-byte header plus the consumed prefix;
- the ignored tail is structurally outside DDS and is represented only by count and SHA-256.

The effective plan is derived from the tracked 21-row anonymous base-plan contract at
`Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv`. Row identity, ordering, hashes,
family, and strict error code are unchanged; only six `qtx_complete_mip_chain` cells become
`qtx_declared_mip_payload_prefix`. The base and effective plan are both hash-bound by the report.
Plan preparation is deliberately acyclic and clean-checkout safe: it reads only the frozen A.13
policy, tracked base-plan contract, P2-12 inventory/catalog, and P2-03 inventory/graph. It never
requires the ignored live A.8 attempt TSV. A.8 separately regenerates that TSV from A.7 and requires
byte equality with the tracked contract. A.13 derives the six probe rows directly from the frozen
inputs and does not read current A.4, A.7, A.8-final, or Core effective state.

## Authority boundary

This evidence is `SOURCE_DERIVED`. Hash-locked source proves that legacy texture allocation and copy
loops use the declared mip count, but no legacy binary is executed and runtime parity is not proven.
Prepare publishes only the ignored effective plan and never publishes a report. Finalize accepts
only `POST_APPLICATION` with exactly 6 resolved targets, 6 passing edges, and 6 applied recovery
edges; transitional PRE state is invalid for tracked/final evidence. Finalize
hash-binds the final A.4/A.7/A.8/Core values after they have consumed the prepared plan. P2-20A.13
itself performs no recovery, adapter application, selection, content disposition, repair, deletion,
or authority change. G2-06 and P3 remain false.
