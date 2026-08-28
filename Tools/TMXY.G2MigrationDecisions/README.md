# TMXY G2 migration decisions

This module deterministically enumerates the anonymous P2-20B decision
population and implements the fail-closed V2 authority workflow. The tracked
authority ledger is initially empty, so all records remain pending until real
owner decisions and independently verifiable, decision-digest-bound approvals
exist.

The generator also emits 39 anonymous risk-signature review packets. Every
packet carries its full member list and exact membership hash; grouping never
replaces any of the 1,359 independent decision subjects and never counts as a
decision.

Run `New-G2MigrationDecisions.ps1`, then rerun it with `-Check` for byte-for-byte
verification. A successful command means generation succeeded; G2-07 remains
blocked while decisions or approvals are pending.
