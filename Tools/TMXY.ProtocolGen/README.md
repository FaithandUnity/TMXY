# TMXY.ProtocolGen

`New-ProtocolTypes.ps1` derives one disclosure-safe data model from the frozen
P2-07 core-table registry and the P2-11 ID limit audit. The locked, networkless
builder then generates standard C++20 backend types and UE 5.8 C++20 types from
that exact model. Numeric identity components always use 64-bit storage;
current observed ranges never authorize narrowing.

Run `New-ProtocolTypes.ps1` to regenerate tracked artifacts and use `-Check` to
prove byte-identical regeneration without modifying them. Backend CMake/CTest
and the TMXYCore UE module compile the two target headers independently.
