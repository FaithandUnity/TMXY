# MSVC 14.51 time-bounded qualification waiver

## Decision

Status: **ACTIVE**
Effective: 2026-08-26 00:00:00 +08:00
Expires: 2026-10-25 23:59:59 +08:00
Issuer: Codex, engineering execution owner
Scope: TMXY UE 5.8.2 Windows x64 baseline only

UE 5.8 reports MSVC 14.51.36256 as newer than its preferred 14.50.35717.
The installed toolchain is accepted temporarily because the complete Editor,
Development and Shipping qualification below passed. This waiver resolves only
the Windows compiler-preference item. It does not qualify the Linux Clang 21
builder and does not close P0-08 by itself.

## Qualified tuple

- Unreal Engine: 5.8.2, changelist 56702186.
- Visual Studio toolset directory: 14.51.36231.
- Compiler product version: 14.51.36256.0.
- Windows SDK: 10.0.26100.0.
- Platform: Windows x64.
- Project input binding: `TMXY.uproject`, `Config/**`, `Source/**`, importer
  plugin sources, the fourteen checked-in `.uasset`/`.umap` golden assets, golden
  fixture generators and the texture/static-mesh/skeletal-mesh/animation/terrain fixture inputs.
- Bound input count: 136 files.
- Bound input manifest SHA-256:
  `119cb080e514483ea6f0d74f434a8300f0dc15acc058e7a488be15d96fef76e0`.

The machine report is
`Data/BuildBaseline/p0-08-ue-packaging-waiver.json`. Its SHA-256 and expiry are
bound into `Data/Toolchain/toolchain.lock.json`.

## Qualification performed

`Tests/Integration/Test-UEPackagingQualification.ps1` performed the following
without writing to any legacy input:

1. Ran Unreal AutomationTool BuildCookRun for Win64 Development.
2. Ran BuildCookRun independently for Win64 Shipping.
3. Required Editor and matching client targets, successful cook, stage,
   Pak/IoStore, package and archive markers.
4. Verified each archive contains its bootstrap/runtime executables and at
   least one `.pak`, two `.utoc` and two `.ucas` files.
5. Required the Development executable to start under NullRHI and exit with
   code 0.
6. Required the Shipping executable to remain alive for a 15-second NullRHI
   window; the test then terminated only that exact process because Shipping
   disables console exit commands.
7. Hashed the actual compiler and SDK resource compiler binaries.
8. Confirmed the source project contains exactly the fourteen allowlisted golden
   `.uasset`/`.umap` assets and that packaging created zero `SecurityToken`
   files.

## Guardrails

The waiver becomes invalid immediately when any of the following occurs:

- the expiry is reached;
- UE version or changelist changes;
- MSVC toolset/compiler or Windows SDK changes;
- the bound UE input fingerprint changes;
- Development or Shipping packaging/launch validation fails;
- a generated SecurityToken appears;
- MSVC 14.50.35717 is installed and successfully qualified, which supersedes
  this waiver.

Any invalidation requires a new qualification report and reviewed expiry. A
waiver must never be extended by editing dates alone. This evidence covers the
current importer implementation and its fourteen golden assets; any change to the
bound sources, generated golden assets or fixture inputs must rerun the complete
qualification.
