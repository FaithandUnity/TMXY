# G2 auxiliary-config reference evidence

P2-20A.3 defines the fail-closed evidence contract for the auxiliary-config
portion of G2-06. It separates four classes that consumers must not merge:

1. `measured_lexical_candidates` contains deterministic lexical observations.
2. `planning_adapter_states` describes workflow states, not approvals.
3. `assumptions` records non-authoritative interpretation boundaries.
4. `blockers` records the reasons the current scope cannot close.

Successful generation or validation is only `review_execution_result: PASS`.
The current evidence remains `result: BLOCKED`, `task_status: BLOCKED`,
`completion_criteria_satisfied: false`, `g2_06_satisfied: false`, and
`p3_authorized: false`.

## Frozen lexical baseline

The current measurement covers 212 file instances and 196 unique content
bodies. Duplicate file instances are deliberately retained. Of the instances,
206 parse and 6 are malformed. The parsers observe 39,522 scalar positions,
of which 39,498 are non-empty. The two empty ECF right-hand sides and 22 empty
XML attributes remain positions in the complete population; no empty value is
dropped to make the measured total agree with a planning estimate.

Exact complete-scalar matching observes 3,043 asset occurrences and 638
package occurrences. The package occurrences comprise 218 unique resolutions
and 420 lexical ambiguities; all 1,136 candidate edges for those ambiguities
are retained. Eight config-to-config lexical edges are also retained. These
counts are measured lexical facts only. They neither approve a semantic
adapter nor establish an approved traversal root.

## Parser and matching rules

The evidence enumerates every file instance, even when multiple instances have
identical content hashes. Duplicate ECF assignments retain source order. XML
processing disables DTD handling and external resolvers.

Only an exact match of the complete scalar is eligible as a lexical candidate.
Substring, basename, and extension-only matches are prohibited. An ambiguity
must retain every candidate edge; selecting the first candidate or any
heuristic target is prohibited. Config-to-config edges require deterministic
transitive-closure and cycle detection once semantic edges and approved roots
exist. A malformed input is never interpreted as having zero references.

## Adapter states and authority

The five adapter states are:

- `semantic-approved`: terminal; requires a hash-bound semantic contract,
  approved root set, and authority record.
- `no-ref-approved`: terminal; requires an explicit authority record. Absence
  of a lexical match cannot create this state.
- `candidate-only`: non-terminal; lexical candidates exist without semantic
  approval.
- `malformed-blocked`: non-terminal; the instance needs an explicit safe
  disposition.
- `editor-undecided`: non-terminal; no authorized semantic disposition exists.

A machine suggestion is not an approval. The current baseline has zero
approved semantic adapters, zero `no-ref-approved` instances, and zero
approved roots. Its six malformed instances remain blocked. No tool may infer
an exclusion merely because an instance has no lexical match or cannot parse.

## Completion rule

G2-06 auxiliary scope can close only in a later evidence revision after all
212 file instances have a terminal, authority-backed disposition; no
`candidate-only`, `malformed-blocked`, or `editor-undecided` instances remain;
malformed dispositions are complete; semantic unknown, ambiguous, and
unresolved occurrence counts are each zero; config closure and cycle review
are complete; all inputs and aggregate sets are hash-bound; heuristic and
first-candidate selections remain zero; and `scope_complete` is true.

The P2-20A.3 Schema intentionally validates the current blocked observation.
A later closing observation must use a new evidence revision and a reviewed
Schema rather than weakening these constants in place. This auxiliary report
cannot by itself approve all of G2 or authorize P3, production, or release.

## Deterministic reproduction contract

A conforming generator must:

1. Verify the six input-role SHA-256 bindings before reading evidence.
2. Enumerate the frozen 212 file instances in deterministic manifest order.
3. Parse with the XML and ECF controls above and preserve duplicate instances
   and duplicate-assignment order.
4. Match complete scalar values against hash-bound asset, package, and config
   indexes without emitting the values.
5. Retain every ambiguous candidate and compute anonymous occurrence-set and
   file-instance-set hashes.
6. Evaluate semantic adapters and approved roots without treating planning
   states as authority.
7. Compute config closure and strongly connected components only from approved
   semantic edges and roots.
8. Canonically serialize with UTF-8 without BOM and LF newlines, validate the
   closed Schema, and verify byte-for-byte stability in a locked non-root,
   read-only, no-network container.

The input aggregate is SHA-256 over the six role bindings in policy order.
Each UTF-8 line is `role`, one tab, the lowercase evidence SHA-256, and LF. The
file-instance-set and occurrence-set aggregates use the same length-delimited,
ordered-record rule defined by the generator contract; contracts must reject
missing, duplicate, reordered, or orphan records.

## Disclosure boundary

Formal evidence contains only anonymous hashes, counts, states, and reason
codes. It must not contain raw scalar values, key or file names, private source
paths, source line numbers, exact primary keys, observed extrema, raw table
rows, legacy source lines, or decoded payloads.
