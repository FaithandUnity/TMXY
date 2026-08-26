# Secret management and redaction baseline

## Boundary

Passwords, tokens, private keys, reusable verification codes, cookies, complete
connection strings, and protected decode material are Secret values. Git stores
only public identifiers, variable names, mount targets, invalid placeholders,
and one-way fingerprints used during incident correlation.

The deployment contract is `Deploy/secret-contract/secret-contract.json`.
Development uses an operator-managed file outside the workspace; CI and
production use a native Secret Store mounted at the same container path. Secret
values are forbidden in process arguments, container images, OCI labels, Git
LFS, test snapshots, reports, and logs.

## Required gates

`Tools/TMXY.Security/Test-RepositorySecrets.ps1` scans the working tree and all
reachable Git blobs. It detects known provider token shapes, private-key
headers, credential-bearing URLs, literal assignments, and high-entropy values.
Reports disclose only fingerprints. The repository contract invokes this scan,
and future hosted CI must run the same command without `-SkipGitHistory`.

The Foundation redaction function removes credential values from structured
key/value text, bearer authorization values, and connection URIs before a value
can reach a logger. Its unit test uses synthetic, non-reusable inputs and proves
both removal and preservation of non-sensitive context.

Local development uses Docker Pass backed by the operating-system keychain.
`Test-SecretStoreRotation.ps1` creates a cryptographically random, non-reusable
test entry through standard input, verifies read-back, overwrites it, verifies
rotation, revokes it, and proves absence afterward. Values are never placed in
arguments, reports, Git, or logs. The provider/mount mapping and boolean drill
evidence are recorded in `Data/Security/secret-provider-binding.json`.

## Incident and rotation

1. Stop merge, release, artifact upload, and further log distribution.
2. Revoke or rotate the value at its authority; deleting a file is insufficient.
3. Record only Secret id, affected scope, timestamps, and fingerprints.
4. Scan every reachable history blob and built artifact before resuming.
5. Clean history only with security-owner approval and coordinated clone/cache
   invalidation; never rewrite `main` casually.
6. Add a regression vector for the leak shape without committing the value.

Regular credentials rotate at most every 90 days. Session and service tokens
should be short-lived where supported. The platform security owner controls
access grants, revocation, and audit review.
