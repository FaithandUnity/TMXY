BEGIN;

CREATE SCHEMA tmxy_system;

CREATE TABLE tmxy_system.runtime_contract
(
    component text PRIMARY KEY,
    schema_version bigint NOT NULL CHECK (schema_version > 0),
    applied_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp()
);

INSERT INTO tmxy_system.runtime_contract (component, schema_version)
VALUES ('foundation', 1);

COMMIT;
