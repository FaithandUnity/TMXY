# G2 malformed XML diagnostic

P2-20A.11 is `BLOCKED / PASS / BLOCKED`. It diagnoses all six frozen P2-05 malformed XML instances without repairing, deleting, normalizing, importing, or approving them.

## Separated evidence layers

- Frozen P2-05 strict .NET evidence rejects 6/6 as documents and 6/6 as fragments.
- Independent GBK-to-Unicode ElementTree evidence rejects 6/6: error code 4 occurs five times and code 9 once.
- Source-built Client and Server TinyXML 2.3.4 both report LoadFile success, no error, and a root for 6/6; both tree shapes agree.
- Direct Parse consumes the full input for 5/6. One API-success instance returns null while retaining a partial tree of 132 elements and 529 attributes.

## Authority boundary

LoadFile success is not a disposition. No legacy binary or runtime was executed; binary, Windows CRT text-mode, client C-string termination, and memory-tail parity remain unproven. Repairs, writes, deletions, semantic imports, adapters, no-reference approvals, roots, and terminal dispositions remain zero. G2 remains 7/9 and P3 remains unauthorized.

The tracked artifacts contain aggregates and hashes only. The ignored detail contains six closed anonymous records and no file names, paths, XML names, values, snippets, or raw parser locations.
