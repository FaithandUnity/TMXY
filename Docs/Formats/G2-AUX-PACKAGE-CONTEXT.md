# G2 auxiliary package-context evidence

P2-20A.9 adds a technical, consumer-derived resolution layer over the frozen P2-20A.5 region
semantic baseline. It does not replace P2-20A.3 as the authority for auxiliary instance terminal
states and it does not approve an adapter, a no-reference disposition, or a traversal root.

## Frozen strict baseline

The input population contains 212 byte- and SHA-256-verified auxiliary instances. The package-context
probe operates only on the 135 region instances accepted by the strict reader and on fields selected
by the observed production consumer contract.

Before package context is applied, those fields contain 3,180 unique references, 211 ambiguous object
references with 422 retained candidate edges, and one unresolved resource reference. Every ambiguous
pair has divergent package bodies. Candidate equivalence, ordering, or the first candidate therefore
cannot be used as a selection rule.

## Package-context rule

The production lookup contract separates a complete package component from the complete object name.
P2-20A.9 uses that observed package prefix only when:

- the full object name still exactly matches the frozen candidate identity;
- the package prefix is an exact complete component after slash normalization and ASCII-only case
  folding;
- the package basename is globally unique in the hash-bound package inventory;
- exactly one member of the frozen candidate set is compatible with the package context; and
- reversing or otherwise permuting candidate order produces the same selection.

A zero-match or multiple-match result remains unresolved or ambiguous. The generator retains the
incompatible candidate edge in ignored proof detail; it does not rewrite the strict candidate set.

The measured result is 211 singleton matches, zero zero-match cases, zero multiple-match cases, and
211 order-invariant selections. Effective region semantics therefore contain 3,391 resolved
references and one unresolved resource. Of the 135 strict region instances, 134 are technically
resolved-only and one retains the unresolved resource.

## Evidence layout

The tracked report contains aggregate counts, contract controls, hashes, and blocker state only. Its
input aggregate binds eleven tracked inputs followed by three ignored artifacts. Each aggregate line
is the role, a tab, the lowercase SHA-256, and LF. Ignored bindings additionally record the portable
repository-relative path, byte count, and line count.

The ignored JSONL contains exactly 135 closed per-instance records. An instance record contains only
an anonymous instance identity, strict and effective counts, a technical state, an aggregate proof
hash, and zero or more anonymous object proofs. An object proof binds the frozen candidate-set hash,
the package-context hash, the selected anonymous candidate identity, and its order-invariance proof.

Tracked and ignored outputs must not contain raw configuration values, key or file names, private
source paths, source lines, exact primary keys, or decoded payloads.

## Authority boundary

Package-context resolution is technical evidence, not semantic approval. P2-20A.9 preserves:

- zero approved consumer contracts, semantic adapters, no-reference dispositions, and roots;
- zero terminal and 212 nonterminal auxiliary instances;
- three ECF parser-parity gaps and four missed assignments;
- six malformed instances and eight unapproved config edges;
- the single unresolved region resource; and
- the `BLOCKED` G2 decision with P3 unauthorized.

Exact-content shadow instances remain separate. No package-context proof grants permission to exclude,
collapse, modify, or delete them.

## Contract requirements

The contract must reject candidate-set tampering, first-candidate selection, candidate-order
dependence, a zero or multiple prefix match, selection outside the frozen set, dropping an
incompatible edge, replacing the observed prefix with a path heuristic, erasing the unresolved
resource, injecting roots or approvals, collapsing a shadow instance, and every unknown field.

Regeneration must run in the locked non-root builder with the repository and legacy inputs mounted
read-only, no network, no capabilities, and no new privileges. Check mode must reproduce tracked and
ignored outputs byte for byte while preserving the captured timestamp from the tracked report.
