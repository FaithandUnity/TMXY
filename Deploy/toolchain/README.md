# Backend toolchain image

This directory owns the immutable Linux amd64 C++20 build environment. It is a
build-time concern only; production service images must copy application
artifacts into smaller runtime images and must not inherit this builder.

`Dockerfile` pins the official Debian index digest, the Debian snapshot,
complete direct apt revisions, LLVM 21 revision, LLVM signing-key hashes,
CMake archive hash, and all Conan Python wheel hashes. The image deliberately
contains no project source, credentials, Registry token, or generated Conan
profile.

Build, qualification, SBOM generation, and lock-file evidence are orchestrated
by `Tools/TMXY.Toolchain/Build-BackendToolchain.ps1`. Do not invoke a floating
base tag or relax TLS and hash verification to work around network failures.
