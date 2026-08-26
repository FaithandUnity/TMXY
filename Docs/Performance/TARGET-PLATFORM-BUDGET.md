# Target platform and performance budget

## Status and scope

This is the frozen P0 engineering baseline, not a claim that unfinished code
already meets the targets. It defines the load and latency envelopes that later
P3, P4, P6, and P8 tests must prove. Any reduction or expansion requires a
reviewed ADR, updated capacity model, and regression evidence.

The machine-readable authority is
`Data/Performance/p0-platform-budget.json`. Windows x64 and Linux x64 are final
product boundaries; mobile, Win32, SQL Server runtime, and Windows backend
production are outside scope.

## Client target

The recommended target is Windows 11 x64, DirectX 12/SM6, 1920×1080 at 60 FPS
with a 45 FPS one-percent-low floor. The frame budget is 16.67 ms, with 6 ms
game-thread, 6 ms render-thread, and 14 ms GPU ceilings measured independently.
The recommended machine has 8 logical CPU threads, 32 GiB system memory, 8 GiB
dedicated VRAM, and NVMe SSD storage.

The supported minimum profile is 6 logical threads, 16 GiB memory, 6 GiB VRAM,
SSD, and 1280×720 at 30 FPS. At 1080p the client process budget is 8 GiB working
set and 7 GiB resident VRAM. Cold start to login must remain within 20 seconds,
world entry within 15 seconds, and representative stress scenes must support
200 relevant network entities with up to 80 fully animated characters.

## Backend and network target

The first production capacity target is 10,000 concurrent sessions with 30%
headroom. Qualification uses an 8-vCPU/16-GiB Linux x64 node: one gateway
instance must sustain 10,000 connections, one world instance 2,000 sessions,
and authoritative simulation runs at 20 Hz. Horizontal scale remains mandatory;
these numbers are not permission to create a monolithic world process.

P95 server budgets are 50 ms for gateway processing and database transactions,
2 seconds for login, 1 second for character list, 250 ms for chat delivery, and
8 seconds for world entry. Supported client RTT is 150 ms P95. Per-client
sustained traffic budgets are 64 KiB/s downstream and 16 KiB/s upstream P95.

The monthly service SLO is 99.9%. PostgreSQL and stateful services require an
RPO of 5 minutes and an RTO of 30 minutes. Backup existence is insufficient;
P8 must time a restore on production-like data.

## Validation rules

- Performance tests run at least 60 minutes after warm-up on declared hardware.
- Client results include frame-time distributions, game/render/GPU threads,
  working set, VRAM, asset streaming, and representative actor counts.
- Backend results include connections, sessions, tick delay, queues, CPU,
  memory, database latency, errors, and saturation point.
- Averages cannot hide P95/P99 or one-percent-low failure.
- Unmeasured budgets block release; they do not silently become waivers.
