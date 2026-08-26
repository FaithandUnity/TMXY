# PostgreSQL migration baseline

`Backend/adapters/persistence_postgres/migrations` is the only product migration
source. SQL remains outside Domain/Application code, and future libpq calls may
exist only in the same PersistencePostgres adapter.

`V0001__runtime_contract.sql` creates the owned `tmxy_system` schema and a
minimal runtime compatibility record. It intentionally has no `IF NOT EXISTS`:
a migration framework applies a version exactly once and must detect duplicate
execution or drift instead of hiding it.

`Tests/Integration/Test-PostgresMigration.ps1` proves the migration from an
empty PostgreSQL 18.6 database. It starts the digest-locked image with no network,
tmpfs storage, and a read-only migration mount; temporary trust authentication
is confined to that networkless container. The test checks server version,
schema ownership, and the inserted compatibility row, then removes the
ephemeral container in `finally`.

The production migration runner and application roles arrive with the P4
PersistencePostgres slice. They must add checksums, monotonic history, least
privilege, upgrade/rollback policy, and previous-version integration tests
without changing the V0001 contents.
