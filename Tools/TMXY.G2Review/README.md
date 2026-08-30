# TMXY G2 review generator

`New-G2Review.ps1` regenerates the P2-20 G2 review inside the locked non-root
builder. The repository is mounted read-only and the container runs without a
network, Linux capabilities, or privilege escalation.

`g2_review.py` assembles the gate report. `g2_evidence.py` independently binds
the prerequisite, P2-20A supplemental/A.4/A.5/A.6/A.7/A.8/A.9 diagnostics,
the P2-20A.10 ECF parser-parity, P2-20A.11 malformed-XML, and P2-20A.12
static-mesh payload-section-prefix diagnostics,
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

P2-20A.10 preserves the immutable A.5 history (61/64 parity, three differences,
and a net legacy-minus-A.3 pair-count delta of four) while separately binding
the source-derived result. The frozen A.3 output differs from that reference in
13 instances; on the same correct plaintext, the A.3 filter differs in one
instance and omits four legacy pair records. This is candidate-only diagnostic
evidence: no legacy runtime was executed, runtime-binary parity is not claimed,
and no semantic import, adapter, consumer contract, root, or terminal state is
approved.

P2-20A.11 keeps four evidence layers separate: frozen P2-05 strict rejection,
independent ElementTree rejection, source-derived TinyXML 2.3.4 behavior, and
the consumer/runtime authority boundary. TinyXML reports API success and equal
Client/Server tree shapes for all six malformed inputs, but consumes only five
completely; one success silently retains a partial tree. The source probe is not
legacy runtime or binary parity, and client NUL termination, memory-tail and
Windows CRT text-mode behavior remain unproved. Repairs, semantic imports,
approved dispositions, adapters, roots, and terminal instances remain zero.
Accordingly, `aux_malformed_xml_contract_safe=true` means only that the blocked
diagnostic is conservative and hash-bindable. It is never closure:
`aux_malformed_xml_closure_ready=false` is mandatory for this fixed BLOCKED
revision. The positive closure predicate is exercised only with synthetic unit
data to prove its logic is not contradictory; P2-20A.11 cannot be promoted in
place. Real dispositions require a new evidence revision, policy, schema, and
binder before G2-06 may consume them.

P2-20A.12 hash-binds its aggregate report, tracked inventory, and ignored
anonymous detail. It proves a source-derived prefix contract for one static-mesh
target and two candidate edges: strict binding rejects both, while the explicit
prefix API passes both with two declared material slots, one nonempty payload
section, and one ignored trailing slot. This diagnostic selects no candidate,
applies no adapter or recovery, changes no A.4/A.8 authority state, and proves no
legacy runtime parity. A.8 therefore remains 17 targets / 21 edges attempted,
7 / 9 successful, and 12 / 15 unresolved; the full workset remains 189 / 546
ambiguous and 12 / 15 unresolved. G2 remains 7/9 `BLOCKED`, and P3 is false.

```powershell
pwsh -File Tools/TMXY.G2Review/New-G2Review.ps1
pwsh -File Tools/TMXY.G2Review/New-G2Review.ps1 -Check
```

The command returning successfully means the review procedure and contracts
worked. It does not convert a `BLOCKED` gate decision into a pass.
