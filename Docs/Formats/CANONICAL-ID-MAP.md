# Canonical ID Map V1

P2-10 defines a Canonical ID as a typed P2-07 primary-key tuple inside the
ASCII-case-folded logical table namespace. IDs are not globally mixed across
tables.

For a key present in both snapshots, the typed value is preserved and remains
active. A current-only key is adopted without renumbering. A legacy-only key is
preserved as a permanent Tombstone, so later content cannot silently reuse it.
The identical-row duplicate policy already approved by P2-07 may collapse
physical rows; divergent or unapproved duplicates fail closed.

If an old key component cannot inhabit its current P2-07 type, it is not
coerced. The exact legacy value is retained only in the ignored map as a
`legacy-opaque` Tombstone and cannot become active without an explicit review.

Automatic renumbering is forbidden. Any semantic conflict, namespace change,
key-type change, or Tombstone resurrection requires an explicit reviewed remap
and a schema version change. This snapshot has no explicit remaps; that is a
measured result, not permission to infer future mappings.

The full JSONL map contains primary-key tuples and therefore remains under the
Git-ignored `Data/Exports/P2-10` directory. The tracked evidence contains only
domain metadata, aggregate counts, and hashes. The query tool returns digests
and classification only.
