# TMXY ID Limit Audit

P2-11 audits every P2-10 Canonical ID component for required width, density,
u8/u16 boundaries, level-cap saturation, string identity, Tombstone reservation,
and legacy type exceptions. It also scans the three read-only legacy source
roots for fixed-capacity signal families without copying source lines.

The complete report contains derived minimum/maximum values and legacy relative
paths, so it remains under Git-ignored `Data/Exports/P2-11`. Tracked evidence
contains only counts, bands, risk labels, and hashes.
