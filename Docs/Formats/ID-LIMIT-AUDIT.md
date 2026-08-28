# ID Width and Fixed-Limit Audit V1

P2-11 evaluates all 16 typed components in the 12 P2-10 Canonical ID domains.
Numeric components receive required signedness/bit width, active density, u8 and
u16 boundary checks, and explicit level-cap checks. String components and
legacy-opaque Tombstones remain non-numeric and cannot be narrowed implicitly.

The audit separately searches `ClientCode`, `ServerCode`, and `ToolCode` through
read-only mounts for u8/u16 numeric boundaries plus level and slot capacity
symbol families. Only match counts and hashes are tracked; no legacy source line
or relative source path is committed.

Exact extrema and source paths are restricted to the ignored full report. A
zero overflow count does not authorize a narrow wire type: P2-17 must consume
the recorded risk labels and preserve compatibility headroom.
