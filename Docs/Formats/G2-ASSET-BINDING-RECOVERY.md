# G2 Asset Binding Recovery Evidence

P2-20A.8 has two deterministic phases.

`prepare` verifies the tracked A.7 report and inventory, verifies the ignored A.7 detail by its bound
SHA-256, resolves each target source hash through the A.7-bound P2-12 catalog, and writes a local-only
TSV. It then requires exact byte equality with the tracked frozen anonymous contract
`Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv`. The file has no header, seven
tab-separated fields, and ordinal `(asset_id, candidate_id)` order:

1. anonymous asset SHA-256 identity;
2. anonymous candidate SHA-256 identity;
3. candidate body SHA-256;
4. source file SHA-256;
5. family (`qtx` or `anim`);
6. explicit recovery API kind;
7. frozen strict production error code.

The prepare output is named `eligible-attempts`, not `recoveries`. A QTX payload-size error does not
prove a complete mip chain. The base plan permits only the earlier explicit complete-chain attempt.
P2-20A.13 overlays exactly six source-proven edges with the explicit declared-mip payload-prefix
kind; its API consumes only the descriptor-declared mip bytes and records the remaining input bytes
as ignored. It neither changes the declared/effective mip count nor treats the larger payload
boundary as an implied full natural chain. Unknown recovery bases remain rejected. An ANIM
frame-count error does not prove that tracks, keys, quaternions, emitters, or the payload tail are
valid. Production code must validate the complete recovery contract.

`finalize` binds both the tracked contract and live A.7-derived ignored plan, rejects any byte
difference, and compares the entire frozen A.7 19-target/24-edge set with regenerated A.4 effective
detail. It proves that the effective plan has the same 21 identities as the base plan and that
only the exact six A.13 `recovery_kind` cells changed. It writes a successful-recovery TSV only for
effective production passes and proves there was no recovery outside the attempt set. Candidate body
and descriptor-semantic hashes must match between A.7 and A.4. Ignored QTX proof detail records only
relation booleans, including whether the effective mip is shorter than declared and whether the
declared-payload-prefix contract applies, never the exact counts. A.8 never edits, derives a
replacement for, or overrides A.4's authoritative resolution counts.

Tracked content contains aggregate counts, file bindings, contract hashes, fail-closed status, and
the 21-row anonymous hash contract. Live per-target detail, regenerated attempt TSV, effective TSV,
and success TSV remain under ignored `Data/Exports`. Raw names, private paths, exact source primary
keys, raw values, offsets, and decoded payloads are not allowed in tracked outputs.
