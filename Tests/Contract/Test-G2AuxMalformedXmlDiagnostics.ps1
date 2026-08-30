[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$ClientLegacySourceRoot = 'E:\QQXYCodeDev\ClientCode',
    [string]$ServerLegacySourceRoot = 'E:\QQXYCodeDev\ServerCode',
    [switch]$VerifyDerivedSources,
    [switch]$SkipRegeneration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$assertions = [Collections.Generic.List[object]]::new()
$negativeCases = [ordered]@{}

function Add-A([string]$Name, [bool]$Passed) {
    $assertions.Add([pscustomobject][ordered]@{
            name = $Name
            result = if ($Passed) { 'PASS' } else { 'FAIL' }
        })
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BytesSha256([byte[]]$Bytes) {
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-DomainHash([string]$Domain, [string[]]$Parts) {
    $stream = [IO.MemoryStream]::new()
    try {
        foreach ($part in @($Domain) + $Parts) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($part)
            $length = [BitConverter]::GetBytes([Int64]$bytes.Length)
            if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($length) }
            $stream.Write($length, 0, $length.Length)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        return Get-BytesSha256 $stream.ToArray()
    }
    finally { $stream.Dispose() }
}

function Get-StringSetHash([string[]]$Values) {
    $text = (@($Values | Sort-Object -Unique -CaseSensitive | ForEach-Object {
                '"' + $_ + '"' + "`n"
            }) -join '')
    return Get-BytesSha256 ([Text.Encoding]::ASCII.GetBytes($text))
}

function Copy-Json([object]$Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-JsonSchema([object]$Value, [string]$SchemaPath) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) |
        Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue
}

function Test-ExactFields([object]$Value, [string[]]$Expected) {
    $actual = @($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive)
    return @(Compare-Object $actual @($Expected | Sort-Object -CaseSensitive) `
            -CaseSensitive).Count -eq 0
}

function Test-AllSchemaObjectsClosed([object]$Node) {
    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) { return $true }
    if ($Node -is [Collections.IEnumerable] -and $Node -isnot [pscustomobject]) {
        foreach ($item in $Node) {
            if (-not (Test-AllSchemaObjectsClosed $item)) { return $false }
        }
        return $true
    }
    if ($Node -is [pscustomobject]) {
        $typeProperty = $Node.PSObject.Properties['type']
        if ($null -ne $typeProperty -and [string]$typeProperty.Value -ceq 'object') {
            $closed = $Node.PSObject.Properties['additionalProperties']
            if ($null -eq $closed -or $closed.Value -isnot [bool] -or $closed.Value) {
                return $false
            }
        }
        foreach ($property in $Node.PSObject.Properties) {
            if (-not (Test-AllSchemaObjectsClosed $property.Value)) { return $false }
        }
    }
    return $true
}

function Test-EvidenceFieldsClosed([object]$Evidence) {
    if (-not (Test-ExactFields $Evidence @(
                'schema_version', 'evidence_revision', 'captured_utc', 'task_id',
                'criterion_id', 'result', 'review_execution_result', 'task_status',
                'completion_criteria_satisfied', 'diagnostic_scope_complete',
                'scope_complete', 'g2_06_satisfied', 'p3_authorized', 'report_json',
                'report_markdown', 'detail_export', 'population', 'layer_outcomes',
                'consumer_boundary', 'authority_boundaries', 'blockers', 'contracts',
                'implementation', 'source_verification', 'isolation', 'disclosure'))) {
        return $false
    }
    $closed = @(
        @($Evidence.report_json, @('bytes', 'sha256')),
        @($Evidence.report_markdown, @('bytes', 'sha256')),
        @($Evidence.detail_export, @('tracked', 'path', 'lines', 'bytes', 'sha256')),
        @($Evidence.population, @('instances', 'unique_contents', 'source_bytes',
                'gbk_instances', 'crlf_only_instances', 'crlf_pairs', 'lone_lf',
                'lone_cr', 'nul_instances', 'doctype_instances', 'entity_instances',
                'instance_set_sha256', 'content_set_sha256')),
        @($Evidence.layer_outcomes, @('p2_05_document_rejections',
                'p2_05_fragment_rejections', 'elementtree_rejections',
                'tinyxml_api_successes', 'tinyxml_full_consumption',
                'tinyxml_silent_partial')),
        @($Evidence.consumer_boundary, @('source_bound', 'dynamic_client_source_bound',
                'literal_server_source_bound', 'unresolved_no_source_literal',
                'client_input_null_termination_proven', 'legacy_memory_tail_observed')),
        @($Evidence.authority_boundaries, @('legacy_runtime_executed',
                'runtime_binary_parity_claimed',
                'windows_crt_text_mode_runtime_parity_claimed', 'repair_applied',
                'source_writes', 'deletions_authorized', 'semantic_values_extracted',
                'semantic_imports_claimed', 'approved_adapters',
                'approved_no_reference_instances', 'approved_roots',
                'terminal_dispositions')),
        @($Evidence.contracts, @('policy_sha256', 'schema_sha256',
                'detail_schema_sha256')),
        @($Evidence.implementation, @('generator_sha256', 'support_sha256',
                'probe_sha256', 'evidence_helper_sha256', 'self_test_assertions')),
        @($Evidence.source_verification, @('performed', 'source_families',
                'builder_image_reference', 'builder_image_digest',
                'toolchain_lock_sha256', 'wrapper_sha256', 'compiler_executable',
                'compiler_major', 'compiler_version_output_sha256',
                'client_source_set_sha256', 'server_source_set_sha256', 'network',
                'repository_mount', 'client_legacy_mount', 'server_legacy_mount',
                'builder_user', 'capabilities', 'no_new_privileges',
                'evidence_boundary', 'elementtree_outcome_sha256',
                'tinyxml_api_and_completeness_outcome_sha256',
                'tinyxml_tree_outcome_sha256', 'legacy_runtime_executed',
                'runtime_binary_parity_claimed')),
        @($Evidence.source_verification.evidence_boundary, @('source_derived_only',
                'legacy_binary_executed', 'runtime_parity_claimed',
                'windows_crt_parity_claimed', 'null_tail_parity_claimed',
                'probe_input_nul_appended', 'client_input_null_termination_proven',
                'runtime_memory_tail_observed', 'api_success_grants_disposition')),
        @($Evidence.isolation, @('network', 'repository_mount', 'client_legacy_mount',
                'server_legacy_mount', 'builder_user', 'capabilities',
                'no_new_privileges')),
        @($Evidence.disclosure, @('tracked_aggregate_and_hash_only',
                'anonymous_detail_only', 'raw_xml', 'decoded_payloads',
                'element_or_attribute_names', 'attribute_or_text_values', 'file_names',
                'private_source_paths', 'source_line_numbers', 'parser_line_or_column',
                'legacy_source_lines'))
    )
    foreach ($entry in $closed) {
        if (-not (Test-ExactFields $entry[0] $entry[1])) { return $false }
    }
    foreach ($blocker in @($Evidence.blockers)) {
        if (-not (Test-ExactFields $blocker @('reason_code', 'count'))) { return $false }
    }
    return $true
}

function Test-ReportSemantics([object]$Candidate, [object]$Policy) {
    if ($Candidate.schema_version -ne 1 -or $Candidate.evidence_revision -cne 'P2-20A.11' -or
        $Candidate.result -cne 'BLOCKED' -or $Candidate.review_execution_result -cne 'PASS' -or
        $Candidate.task_status -cne 'BLOCKED' -or
        [bool]$Candidate.completion_criteria_satisfied -or
        -not [bool]$Candidate.diagnostic_scope_complete -or [bool]$Candidate.scope_complete -or
        [bool]$Candidate.g2_06_satisfied -or [bool]$Candidate.p3_authorized) { return $false }
    $inputRoles = @($Candidate.input_bindings.entries.role)
    $requiredRoles = @($Policy.required_input_roles)
    $legacyRoles = @($Candidate.input_bindings.legacy_sources.role)
    $expectedLegacyRoles = @($Policy.legacy_source_bindings.PSObject.Properties.Name)
    if (($inputRoles -join "`n") -cne ($requiredRoles -join "`n") -or
        @($inputRoles | Sort-Object -Unique -CaseSensitive).Count -ne $requiredRoles.Count -or
        @($legacyRoles | Sort-Object -Unique -CaseSensitive).Count -ne
            $expectedLegacyRoles.Count -or
        (@($legacyRoles | Sort-Object -CaseSensitive) -join "`n") -cne
            (@($expectedLegacyRoles | Sort-Object -CaseSensitive) -join "`n")) { return $false }
    $population = $Candidate.population
    foreach ($property in $Policy.expected_population.PSObject.Properties) {
        if ([string]$population.($property.Name) -cne [string]$property.Value) { return $false }
    }
    $strict = $Candidate.p2_05_strict
    if ($strict.evidence_revision -cne 'P2-05' -or -not [bool]$strict.frozen_baseline -or
        [int]$strict.document_rejections -ne 6 -or [int]$strict.fragment_rejections -ne 6 -or
        ($strict.classifications | ConvertTo-Json -Compress) -cne
            ($Policy.expected_p2_05_strict.classifications | ConvertTo-Json -Compress) -or
        $strict.error_distribution_sha256 -cne $Policy.expected_p2_05_strict.error_distribution_sha256 -or
        $strict.strict_baseline_sha256 -cne $Policy.expected_p2_05_strict.strict_baseline_sha256) {
        return $false
    }
    $et = $Candidate.independent_elementtree
    if ($et.implementation -cne 'python-xml.etree.ElementTree' -or
        $et.decode_boundary -cne 'strict-gbk-to-unicode' -or [bool]$et.dtd_enabled -or
        [bool]$et.external_resolver_enabled -or [int]$et.accepted -ne 0 -or
        [int]$et.rejected -ne 6 -or [int]$et.error_codes.'4' -ne 5 -or
        [int]$et.error_codes.'9' -ne 1 -or
        ($et.outcome_projection | ConvertTo-Json -Depth 20 -Compress) -cne
            ($Policy.expected_elementtree.outcome_projection | ConvertTo-Json -Depth 20 -Compress) -or
        $et.outcome_sha256 -cne $Policy.expected_elementtree.outcome_sha256) { return $false }
    $tiny = $Candidate.source_derived_tinyxml
    if ($tiny.derivation_scope -cne 'SOURCE_DERIVED_DIAGNOSTIC_ONLY' -or
        $tiny.version -cne '2.3.4' -or [int]$tiny.source_families -ne 2 -or
        [int]$tiny.instances_per_family -ne 6 -or -not [bool]$tiny.probe_input_nul_appended -or
        [int]$tiny.api_acceptance.client_load_file_successes -ne 6 -or
        [int]$tiny.api_acceptance.server_load_file_successes -ne 6 -or
        [int]$tiny.api_acceptance.client_error_false -ne 6 -or
        [int]$tiny.api_acceptance.server_error_false -ne 6 -or
        [int]$tiny.api_acceptance.client_roots_present -ne 6 -or
        [int]$tiny.api_acceptance.server_roots_present -ne 6 -or
        [int]$tiny.api_acceptance.client_server_tree_shape_equal -ne 6 -or
        [bool]$tiny.api_acceptance.accepted_as_terminal_disposition -or
        [int]$tiny.parse_completeness.full_input_consumed -ne 5 -or
        [int]$tiny.parse_completeness.direct_parse_returned_null -ne 1 -or
        [int]$tiny.parse_completeness.silent_partial_instances -ne 1 -or
        $tiny.parse_completeness.partial_content_sha256 -cne
            $Policy.expected_source_derived_tinyxml.partial_content_sha256 -or
        [int]$tiny.parse_completeness.partial_elements -ne 132 -or
        [int]$tiny.parse_completeness.partial_attributes -ne 529 -or
        ($tiny.tree_totals | ConvertTo-Json -Compress) -cne
            ($Policy.expected_source_derived_tinyxml.tree_totals | ConvertTo-Json -Compress) -or
        ($tiny.api_and_completeness_projection | ConvertTo-Json -Depth 20 -Compress) -cne
            ($Policy.expected_source_derived_tinyxml.api_and_completeness_projection |
                ConvertTo-Json -Depth 20 -Compress) -or
        $tiny.api_and_completeness_outcome_sha256 -cne
            $Policy.expected_source_derived_tinyxml.api_and_completeness_outcome_sha256 -or
        ($tiny.tree_projection | ConvertTo-Json -Depth 20 -Compress) -cne
            ($Policy.expected_source_derived_tinyxml.tree_projection |
                ConvertTo-Json -Depth 20 -Compress) -or
        ($tiny.execution_environment | ConvertTo-Json -Depth 20 -Compress) -cne
            ($Policy.expected_execution_environment | ConvertTo-Json -Depth 20 -Compress) -or
        ($tiny.evidence_boundary | ConvertTo-Json -Depth 20 -Compress) -cne
            ($Policy.expected_evidence_boundary | ConvertTo-Json -Depth 20 -Compress) -or
        $tiny.tree_outcome_sha256 -cne $Policy.expected_source_derived_tinyxml.tree_outcome_sha256) {
        return $false
    }
    if (($Candidate.consumer_boundary | ConvertTo-Json -Compress) -cne
            ($Policy.expected_consumer_boundary | ConvertTo-Json -Compress) -or
        ($Candidate.authority_boundaries | ConvertTo-Json -Compress) -cne
            ($Policy.authority_controls | ConvertTo-Json -Compress) -or
        ($Candidate.blockers | ConvertTo-Json -Compress) -cne
            ($Policy.blockers | ConvertTo-Json -Compress) -or
        ($Candidate.negative_contracts -join "`n") -cne
            ($Policy.negative_contracts -join "`n")) { return $false }
    $metrics = $Candidate.g2_projection.metrics
    return $Candidate.g2_projection.g2_decision -ceq 'BLOCKED' -and
        [int]$Candidate.g2_projection.satisfied -eq 7 -and
        [int]$Candidate.g2_projection.blocked -eq 2 -and
        -not [bool]$Candidate.g2_projection.g2_06_satisfied -and
        [bool]$metrics.aux_malformed_xml_diagnostic_hash_bound -and
        [int]$metrics.aux_malformed_xml_instances -eq 6 -and
        [int]$metrics.aux_malformed_xml_tinyxml_full_consumption -eq 5 -and
        [int]$metrics.aux_malformed_xml_tinyxml_silent_partial -eq 1 -and
        [int]$metrics.aux_malformed_xml_consumer_unresolved -eq 1 -and
        -not [bool]$metrics.aux_malformed_xml_client_input_termination_proven -and
        -not [bool]$metrics.aux_malformed_xml_legacy_runtime_executed -and
        -not [bool]$metrics.aux_malformed_xml_runtime_binary_parity_claimed -and
        [int]$metrics.aux_malformed_xml_semantic_imports_claimed -eq 0 -and
        [int]$metrics.aux_malformed_xml_terminal_dispositions -eq 0
}

$paths = [ordered]@{
    policy = Join-Path $root 'Contracts\data-schema\g2-aux-malformed-xml-diagnostics-policy-v1.json'
    schema = Join-Path $root 'Contracts\data-schema\g2-aux-malformed-xml-diagnostics-v1.schema.json'
    detail_schema = Join-Path $root 'Contracts\data-schema\g2-aux-malformed-xml-diagnostics-detail-v1.schema.json'
    report = Join-Path $root 'Data\Reports\p2-20a-aux-malformed-xml-diagnostics-report.json'
    markdown = Join-Path $root 'Data\Reports\p2-20a-aux-malformed-xml-diagnostics-report.md'
    evidence = Join-Path $root 'Data\Inventory\p2-20a-aux-malformed-xml-diagnostics.json'
    detail = Join-Path $root 'Data\Exports\P2-20\p2-20a-aux-malformed-xml-diagnostics.jsonl'
    wrapper = Join-Path $root ('Tools\TMXY.G2Aux' +
        'MalformedXml' + 'Diagnostics\New-G2Aux' + 'MalformedXmlDiagnostics.ps1')
    generator = Join-Path $root 'Tools\TMXY.G2AuxMalformedXmlDiagnostics\g2_aux_malformed_xml_diagnostics.py'
    evidence_helper = Join-Path $root 'Tools\TMXY.G2AuxMalformedXmlDiagnostics\g2_aux_malformed_xml_evidence.py'
    support = Join-Path $root 'Tools\TMXY.G2AuxMalformedXmlDiagnostics\aux_malformed_xml_support.py'
    probe = Join-Path $root 'Tools\TMXY.G2AuxMalformedXmlDiagnostics\tinyxml_probe.cpp'
    toolchain_lock = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
    inventory = Join-Path $root 'Data\Inventory\p2-05-auxiliary-config-inventory.json'
}
foreach ($entry in $paths.GetEnumerator()) {
    Add-A "artifact_exists_$($entry.Key)" (Test-Path -LiteralPath $entry.Value -PathType Leaf)
}

if (-not $SkipRegeneration -and $VerifyDerivedSources) {
    $regenerated = & $paths.wrapper -RebuildRoot $root `
        -ClientLegacySourceRoot $ClientLegacySourceRoot `
        -ServerLegacySourceRoot $ServerLegacySourceRoot `
        -VerifyDerivedSources -Check | ConvertFrom-Json -Depth 50
    Add-A 'deterministic_source_derived_regeneration' (
        $regenerated.result -ceq 'BLOCKED' -and
        $regenerated.review_execution_result -ceq 'PASS' -and
        [int]$regenerated.instances -eq 6 -and
        [int]$regenerated.strict_rejections -eq 6 -and
        [int]$regenerated.elementtree_rejections -eq 6 -and
        [int]$regenerated.tinyxml_api_successes -eq 6 -and
        [int]$regenerated.tinyxml_full_consumption -eq 5 -and
        [int]$regenerated.tinyxml_silent_partial -eq 1 -and
        -not [bool]$regenerated.legacy_runtime_executed -and
        -not [bool]$regenerated.runtime_binary_parity_claimed)
}

$policy = Get-Content $paths.policy -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$schema = Get-Content $paths.schema -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$detailSchema = Get-Content $paths.detail_schema -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$report = Get-Content $paths.report -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$evidence = Get-Content $paths.evidence -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$toolchainLock = Get-Content $paths.toolchain_lock -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String

Add-A 'report_schema_closed' (Test-JsonSchema $report $paths.schema)
Add-A 'all_report_schema_objects_closed' (Test-AllSchemaObjectsClosed $schema)
Add-A 'all_detail_schema_objects_closed' (Test-AllSchemaObjectsClosed $detailSchema)
Add-A 'evidence_fields_closed' (Test-EvidenceFieldsClosed $evidence)
Add-A 'report_semantics_closed' (Test-ReportSemantics $report $policy)
Add-A 'policy_identity' (
    $policy.schema_version -eq 1 -and $policy.evidence_revision -ceq 'P2-20A.11' -and
    $policy.task_id -ceq 'P2-20A' -and $policy.criterion_id -ceq 'G2-06')
Add-A 'contract_hashes_bound' (
    $report.contracts.policy_sha256 -ceq (Get-Sha256 $paths.policy) -and
    $report.contracts.schema_sha256 -ceq (Get-Sha256 $paths.schema) -and
    $report.contracts.detail_schema_sha256 -ceq (Get-Sha256 $paths.detail_schema) -and
    $evidence.implementation.generator_sha256 -ceq (Get-Sha256 $paths.generator) -and
    $evidence.implementation.evidence_helper_sha256 -ceq
        (Get-Sha256 $paths.evidence_helper) -and
    $evidence.implementation.support_sha256 -ceq (Get-Sha256 $paths.support) -and
    $evidence.implementation.probe_sha256 -ceq (Get-Sha256 $paths.probe) -and
    [int]$evidence.implementation.self_test_assertions -ge 6)
Add-A 'report_evidence_cross_binding' (
    $evidence.evidence_revision -ceq 'P2-20A.11' -and
    $evidence.result -ceq 'BLOCKED' -and $evidence.review_execution_result -ceq 'PASS' -and
    [int]$evidence.report_json.bytes -eq (Get-Item $paths.report).Length -and
    $evidence.report_json.sha256 -ceq (Get-Sha256 $paths.report) -and
    [int]$evidence.report_markdown.bytes -eq (Get-Item $paths.markdown).Length -and
    $evidence.report_markdown.sha256 -ceq (Get-Sha256 $paths.markdown) -and
    -not [bool]$evidence.g2_06_satisfied -and -not [bool]$evidence.p3_authorized)
Add-A 'source_verification_boundary_closed' (
    [bool]$evidence.source_verification.performed -and
    $evidence.source_verification.builder_image_reference -ceq
        [string]$toolchainLock.backend_toolchain.container_image_reference -and
    $evidence.source_verification.builder_image_digest -ceq
        [string]$toolchainLock.backend_toolchain.container_image_digest -and
    $evidence.source_verification.toolchain_lock_sha256 -ceq
        (Get-Sha256 $paths.toolchain_lock) -and
    $evidence.source_verification.wrapper_sha256 -ceq (Get-Sha256 $paths.wrapper) -and
    $evidence.source_verification.compiler_executable -ceq 'clang++-21' -and
    [int]$evidence.source_verification.compiler_major -eq 21 -and
    $evidence.source_verification.compiler_version_output_sha256 -ceq
        $policy.expected_execution_environment.compiler_version_output_sha256 -and
    [int]$evidence.source_verification.source_families -eq 2 -and
    ($evidence.source_verification.evidence_boundary | ConvertTo-Json -Depth 20 -Compress) -ceq
        ($policy.expected_evidence_boundary | ConvertTo-Json -Depth 20 -Compress) -and
    $evidence.source_verification.elementtree_outcome_sha256 -ceq
        $policy.expected_elementtree.outcome_sha256 -and
    $evidence.source_verification.tinyxml_api_and_completeness_outcome_sha256 -ceq
        $policy.expected_source_derived_tinyxml.api_and_completeness_outcome_sha256 -and
    $evidence.source_verification.tinyxml_tree_outcome_sha256 -ceq
        $policy.expected_source_derived_tinyxml.tree_outcome_sha256 -and
    -not [bool]$evidence.source_verification.legacy_runtime_executed -and
    -not [bool]$evidence.source_verification.runtime_binary_parity_claimed)

$requiredRoles = @($policy.required_input_roles)
Add-A 'ordered_input_roles_closed' (
    $requiredRoles.Count -eq @($requiredRoles | Sort-Object -Unique -CaseSensitive).Count -and
    @($report.input_bindings.entries).Count -eq $requiredRoles.Count -and
    @($report.input_bindings.entries.role | Sort-Object -Unique -CaseSensitive).Count -eq
        $requiredRoles.Count -and
    (@($report.input_bindings.entries.role) -join "`n") -ceq ($requiredRoles -join "`n"))
$inputMap = [ordered]@{
    auxiliary_inventory = 'Data/Inventory/p2-05-auxiliary-config-inventory.json'
    a3_report = 'Data/Reports/p2-20a-aux-config-reference-report.json'
    a3_evidence = 'Data/Inventory/p2-20a-aux-config-reference-evidence.json'
    a5_report = 'Data/Reports/p2-20a-aux-semantic-diagnostics-report.json'
    a5_evidence = 'Data/Inventory/p2-20a-aux-semantic-diagnostics.json'
    p2_05_transform_implementation = 'Tools/TMXY.Table/New-AuxiliaryConfigInventory.ps1'
    a3_extract_implementation = 'Tools/TMXY.G2AuxConfigClosure/aux_extract_runner.py'
    a5_diagnostic_implementation = 'Tools/TMXY.G2AuxSemanticDiagnostics/g2_aux_semantic_diagnostics.py'
    policy = 'Contracts/data-schema/g2-aux-malformed-xml-diagnostics-policy-v1.json'
    schema = 'Contracts/data-schema/g2-aux-malformed-xml-diagnostics-v1.schema.json'
    detail_schema = 'Contracts/data-schema/g2-aux-malformed-xml-diagnostics-detail-v1.schema.json'
    generator = 'Tools/TMXY.G2AuxMalformedXmlDiagnostics/g2_aux_malformed_xml_diagnostics.py'
    support = 'Tools/TMXY.G2AuxMalformedXmlDiagnostics/aux_malformed_xml_support.py'
    tinyxml_probe = ('Tools/TMXY.G2Aux' + 'MalformedXmlDiagnostics/tinyxml_probe.cpp')
    evidence_helper = 'Tools/TMXY.G2AuxMalformedXmlDiagnostics/g2_aux_malformed_xml_evidence.py'
    wrapper = ('Tools/TMXY.G2Aux' + 'MalformedXml' + 'Diagnostics/New-G2Aux' +
        'MalformedXmlDiagnostics.ps1')
    toolchain_lock = 'Data/Toolchain/toolchain.lock.json'
}
$inputValid = $true
foreach ($binding in $report.input_bindings.entries) {
    $relative = $inputMap[[string]$binding.role]
    $inputValid = $inputValid -and $null -ne $relative -and
        [string]$binding.sha256 -ceq (Get-Sha256 (Join-Path $root $relative))
}
$legacyRoles = @($report.input_bindings.legacy_sources.role)
$expectedLegacyRoles = @($policy.legacy_source_bindings.PSObject.Properties.Name)
$legacyValid = @($report.input_bindings.legacy_sources).Count -eq 20 -and
    @($legacyRoles | Sort-Object -Unique -CaseSensitive).Count -eq 20 -and
    (@($legacyRoles | Sort-Object -CaseSensitive) -join "`n") -ceq
        (@($expectedLegacyRoles | Sort-Object -CaseSensitive) -join "`n")
foreach ($binding in $report.input_bindings.legacy_sources) {
    $expected = $policy.legacy_source_bindings.PSObject.Properties[[string]$binding.role]
    $legacyValid = $legacyValid -and $null -ne $expected -and
        [string]$binding.sha256 -ceq [string]$expected.Value
}
$aggregateValues = @($report.input_bindings.entries | ForEach-Object {
        "$($_.role):$($_.sha256)"
    }) + @($report.input_bindings.legacy_sources | ForEach-Object {
        "$($_.role):$($_.sha256)"
    })
Add-A 'input_and_legacy_hashes_recomputed' (
    $inputValid -and $legacyValid -and
    $report.input_bindings.aggregate_sha256 -ceq (Get-StringSetHash $aggregateValues))

$detailLines = [Collections.Generic.List[object]]::new()
$detailValid = $true
foreach ($line in [IO.File]::ReadLines($paths.detail)) {
    $record = $line | ConvertFrom-Json -Depth 100 -DateKind String
    $detailLines.Add($record)
    if (-not (Test-JsonSchema $record $paths.detail_schema)) { $detailValid = $false }
}
Add-A 'detail_schema_closed_for_all_records' ($detailValid -and $detailLines.Count -eq 6)
Add-A 'detail_binding_recomputed' (
    $report.detail_export.path -ceq
        'Data/Exports/P2-20/p2-20a-aux-malformed-xml-diagnostics.jsonl' -and
    -not [bool]$report.detail_export.tracked -and [int]$report.detail_export.lines -eq 6 -and
    [int]$report.detail_export.bytes -eq (Get-Item $paths.detail).Length -and
    $report.detail_export.sha256 -ceq (Get-Sha256 $paths.detail) -and
    $report.detail_export.sha256 -ceq $policy.expected_detail.sha256 -and
    ($evidence.detail_export | ConvertTo-Json -Compress) -ceq
        ($report.detail_export | ConvertTo-Json -Compress))

$inventory = Get-Content $paths.inventory -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 100 -DateKind String
$sandbox = Join-Path $root ([string]$inventory.source.sandbox_relative_path)
$entries = @{}
foreach ($entry in $inventory.files) {
    $entries[[string]$entry.path] = $entry
}
$expectedMembers = [Collections.Generic.List[object]]::new()
foreach ($isolated in $inventory.malformed_xml_isolation) {
    $entry = $entries[[string]$isolated.path]
    $canonical = ([string]$entry.path).Trim().Replace('\', '/').ToLowerInvariant()
    $instance = Get-DomainHash 'g2-aux-source-file-v1' @($canonical, [string]$entry.sha256)
    $member = Get-DomainHash 'g2-aux-malformed-xml-diagnostic-member-v1' `
        @($canonical, [string]$entry.sha256)
    $sourcePath = Join-Path $sandbox ([string]$entry.path).Replace('/', '\')
    $raw = [IO.File]::ReadAllBytes($sourcePath)
    if ((Get-BytesSha256 $raw) -cne [string]$entry.sha256) {
        throw 'P2-20A.11 source-byte recomputation drifted.'
    }
    $expectedMembers.Add([pscustomobject][ordered]@{
            member_id = $member
            instance_sha256 = $instance
            content_sha256 = [string]$entry.sha256
            source_bytes = $raw.Length
            source_role = [string]$entry.ownership.role
            error_category = [string]$entry.structure.error
        })
}
$expectedMembers = @($expectedMembers | Sort-Object member_id)
$detailPopulationValid = $detailLines.Count -eq $expectedMembers.Count
for ($index = 0; $index -lt $detailLines.Count; ++$index) {
    $actual = $detailLines[$index]
    $expected = $expectedMembers[$index]
    $detailPopulationValid = $detailPopulationValid -and
        $actual.member_id -ceq $expected.member_id -and
        $actual.instance_sha256 -ceq $expected.instance_sha256 -and
        $actual.content_sha256 -ceq $expected.content_sha256 -and
        [int]$actual.source_bytes -eq [int]$expected.source_bytes -and
        $actual.source_role -ceq $expected.source_role -and
        $actual.p2_05_strict.error_category -ceq $expected.error_category
}
Add-A 'per_line_identity_content_and_source_recomputed' $detailPopulationValid
Add-A 'population_set_hashes_recomputed' (
    $report.population.instance_set_sha256 -ceq
        (Get-StringSetHash @($detailLines.instance_sha256)) -and
    $report.population.content_set_sha256 -ceq
        (Get-StringSetHash @($detailLines.content_sha256)) -and
    @($detailLines.instance_sha256 | Sort-Object -Unique).Count -eq 6 -and
    @($detailLines.content_sha256 | Sort-Object -Unique).Count -eq 6 -and
    (@($detailLines.source_bytes | Measure-Object -Sum).Sum) -eq 1082028)
$etProjectionText, $apiProjectionText, $treeProjectionText = '', '', ''
foreach ($detail in $detailLines) {
    $et = $detail.elementtree
    $tiny = $detail.source_derived_tinyxml
    $tree = $tiny.tree_shape
    $etProjectionText += ([ordered]@{
            accepted = $et.accepted
            error_class_code = $et.error_class_code
            error_code = [int]$et.error_code
            failure_location_sha256 = $et.failure_location_sha256
            member_id = $detail.member_id
            projection_version = 'g2-a11-elementtree-outcome-v1'
        } | ConvertTo-Json -Compress) + "`n"
    $apiProjectionText += ([ordered]@{
            client_error_flag = $tiny.client_error_flag
            client_load_file_success = $tiny.client_load_file_success
            client_root_present = $tiny.client_root_present
            client_server_tree_shape_equal = $tiny.client_server_tree_shape_equal
            direct_parse_returned_null = $tiny.direct_parse_returned_null
            full_input_consumed = $tiny.full_input_consumed
            member_id = $detail.member_id
            probe_input_nul_appended = $tiny.probe_input_nul_appended
            projection_version = 'g2-a11-tinyxml-api-completeness-outcome-v1'
            server_error_flag = $tiny.server_error_flag
            server_load_file_success = $tiny.server_load_file_success
            server_root_present = $tiny.server_root_present
        } | ConvertTo-Json -Compress) + "`n"
    $treeProjectionText += ([ordered]@{
            attributes = [int]$tree.attributes
            comments = [int]$tree.comments
            elements = [int]$tree.elements
            member_id = $detail.member_id
            nodes = [int]$tree.nodes
            projection_version = 'g2-a11-tinyxml-tree-outcome-v1'
            texts = [int]$tree.texts
        } | ConvertTo-Json -Compress) + "`n"
}
$etProjectionBytes = [Text.Encoding]::UTF8.GetBytes($etProjectionText)
$apiProjectionBytes = [Text.Encoding]::UTF8.GetBytes($apiProjectionText)
$treeProjectionBytes = [Text.Encoding]::UTF8.GetBytes($treeProjectionText)
Add-A 'versioned_outcome_projections_recomputed' (
    [int]$report.independent_elementtree.outcome_projection.bytes -eq
        $etProjectionBytes.Length -and
    $report.independent_elementtree.outcome_sha256 -ceq
        (Get-BytesSha256 $etProjectionBytes) -and
    [int]$report.source_derived_tinyxml.api_and_completeness_projection.bytes -eq
        $apiProjectionBytes.Length -and
    $report.source_derived_tinyxml.api_and_completeness_outcome_sha256 -ceq
        (Get-BytesSha256 $apiProjectionBytes) -and
    [int]$report.source_derived_tinyxml.tree_projection.bytes -eq
        $treeProjectionBytes.Length -and
    $report.source_derived_tinyxml.tree_outcome_sha256 -ceq
        (Get-BytesSha256 $treeProjectionBytes))
Add-A 'strict_and_elementtree_partitions_closed' (
    @($detailLines | Where-Object { $_.p2_05_strict.document_conformance -or
                $_.p2_05_strict.fragment_conformance }).Count -eq 0 -and
    @($detailLines | Where-Object { $_.elementtree.accepted }).Count -eq 0 -and
    @($detailLines | Where-Object { [int]$_.elementtree.error_code -eq 4 }).Count -eq 5 -and
    @($detailLines | Where-Object { [int]$_.elementtree.error_code -eq 9 }).Count -eq 1 -and
    @($detailLines.elementtree.failure_location_sha256 | Sort-Object -Unique).Count -eq 6)
$treeNodes = @($detailLines.source_derived_tinyxml.tree_shape.nodes | Measure-Object -Sum).Sum
$treeElements = @($detailLines.source_derived_tinyxml.tree_shape.elements | Measure-Object -Sum).Sum
$treeAttributes = @($detailLines.source_derived_tinyxml.tree_shape.attributes | Measure-Object -Sum).Sum
$treeTexts = @($detailLines.source_derived_tinyxml.tree_shape.texts | Measure-Object -Sum).Sum
$treeComments = @($detailLines.source_derived_tinyxml.tree_shape.comments | Measure-Object -Sum).Sum
Add-A 'tinyxml_api_and_completeness_layers_closed' (
    @($detailLines | Where-Object { -not $_.source_derived_tinyxml.client_load_file_success -or
                -not $_.source_derived_tinyxml.server_load_file_success -or
                $_.source_derived_tinyxml.client_error_flag -or
                $_.source_derived_tinyxml.server_error_flag -or
                -not $_.source_derived_tinyxml.client_root_present -or
                -not $_.source_derived_tinyxml.server_root_present -or
                -not $_.source_derived_tinyxml.client_server_tree_shape_equal }).Count -eq 0 -and
    @($detailLines | Where-Object { $_.source_derived_tinyxml.full_input_consumed }).Count -eq 5 -and
    @($detailLines | Where-Object { $_.source_derived_tinyxml.direct_parse_returned_null }).Count -eq 1 -and
    $treeNodes -eq 13319 -and $treeElements -eq 12673 -and
    $treeAttributes -eq 59141 -and $treeTexts -eq 28 -and $treeComments -eq 618)
$partial = @($detailLines | Where-Object {
        $_.content_sha256 -ceq
            '10302e38d179050923d4088bbb785a658aac16d1037a6c4c6ff4caf3240730ba'
    })
Add-A 'silent_partial_member_closed' (
    $partial.Count -eq 1 -and $partial[0].source_derived_tinyxml.direct_parse_returned_null -and
    -not $partial[0].source_derived_tinyxml.full_input_consumed -and
    [int]$partial[0].source_derived_tinyxml.tree_shape.elements -eq 132 -and
    [int]$partial[0].source_derived_tinyxml.tree_shape.attributes -eq 529)
Add-A 'consumer_partition_and_authority_closed' (
    @($detailLines | Where-Object consumer_binding_state -ceq 'dynamic-client-source-bound').Count -eq 1 -and
    @($detailLines | Where-Object consumer_binding_state -ceq 'literal-server-source-bound').Count -eq 4 -and
    @($detailLines | Where-Object consumer_binding_state -ceq 'unresolved-no-source-literal').Count -eq 1 -and
    @($detailLines | Where-Object { $_.authority.legacy_runtime_executed -or
                $_.authority.runtime_binary_parity_claimed -or
                $_.authority.windows_crt_text_mode_runtime_parity_claimed -or
                $_.authority.runtime_input_tail_observed -or
                [int]$_.authority.semantic_imports_claimed -ne 0 -or
                [int]$_.authority.repair_applied -ne 0 -or
                [int]$_.authority.terminal_disposition_approved -ne 0 }).Count -eq 0)

$detailRelative = 'Data/Exports/P2-20/p2-20a-aux-malformed-xml-diagnostics.jsonl'
$trackedDetail = @(git -C $root ls-files --error-unmatch -- $detailRelative 2>$null)
$detailIgnored = @(git -C $root check-ignore -- $detailRelative 2>$null)
Add-A 'detail_is_ignored_and_untracked' (
    $trackedDetail.Count -eq 0 -and $detailIgnored.Count -eq 1 -and
    $detailIgnored[0] -ceq $detailRelative)

$a11TextFiles = @($paths.policy, $paths.schema, $paths.detail_schema, $paths.wrapper,
    $paths.generator, $paths.evidence_helper, $paths.support, $paths.probe,
    (Join-Path $root 'Tools\TMXY.G2AuxMalformedXmlDiagnostics\README.md'),
    (Join-Path $root 'Docs\Formats\G2-AUX-MALFORMED-XML-DIAGNOSTICS.md'),
    $paths.report, $paths.markdown, $paths.evidence, $paths.detail)
$encodingValid = $true
foreach ($file in $a11TextFiles) {
    $bytes = [IO.File]::ReadAllBytes($file)
    $encodingValid = $encodingValid -and
        -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) -and
        -not ([Text.Encoding]::UTF8.GetString($bytes).Contains("`r"))
}
Add-A 'a11_text_is_lf_without_bom' $encodingValid

$unknownReport = Copy-Json $report
$unknownReport | Add-Member raw_xml '<forbidden/>'
$negativeCases.unknown_report_field_rejected = -not (Test-JsonSchema $unknownReport $paths.schema)
$unknownEvidence = Copy-Json $evidence
$unknownEvidence | Add-Member file_name 'forbidden.xml'
$negativeCases.unknown_evidence_field_rejected =
    -not (Test-EvidenceFieldsClosed $unknownEvidence)
$missingPopulation = Copy-Json $report
$missingPopulation.PSObject.Properties.Remove('population')
$negativeCases.missing_population_rejected = -not (Test-JsonSchema $missingPopulation $paths.schema)
$duplicateInputRole = Copy-Json $report
$duplicateInputRole.input_bindings.entries[1].role =
    $duplicateInputRole.input_bindings.entries[0].role
$negativeCases.duplicate_input_role_rejected =
    -not (Test-ReportSemantics $duplicateInputRole $policy)
$duplicateLegacyRole = Copy-Json $report
$duplicateLegacyRole.input_bindings.legacy_sources[1].role =
    $duplicateLegacyRole.input_bindings.legacy_sources[0].role
$negativeCases.duplicate_legacy_role_rejected =
    -not (Test-ReportSemantics $duplicateLegacyRole $policy)
$countDrift = Copy-Json $report; $countDrift.population.instances = 5
$negativeCases.population_count_drift_rejected = -not (Test-JsonSchema $countDrift $paths.schema)
$setDrift = Copy-Json $report; $setDrift.population.content_set_sha256 = '0' * 64
$negativeCases.population_hash_drift_rejected = -not (Test-JsonSchema $setDrift $paths.schema)
$strictAcceptance = Copy-Json $report; $strictAcceptance.p2_05_strict.document_rejections = 5
$negativeCases.strict_rejection_erasure_rejected = -not (Test-JsonSchema $strictAcceptance $paths.schema)
$classMutation = Copy-Json $report; $classMutation.p2_05_strict.classifications.'unclosed-element' = 0
$negativeCases.classification_mutation_rejected = -not (Test-JsonSchema $classMutation $paths.schema)
$etAcceptance = Copy-Json $report; $etAcceptance.independent_elementtree.accepted = 1
$negativeCases.elementtree_acceptance_rejected = -not (Test-JsonSchema $etAcceptance $paths.schema)
$etDistribution = Copy-Json $report; $etDistribution.independent_elementtree.error_codes.'4' = 4
$negativeCases.elementtree_distribution_rejected = -not (Test-JsonSchema $etDistribution $paths.schema)
$etProjection = Copy-Json $report
$etProjection.independent_elementtree.outcome_projection.sha256 = '0' * 64
$negativeCases.elementtree_projection_drift_rejected =
    -not (Test-JsonSchema $etProjection $paths.schema)
$apiDrift = Copy-Json $report; $apiDrift.source_derived_tinyxml.api_acceptance.client_load_file_successes = 5
$negativeCases.tinyxml_api_drift_rejected = -not (Test-JsonSchema $apiDrift $paths.schema)
$apiDisposition = Copy-Json $report; $apiDisposition.source_derived_tinyxml.api_acceptance.accepted_as_terminal_disposition = $true
$negativeCases.api_as_disposition_rejected = -not (Test-JsonSchema $apiDisposition $paths.schema)
$completeForgery = Copy-Json $report; $completeForgery.source_derived_tinyxml.parse_completeness.full_input_consumed = 6
$negativeCases.parse_completeness_forgery_rejected = -not (Test-JsonSchema $completeForgery $paths.schema)
$partialErasure = Copy-Json $report; $partialErasure.source_derived_tinyxml.parse_completeness.silent_partial_instances = 0
$negativeCases.silent_partial_erasure_rejected = -not (Test-JsonSchema $partialErasure $paths.schema)
$treeDrift = Copy-Json $report; $treeDrift.source_derived_tinyxml.tree_totals.elements = 12672
$negativeCases.tree_total_drift_rejected = -not (Test-JsonSchema $treeDrift $paths.schema)
$apiProjection = Copy-Json $report
$apiProjection.source_derived_tinyxml.api_and_completeness_projection.sha256 = '0' * 64
$negativeCases.tinyxml_api_projection_drift_rejected =
    -not (Test-JsonSchema $apiProjection $paths.schema)
$treeProjection = Copy-Json $report
$treeProjection.source_derived_tinyxml.tree_projection.sha256 = '0' * 64
$negativeCases.tinyxml_tree_projection_drift_rejected =
    -not (Test-JsonSchema $treeProjection $paths.schema)
$imageDrift = Copy-Json $report
$imageDrift.source_derived_tinyxml.execution_environment.builder_image_digest = 'sha256:' + ('0' * 64)
$negativeCases.builder_image_drift_rejected = -not (Test-JsonSchema $imageDrift $paths.schema)
$compilerDrift = Copy-Json $report
$compilerDrift.source_derived_tinyxml.execution_environment.compiler_version_output_sha256 = '0' * 64
$negativeCases.compiler_version_drift_rejected = -not (Test-JsonSchema $compilerDrift $paths.schema)
$boundaryPromotion = Copy-Json $report
$boundaryPromotion.source_derived_tinyxml.evidence_boundary.runtime_parity_claimed = $true
$negativeCases.runtime_boundary_promotion_rejected =
    -not (Test-JsonSchema $boundaryPromotion $paths.schema)
$runtimePromotion = Copy-Json $report; $runtimePromotion.authority_boundaries.legacy_runtime_executed = $true
$negativeCases.runtime_execution_promotion_rejected = -not (Test-JsonSchema $runtimePromotion $paths.schema)
$binaryPromotion = Copy-Json $report; $binaryPromotion.authority_boundaries.runtime_binary_parity_claimed = $true
$negativeCases.binary_parity_promotion_rejected = -not (Test-JsonSchema $binaryPromotion $paths.schema)
$crtPromotion = Copy-Json $report; $crtPromotion.authority_boundaries.windows_crt_text_mode_runtime_parity_claimed = $true
$negativeCases.windows_crt_promotion_rejected = -not (Test-JsonSchema $crtPromotion $paths.schema)
$terminationForgery = Copy-Json $report; $terminationForgery.consumer_boundary.client_input_null_termination_proven = $true
$negativeCases.client_termination_forgery_rejected = -not (Test-JsonSchema $terminationForgery $paths.schema)
$memoryTail = Copy-Json $report; $memoryTail.consumer_boundary.legacy_memory_tail_observed = $true
$negativeCases.memory_tail_forgery_rejected = -not (Test-JsonSchema $memoryTail $paths.schema)
foreach ($field in @('repair_applied', 'deletions_authorized', 'semantic_imports_claimed',
        'approved_adapters', 'approved_no_reference_instances', 'approved_roots',
        'terminal_dispositions')) {
    $promotion = Copy-Json $report
    $promotion.authority_boundaries.$field = 1
    $negativeCases["authority_${field}_rejected"] = -not (Test-JsonSchema $promotion $paths.schema)
}
$unresolvedPromotion = Copy-Json $report; $unresolvedPromotion.consumer_boundary.unresolved_no_source_literal = 0
$negativeCases.unresolved_consumer_promotion_rejected = -not (Test-JsonSchema $unresolvedPromotion $paths.schema)
$g2Promotion = Copy-Json $report; $g2Promotion.g2_06_satisfied = $true
$negativeCases.g2_promotion_rejected = -not (Test-JsonSchema $g2Promotion $paths.schema)
$p3Promotion = Copy-Json $report; $p3Promotion.p3_authorized = $true
$negativeCases.p3_promotion_rejected = -not (Test-JsonSchema $p3Promotion $paths.schema)
$pathEscape = Copy-Json $report; $pathEscape.detail_export.path = 'E:\private\payload.jsonl'
$negativeCases.detail_path_escape_rejected = -not (Test-JsonSchema $pathEscape $paths.schema)
$trackedPromotion = Copy-Json $report; $trackedPromotion.detail_export.tracked = $true
$negativeCases.detail_tracking_rejected = -not (Test-JsonSchema $trackedPromotion $paths.schema)
$first = $detailLines[0]
$rawLeak = Copy-Json $first; $rawLeak | Add-Member raw_xml '<forbidden/>'
$negativeCases.detail_raw_xml_rejected = -not (Test-JsonSchema $rawLeak $paths.detail_schema)
$nameLeak = Copy-Json $first; $nameLeak | Add-Member file_name 'forbidden.xml'
$negativeCases.detail_file_name_rejected = -not (Test-JsonSchema $nameLeak $paths.detail_schema)
$missingMember = Copy-Json $first; $missingMember.PSObject.Properties.Remove('member_id')
$negativeCases.detail_missing_member_rejected = -not (Test-JsonSchema $missingMember $paths.detail_schema)
$detailEtAcceptance = Copy-Json $first; $detailEtAcceptance.elementtree.accepted = $true
$negativeCases.detail_elementtree_acceptance_rejected = -not (Test-JsonSchema $detailEtAcceptance $paths.detail_schema)
$detailEtClass = Copy-Json $first; $detailEtClass.elementtree.error_class_code = 'JUNK_AFTER_DOCUMENT_ELEMENT'
$negativeCases.detail_elementtree_code_class_mismatch_rejected = -not (Test-JsonSchema $detailEtClass $paths.detail_schema)
$partialForgery = Copy-Json $partial[0]; $partialForgery.source_derived_tinyxml.full_input_consumed = $true
$negativeCases.detail_partial_as_complete_rejected = -not (Test-JsonSchema $partialForgery $paths.detail_schema)
$fullRecord = @($detailLines | Where-Object { $_.source_derived_tinyxml.full_input_consumed })[0]
$fullErasure = Copy-Json $fullRecord; $fullErasure.source_derived_tinyxml.full_input_consumed = $false
$negativeCases.detail_full_consumption_erasure_rejected = -not (Test-JsonSchema $fullErasure $paths.detail_schema)
$consumerMismatch = Copy-Json $first
$consumerMismatch.consumer_input_termination_state = 'unresolved-consumer'
$negativeCases.detail_consumer_termination_mismatch_rejected = -not (Test-JsonSchema $consumerMismatch $paths.detail_schema)
$detailRuntime = Copy-Json $first; $detailRuntime.authority.legacy_runtime_executed = $true
$negativeCases.detail_runtime_promotion_rejected = -not (Test-JsonSchema $detailRuntime $paths.detail_schema)
$badBlocker = Copy-Json $report; $badBlocker.blockers[0].count = 5
$negativeCases.blocker_count_mutation_rejected = -not (Test-ReportSemantics $badBlocker $policy)
Add-A 'fail_closed_negative_contracts_satisfied' (
    $negativeCases.Count -ge 32 -and
    @($negativeCases.Values | Where-Object { -not $_ }).Count -eq 0)

$disclosureText = (Get-Content $paths.report -Raw -Encoding UTF8) +
    (Get-Content $paths.evidence -Raw -Encoding UTF8) +
    (Get-Content $paths.detail -Raw -Encoding UTF8)
Add-A 'tracked_and_detail_disclosure_closed' (
    $disclosureText -cnotmatch '(?i)ClientCode|ServerCode|ToolCode|[A-Z]:\\|<[^>]+>' -and
    $report.disclosure.tracked_aggregate_and_hash_only -and
    $report.disclosure.anonymous_detail_only -and
    @($report.disclosure.PSObject.Properties | Where-Object {
            $_.Name -notin @('tracked_aggregate_and_hash_only', 'anonymous_detail_only') -and
            ($_.Value -isnot [bool] -or $_.Value)
        }).Count -eq 0)

$failed = @($assertions | Where-Object result -eq 'FAIL')
$result = [ordered]@{
    schema_version = 1
    task_id = 'P2-20A.11'
    result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    contract_assertions_satisfied = $failed.Count -eq 0
    failures = $failed.Count
    completion_criteria_satisfied = $false
    g2_06_satisfied = $false
    p3_authorized = $false
    evidence_result = [string]$report.result
    review_execution_result = [string]$report.review_execution_result
    diagnostic_scope_complete = [bool]$report.diagnostic_scope_complete
    malformed_instances = [int]$report.population.instances
    tinyxml_api_successes = [int]$report.source_derived_tinyxml.api_acceptance.client_load_file_successes
    tinyxml_full_consumption = [int]$report.source_derived_tinyxml.parse_completeness.full_input_consumed
    tinyxml_silent_partial = [int]$report.source_derived_tinyxml.parse_completeness.silent_partial_instances
    legacy_runtime_executed = [bool]$report.authority_boundaries.legacy_runtime_executed
    runtime_binary_parity_claimed = [bool]$report.authority_boundaries.runtime_binary_parity_claimed
    assertions = $assertions
    negative_cases = $negativeCases
}
$result | ConvertTo-Json -Depth 100 -Compress
if ($failed.Count -ne 0) { throw 'P2-20A.11 malformed XML diagnostics contract failed.' }
