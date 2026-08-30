# TMXY.G2AuxConfigClosure

This tool produces the P2-20A.3 fail-closed auxiliary-configuration reference
evidence for G2-06. It reuses the frozen P2-05 sandbox, independently verifies
the ignored P2-12 asset catalog and P2-13 reference graph, and emits only
anonymous closed records.

`aux_extract.py` enumerates all 212 file instances, preserves duplicate content
instances and ordered ECF assignments, rejects DTD/entity XML, and performs
only complete-scalar exact matching. `g2_aux_config.py` binds all prerequisite
evidence and creates the tracked report and governance record. The PowerShell
wrapper runs both in the locked non-root builder with a read-only repository,
no network, no capabilities, and no new privileges.

Generate or refresh:

```powershell
Tools/TMXY.G2AuxConfigClosure/New-G2AuxiliaryConfigClosure.ps1
```

Verify byte-for-byte reproduction:

```powershell
Tools/TMXY.G2AuxConfigClosure/New-G2AuxiliaryConfigClosure.ps1 -Check
```

The ignored candidate export retains all anonymous lexical candidates. A
successful run means the review executed correctly; it does not approve a
semantic adapter, close G2-06, authorize P3, prove playability, or grant release
authority.
