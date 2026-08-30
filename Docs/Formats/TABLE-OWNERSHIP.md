# P2-08 table ownership

## Ownership is not the same as consumption

P2-08 classifies all 225 active TBL files and all 355 P2-07 core columns. A client
shipping or reading a value does not make that client authoritative. The registry keeps
three separate facts:

- observed consumers in the current client configuration and legacy source trees;
- target Schema ownership (`client`, `server` or `shared`);
- target runtime authority (`client-presentation` or `server-authoritative`).

Every server-authoritative table is distributed to both the target client and server,
but the server must never trust the client's copy. Client-owned tables are presentation
catalogs and are not server inputs.

## Evidence inputs

`Tools/TMXY.Table/New-TableOwnershipRegistry.ps1` binds P2-05, P2-06 and P2-07 hashes,
then scans 1,096 legacy client source files and 1,972 legacy server source files without
writing to either tree. It also decodes only the frozen sandbox copy of
`QGameEngine.ecf`, verifies the self-inverse transform round trip, records its SHA-256,
and clears encoded/decoded buffers. No decoded line, configuration value, TBL row or
Secret is emitted.

The current client configuration names 127 active tables. Static source references
identify 3 client-side and 45 server-side tables. Ninety-eight presentation tables have
no exact static/config reference because they are selected through runtime appearance
or package metadata; that absence is recorded as `observed_consumers.scope=none`, not
misrepresented as proof of non-use.

## Table decisions

`CLSVShare` defaults to a shared Schema with server runtime authority. This is
fail-closed for gameplay features that exist in the current client but not the visible
legacy server source. Nine narrow tables are explicitly client presentation catalogs:
lighting, emotes, display-ID maps, map markers/icons and name catalogs.

The legacy server loads both `face` and `hair`, so those choice domains remain shared
and server-authoritative even though their payload ultimately controls appearance.
This prevents a client from inventing an unsupported appearance ID.

`Table` defaults to client presentation. Four exact exceptions are shared and
server-authoritative: activities, initial equipment, quests and supply/economy data.
The result is 117 client-owned presentation tables and 108 shared/server-authoritative
tables. There are no server-only Schema tables because the source population is an
installed client snapshot; server authority is expressed independently.

## Core-column decisions

P2-07 primary-key and foreign-key columns have first precedence and become shared
identifiers with server validation. Forty-eight columns are client-owned presentation:
36 localization columns and 12 resource/action presentation columns. The remaining
277 columns default to server-owned gameplay rules. This fail-closed default keeps
combat, economy, progression, rewards, cooldowns, skills, states and coordinates out of
client authority even when exact historical server implementation is unavailable.

The registry is the target architecture ownership contract, not a claim that the
legacy server already implements every current-client feature. Future exceptions must
be policy changes reviewed and regenerated, never runtime guesses.

## Reproduction

```powershell
& .\Tools\TMXY.Table\New-TableOwnershipRegistry.ps1
& .\Tools\TMXY.Table\New-TableOwnershipRegistry.ps1 -Check
& .\Tests\Contract\Test-TableOwnershipRegistry.ps1 -VerifyLegacySources
```

The tracked registry is `Data/Schemas/table-ownership-registry-v1.json`; the compact
machine evidence is `Data/Inventory/p2-08-table-ownership.json`. Hosted CI validates
the tracked hash chain. A source-authority machine additionally performs the full
legacy-source and sandbox-config recheck.
