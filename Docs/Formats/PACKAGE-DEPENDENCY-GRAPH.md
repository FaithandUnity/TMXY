# Package dependency graph

P2-03 builds a deterministic graph over every object in the 163 recognized
Packages. The machine summary is
`Data/Inventory/p2-03-package-dependency-graph.json`; the reproducible full
JSONL graph is generated locally at
`Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl`.

All 121,715 object bodies conform to the bounded legacy property envelope, with
1,639,860 properties and zero envelope failures. Reference rules come only
from seven hash-bound legacy class-registration sources. The extractor does not
scan arbitrary strings or create similarity edges.

The graph contains 121,715 nodes across 19 observed classes and 147,349 edges.
It covers texture, material, static/skeletal mesh, level/actor/terrain,
particle/emitter, animation/notify, sound and action logical-name families.
Object resolution is explicit:

- 94,882 edges resolve to one object;
- 21,146 resolve to multiple same-name candidates;
- 1,076 have no object in the installed Package set;
- 30,245 are intentionally logical names such as animation or bone names.

Ambiguous and unresolved edges are valid work queues, not parser errors. No
consumer may silently pick the first candidate.

## Public-repository boundary

Node IDs hash `package path + NUL + opaque object-name bytes`. Logical names are
stored only as exact and ASCII-case-folded SHA-256 values, matching the legacy
object lookup without disclosing names. The graph includes known class and
property names but no raw object names or body bytes. The 106,382,503-byte full graph is ignored by
Git; the repository tracks its SHA-256
`7a2fc8751bda61306c7abb6a4796ddc7eb90e921aaf758e68c22a68e8e466c57`,
generator, query tool and aggregate evidence.

`Find-PackageDependency.ps1` accepts a UTF-8 logical name, opaque name hex or a
node SHA-256 ID, checks both exact and ASCII-case-folded hashes, and reports matching nodes plus incoming/outgoing edges without
echoing the raw name. Regenerate the local graph before querying on a clean
checkout.
