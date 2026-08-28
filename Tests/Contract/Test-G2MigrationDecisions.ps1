[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyDerivedSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$policyPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-policy-v1.json'
$schemaPath = Join-Path $root 'Contracts\data-schema\g2-migration-decision-registry-v1.schema.json'
$registryPath = Join-Path $root 'Data\Governance\p2-g2-migration-decisions.json'
$evidencePath = Join-Path $root 'Data\Inventory\p2-20b-migration-decisions.json'
$reportPath = Join-Path $root 'Data\Reports\p2-20b-migration-decisions-report.md'
$wrapperPath = Join-Path $root 'Tools\TMXY.G2MigrationDecisions\New-G2MigrationDecisions.ps1'
$assertions = [Collections.Generic.List[object]]::new()

function Add-A([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
            detail = $Detail
        })
}

function Get-Sha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Add-StringValues([object]$Value, [Collections.Generic.HashSet[string]]$Target) {
    if ($null -eq $Value) { return }
    if ($Value -is [string]) {
        [void]$Target.Add([string]$Value)
        return
    }
    if ($Value -is [Collections.IDictionary]) {
        foreach ($item in $Value.Values) { Add-StringValues $item $Target }
        return
    }
    if ($Value -is [Collections.IEnumerable]) {
        foreach ($item in $Value) { Add-StringValues $item $Target }
        return
    }
    foreach ($property in $Value.PSObject.Properties) {
        Add-StringValues $property.Value $Target
    }
}

function Get-ManifestSha([object[]]$Items) {
    $members = @($Items | ForEach-Object {
            [pscustomobject][ordered]@{
                decision_id = [string]$_.decision_id
                subject_membership_sha256 = [string]$_.subject_membership_sha256
            }
        })
    return Get-TextSha ($members | ConvertTo-Json -Depth 5 -Compress)
}

function Test-DecisionState([object]$Item) {
    if ($Item.machine_suggestion.counts_as_decision -ne $false) { return $false }
    if ($Item.decision.status -eq 'PENDING') {
        return $null -eq $Item.decision.chosen_action -and $null -eq $Item.decision.rationale -and
            $null -eq $Item.decision.migration_plan_sha256 -and
            $null -eq $Item.decision.rollback_plan_sha256 -and
            $Item.approval.status -eq 'PENDING' -and [int]$Item.approval.approval_count -eq 0 -and
            $Item.approval.external_authority_verified -eq $false -and
            @($Item.approval.approval_refs).Count -eq 0
    }
    return $false
}

function Test-Coverage([object[]]$Items, [object[]]$Manifests, [int]$ExpectedTotal) {
    if ($Items.Count -ne $ExpectedTotal) { return $false }
    $ids = @($Items.decision_id)
    if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { return $false }
    foreach ($manifest in $Manifests) {
        $members = @($Items | Where-Object subject_kind -eq $manifest.subject_kind)
        if ($members.Count -ne [int]$manifest.expected -or
            $members.Count -ne [int]$manifest.enumerated -or
            (Get-ManifestSha $members) -cne [string]$manifest.membership_sha256) { return $false }
    }
    return $true
}

function Test-EvidenceBindings([object]$Registry, [object]$Policy) {
    $specifications = @($Policy.required_inputs)
    if (@($Registry.input_bindings.evidence).Count -ne $specifications.Count) { return $false }
    foreach ($specification in $specifications) {
        $binding = @($Registry.input_bindings.evidence | Where-Object task_id -eq $specification.task_id)
        $path = Join-Path $root ([string]$specification.path).Replace('/', '\')
        if ($binding.Count -ne 1 -or [string]$binding[0].path -ne [string]$specification.path -or
            [string]$binding[0].sha256 -cne (Get-Sha $path)) { return $false }
    }
    $derived = @($Registry.input_bindings.derived_sources)
    $p209 = Get-Content (Join-Path $root 'Data\Inventory\p2-09-legacy-current-diff.json') -Raw |
        ConvertFrom-Json -Depth 100 -DateKind String
    $p211 = Get-Content (Join-Path $root 'Data\Inventory\p2-11-id-limit-audit.json') -Raw |
        ConvertFrom-Json -Depth 100 -DateKind String
    $checks = @{
        G2_POLICY = Get-Sha (Join-Path $root 'Contracts\data-schema\g2-review-policy-v1.json')
        CORE_REGISTRY = Get-Sha (Join-Path $root 'Data\Schemas\core-table-registry-v1.json')
        P2_09_TABLE_DIFF_REPORT = [string]$p209.report.sha256
        P2_11_ID_LIMIT_REPORT = [string]$p211.report.sha256
    }
    foreach ($name in $checks.Keys) {
        $binding = @($derived | Where-Object artifact_id -eq $name)
        if ($binding.Count -ne 1 -or [string]$binding[0].sha256 -cne $checks[$name]) { return $false }
    }
    if ($VerifyDerivedSources) {
        if ($checks.P2_09_TABLE_DIFF_REPORT -cne
            (Get-Sha (Join-Path $root 'Data\Exports\P2-09\p2-09-legacy-current-diff.jsonl')) -or
            $checks.P2_11_ID_LIMIT_REPORT -cne
            (Get-Sha (Join-Path $root 'Data\Exports\P2-11\p2-11-id-limit-audit.jsonl'))) {
            return $false
        }
    }
    $legacy = @($derived | Where-Object artifact_id -eq 'LEGACY_SNAPSHOT_MANIFEST')
    if ($legacy.Count -ne 1 -or [string]$legacy[0].sha256 -cne [string]$p209.input.legacy_manifest_sha256) {
        return $false
    }
    $lines = @($Registry.input_bindings.evidence | ForEach-Object {
            "$($_.task_id)|$($_.path)|$($_.sha256)"
        })
    $g2 = @($derived | Where-Object artifact_id -eq 'G2_POLICY')[0]
    $lines += "G2_POLICY|$($g2.sha256)"
    $lines += @($derived | ForEach-Object { "$($_.artifact_id)|$($_.sha256)|$($_.records)" })
    return (Get-TextSha ($lines | ConvertTo-Json -Compress)) -ceq
        [string]$Registry.input_bindings.aggregate_sha256
}

function Test-NoIdentityLeak([string]$Raw, [object]$Registry) {
    if ($Raw -match '(?i)([A-Z]:\\|\.cpp"|\.hpp"|\.csv"|ClientCode|ServerCode|ToolCode|DevDoc)') {
        return $false
    }
    $core = Get-Content (Join-Path $root 'Data\Schemas\core-table-registry-v1.json') -Raw |
        ConvertFrom-Json -Depth 100 -DateKind String
    $identities = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($table in $core.tables) {
        [void]$identities.Add([string]$table.source_path)
        [void]$identities.Add([string]$table.logical_name)
        foreach ($column in $table.columns) { [void]$identities.Add([string]$column.source_name) }
        foreach ($foreignKey in $table.foreign_keys) {
            [void]$identities.Add([string]$foreignKey.id)
            [void]$identities.Add([string]$foreignKey.target_table)
        }
    }
    $p210 = Get-Content (Join-Path $root 'Data\Inventory\p2-10-canonical-id-map.json') -Raw |
        ConvertFrom-Json -Depth 100 -DateKind String
    foreach ($domain in $p210.domains) {
        [void]$identities.Add([string]$domain.domain)
    }
    if ($VerifyDerivedSources) {
        $p209Report = Join-Path $root 'Data\Exports\P2-09\p2-09-legacy-current-diff.jsonl'
        foreach ($line in [IO.File]::ReadLines($p209Report)) {
            $item = $line | ConvertFrom-Json -Depth 50 -DateKind String
            [void]$identities.Add([string]$item.table)
        }
        $p211Report = Join-Path $root 'Data\Exports\P2-11\p2-11-id-limit-audit.jsonl'
        foreach ($line in [IO.File]::ReadLines($p211Report)) {
            $item = $line | ConvertFrom-Json -Depth 30 -DateKind String
            if ($item.record -eq 'legacy_source_limit_signal') {
                [void]$identities.Add([string]$item.relative_path)
            }
        }
    }
    $emitted = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    Add-StringValues $Registry $emitted
    foreach ($identity in $identities) {
        if ([string]::IsNullOrWhiteSpace($identity)) { continue }
        if ($emitted.Contains($identity)) { return $false }
    }
    return $Registry.disclosure.table_or_field_names -eq $false -and
        $Registry.disclosure.legacy_source_paths -eq $false -and
        $Registry.disclosure.exact_primary_keys -eq $false -and
        $Registry.disclosure.exact_observed_extrema -eq $false -and
        $Registry.disclosure.raw_table_rows -eq $false -and
        $Registry.disclosure.legacy_source_lines -eq $false
}

$required = @($policyPath, $schemaPath, $registryPath, $evidencePath, $reportPath, $wrapperPath,
    (Join-Path $root 'Tools\TMXY.G2MigrationDecisions\migration_decisions.py'),
    (Join-Path $root 'Tools\TMXY.G2MigrationDecisions\g2_common.py'),
    (Join-Path $root 'Tools\TMXY.G2MigrationDecisions\legacy_reference.py'))
foreach ($path in $required) { Add-A "Required file $([IO.Path]::GetRelativePath($root, $path))" (Test-Path $path -PathType Leaf) }
if (@($required | Where-Object { -not (Test-Path $_ -PathType Leaf) }).Count -gt 0) {
    throw 'P2-20B required files are missing.'
}

$raw = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8
$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$registry = $raw | ConvertFrom-Json -Depth 100 -DateKind String
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
Add-A 'Policy schema registry and task evidence are valid JSON' ($null -ne $policy -and $null -ne $schema -and $null -ne $registry -and $null -ne $evidence)
Add-A 'Registry validates against the closed JSON Schema' ($raw | Test-Json -SchemaFile $schemaPath)
Add-A 'Registry is fail-closed while generation succeeds' ($registry.result -eq 'BLOCKED' -and
    $registry.generation_result -eq 'PASS' -and $registry.task_status -eq 'BLOCKED' -and
    $registry.completion_criteria_satisfied -eq $false -and $registry.g2_07_satisfied -eq $false)

$decisions = @($registry.decisions)
$coverageOk = Test-Coverage $decisions @($registry.manifests) 1359
Add-A 'All 1359 anonymous subjects are exactly and uniquely manifest-bound' $coverageOk
$counts = $registry.summary.by_subject_kind
Add-A 'Subject populations are exactly 52 12 12 16 and 1267' (
    [int]$counts.schema_table -eq 52 -and [int]$counts.schema_reference -eq 12 -and
    [int]$counts.canonical_id_domain -eq 12 -and [int]$counts.id_component -eq 16 -and
    [int]$counts.fixed_limit_signal -eq 1267)
Add-A 'Reference membership is truly enumerated rather than count-filled' (
    $registry.completeness.reference_membership_enumerated -eq $true -and
    @($decisions | Where-Object subject_kind -eq 'SCHEMA_REFERENCE').Count -eq 12)
Add-A 'Every machine suggestion remains a pending non-decision without approval' (
    @($decisions | Where-Object { -not (Test-DecisionState $_) }).Count -eq 0 -and
    [int]$registry.summary.pending -eq 1359 -and [int]$registry.summary.approval_count -eq 0)
Add-A 'All required evidence and derived inputs are exactly hash-bound' (Test-EvidenceBindings $registry $policy)
Add-A 'No table field source-path primary-key extrema row or source-line identity leaks' (Test-NoIdentityLeak $raw $registry)
Add-A 'Hard invariants forbid narrowing implicit numeric IDs mode defaults Tombstone reuse and limit copying' (
    @($registry.hard_invariants.PSObject.Properties | Where-Object { $_.Value -ne $true }).Count -eq 0)
Add-A 'Machine cannot approve G2 P3 or release' ($registry.authority_boundaries.machine_can_approve -eq $false -and
    $registry.authority_boundaries.approval_authority_present -eq $false -and
    $registry.authority_boundaries.g2_approved -eq $false -and
    $registry.authority_boundaries.p3_authorized -eq $false -and
    $registry.authority_boundaries.release_authority -eq $false)
Add-A 'Policy and Schema hashes are exact' ($registry.contracts.policy_sha256 -eq (Get-Sha $policyPath) -and
    $registry.contracts.schema_sha256 -eq (Get-Sha $schemaPath))
Add-A 'Task evidence exactly binds registry report contracts and blocked status' (
    $evidence.result -eq 'BLOCKED' -and $evidence.generation_result -eq 'PASS' -and
    $evidence.g2_07_satisfied -eq $false -and $evidence.registry.sha256 -eq (Get-Sha $registryPath) -and
    $evidence.report.sha256 -eq (Get-Sha $reportPath) -and
    $evidence.contracts.policy_sha256 -eq (Get-Sha $policyPath) -and
    $evidence.contracts.schema_sha256 -eq (Get-Sha $schemaPath))

$missingCase = @($decisions | Select-Object -Skip 1)
$duplicateCase = @($decisions) + @($decisions[0])
$orphan = $decisions[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
$orphan.decision_id = 'MIG-ORPHAN-9999'; $orphan.subject_membership_sha256 = 'f' * 64
$orphanCase = @($decisions) + @($orphan)
$fakeApproval = $decisions[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
$fakeApproval.decision.status = 'DECIDED'; $fakeApproval.decision.chosen_action = 'FAKE'
$fakeApproval.approval.status = 'APPROVED'; $fakeApproval.approval.approval_count = 1
$fakeApproval.approval.external_authority_verified = $true
$fakeApproval.approval.approval_refs = @([pscustomobject]@{
        role = 'data-owner'; authority_kind = 'SIGNED_DECISION_RECORD'
        authority_record_sha256 = 'a' * 64; decision_digest_sha256 = 'b' * 64; verified = $true
    })
$compressed = @($decisions | Group-Object subject_kind | ForEach-Object { $_.Group[0] })
$noMember = $decisions[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
$noMember.subject_membership_sha256 = $null
$noMemberCase = @($noMember) + @($decisions | Select-Object -Skip 1)
$drift = $registry.input_bindings.evidence | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10 -DateKind String
$drift[0].sha256 = '0' * 64
$driftObject = [pscustomobject]@{ input_bindings = [pscustomobject]@{
        evidence = $drift; derived_sources = $registry.input_bindings.derived_sources } }
$unknownRawObject = $raw | ConvertFrom-Json -Depth 100 -DateKind String
$unknownRawObject | Add-Member -NotePropertyName untrusted_approval -NotePropertyValue $true
$negative = [ordered]@{
    missing_rejected = -not (Test-Coverage $missingCase @($registry.manifests) 1359)
    duplicate_rejected = -not (Test-Coverage $duplicateCase @($registry.manifests) 1359)
    orphan_rejected = -not (Test-Coverage $orphanCase @($registry.manifests) 1359)
    fake_approval_rejected = -not (Test-DecisionState $fakeApproval)
    input_drift_rejected = -not (Test-EvidenceBindings $driftObject $policy)
    aggregate_compression_rejected = -not (Test-Coverage $compressed @($registry.manifests) 1359)
    aggregate_without_membership_hash_rejected = -not (Test-Coverage $noMemberCase @($registry.manifests) 1359)
    unknown_field_rejected = -not (($unknownRawObject | ConvertTo-Json -Depth 100 -Compress) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
}
Add-A 'Missing duplicate orphan fake approval input drift aggregate compression membership hash and unknown field fail closed' (
    @($negative.Values | Where-Object { $_ -ne $true }).Count -eq 0)

$localCheck = $null
if ($VerifyDerivedSources) {
    $localCheck = & pwsh -NoProfile -File $wrapperPath -RebuildRoot $root -Check | ConvertFrom-Json -Depth 100 -DateKind String
    Add-A 'Locked isolated byte-for-byte regeneration passes' ($LASTEXITCODE -eq 0 -and
        $localCheck.generation_result -eq 'PASS' -and $localCheck.g2_07_satisfied -eq $false)
}

$failures = @($assertions | Where-Object result -eq 'FAIL')
$result = [pscustomobject][ordered]@{
    schema_version = 1
    task_id = 'P2-20B'
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    contract_assertions_satisfied = $failures.Count -eq 0
    completion_criteria_satisfied = $false
    g2_07_satisfied = $false
    verify_derived_sources = [bool]$VerifyDerivedSources
    negative_cases = [pscustomobject]$negative
    assertions = $assertions
}
$result | ConvertTo-Json -Depth 100
if ($failures.Count -gt 0) { throw "P2-20B contract failed: $($failures.name -join '; ')" }
