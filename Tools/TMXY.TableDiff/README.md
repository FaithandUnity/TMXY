# TMXY.TableDiff

P2-09 compares the hash-locked, already-decrypted 52-table DevDoc CSV snapshot
with the current P2-06 active CLSVShare data. The legacy snapshot has no proven
client build, so it remains `unknown-not-inferred` rather than being assigned an
official version by timestamp or filename.

The full local diff contains table names and per-table hashes but no raw values.
Tracked evidence contains aggregates only. Observed modal-value hashes are
comparison candidates, never authoritative schema defaults.

```powershell
.\Tools\TMXY.TableDiff\New-LegacyCurrentDiff.ps1
.\Tools\TMXY.TableDiff\New-LegacyCurrentDiff.ps1 -Check
.\Tools\TMXY.TableDiff\Find-LegacyCurrentDiff.ps1 -Table item_table
```
