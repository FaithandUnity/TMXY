# TMXY G2 migration decisions

This module deterministically enumerates the anonymous P2-20B decision
population and keeps every record pending until real owner decisions and
independently verifiable approvals exist.

Run `New-G2MigrationDecisions.ps1`, then rerun it with `-Check` for byte-for-byte
verification. A successful command means generation succeeded; G2-07 remains
blocked while decisions or approvals are pending.
