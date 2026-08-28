# TMXY.DependencyGraph

This offline P2 tool consumes deterministic `tmxy_package_tree_export` output,
opens only the corresponding read-only Package source spans, validates every
legacy property envelope, and emits a SHA-256-redacted dependency graph.

`package_dependency_graph.py` owns the evidence-backed reference registry and
deterministic JSONL writer. `New-FullPackageDependencyGraph.ps1` verifies the
frozen Manifest and P2-02 evidence, runs the Package exporter and Python self
test in the locked non-root builder, then writes the ignored local graph and
tracked aggregate report. `Find-PackageDependency.ps1` queries by UTF-8 name,
opaque name hex, or node ID without echoing raw names. Exact and ASCII-case-folded
logical-name hashes preserve the case-insensitive lookup behavior of the legacy
object registry while keeping raw names out of tracked evidence.

Arbitrary strings are never promoted to edges. Ambiguous and unresolved object
references remain explicit graph states for later ownership and repair work.
