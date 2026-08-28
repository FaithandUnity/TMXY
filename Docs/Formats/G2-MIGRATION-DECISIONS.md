# G2 migration decision registry

P2-20B produces the fail-closed G2-07 decision registry at
`Data/Governance/p2-g2-migration-decisions.json`. The registry enumerates
subjects and machine suggestions; it does not invent project or data-owner
decisions.

## Subject population

The V1 policy requires exactly 1,359 active anonymous units:

| Subject kind | Units |
| --- | ---: |
| Old-to-new Schema table | 52 |
| Schema reference rule | 12 |
| Canonical ID domain | 12 |
| ID component/width | 16 |
| Legacy fixed-limit signal | 1,267 |

The fixed-limit unit is one source-file/rule-family record, not one raw literal
hit. The public registry contains no source file name or matched value.

Reference membership is reconstructed from the frozen read-only legacy headers
and the P2-09-bound core registry. The output contains only anonymous case IDs,
record ordinals, and membership hashes. If the reconstructed membership count
or digest changes, coverage fails closed.

## Suggestion, decision, and approval

`machine_suggestion` is always marked `counts_as_decision: false`. A pending
record has no chosen action, rationale, migration plan, rollback plan, effective
Schema version, verification evidence, or approval.

G2-07 can become satisfied only when:

1. the active subject set exactly matches all five membership manifests;
2. every subject has one active decision and no duplicate or orphan record;
3. every decision has an explicit chosen action and required plans;
4. the required project/data-owner roles approve the decision digest through
   independently verifiable authority evidence;
5. verification passes and all hard invariants remain true.

A name typed into the registry is not approval evidence. A rejected suggestion
also does not close a subject; it needs an approved replacement decision.

## Hard invariants

- Numeric identities cannot be narrowed from the shared uint64 contract.
- String identities cannot be converted implicitly into numbers.
- An observed modal value cannot become an authoritative default.
- Tombstones cannot be reused without an explicit approved decision.
- IDs cannot be automatically renumbered without an approved remap.
- A legacy fixed limit cannot be copied without classification and rationale.

## Disclosure boundary

The tracked registry and report do not contain table or field names, private
legacy source paths, exact primary keys or observed extrema, table rows, source
lines, or matched literal values. Sensitive identity-to-case mappings remain in
existing ignored evidence and are referenced only by exact artifact hash and
record ordinal.

## Reproduction

```powershell
pwsh -NoProfile -File Tools/TMXY.G2MigrationDecisions/New-G2MigrationDecisions.ps1
pwsh -NoProfile -File Tools/TMXY.G2MigrationDecisions/New-G2MigrationDecisions.ps1 -Check
pwsh -NoProfile -File Tests/Contract/Test-G2MigrationDecisions.ps1
pwsh -NoProfile -File Tests/Contract/Test-G2MigrationDecisions.ps1 -VerifyDerivedSources
```

Generation uses the locked non-root builder with the repository and authorized
legacy input mounted read-only, no network, all capabilities dropped, and
`no-new-privileges`. Successful generation does not approve G2, authorize P3,
or grant release authority.
