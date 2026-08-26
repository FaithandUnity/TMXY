# Secret injection contract

Secret values never enter this directory. The committed contract defines names,
mount targets, allowed sources, ownership, and rotation only.

For local Compose, `TMXY_POSTGRES_PASSWORD_FILE` must point to an
operator-managed file outside `E:\QQXYCodeDev`. Compose mounts it read-only at
`/run/secrets/tmxy_postgres_password`, and the PostgreSQL image reads it through
`POSTGRES_PASSWORD_FILE`. The password is therefore absent from Compose YAML,
the process environment, command arguments, and image layers.

CI and production must bind the same container target from their native Secret
Store. Choosing a hosted provider belongs to the CI/deployment platform decision;
it must not change the application-facing path.

The source file must be readable only by the current operator or service
identity. Never place it under the workspace, paste it into a shell command, or
attach it to an incident. Rotation is required at least every 90 days and
immediately after any suspected disclosure.
