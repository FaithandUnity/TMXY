[CmdletBinding()]
param(
    [string]$ReportPath = 'E:\QQXYCodeDev\Rebuild\Data\Reports\p2-18-content-health-report.json',
    [ValidateSet('all', 'critical', 'high', 'medium', 'low')]
    [string]$Severity = 'all',
    [ValidateSet('all', 'open', 'controlled-open', 'review-only')]
    [string]$State = 'all',
    [string]$Dimension = 'all',
    [ValidateRange(1, 100)]
    [int]$MaximumResults = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
if ($report.task_id -ne 'P2-18' -or $report.result -ne 'PASS_WITH_OPEN_CONTENT_RISKS') {
    throw 'The input is not a completed P2-18 content-health report.'
}
$matches = @($report.risk_register | Where-Object {
        ($Severity -eq 'all' -or $_.severity -eq $Severity) -and
        ($State -eq 'all' -or $_.state -eq $State) -and
        ($Dimension -eq 'all' -or $_.dimension -eq $Dimension)
    } | Select-Object -First $MaximumResults)
[pscustomobject][ordered]@{
    result = 'PASS'
    query = [pscustomobject][ordered]@{
        severity = $Severity
        state = $State
        dimension = $Dimension
        maximum_results = $MaximumResults
    }
    matches = $matches.Count
    risks = $matches
    disclosure = [pscustomobject][ordered]@{
        private_source_paths = $false
        exact_primary_keys = $false
        raw_values = $false
    }
} | ConvertTo-Json -Depth 20
