# Package full inventory

P2-01 scans every file below the frozen client `Packages` directory with the
same bounded C++ readers proven in P1. The authoritative machine inventory is
`Data/Inventory/p2-01-package-inventory.json`; the generator is
`Tools/TMXY.Package/New-FullPackageInventory.ps1`.

The frozen set contains 167 files and 42,437,699 bytes:

- one Package 1.0 file;
- 22 Package 2.0 files;
- 140 Package 3.0 files;
- one zero-byte file;
- three Subversion metadata files with no Package signature.

All 163 recognized packages parse without an error. Together they contain
121,715 records and 5,510,040 directory/header bytes. P2-01 intentionally marks
all 121,715 object bodies as unknown: the container boundary is proven, while a
class-specific body decoder must earn authority separately. The inventory
records only relative paths, sizes, SHA-256 values, counts, stable error classes,
and metadata fingerprints; it emits no object/class names and copies no body.

The scan runs in the locked non-root Clang 21 image with read-only source and
client mounts, no network, no capabilities, no-new-privileges, a read-only root
filesystem, and ephemeral build storage. It runs formatting, compilation,
clang-tidy, seven CTests, then the full 167-file scan.

P2-02 uses this inventory for boundary/completeness percentages. P2-03 may use
the source spans as graph nodes, but it must not infer references from opaque
body bytes without a versioned class decoder.
