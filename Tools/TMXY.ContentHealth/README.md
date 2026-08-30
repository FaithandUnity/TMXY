# TMXY.ContentHealth

`New-ContentHealthReport.ps1` runs the deterministic P2-18 aggregator in the locked, non-root and networkless builder. It consumes only tracked, redacted P2-01 through P2-17 evidence and writes the JSON and Markdown reports plus frozen completion evidence.

Use `-Check` to regenerate into a temporary directory and require byte-identical report outputs. `Find-ContentHealth.ps1` filters the tracked risk register by severity, state, or dimension without exposing private source data.
