# Package boundary completeness

P2-02 promotes the P2-01 inventory from a successful scan to a measurable
completeness gate. The authoritative report is
`Data/Inventory/p2-02-package-boundary-completeness.json`; its generator is
`Tools/TMXY.Package/New-PackageBoundaryCompleteness.ps1`.

The denominator is the 163 files with an authenticated Package 1.0, 2.0, or
3.0 signature in the frozen 167-file Manifest. The one empty file and three
Subversion metadata files are classified explicitly and are not misreported as
parser failures. All 163 recognized Packages are complete, giving a 100.0000%
parse rate against the required 99.9% threshold.

The core set is not selected after seeing the result. It is the 12
`source_verified` Package samples for versions 1.0/2.0/3.0 already frozen by
`Data/GoldenSamples/p0-golden-samples.json`. All 12 pass, satisfying the 100%
core requirement.

## Boundary proof

The readers require each object range to begin at the prior range end, the
first object to begin at `header_size`, and the final range to end exactly at
`file_size`. Package 2.0/3.0 readers also require complete consumption of the
decoded directory. Across the recognized set this accounts for 42,437,084
source bytes: 5,514,738 header bytes plus 36,922,346 opaque object bytes, with
zero uncovered bytes.

P2-02 also creates two ephemeral adversarial variants for every recognized
Package. Removing the final byte must produce `object_range_out_of_file`; adding
one zero byte must produce `non_contiguous_object_range`. All 326 mutations are
rejected. The variants live only in container tmpfs and are never copied into
the repository.

The audit uses the locked non-root Clang 21 image, read-only source/client
mounts, no network, no capabilities, no-new-privileges, a read-only container
root, and ephemeral build storage. Reports contain paths, hashes, counts and
offsets only; object/class names and object bodies are not emitted.
