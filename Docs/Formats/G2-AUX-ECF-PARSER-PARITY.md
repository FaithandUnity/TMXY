# G2 auxiliary ECF parser-parity diagnostic

P2-20A.10 is a disclosure-safe, source-derived diagnostic overlay for G2-06. It does not replace or
reinterpret the historical P2-20A.5 evidence and does not modify the frozen P2-20A.3 outputs.

## Three evidence layers

1. The immutable P2-20A.5 baseline remains 61/64 parity, three differences, and a net legacy-minus-A.3
   pair-count delta of four. Its three-instance set is hash-bound.
2. The actual frozen A.3 transform and parser output is compared with the source-derived legacy
   transform and pair reference: 51/64 instances agree and 13 differ. The 13-instance set is hash-bound.
3. On the same correct plaintext, the A.3 line filter and the legacy CRLF pair parser agree for 63/64
   instances. Four legacy pair records are absent from A.3; all are retained only as anonymous counts
   and hashes and are not declared valid semantic assignments or imports.

The observed legacy transform swaps byte positions 0 and 2 whenever a third byte exists, including a
three-byte final block, then complements every byte. The frozen Rebuild implementations only swapped
complete four-byte blocks. Fourteen files have a three-byte remainder; 13 bodies differ because one
tail happens to contain equal first and third bytes.

## Diagnostic proof and limits

Two independent transform ports and two independent CRLF pair-parser ports must agree for all 64
instances. This proves only that the diagnostic implementations consistently reproduce the source-derived
contract. The legacy runtime is not executed and compiled-binary parity is not claimed.

Candidate projections use only the frozen P2-12 asset catalog, P2-13 package graph, and P2-05 config
population. They are non-mutating and candidate-only. Selection, consumer-contract approval, semantic
adapter approval, no-reference disposition, approved roots, semantic imports, and terminal instances all
remain zero.

## Disclosure and authority boundary

The tracked report and evidence contain aggregates, anonymous set hashes, contract hashes, and state
flags only. The ignored detail contains exactly 64 closed-schema anonymous records and no raw values,
keys, file names, private paths, source lines, legacy lines, primary keys, or decoded payloads.

P2-20A.10 remains `BLOCKED / PASS / BLOCKED`: diagnostic coverage is complete, task scope is not.
G2 remains 7/9, G2-06 remains unsatisfied, and P3 remains unauthorized.
