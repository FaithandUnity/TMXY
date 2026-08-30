# TMXY Canonical ID

P2-10 freezes typed, table-namespaced Canonical IDs from the P2-07 primary-key
contract and the P2-09 legacy/current comparison.

`New-CanonicalIdMap.ps1` runs in the locked non-root builder with read-only
workspace and legacy mounts and no network. The complete map is written below
the Git-ignored `Data/Exports/P2-10` directory because it contains primary-key
values. Only counts, hashes, domain metadata, contracts, and rebuild tooling are
tracked.

`Find-CanonicalIdMapping.ps1` queries by domain, state, action, or exact digest.
It emits mapping metadata and digests, never the underlying key tuple.
