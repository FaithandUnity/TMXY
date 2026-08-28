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

- 95,070 edges resolve to one object;
- 20,955 resolve to multiple same-name candidates;
- 1,079 have no object in the installed Package set;
- 30,245 are intentionally logical names such as animation or bone names.

Ambiguous and unresolved edges are valid work queues, not parser errors. No
consumer may silently pick the first candidate.

## Public-repository boundary

Node IDs hash `package path + NUL + opaque object-name bytes`. Logical names are
stored only as SHA-256. The graph includes known class and property names but no
raw object names or body bytes. The 78,175,035-byte full graph is ignored by
Git; the repository tracks its SHA-256
`c7582df5c9655f506142e056626baabb8e461dee488a962e3634ea013c06a481`,
generator, query tool and aggregate evidence.

`Find-PackageDependency.ps1` accepts a UTF-8 logical name, opaque name hex or a
node SHA-256 ID and reports matching nodes plus incoming/outgoing edges without
echoing the raw name. Regenerate the local graph before querying on a clean
checkout.
