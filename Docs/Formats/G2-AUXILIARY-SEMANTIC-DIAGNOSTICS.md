# G2 auxiliary semantic diagnostics

P2-20A.5 records consumer-derived observations for the frozen auxiliary
configuration population. It supplements, but does not supersede, the P2-20A.3
lexical candidate evidence.

All 212 source instances are verified against the P2-05 byte count and SHA-256
before any branch can count or parse them. The eight input roles, their ordered
aggregate, six unique legacy consumer bodies, and blocker mapping are exact and
fail closed on omission, duplication, reordering, or drift.

Tracked JSON contains only aggregate counts, role labels, SHA-256 bindings, and
closed reason codes. It must not contain source instance names, configuration
selectors or values, source paths or line numbers, exact primary keys, or
decoded payloads.

The region contract follows only fields actually consumed by the observed
legacy loader and distinguishes file resources, object logical names, and
package roots. Candidate sets remain complete; a two-target result is
ambiguous even when both candidates have the expected type.

The ECF diagnostic compares the A.3 line splitter with the observed legacy
CRLF parser. Mixed-newline differences and missed assignments are blockers.
Repeated values retain source order; this milestone does not infer a winning
value or approve a reflected-property adapter.

The following promotions are forbidden:

- choosing the first candidate;
- treating zero lexical matches as a no-reference disposition;
- excluding a shadow copy without a complete root contract;
- repairing or excluding malformed input automatically;
- accepting unknown report fields.

A successful generator or contract run means the diagnostic executed
correctly. It does not satisfy G2-06, complete P2-20A, authorize P3, or grant
release authority. Ordinary development authorization is not semantic
approval.
