[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\resource-budget-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\resource-budget-report-v1.schema.json'
$reportPath = Join-Path $root 'Data\Reports\p2-19-resource-budget-report.json'
$markdownPath = Join-Path $root 'Data\Reports\p2-19-resource-budget-report.md'
$evidencePath = Join-Path $root 'Data\Inventory\p2-19-resource-budget.json'
$p215Path = Join-Path $root 'Data\Inventory\p2-15-conversion-routing.json'
$p218Path = Join-Path $root 'Data\Inventory\p2-18-content-health.json'
$pilotPath = Join-Path $root 'Data\Performance\p2-19-conversion-pilot.json'
$generatorPath = Join-Path $root 'Tools\TMXY.ResourceBudget\resource_budget.py'
$wrapperPath = Join-Path $root 'Tools\TMXY.ResourceBudget\New-ResourceBudgetReport.ps1'
$pilotScriptPath = Join-Path $root 'Tools\TMXY.ResourceBudget\Measure-ConversionPilot.ps1'
$assertions = [Collections.Generic.List[object]]::new()

function Add-A([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
            detail = $Detail
        })
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length + 1)).Replace('\', '/')
}

function Get-LineCount([string]$Path) {
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Path)) { ++$count }
    return $count
}

function Copy-JsonObject([object]$Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-AgainstSchema([object]$Value) {
    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    return [bool](Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
}

function Test-Close([double]$Actual, [double]$Expected, [double]$Tolerance = 0.002) {
    return [Math]::Abs($Actual - $Expected) -le $Tolerance
}

function Get-Metric([object[]]$Group, [string]$Id) {
    $matches = @($Group | Where-Object { [string]$_.id -eq $Id })
    if ($matches.Count -ne 1) { return $null }
    return $matches[0]
}

function Get-BasisReferences([object]$Value) {
    $found = [Collections.Generic.List[string]]::new()
    function Visit([object]$Node) {
        if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) { return }
        if ($Node -is [Collections.IEnumerable] -and $Node -isnot [pscustomobject]) {
            foreach ($item in $Node) { Visit $item }
            return
        }
        foreach ($property in $Node.PSObject.Properties) {
            if ($property.Name -eq 'basis_ids') {
                foreach ($id in @($property.Value)) { $found.Add([string]$id) }
            }
            else { Visit $property.Value }
        }
    }
    Visit $Value
    return @($found)
}

function Test-BasisSemantics([object]$Candidate) {
    $requiredKinds = @('measured_fact', 'planning_coefficient', 'assumption',
        'risk_reserve', 'missing_measurement')
    $kindById = @{}
    foreach ($kind in $requiredKinds) {
        $entries = @($Candidate.basis_catalog.$kind)
        if ($entries.Count -lt 1) { return $false }
        foreach ($entry in $entries) {
            $id = [string]$entry.id
            if ($kindById.ContainsKey($id)) { return $false }
            $kindById[$id] = $kind
        }
    }
    foreach ($groupProperty in $Candidate.measured_facts.PSObject.Properties) {
        foreach ($metric in @($groupProperty.Value)) {
            $metricId = if ($null -ne $metric.PSObject.Properties['id']) {
                [string]$metric.id
            }
            else { '' }
            $expectedKind = if ($metricId -eq 'measured_human_hours') {
                'missing_measurement'
            }
            else { 'measured_fact' }
            foreach ($id in @($metric.basis_ids)) {
                if (-not $kindById.ContainsKey([string]$id) -or
                    $kindById[[string]$id] -ne $expectedKind) { return $false }
            }
        }
    }
    foreach ($id in @(Get-BasisReferences $Candidate)) {
        if (-not $kindById.ContainsKey([string]$id)) { return $false }
    }
    return $true
}

function Test-PilotAliasSemantics([object]$Candidate) {
    $totals = $Candidate.routing_totals
    $invariants = $Candidate.extrapolation_invariants
    if (-not $invariants.aliases_excluded_from_job_counts -or
        -not $invariants.aliases_excluded_from_ready_job_bytes -or
        [int64]$totals.files -ne [int64]$totals.jobs + [int64]$totals.aliases -or
        [int64]$totals.ready -ne [int64]$invariants.ready_job_count +
            [int64]$invariants.alias_file_count -or
        [int64]$invariants.ready_job_bytes_plus_manual_job_bytes -ne
            [int64]$totals.ready_job_bytes + [int64]$totals.manual_job_bytes -or
        [int64]$invariants.full_asset_bytes_include_aliases -ne [int64]$totals.bytes -or
        [int64]$invariants.ready_job_bytes_plus_manual_job_bytes -ge [int64]$totals.bytes) {
        return $false
    }
    $sumReadyBytes = [int64]0
    foreach ($route in @($Candidate.routing_by_family)) {
        if ([int64]$route.files -ne [int64]$route.jobs + [int64]$route.aliases) {
            return $false
        }
        $sumReadyBytes += [int64]$route.ready_job_bytes
    }
    return $sumReadyBytes -eq [int64]$totals.ready_job_bytes
}

function Get-JsonStrings([object]$Value) {
    $found = [Collections.Generic.List[string]]::new()
    function Visit-String([object]$Node) {
        if ($null -eq $Node) { return }
        if ($Node -is [string]) { $found.Add([string]$Node); return }
        if ($Node -is [ValueType]) { return }
        if ($Node -is [Collections.IEnumerable] -and $Node -isnot [pscustomobject]) {
            foreach ($item in $Node) { Visit-String $item }
            return
        }
        foreach ($property in $Node.PSObject.Properties) { Visit-String $property.Value }
    }
    Visit-String $Value
    return @($found)
}

function Test-JsonEqual([object]$Left, [object]$Right) {
    return ($Left | ConvertTo-Json -Depth 100 -Compress) -ceq
        ($Right | ConvertTo-Json -Depth 100 -Compress)
}

$required = @($policyPath, $schemaPath, $reportPath, $markdownPath, $evidencePath,
    $p215Path, $p218Path, $pilotPath, $generatorPath, $wrapperPath, $pilotScriptPath)
foreach ($path in $required) {
    Add-A "Required file $(Get-Relative $path)" (Test-Path -LiteralPath $path -PathType Leaf)
}
if (@($assertions | Where-Object result -eq 'FAIL').Count -gt 0) {
    [pscustomobject][ordered]@{
        schema_version = 1; task_id = 'P2-19'; result = 'FAIL'
        completion_criteria_satisfied = $false; assertions = $assertions
    } | ConvertTo-Json -Depth 100
    exit 1
}

$policyText = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8
$schemaText = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
$reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
$policy = $policyText | ConvertFrom-Json -Depth 100
$schema = $schemaText | ConvertFrom-Json -Depth 100
$report = $reportText | ConvertFrom-Json -Depth 100 -DateKind String
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$p215 = Get-Content -LiteralPath $p215Path -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$p218 = Get-Content -LiteralPath $p218Path -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$pilot = Get-Content -LiteralPath $pilotPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String

function Test-EvidenceSemantics([object]$Candidate) {
    $expectedTop = @('schema_version', 'captured_utc', 'task_id', 'result', 'task_status',
        'completion_criteria_satisfied', 'input', 'report', 'summary', 'contracts',
        'implementation', 'disclosure', 'reproduction', 'next_scope' | Sort-Object)
    $actualTop = @($Candidate.PSObject.Properties.Name | Sort-Object)
    if ($actualTop.Count -ne $expectedTop.Count -or
        @(Compare-Object $actualTop $expectedTop).Count -ne 0 -or
        $Candidate.schema_version -ne 1 -or $Candidate.task_id -ne 'P2-19' -or
        $Candidate.result -ne 'PASS' -or $Candidate.task_status -ne 'COMPLETE' -or
        -not $Candidate.completion_criteria_satisfied) { return $false }
    try { [void][DateTimeOffset]::Parse([string]$Candidate.captured_utc) }
    catch { return $false }
    $expectedKinds = @($policy.basis_categories | Sort-Object)
    if ($Candidate.input.source_build -ne $report.source_build -or
        -not (Test-JsonEqual $Candidate.input.bindings $report.input_bindings) -or
        @(Compare-Object @($Candidate.input.basis_kinds | Sort-Object) $expectedKinds).Count -ne 0) {
        return $false
    }
    if ($Candidate.report.json.path -ne 'Data/Reports/p2-19-resource-budget-report.json' -or
        $Candidate.report.markdown.path -ne 'Data/Reports/p2-19-resource-budget-report.md' -or
        -not $Candidate.report.json.tracked -or -not $Candidate.report.markdown.tracked -or
        $Candidate.report.json.sha256 -ne (Get-Sha256 $reportPath) -or
        $Candidate.report.markdown.sha256 -ne (Get-Sha256 $markdownPath) -or
        $Candidate.report.json.bytes -ne (Get-Item -LiteralPath $reportPath).Length -or
        $Candidate.report.markdown.bytes -ne (Get-Item -LiteralPath $markdownPath).Length -or
        $Candidate.report.json.lines -ne (Get-LineCount $reportPath) -or
        $Candidate.report.markdown.lines -ne (Get-LineCount $markdownPath)) { return $false }
    if ($Candidate.summary.report_result -ne $report.result -or
        $Candidate.summary.budget_status -ne $report.budget_status -or
        -not (Test-JsonEqual $Candidate.summary.human_budget $report.human_budget) -or
        -not (Test-JsonEqual $Candidate.summary.machine_budget $report.machine_budget) -or
        -not (Test-JsonEqual $Candidate.summary.storage_budget $report.storage_budget) -or
        -not (Test-JsonEqual $Candidate.summary.program_forecast $report.program_forecast) -or
        -not (Test-JsonEqual $Candidate.summary.team_plan $report.team_plan) -or
        $Candidate.summary.risk_items -ne @($report.risk_register).Count -or
        $Candidate.summary.missing_measurements -ne @($report.missing_measurements).Count -or
        -not (Test-JsonEqual $Candidate.summary.decisions $report.decisions)) { return $false }
    $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'Tools\TMXY.ResourceBudget') -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
    $sourceLines = @($sourceFiles | ForEach-Object {
            "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
        })
    $sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
    if ($Candidate.contracts.policy -ne 'Contracts/data-schema/resource-budget-policy-v1.json' -or
        $Candidate.contracts.schema -ne 'Contracts/data-schema/resource-budget-report-v1.schema.json' -or
        $Candidate.contracts.pilot -ne 'Data/Performance/p2-19-conversion-pilot.json' -or
        $Candidate.contracts.policy_sha256 -ne (Get-Sha256 $policyPath) -or
        $Candidate.contracts.schema_sha256 -ne (Get-Sha256 $schemaPath) -or
        $Candidate.contracts.pilot_sha256 -ne (Get-Sha256 $pilotPath) -or
        $Candidate.implementation.generator -ne 'Tools/TMXY.ResourceBudget/resource_budget.py' -or
        $Candidate.implementation.wrapper -ne 'Tools/TMXY.ResourceBudget/New-ResourceBudgetReport.ps1' -or
        $Candidate.implementation.generator_sha256 -ne (Get-Sha256 $generatorPath) -or
        $Candidate.implementation.wrapper_sha256 -ne (Get-Sha256 $wrapperPath) -or
        $Candidate.implementation.source_files -ne $sourceFiles.Count -or
        $Candidate.implementation.source_sha256 -ne $sourceSha -or
        $Candidate.implementation.self_test_assertions -lt 12) { return $false }
    if ($Candidate.disclosure.private_source_paths -or $Candidate.disclosure.exact_primary_keys -or
        $Candidate.disclosure.exact_observed_extrema -or $Candidate.disclosure.raw_table_rows -or
        $Candidate.disclosure.decoded_confidential_payloads -or
        $Candidate.disclosure.legacy_source_lines -or $Candidate.reproduction.check_mode -or
        $Candidate.reproduction.repository_mount -ne 'read-only' -or
        $Candidate.reproduction.network -ne 'none' -or
        $Candidate.reproduction.builder_user -ne 'tmxy' -or
        @(Compare-Object @($Candidate.next_scope.tasks) @('P2-20')).Count -ne 0) { return $false }
    return $true
}

Add-A 'Policy and schema are valid JSON' (
    [bool](Test-Json -Json $policyText -ErrorAction SilentlyContinue) -and
    [bool](Test-Json -Json $schemaText -ErrorAction SilentlyContinue))
Add-A 'Report validates against the closed JSON Schema' (
    [bool](Test-Json -Json $reportText -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
$actualTop = @($report.PSObject.Properties.Name | Sort-Object)
$requiredTop = @($schema.required | Sort-Object)
Add-A 'Closed report has exactly the 17 required top-level fields' (
    $schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema' -and
    $schema.type -eq 'object' -and $schema.additionalProperties -eq $false -and
    $actualTop.Count -eq 17 -and $requiredTop.Count -eq 17 -and
    @(Compare-Object $actualTop $requiredTop).Count -eq 0 -and
    $report.schema_version -eq 1 -and $report.task_id -eq 'P2-19' -and
    $report.result -eq 'PASS_WITH_OPEN_MEASUREMENT_GAPS' -and
    $report.budget_status -eq 'CONDITIONAL_PLANNING_BASELINE')

$bindings = $report.input_bindings
$bindingPassed = $p215.result -eq 'PASS' -and $p215.task_status -eq 'COMPLETE' -and
    $p215.completion_criteria_satisfied -and $p218.result -eq 'PASS' -and
    $p218.task_status -eq 'COMPLETE' -and $p218.completion_criteria_satisfied -and
    $pilot.result -eq 'PASS' -and $pilot.task_status -eq 'COMPLETE' -and
    $pilot.completion_criteria_satisfied -and $pilot.measurement_complete -and
    $bindings.conversion_routing.task_id -eq 'P2-15' -and
    $bindings.conversion_routing.path -eq 'Data/Inventory/p2-15-conversion-routing.json' -and
    $bindings.conversion_routing.sha256 -eq (Get-Sha256 $p215Path) -and
    $bindings.content_health.task_id -eq 'P2-18' -and
    $bindings.content_health.path -eq 'Data/Inventory/p2-18-content-health.json' -and
    $bindings.content_health.sha256 -eq (Get-Sha256 $p218Path) -and
    $bindings.conversion_pilot.task_id -eq 'P2-19-PILOT' -and
    $bindings.conversion_pilot.path -eq 'Data/Performance/p2-19-conversion-pilot.json' -and
    $bindings.conversion_pilot.sha256 -eq (Get-Sha256 $pilotPath)
$bindingLines = @(@('conversion_routing', 'content_health', 'conversion_pilot') | ForEach-Object {
        $item = $bindings.$_
        "$($item.task_id)|$($item.path)|$($item.sha256)"
    })
$bindingPassed = $bindingPassed -and $bindings.aggregate_sha256 -eq
    (Get-TextSha256 (($bindingLines -join "`n") + "`n"))
Add-A 'P2-15 P2-18 and pilot are complete and exactly SHA-256 bound' $bindingPassed

$basisKinds = @($report.basis_catalog.PSObject.Properties.Name | Sort-Object)
$expectedKinds = @($policy.basis_categories | Sort-Object)
$basisIds = @($report.basis_catalog.PSObject.Properties | ForEach-Object {
        @($_.Value) | ForEach-Object { [string]$_.id }
    })
Add-A 'All five disjoint basis categories are populated' (
    $basisKinds.Count -eq 5 -and @(Compare-Object $basisKinds $expectedKinds).Count -eq 0 -and
    @($basisIds | Sort-Object -Unique).Count -eq $basisIds.Count -and
    (Test-BasisSemantics $report))
Add-A 'Measured facts never cite planning assumptions or risk reserves' (Test-BasisSemantics $report)

$assetMetrics = @($report.measured_facts.assets)
$conversionMetrics = @($report.measured_facts.conversion)
$riskMetrics = @($report.measured_facts.content_risks)
$assetCount = Get-Metric $assetMetrics 'assets'
$jobCount = Get-Metric $conversionMetrics 'conversion_jobs'
$readyJobCount = Get-Metric $conversionMetrics 'ready_unique_jobs'
$aliasCount = Get-Metric $conversionMetrics 'alias_assignments'
$manualCount = Get-Metric $conversionMetrics 'blocked_manual_jobs'
$unresolvedCount = Get-Metric $riskMetrics 'asset_structure_unresolved'
$corruptCount = Get-Metric $riskMetrics 'asset_corrupt'
Add-A 'Measured asset conversion and risk populations preserve all P2 invariants' (
    $null -ne $assetCount -and $assetCount.value -eq 40090 -and
    $null -ne $jobCount -and $jobCount.value -eq 34601 -and
    $null -ne $readyJobCount -and $readyJobCount.value -eq 33801 -and
    $null -ne $aliasCount -and $aliasCount.value -eq 5489 -and
    $null -ne $manualCount -and $manualCount.value -eq 800 -and
    $null -ne $unresolvedCount -and $unresolvedCount.value -eq 786 -and
    $null -ne $corruptCount -and $corruptCount.value -eq 14 -and
    $p215.summary.assets.files -eq 40090 -and $p215.summary.assets.conversion_jobs -eq 34601 -and
    $p215.summary.assets.alias_reuse -eq 5489 -and
    $p218.summary.conversion.distinct_ready_keys -eq 33801 -and
    $p218.summary.conversion.blocked_manual_jobs -eq 800 -and
    $p218.summary.unknown_or_opaque.asset_structure_unresolved -eq 786 -and
    $p218.summary.damage.asset_corrupt -eq 14)

$pilotFamilies = @($pilot.cases | ForEach-Object { [string]$_.family } | Sort-Object)
$expectedPilotFamilies = @('anim', 'qtx', 'skem', 'sm', 'ter' | Sort-Object)
$pilotCasesPassed = @($pilot.cases).Count -eq 5 -and
    @(Compare-Object $pilotFamilies $expectedPilotFamilies).Count -eq 0 -and
    $pilot.protocol.measurement_runs_per_case -eq 5 -and
    -not $pilot.selection.source_paths_emitted -and -not $pilot.selection.object_names_emitted -and
    -not $pilot.disclosure.exact_observed_extrema
foreach ($case in @($pilot.cases)) {
    $pilotCasesPassed = $pilotCasesPassed -and @($case.elapsed_ms).Count -eq 5 -and
        $case.case_id -match '^[a-f0-9]{64}$' -and
        $case.output_sha256 -match '^[a-f0-9]{64}$' -and
        $case.output_hash_stable -and $case.output_size_stable -and
        [double]$case.median_ms -gt 0 -and [double]$case.p80_ms -ge [double]$case.median_ms
}
Add-A 'Five anonymous pilot families each have five stable measured outputs' $pilotCasesPassed
Add-A 'Pilot publishable selection protocol and cases contain no extremum-selection semantics' (
    @((Get-JsonStrings @($pilot.selection, $pilot.protocol, $pilot.cases)) |
        Where-Object { $_ -match '(?i)\b(maximum|largest|extrema)\b' }).Count -eq 0 -and
    -not $pilot.disclosure.exact_observed_extrema)
Add-A 'Pilot excludes aliases from conversion jobs and ready-job bytes' (Test-PilotAliasSemantics $pilot)

$routes = @($policy.route_risk_reserve_basis_points.PSObject.Properties.Name | Sort-Object)
$humanRoutes = @($report.human_budget.by_route)
$humanPassed = $humanRoutes.Count -eq 5 -and
    @(Compare-Object $routes @($humanRoutes.route | Sort-Object)).Count -eq 0
foreach ($route in $humanRoutes) {
    $expectedBp = [int]$policy.route_risk_reserve_basis_points.([string]$route.route)
    $humanPassed = $humanPassed -and [int]$route.risk_reserve_basis_points -eq $expectedBp -and
        (Test-Close $route.risk_reserve_hours ($route.base_hours * $expectedBp / 10000.0)) -and
        (Test-Close $route.total_hours ($route.base_hours + $route.risk_reserve_hours))
}
$humanPassed = $humanPassed -and
    (Test-Close $report.human_budget.base_planning_hours (($humanRoutes | Measure-Object base_hours -Sum).Sum)) -and
    (Test-Close $report.human_budget.risk_reserve_hours (($humanRoutes | Measure-Object risk_reserve_hours -Sum).Sum)) -and
    (Test-Close $report.human_budget.total_planning_hours ($report.human_budget.base_planning_hours + $report.human_budget.risk_reserve_hours))
$fteValues = @($report.human_budget.workforce_scenarios.content_specialist_fte | Sort-Object)
$humanPassed = $humanPassed -and @(Compare-Object $fteValues @(2, 3, 4)).Count -eq 0
foreach ($scenario in @($report.human_budget.workforce_scenarios)) {
    $capacity = 28.0 * [int]$scenario.content_specialist_fte
    $humanPassed = $humanPassed -and $scenario.productive_hours_per_fte_week -eq 28 -and
        (Test-Close $scenario.base_weeks ($report.human_budget.base_planning_hours / $capacity)) -and
        (Test-Close $scenario.risk_reserve_weeks ($report.human_budget.risk_reserve_hours / $capacity)) -and
        (Test-Close $scenario.risk_adjusted_weeks ($report.human_budget.total_planning_hours / $capacity))
}
Add-A 'Human base reserve total arithmetic and 2 3 4 FTE weeks close' $humanPassed

$basisKindById = @{}
foreach ($property in $report.basis_catalog.PSObject.Properties) {
    foreach ($entry in @($property.Value)) { $basisKindById[[string]$entry.id] = $property.Name }
}
$machineBasisKinds = @(Get-BasisReferences $report.machine_budget | ForEach-Object {
        $basisKindById[[string]$_]
    } | Sort-Object -Unique)
$machineRoutes = @($report.machine_budget.by_route)
$automaticMachine = @($machineRoutes | Where-Object route -eq 'automatic-qualified-interchange')
$machinePassed = $report.machine_budget.projection_status -eq 'PARTIALLY_PILOT_CALIBRATED' -and
    $report.machine_budget.risk_reserve_basis_points -eq 5000 -and
    $machineRoutes.Count -eq 5 -and $machineBasisKinds -contains 'measured_fact' -and
    $machineBasisKinds -contains 'planning_coefficient' -and
    $automaticMachine.Count -eq 1 -and $automaticMachine[0].pilot_sample_count -eq 25 -and
    @($machineRoutes | Where-Object {
            $_.route -ne 'automatic-qualified-interchange' -and $_.pilot_sample_count -ne 0
        }).Count -eq 0 -and
    (Test-Close $report.machine_budget.risk_reserve_seconds ($report.machine_budget.base_sequential_seconds * 0.5)) -and
    (Test-Close $report.machine_budget.total_sequential_seconds ($report.machine_budget.base_sequential_seconds + $report.machine_budget.risk_reserve_seconds)) -and
    (Test-Close $report.machine_budget.base_sequential_seconds (($machineRoutes | Measure-Object base_seconds -Sum).Sum)) -and
    (Test-Close $report.machine_budget.risk_reserve_seconds (($machineRoutes | Measure-Object risk_reserve_seconds -Sum).Sum))
Add-A 'Machine projection is measured-planning mixed with a separate 5000bp reserve' $machinePassed

$storage = $report.storage_budget
$expectedRecovery = [int64]$storage.one_copy_bytes * 2
$baseIncremental = [int64]$storage.intermediate_estimated_bytes +
    [int64]$storage.ue_content_estimated_bytes + [int64]$storage.build_cache_estimated_bytes +
    [int64]$storage.recovery_bytes
$expectedReserve = [int64][Math]::Ceiling([decimal]$baseIncremental * 3500 / 10000)
$expectedGap = [Math]::Max([int64]0,
    [int64]$storage.incremental_required_bytes - [int64]$storage.disk_free_bytes)
$storagePassed = $storage.disk_total_bytes -eq $pilot.environment.storage.workspace_volume_total_bytes -and
    $storage.disk_free_bytes -eq $pilot.environment.storage.workspace_volume_available_bytes -and
    $storage.existing_workspace_bytes -eq $pilot.environment.storage.rebuild_bytes -and
    $storage.source_retained_bytes -eq $pilot.routing_totals.bytes -and
    $storage.duplicate_redundant_review_only_bytes -eq
        $p218.summary.capacity.exact_duplicate_redundant_bytes_review_only -and
    -not $storage.deduplication_savings_assumed -and $storage.recovery_copy_count -eq 2 -and
    $storage.recovery_bytes -eq $expectedRecovery -and
    $storage.risk_reserve_basis_points -eq 3500 -and
    $storage.risk_reserve_bytes -eq $expectedReserve -and
    $storage.capacity_gap_bytes -eq $expectedGap -and
    $storage.capacity_sufficient -eq ($expectedGap -eq 0) -and
    $storage.total_budget_bytes -eq $storage.existing_workspace_bytes + $storage.incremental_required_bytes
Add-A 'Storage keeps review-only duplicates and closes two recovery copies 3500bp reserve and E drive gap' $storagePassed

$phaseIds = @($report.program_forecast.phase_ranges.phase | Sort-Object)
$programPassed = $report.program_forecast.scope -eq 'P3-P8' -and
    @(Compare-Object $phaseIds @('P3', 'P4', 'P5', 'P6', 'P7', 'P8')).Count -eq 0 -and
    $null -eq $report.program_forecast.g2_blocking_delay_weeks -and
    $report.program_forecast.g2_delay_status -eq 'unbounded' -and
    -not $report.program_forecast.delivery_commitment
foreach ($phase in @($report.program_forecast.phase_ranges)) {
    $frozen = $policy.program_phase_ranges_weeks.([string]$phase.phase)
    $programPassed = $programPassed -and $phase.minimum_weeks -eq $frozen.minimum -and
        $phase.maximum_weeks -eq $frozen.maximum
}
$scenarioIds = @($report.program_forecast.scenarios.id | Sort-Object)
$programPassed = $programPassed -and
    @(Compare-Object $scenarioIds @('accelerated', 'constrained', 'recommended')).Count -eq 0
$sequentialMinimum = ($report.program_forecast.phase_ranges | Measure-Object minimum_weeks -Sum).Sum
$sequentialMaximum = ($report.program_forecast.phase_ranges | Measure-Object maximum_weeks -Sum).Sum
foreach ($scenario in @($report.program_forecast.scenarios)) {
    $frozen = $policy.program_scenarios.([string]$scenario.id)
    $programPassed = $programPassed -and $scenario.core_fte -eq $frozen.core_fte -and
        $scenario.shared_fte -eq $frozen.shared_fte -and
        $scenario.phase_overlap_basis_points -eq $frozen.phase_overlap_basis_points -and
        $scenario.risk_reserve_basis_points -eq $frozen.risk_reserve_basis_points -and
        (Test-Close $scenario.base_weeks.minimum ($sequentialMinimum * $scenario.phase_overlap_basis_points / 10000.0)) -and
        (Test-Close $scenario.base_weeks.maximum ($sequentialMaximum * $scenario.phase_overlap_basis_points / 10000.0))
    foreach ($bound in @('minimum', 'maximum')) {
        $programPassed = $programPassed -and
            (Test-Close $scenario.risk_reserve_weeks.$bound ($scenario.base_weeks.$bound * $scenario.risk_reserve_basis_points / 10000.0)) -and
            (Test-Close $scenario.total_weeks.$bound ($scenario.base_weeks.$bound + $scenario.risk_reserve_weeks.$bound))
    }
}
Add-A 'P3-P8 scenarios stay non-committing and G2 delay remains null and unbounded' $programPassed

$teamIds = @($report.team_plan.scenarios.id | Sort-Object)
$teamPassed = $report.team_plan.productive_hours_per_fte_week -eq 28 -and
    $report.team_plan.content_specialist_fte.minimum -eq 2 -and
    $report.team_plan.content_specialist_fte.recommended -eq 3 -and
    $report.team_plan.content_specialist_fte.maximum -eq 4 -and
    @(Compare-Object $teamIds @('accelerated', 'constrained', 'recommended')).Count -eq 0
foreach ($scenario in @($report.team_plan.scenarios)) {
    $frozen = $policy.program_scenarios.([string]$scenario.id)
    $specialistKey = if ($scenario.id -eq 'constrained') { 'minimum' }
        elseif ($scenario.id -eq 'recommended') { 'recommended' } else { 'maximum' }
    $teamPassed = $teamPassed -and $scenario.core_fte -eq $frozen.core_fte -and
        $scenario.shared_fte -eq $frozen.shared_fte -and
        $scenario.content_specialist_fte -eq
            $policy.workforce_policy.content_specialist_fte.$specialistKey -and
        $scenario.productive_hours_per_week -eq 28
}
Add-A 'Team scenarios preserve the frozen 2 3 4 specialist and program staffing plan' $teamPassed

$money = $report.human_budget.money_budget
Add-A 'Money remains explicitly unestimated until rates and currency exist' (
    -not $money.estimated -and $null -eq $money.currency -and $null -eq $money.amount -and
    @($money.missing_inputs).Count -eq @($policy.money_budget.missing_inputs).Count -and
    @(Compare-Object -ReferenceObject @($money.missing_inputs | Sort-Object) -DifferenceObject @($policy.money_budget.missing_inputs | Sort-Object)).Count -eq 0)
Add-A 'No playable G2 release repair delete or schedule authority is claimed' (
    $report.decisions.all_numeric_outputs_are_non_price_planning_values -and
    -not $report.decisions.schedule_is_delivery_commitment -and
    -not $report.decisions.money_budget_estimated -and -not $report.decisions.g2_approved -and
    -not $report.decisions.playable_experience_proven -and
    -not $report.decisions.release_authority -and
    -not $p218.summary.decisions.automatic_repair_authorized -and
    -not $p218.summary.decisions.automatic_deletion_authorized)
Add-A 'Tracked outputs preserve every disclosure boundary' (
    -not $report.disclosure.private_source_paths -and -not $report.disclosure.exact_primary_keys -and
    -not $report.disclosure.exact_observed_extrema -and -not $report.disclosure.raw_table_rows -and
    -not $report.disclosure.decoded_confidential_payloads -and
    -not $report.disclosure.legacy_source_lines -and -not $report.disclosure.prices -and
    -not $report.disclosure.schedule_commitments -and
    -not $evidence.disclosure.private_source_paths -and -not $evidence.disclosure.exact_primary_keys -and
    -not $pilot.disclosure.legacy_source_paths -and -not $pilot.disclosure.legacy_object_names)

$moduleRoot = Join-Path $root 'Tools\TMXY.ResourceBudget'
$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.py') } | Sort-Object FullName)
$sourceLines = @($sourceFiles | ForEach-Object {
        "$(Get-Relative $_.FullName)|$(Get-Sha256 $_.FullName)"
    })
$sourceSha = Get-TextSha256 (($sourceLines -join "`n") + "`n")
Add-A 'Policy schema pilot and implementation hashes are exact' (
    $evidence.result -eq 'PASS' -and $evidence.task_status -eq 'COMPLETE' -and
    $evidence.completion_criteria_satisfied -and
    $evidence.contracts.policy_sha256 -eq (Get-Sha256 $policyPath) -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha256 $schemaPath) -and
    $evidence.contracts.pilot_sha256 -eq (Get-Sha256 $pilotPath) -and
    $evidence.implementation.generator_sha256 -eq (Get-Sha256 $generatorPath) -and
    $evidence.implementation.wrapper_sha256 -eq (Get-Sha256 $wrapperPath) -and
    $evidence.implementation.source_files -eq $sourceFiles.Count -and
    $evidence.implementation.source_sha256 -eq $sourceSha)
Add-A 'Complete evidence envelope matches report contracts implementation and isolation' (
    Test-EvidenceSemantics $evidence)
Add-A 'Tracked JSON and Markdown report hashes sizes and lines are frozen' (
    $evidence.report.json.path -eq 'Data/Reports/p2-19-resource-budget-report.json' -and
    $evidence.report.markdown.path -eq 'Data/Reports/p2-19-resource-budget-report.md' -and
    $evidence.report.json.tracked -and $evidence.report.markdown.tracked -and
    $evidence.report.json.sha256 -eq (Get-Sha256 $reportPath) -and
    $evidence.report.markdown.sha256 -eq (Get-Sha256 $markdownPath) -and
    $evidence.report.json.bytes -eq (Get-Item -LiteralPath $reportPath).Length -and
    $evidence.report.markdown.bytes -eq (Get-Item -LiteralPath $markdownPath).Length -and
    $evidence.report.json.lines -eq (Get-LineCount $reportPath) -and
    $evidence.report.markdown.lines -eq (Get-LineCount $markdownPath))

$negativeCases = [ordered]@{}
$unknownField = Copy-JsonObject $report
$unknownField | Add-Member -NotePropertyName unreviewed_budget_claim -NotePropertyValue 1
$negativeCases.schema_unknown_field_rejected = -not (Test-AgainstSchema $unknownField)
$basisMutation = Copy-JsonObject $report
$basisMutation.measured_facts.assets[0].basis_ids[0] =
    [string]$basisMutation.basis_catalog.planning_coefficient[0].id
$negativeCases.basis_category_mutation_rejected =
    (Test-AgainstSchema $basisMutation) -and -not (Test-BasisSemantics $basisMutation)
$aliasMutation = Copy-JsonObject $pilot
$aliasMutation.routing_totals.ready_job_bytes = [int64]$aliasMutation.routing_totals.ready_job_bytes + 1
$negativeCases.alias_ready_bytes_mutation_rejected = -not (Test-PilotAliasSemantics $aliasMutation)
$evidenceMutation = Copy-JsonObject $evidence
$evidenceMutation.implementation.source_sha256 = '0' * 64
$negativeCases.complete_evidence_tamper_rejected = -not (Test-EvidenceSemantics $evidenceMutation)
Add-A 'Unknown-field basis-category alias-byte and full-evidence negative cases fail closed' (
    @($negativeCases.Values | Where-Object { -not $_ }).Count -eq 0)

$localCheck = $null
if ($VerifyDerivedSources) {
    $localCheck = & $wrapperPath -RebuildRoot $root -Check | ConvertFrom-Json -Depth 100
    Add-A 'Byte-identical isolated regeneration passes wrapper check mode' (
        $localCheck.result -eq 'PASS' -and $localCheck.completion_criteria_satisfied -and
        $localCheck.report.json.sha256 -eq $evidence.report.json.sha256 -and
        $localCheck.report.markdown.sha256 -eq $evidence.report.markdown.sha256 -and
        $localCheck.implementation.source_sha256 -eq $evidence.implementation.source_sha256)
}

$failed = @($assertions | Where-Object result -eq 'FAIL')
[pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-19'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    completion_criteria_satisfied = $failed.Count -eq 0
    verify_derived_sources = [bool]$VerifyDerivedSources
    negative_cases = $negativeCases
    report = $evidence.report
    summary = $evidence.summary
    local_check = $localCheck
    assertions = $assertions
} | ConvertTo-Json -Depth 100
if ($failed.Count -gt 0) { exit 1 }
