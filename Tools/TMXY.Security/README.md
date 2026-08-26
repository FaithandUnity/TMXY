# TMXY.Security

`Test-RepositorySecrets.ps1` scans Git candidate files and every reachable
history blob for known credential shapes, literal Secret assignments, private
keys, credential-bearing URLs, and high-entropy tokens. Findings contain only a
rule, location, origin, and one-way fingerprint; suspected values are never
printed.

```powershell
pwsh -NoProfile -File .\Tools\TMXY.Security\Test-RepositorySecrets.ps1 `
  -ReportPath .\Data\Security\p0-14-secret-scan.json
```

`-SkipGitHistory` is reserved for isolated scanner tests. It must not be used
for a merge or release gate.

`Test-SecretStoreRotation.ps1` exercises the installed Docker Pass system
keychain using a temporary synthetic value. It verifies create/read/rotate/revoke
without printing the value and removes the entry before writing its report.
