# G2 Asset Binding Recovery Evidence

P2-20A.8 has two deterministic phases.

`prepare` verifies the tracked A.7 report and inventory, verifies the ignored A.7 detail by its bound
SHA-256, resolves each target source hash through the A.7-bound P2-12 catalog, and writes a local-only
TSV. The file has no header, seven tab-separated fields, and ordinal `(asset_id, candidate_id)` order:

1. anonymous asset SHA-256 identity;
2. anonymous candidate SHA-256 identity;
3. candidate body SHA-256;
4. source file SHA-256;
5. family (`qtx` or `anim`);
6. explicit recovery API kind;
7. frozen strict production error code.

The prepare output is named `eligible-attempts`, not `recoveries`. A QTX payload-size error does not
prove a complete mip chain. QTX recovery requires an explicit stored mip declaration equal to the
normalized declared count, accepts only a unique complete prefix shorter than that declared chain,
and rejects unknown recovery bases; it never adds payload mips. An ANIM frame-count error does not
prove that tracks, keys, quaternions, emitters, or the payload tail are valid. Production code must
validate the complete recovery contract.

`finalize` compares the entire frozen A.7 19-target/24-edge set with the regenerated A.4 effective
detail. It writes a successful-recovery TSV only for effective production passes and proves there was
no recovery outside the attempt set. Candidate body and descriptor-semantic hashes must match between
A.7 and A.4. Ignored QTX proof detail records only relation booleans (stored explicit, stored equals
declared, effective less than declared, unique complete prefix), never the exact counts. A.8 never
edits, derives a replacement for, or overrides A.4's authoritative resolution counts.

Tracked JSON, Markdown, and inventory files contain aggregate counts, file bindings, hashes, contract
hashes, and fail-closed status only. Anonymous per-target detail and both TSVs remain under ignored
`Data/Exports`. Names, paths, exact primary keys, raw values, offsets, and decoded payloads are not
allowed in tracked outputs.
