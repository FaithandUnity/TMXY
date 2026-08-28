# P2-18 Content Health Report

P2-18 aggregates the completed P2-01 through P2-17 evidence into one deterministic health report. It reports parsing coverage, damaged inputs, opaque or unresolved content, reference integrity, conversion readiness, planning effort, capacity risks, and an explicit risk register.

Rates use integer parts per million with floor division. An opaque Package object body is not counted as a parser failure, a nullable unresolved object reference is not counted as a core foreign-key violation, and an unlinked or duplicate asset is never deletion authority.

`Data/Reports/p2-18-content-health-report.json` is the machine report. The adjacent Markdown file is the human summary. Both bind the exact SHA-256 of all 17 upstream evidence files and are generated in the locked non-root, networkless builder. Tracked outputs contain no private source paths, exact primary keys, observed extrema, raw rows, decoded confidential payloads, or legacy source lines.

`PASS_WITH_OPEN_CONTENT_RISKS` means the P2-18 accounting contract is complete; it does not mean all content is repaired, a playable experience is proven, G2 is approved, or release authority is granted.
