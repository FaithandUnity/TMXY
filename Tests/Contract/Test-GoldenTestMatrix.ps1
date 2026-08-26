[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p1-27-golden-test-matrix.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Resolve-RepositoryFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $candidate = [System.IO.Path]::GetFullPath(
        (Join-Path $root $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
    if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure -Message "P1-27 path escaped Rebuild: $RelativePath"
        return $null
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        Add-Failure -Message "P1-27 required file is missing: $RelativePath"
        return $null
    }
    return $candidate
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)
    return ($Value | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json
}

function Test-MatrixShape {
    param([Parameter(Mandatory = $true)][object]$Value)

    $requiredCategories = @('normal', 'boundary', 'corrupt', 'unknown')
    $suiteIds = @($Value.suites | ForEach-Object { [string]$_.id })
    if (@($suiteIds | Group-Object | Where-Object Count -gt 1).Count -ne 0) {
        return $false
    }
    $caseIds = @($Value.suites.cases | ForEach-Object { [string]$_.id })
    if (@($caseIds | Group-Object | Where-Object Count -gt 1).Count -ne 0) {
        return $false
    }
    foreach ($suite in @($Value.suites)) {
        $categories = @($suite.cases | ForEach-Object { [string]$_.category } | Sort-Object -Unique)
        if (Compare-Object ($requiredCategories | Sort-Object) $categories) {
            return $false
        }
    }
    return $true
}

$schemaRelative = 'Contracts/data-schema/golden-test-matrix-v1.schema.json'
$matrixRelative = 'Data/GoldenSamples/p1-golden-test-matrix-v1.json'
$ciRelative = 'Tests/CI/Invoke-LocalQualityGates.ps1'
$documentRelative = 'Docs/Testing/GOLDEN-TEST-MATRIX.md'
$schemaPath = Resolve-RepositoryFile -RelativePath $schemaRelative
$matrixPath = Resolve-RepositoryFile -RelativePath $matrixRelative
$ciPath = Resolve-RepositoryFile -RelativePath $ciRelative
$documentPath = Resolve-RepositoryFile -RelativePath $documentRelative
$selfPath = Resolve-RepositoryFile -RelativePath 'Tests/Contract/Test-GoldenTestMatrix.ps1'
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$schemaText = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
$matrixText = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8
$matrix = $matrixText | ConvertFrom-Json
if (-not (Test-Json -Json $schemaText -ErrorAction SilentlyContinue)) {
    Add-Failure -Message 'P1-27 matrix Schema is not valid JSON.'
}
if (-not (Test-Json -Json $matrixText -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
    Add-Failure -Message 'P1-27 matrix does not validate against its Schema.'
}

$requiredCategories = @('normal', 'boundary', 'corrupt', 'unknown')
$requiredDomains = @(
    'package-container',
    'legacy-table',
    'texture',
    'static-mesh',
    'skeletal-mesh',
    'animation',
    'terrain',
    'asset-interchange',
    'ue-importer'
)
$declaredCategories = @($matrix.required_categories | ForEach-Object { [string]$_ })
$declaredDomains = @($matrix.required_domains | ForEach-Object { [string]$_ })
$suiteIds = @($matrix.suites | ForEach-Object { [string]$_.id })
if (Compare-Object ($requiredCategories | Sort-Object) ($declaredCategories | Sort-Object)) {
    Add-Failure -Message 'P1-27 required coverage categories changed.'
}
if (Compare-Object ($requiredDomains | Sort-Object) ($declaredDomains | Sort-Object)) {
    Add-Failure -Message 'P1-27 required domain declaration changed.'
}
if (Compare-Object ($requiredDomains | Sort-Object) ($suiteIds | Sort-Object)) {
    Add-Failure -Message 'P1-27 suites do not cover each required domain exactly once.'
}
if (-not (Test-MatrixShape -Value $matrix)) {
    Add-Failure -Message 'P1-27 suite/category shape or ID uniqueness is invalid.'
}

$ciText = Get-Content -LiteralPath $ciPath -Raw -Encoding UTF8
if (-not $ciText.Contains('Test-GoldenTestMatrix.ps1', [System.StringComparison]::Ordinal)) {
    Add-Failure -Message 'P1-27 total matrix gate is not wired into the local CI aggregate.'
}

$sourceHashes = [ordered]@{}
$gateScriptHashes = [ordered]@{}
$evidenceHashes = [ordered]@{}
$caseIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$gateKeys = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$categoryCounts = [ordered]@{
    normal = 0
    boundary = 0
    corrupt = 0
    unknown = 0
}
$suiteSummary = [System.Collections.Generic.List[object]]::new()

foreach ($suite in @($matrix.suites)) {
    $suiteCategories = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($case in @($suite.cases)) {
        $caseId = [string]$case.id
        $category = [string]$case.category
        if (-not $caseIds.Add($caseId)) {
            Add-Failure -Message "P1-27 duplicate case ID: $caseId"
        }
        [void]$suiteCategories.Add($category)
        $categoryCounts[$category] = [int]$categoryCounts[$category] + 1

        $sourceRelative = [string]$case.test_source
        $sourcePath = Resolve-RepositoryFile -RelativePath $sourceRelative
        if ($null -eq $sourcePath) { continue }
        $sourceText = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
        $marker = [string]$case.source_marker
        if (-not $sourceText.Contains($marker, [System.StringComparison]::Ordinal)) {
            Add-Failure -Message "P1-27 source assertion marker is missing: $caseId"
        }
        if (-not $sourceHashes.Contains($sourceRelative)) {
            $sourceHashes[$sourceRelative] = Get-FileSha256 -Path $sourcePath
        }
    }
    foreach ($category in $requiredCategories) {
        if (-not $suiteCategories.Contains($category)) {
            Add-Failure -Message "P1-27 suite lacks $category coverage: $($suite.id)"
        }
    }

    foreach ($gate in @($suite.gates)) {
        $scriptRelative = [string]$gate.script
        $reportRelative = [string]$gate.evidence_report
        $gateKey = "$scriptRelative|$reportRelative"
        if (-not $gateKeys.Add($gateKey)) {
            Add-Failure -Message "P1-27 duplicate gate binding: $gateKey"
        }
        $scriptPath = Resolve-RepositoryFile -RelativePath $scriptRelative
        $reportPath = Resolve-RepositoryFile -RelativePath $reportRelative
        if ($null -eq $scriptPath -or $null -eq $reportPath) { continue }

        $scriptName = Split-Path -Leaf $scriptPath
        if (-not $ciText.Contains($scriptName, [System.StringComparison]::Ordinal)) {
            Add-Failure -Message "P1-27 declared gate is not invoked by local CI: $scriptName"
        }
        $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$report.result -ne [string]$gate.expected_result) {
            Add-Failure -Message "P1-27 evidence result mismatch: $reportRelative"
        }
        if ([bool]$gate.completion_required -and
            -not [bool]$report.completion_criteria_satisfied) {
            Add-Failure -Message "P1-27 evidence is not complete: $reportRelative"
        }
        if ([bool]$gate.automation_required -and
            -not [bool]$report.automation_evidence.passed) {
            Add-Failure -Message "P1-27 UE Automation evidence is absent: $reportRelative"
        }
        $gateScriptHashes[$scriptRelative] = Get-FileSha256 -Path $scriptPath
        $evidenceHashes[$reportRelative] = Get-FileSha256 -Path $reportPath
    }

    $suiteSummary.Add([pscustomobject][ordered]@{
        id = [string]$suite.id
        layer = [string]$suite.layer
        case_count = @($suite.cases).Count
        gate_count = @($suite.gates).Count
        categories = @($suiteCategories | Sort-Object)
    })
}

$missingCategory = Copy-JsonObject -Value $matrix
$missingCategory.suites[0].cases = @($missingCategory.suites[0].cases | Select-Object -First 3)
$missingCategoryRejected = -not (Test-MatrixShape -Value $missingCategory)
$duplicateCase = Copy-JsonObject -Value $matrix
$duplicateCase.suites[1].cases[0].id = [string]$duplicateCase.suites[0].cases[0].id
$duplicateCaseRejected = -not (Test-MatrixShape -Value $duplicateCase)
if (-not $missingCategoryRejected -or -not $duplicateCaseRejected) {
    Add-Failure -Message 'P1-27 matrix validator negative self-test failed.'
}

$sourceBindingLines = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $sourceHashes.GetEnumerator() | Sort-Object Key) {
    $sourceBindingLines.Add("$($entry.Key)`t$($entry.Value)")
}
$bindingBytes = [System.Text.Encoding]::UTF8.GetBytes(($sourceBindingLines -join "`n") + "`n")
$bindingSha256 = [System.Convert]::ToHexString(
    [System.Security.Cryptography.SHA256]::HashData($bindingBytes)).ToLowerInvariant()
$completion = $failures.Count -eq 0
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($completion) { 'PASS' } else { 'FAIL' }
    task = 'P1-27'
    completion_criteria_satisfied = $completion
    matrix = [pscustomobject][ordered]@{
        schema = [string]$matrix.schema
        version = [string]$matrix.matrix_version
        sha256 = Get-FileSha256 -Path $matrixPath
        schema_sha256 = Get-FileSha256 -Path $schemaPath
        suite_count = @($matrix.suites).Count
        case_count = $caseIds.Count
        gate_count = $gateKeys.Count
        required_domains = $requiredDomains
        required_categories = $requiredCategories
        category_counts = $categoryCounts
    }
    ci = [pscustomobject][ordered]@{
        aggregate = $ciRelative
        aggregate_sha256 = Get-FileSha256 -Path $ciPath
        all_declared_gates_bound = $completion
    }
    source_binding = [pscustomobject][ordered]@{
        file_count = $sourceHashes.Count
        sha256 = $bindingSha256
        files = $sourceHashes
    }
    gate_script_sha256 = $gateScriptHashes
    evidence_report_sha256 = $evidenceHashes
    suites = $suiteSummary
    negative_self_test = [pscustomobject][ordered]@{
        missing_category_rejected = $missingCategoryRejected
        duplicate_case_id_rejected = $duplicateCaseRejected
    }
    document_sha256 = Get-FileSha256 -Path $documentPath
    validator_sha256 = Get-FileSha256 -Path $selfPath
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $completion) { throw 'P1-27 golden test matrix gate failed.' }
