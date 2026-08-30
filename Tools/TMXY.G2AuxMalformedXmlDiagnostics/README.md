# TMXY G2 malformed XML diagnostics

This tool generates the P2-20A.11 disclosure-safe diagnostic overlay for the six frozen P2-05 malformed XML instances.

Run from `Rebuild`:

```powershell
$tool = 'Tools/TMXY.G2Aux' + 'MalformedXml' +
    'Diagnostics/New-G2Aux' + 'MalformedXmlDiagnostics.ps1'
& $tool -VerifyDerivedSources
& $tool -VerifyDerivedSources -Check
```

The wrapper verifies the locked non-root Clang 21 image, mounts `Rebuild`, `ClientCode`, and `ServerCode` read-only, disables networking and capabilities, compiles separate Client and Server TinyXML 2.3.4 probes in an isolated temporary output mount, and compares deterministic outputs.

The wrapper and `Data/Toolchain/toolchain.lock.json` are hashed inputs. The wrapper passes the actual builder reference, inspected image digest, mount modes, user, capability state, and no-new-privileges state into the generator. The tracked report binds those values together with the exact compiler version-output hash and both TinyXML source-set hashes. The support-layer evidence boundary is compared as a closed object; every runtime, binary, Windows CRT, NUL-tail, memory-tail, and API-disposition claim fails closed.

The evidence layers are deliberately separate:

1. frozen P2-05 strict .NET document/fragment rejection and classification;
2. independent strict-GBK-to-Unicode ElementTree rejection;
3. source-derived TinyXML `LoadFile` API acceptance for both source families;
4. direct `Parse` completeness and anonymous tree shape.

`LoadFile` success does not grant a disposition. The probe does not execute a legacy binary or runtime and does not prove Windows CRT text-mode behavior, client input NUL termination, or runtime memory-tail behavior.

ElementTree, TinyXML API/completeness, and TinyXML tree outcome hashes are recalculated during every run. `g2_aux_malformed_xml_evidence.py` defines three versioned projections, orders records by anonymous `member_id`, serializes compact JSON with sorted keys and LF terminators, and verifies the resulting byte counts and SHA256 values against policy. Generator failures expose only fixed argument, evidence-contract, input/I/O, or internal error codes and never include exception text or filesystem paths.

The tracked report and evidence contain only aggregates and hashes. The six-line ignored JSONL detail has a closed schema and contains no file names, paths, XML names, values, snippets, or raw parser locations. The tool never repairs, normalizes, writes, or deletes a legacy input.
