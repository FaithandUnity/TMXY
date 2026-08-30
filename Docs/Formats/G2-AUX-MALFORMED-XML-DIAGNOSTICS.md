# G2 auxiliary malformed XML diagnostics

P2-20A.11 closes the diagnostic evidence contract for the six XML instances that P2-05 isolated as malformed. It does not close their semantic or runtime disposition.

## Evidence contract

The population is frozen at six unique GBK contents totaling 1,082,028 bytes. Every input is CRLF-only, contains no NUL byte, and contains no detected DTD or entity declaration. Instance and content populations are set-hash bound.

Four layers remain distinct:

1. P2-05 strict .NET evidence rejects all six as both documents and fragments, with three malformed-attribute-spacing, one invalid-comment, one invalid-attribute-character, and one unclosed-element classification.
2. Python `xml.etree.ElementTree`, after strict GBK-to-Unicode decoding, independently rejects all six. Error code 4 occurs five times and code 9 once. Failure positions are retained only as domain-separated hashes.
3. Separately compiled Client and Server TinyXML 2.3.4 source probes report `LoadFile` success, no error flag, and a root for all six. The two source families produce equal anonymous tree shapes.
4. Direct `Parse` consumes the full input for five instances. The unclosed instance returns null without setting the error flag while retaining a partial root/tree with 132 elements and 529 attributes. `LoadFile` API acceptance is therefore never treated as parse completeness or as a disposition.

Across the six direct-parse trees, the locked totals are 13,319 nodes, 12,673 elements, 59,141 attributes, 28 text nodes, and 618 comments.

## Versioned outcome projections

All three parser outcome hashes are computed from the current run rather than copied from policy. Records are ordered by anonymous `member_id` and serialized as UTF-8 compact JSON with sorted keys and one LF terminator per record.

- `g2-a11-elementtree-outcome-v1` binds member identity, acceptance, numeric error code, anonymous error class, and hashed failure location.
- `g2-a11-tinyxml-api-completeness-outcome-v1` binds both families' `LoadFile` acceptance/error/root flags, diagnostic NUL append, direct-parse null return, full consumption, and family tree equality.
- `g2-a11-tinyxml-tree-outcome-v1` binds member identity and anonymous node, element, attribute, text, and comment counts.

The generator compares each version, exact field list, row order, byte count, and computed SHA256 with policy before emitting evidence.

## Consumer boundary

Five instances have source-level consumer bindings: one dynamic client-region loader and four literal server loaders. One has no source literal and remains unresolved; it is not classified as unused or no-reference. The client loader passes an exact-length byte array to a C-string parser, and a terminating NUL or stable zero tail is not proven. Runtime memory-tail behavior remains unobserved.

## Isolation and disclosure

Generation uses the locked non-root Clang 21 image with networking disabled, a read-only repository mount, separate read-only Client and Server legacy mounts, no capabilities, and no new privileges. Probe inputs receive an explicit diagnostic-only NUL byte. No legacy binary or runtime is executed, and binary parity or Windows CRT text-mode parity is not claimed.

The wrapper and toolchain lock are direct hashed inputs. The report records the actual builder image reference and inspected digest, exact compiler version-output SHA256, Client and Server TinyXML source-set SHA256 values, and the closed support evidence boundary. Evidence isolation fields are projected from those validated run parameters rather than restated as unverified constants.

The tracked report and evidence retain only counts, booleans, source-role hashes, population hashes, and contract hashes. The ignored detail contains exactly six anonymous closed records. It excludes file names, paths, XML element or attribute names, values, raw snippets, parser text, and raw line or column positions.

## Authority boundary

P2-20A.11 performs no repair, normalization, source write, deletion, semantic extraction, semantic import, adapter approval, no-reference approval, root approval, or terminal disposition. A.3 remains `malformed-blocked` for six instances with zero lexical candidates or semantic edges. G2 remains 7/9, G2-06 remains unsatisfied, and P3 remains unauthorized.

Top-level generator failures expose only fixed `A11_ARGUMENT_VALIDATION_FAILED`, `A11_EVIDENCE_CONTRACT_FAILED`, `A11_INPUT_OR_IO_FAILED`, or `A11_INTERNAL_FAILURE` codes. Exception messages, parser text, and filesystem paths are never serialized.
