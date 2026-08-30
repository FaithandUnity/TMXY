# TMXY GitHub hosted-CI audit

`Get-GitHubHostedCIStatus.ps1` performs a read-only GitHub API audit using an
ephemeral environment credential or Git Credential Manager. It never emits the
credential and writes only repository policy, runner, workflow, and capability
facts required by P0-12.

The report is diagnostic. It cannot enable branch protection, add reviewers,
register a runner, create a secret, publish the builder image, or issue
provenance.

