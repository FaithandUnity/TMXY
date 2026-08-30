# TMXY G2 review generator

`New-G2Review.ps1` regenerates the P2-20 G2 review inside the locked non-root
builder. The repository is mounted read-only and the container runs without a
network, Linux capabilities, or privilege escalation.

`g2_review.py` assembles the gate report. `g2_evidence.py` independently binds
the prerequisite, P2-20A supplemental/A.4/A.5/A.6/A.7/A.8/A.9 diagnostics,
P2-20B remediation, and quality inputs, then recomputes G2-06 and G2-07 from
their full machine evidence instead of trusting reported completion flags or
machine suggestions.

P2-20A.9 proves the technical package-context selection contract for all 211
strictly ambiguous region object references. The effective region observation
has 3,391 resolved references, no remaining object ambiguity, one unresolved
resource, and 134 consumer-clean region instances. This evidence retains all
incompatible candidate edges and performs no first-candidate selection.

That technical disambiguation is not semantic approval. Approved adapters,
approved roots, and terminal auxiliary instances remain zero; all 212 auxiliary
instances remain nonterminal. G2 and P3 therefore remain blocked.

```powershell
pwsh -File Tools/TMXY.G2Review/New-G2Review.ps1
pwsh -File Tools/TMXY.G2Review/New-G2Review.ps1 -Check
```

The command returning successfully means the review procedure and contracts
worked. It does not convert a `BLOCKED` gate decision into a pass.
