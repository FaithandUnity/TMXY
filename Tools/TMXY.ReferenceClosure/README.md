# TMXY.ReferenceClosure

P2-13 builds a deterministic, value-redacted closure over the P2-03 Package graph,
the P2-07 canonical core-table rows, and the P2-12 full asset catalog.
The command-line orchestrator lives in `reference_closure.py`; deterministic
hashing, JSONL writing, and source index construction are isolated in
`reference_closure_core.py` so each production source stays within repository
size limits.

```powershell
.\Tools\TMXY.ReferenceClosure\New-ReferenceClosure.ps1
.\Tools\TMXY.ReferenceClosure\New-ReferenceClosure.ps1 -Check
.\Tools\TMXY.ReferenceClosure\Find-ReferenceClosure.ps1 -RootKind skill
```

The full JSONL graph is reproducible and remains under the ignored
`Data/Exports/P2-13` directory. Tracked evidence contains only counts, hashes,
policies, and explicit health classifications. It never contains decoded table
values, primary keys, Package object names, or payload bytes.
