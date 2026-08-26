# TMXY Importer Plugin Baseline

P1-21 introduces `TMXYImporter` as a real Win64 Editor-only plugin. It does not add a runtime client module and does
not import legacy content. Its first executable responsibility is to validate one or more P1-19 interchange manifests,
produce the P1-20 before/after report, and enforce the registration and reimport boundary used by later format handlers.

## Loading and platform boundary

The project explicitly enables `TMXYImporter`. Its single module is `Editor`/`PostEngineInit`, the descriptor is
limited to `Win64`, and `CanContainContent` is false. `TMXY.Target.cs` does not reference the plugin. P1-21 keeps the
Content allowlist at the single `/Game/TMXY/Golden/Maps/TMXYGoldenTestMap` package.

The plugin uses UE Core/Json plus Windows CNG `bcrypt.lib` for SHA-256. It does not ship a private crypto
implementation and does not depend on Python, legacy runtime code or raw client packages.

## Validated batch

`FTMXYImporterService::ValidateBatch` accepts an ordered set of requests. P1-21 supports `ValidateOnly`; requests for
`SingleFixture` or `Batch` asset creation fail with the stable `unsupported-mode` code until a real format handler is
added. Each manifest path must be repository-relative, use forward slashes, stay below the Rebuild root, and contain
no empty, `.` or `..` segments.

Validation currently enforces the `tmxy.asset.interchange` 1.0.0 identity, source/artifact arrays, unique non-empty
IDs, safe relative source and artifact paths, and non-empty format IDs. Every result records its raw-file SHA-256 and
source/artifact counts. One failure does not prevent remaining batch requests from being validated.

## Report boundary

`WriteGoldenReport` emits `tmxy.ue.golden-import-report` 1.0.0 with the fixed root and Map. It hashes the real Map,
writes identical before/after inventories, records zero imported assets, and reports the aggregate validation outcome.
The output is UTF-8 without BOM and LF-normalized. P1-21 Automation writes only below `Saved/Automation`, which is an
ignored test-output directory; the contract validates that generated JSON against the canonical Schema.

## Format handlers and reimport

`ITMXYAssetImporter` is the narrow extension point for one registered `format_id`. Duplicate or empty registrations
are rejected. Import and reimport are separate methods. Before dispatch, reimport requires a package below
`/Game/TMXY/Golden`, a safe relative manifest path, a non-empty artifact ID and an installed handler.

P1-21 uses a test-only handler to prove registration, duplicate rejection, bounded dispatch and out-of-root rejection.
No production format handler exists yet. P1-22 must implement the first real qtx/DDS texture handler through this
interface and add source fingerprint/reimport metadata to the generated UE asset.

## Headless verification

`TMXY.Importer.ManifestBatch` validates two ordered requests against the P1-19 example, writes and parses the report,
then exercises the handler registry and reimport boundary. The shared UE baseline runs all three project tests:

- `TMXY.Core.BuildInfo`;
- `TMXY.Golden.Host`;
- `TMXY.Importer.ManifestBatch`.

The P1-21 contract additionally checks descriptor/runtime separation, source markers, report Schema compliance, zero
new Content assets and the corresponding Headless Automation evidence.
