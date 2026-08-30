Set-StrictMode -Version Latest

function Test-ExactFalse([object]$Value) {
    return $Value -is [bool] -and $Value -eq $false
}

function Test-ExactZero([object]$Value) {
    return $Value -isnot [bool] -and [int64]$Value -eq 0
}

function Get-G2A11StringSetSha256([string[]]$Values) {
    $text = [Text.StringBuilder]::new()
    foreach ($value in @($Values | Sort-Object -Unique)) {
        if ($value -cnotmatch '^[A-Za-z0-9_:-]+$') { return $null }
        [void]$text.Append('"').Append($value).Append('"').Append("`n")
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes($text.ToString())
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Test-G2MalformedXmlPolicy([object]$Candidate) {
    $spec = $Candidate.aux_malformed_xml_diagnostics
    return $spec.task_id -eq 'P2-20A' -and $spec.criterion_id -eq 'G2-06' -and
        $spec.evidence_revision -eq 'P2-20A.11' -and $spec.path -eq
            'Data/Reports/p2-20a-aux-malformed-xml-diagnostics-report.json' -and
        $Candidate.fail_closed_rules.source_derived_tinyxml_api_success_is_not_legacy_runtime_or_binary_parity -eq $true -and
        $Candidate.fail_closed_rules.tinyxml_api_success_or_tree_shape_agreement_is_not_a_malformed_disposition -eq $true -and
        $Candidate.fail_closed_rules.silent_partial_parse_and_unproved_client_memory_tail_or_crt_behavior_block_closure -eq $true -and
        $Candidate.fail_closed_rules.fixed_blocked_aux_diagnostic_revision_requires_new_revision_and_binder_for_closure -eq $true
}

function Test-G2MalformedXmlMetrics([object]$Criterion) {
    $expected = [ordered]@{
        aux_malformed_xml_diagnostic_hash_bound = $true
        aux_malformed_xml_contract_safe = $true
        aux_malformed_xml_closure_ready = $false
        aux_malformed_xml_instances = 6
        aux_malformed_xml_source_bytes = 1082028
        aux_malformed_xml_strict_document_rejections = 6
        aux_malformed_xml_strict_fragment_rejections = 6
        aux_malformed_xml_elementtree_rejections = 6
        aux_malformed_xml_tinyxml_api_successes = 6
        aux_malformed_xml_tinyxml_full_consumption = 5
        aux_malformed_xml_tinyxml_silent_partial = 1
        aux_malformed_xml_client_server_agreement = 6
        aux_malformed_xml_consumer_bound = 5
        aux_malformed_xml_consumer_unresolved = 1
        aux_malformed_xml_client_input_termination_proven = $false
        aux_malformed_xml_legacy_runtime_executed = $false
        aux_malformed_xml_runtime_binary_parity_claimed = $false
        aux_malformed_xml_windows_crt_parity_claimed = $false
        aux_malformed_xml_repairs = 0
        aux_malformed_xml_deletions = 0
        aux_malformed_xml_dispositions = 0
        aux_malformed_xml_approved_adapters = 0
        aux_malformed_xml_approved_no_reference = 0
        aux_malformed_xml_approved_roots = 0
        aux_malformed_xml_semantic_imports_claimed = 0
        aux_malformed_xml_terminal_dispositions = 0
        aux_malformed_xml_malformed_blocked = 6
    }
    $allNames = @($Criterion.metrics | ForEach-Object { [string]$_.name })
    if ($allNames.Count -ne 197 -or
        @($allNames | Sort-Object -Unique).Count -ne 197) { return $false }
    $observed = @($Criterion.metrics | Where-Object {
            [string]$_.name -clike 'aux_malformed_xml_*'
        } | ForEach-Object { [string]$_.name })
    if ($observed.Count -ne $expected.Count -or
        @(Compare-Object @($expected.Keys) $observed).Count -ne 0) { return $false }
    foreach ($name in $expected.Keys) {
        $matches = @($Criterion.metrics | Where-Object { [string]$_.name -ceq $name })
        if ($matches.Count -ne 1) { return $false }
        $actual, $wanted = $matches[0].value, $expected[$name]
        if ($wanted -is [bool]) {
            if ($actual -isnot [bool] -or $actual -ne $wanted) { return $false }
        }
        elseif ($actual -is [bool] -or [int64]$actual -ne [int64]$wanted) { return $false }
        $unit = if ($wanted -is [bool]) { 'boolean' }
            elseif ($name -eq 'aux_malformed_xml_source_bytes') { 'bytes' }
            elseif ($name -eq 'aux_malformed_xml_approved_roots') { 'roots' }
            elseif ($name -in @('aux_malformed_xml_approved_adapters',
                    'aux_malformed_xml_semantic_imports_claimed')) { 'count' }
            else { 'files' }
        if ([string]$matches[0].unit -cne $unit) { return $false }
    }
    return (Test-ExactFalse $Criterion.satisfied) -and
        $Criterion.observed_status -eq 'BLOCKED' -and
        @($Criterion.blocker_ids).Count -eq 1 -and
        $Criterion.blocker_ids[0] -eq 'G2-BLK-06'
}

function Test-G2MalformedXmlDocument(
    [object]$Document, [string]$Root, [switch]$SkipDetailHash) {
    $schemaPath = Join-Path $Root `
        'Contracts\data-schema\g2-aux-malformed-xml-diagnostics-v1.schema.json'
    try {
        $json = $Document | ConvertTo-Json -Depth 100 -Compress
        if (-not [bool](Test-Json -Json $json -SchemaFile $schemaPath `
                    -ErrorAction SilentlyContinue)) { return $false }
    }
    catch { return $false }
    if ($Document.evidence_revision -ne 'P2-20A.11' -or
        $Document.task_id -ne 'P2-20A' -or $Document.criterion_id -ne 'G2-06' -or
        $Document.result -ne 'BLOCKED' -or $Document.review_execution_result -ne 'PASS' -or
        $Document.task_status -ne 'BLOCKED' -or
        -not (Test-ExactFalse $Document.completion_criteria_satisfied) -or
        $Document.diagnostic_scope_complete -ne $true -or
        -not (Test-ExactFalse $Document.scope_complete) -or
        -not (Test-ExactFalse $Document.g2_06_satisfied) -or
        -not (Test-ExactFalse $Document.p3_authorized)) { return $false }
    $population = $Document.population
    if ([int]$population.instances -ne 6 -or [int]$population.unique_contents -ne 6 -or
        [int64]$population.source_bytes -ne 1082028 -or
        [int]$Document.p2_05_strict.document_rejections -ne 6 -or
        [int]$Document.p2_05_strict.fragment_rejections -ne 6 -or
        [int]$Document.independent_elementtree.accepted -ne 0 -or
        [int]$Document.independent_elementtree.rejected -ne 6) { return $false }
    $tiny = $Document.source_derived_tinyxml
    $api, $complete = $tiny.api_acceptance, $tiny.parse_completeness
    if ([int]$api.client_load_file_successes -ne 6 -or
        [int]$api.server_load_file_successes -ne 6 -or
        [int]$api.client_server_tree_shape_equal -ne 6 -or
        -not (Test-ExactFalse $api.accepted_as_terminal_disposition) -or
        [int]$complete.full_input_consumed -ne 5 -or
        [int]$complete.direct_parse_returned_null -ne 1 -or
        [int]$complete.silent_partial_instances -ne 1) { return $false }
    $environment, $boundary = $tiny.execution_environment, $tiny.evidence_boundary
    if ($Document.independent_elementtree.outcome_projection.sha256 -cne
            'cf1c56d9f99ff2c379d3ed7640c057c0ceadaa2908ed9aa3d898e591f22a52e6' -or
        $tiny.api_and_completeness_projection.sha256 -cne
            '2d0e19ea598284a59532082a495c3dd739aae10d69ca4d7be8dd35bf09f61e3f' -or
        $tiny.tree_projection.sha256 -cne
            '6d1a33ecde5cc3c1de346c02671c8a421c264c1f468db5b4a722881c6a425fcd' -or
        $environment.builder_image_digest -cne
            'sha256:95f30cbb0f406f387a8aa0d4d56323105610ad6fc0629196bc5074847cac90a9' -or
        $environment.compiler_executable -cne 'clang++-21' -or
        [int]$environment.compiler_major -ne 21 -or $environment.network -cne 'none' -or
        $environment.repository_mount -cne 'read-only' -or
        $environment.client_legacy_mount -cne 'read-only' -or
        $environment.server_legacy_mount -cne 'read-only' -or
        $environment.builder_user -cne 'tmxy' -or $environment.capabilities -cne 'none' -or
        $environment.no_new_privileges -ne $true -or
        $environment.toolchain_lock_sha256 -cne
            (Get-Sha256 (Join-Path $Root 'Data\Toolchain\toolchain.lock.json')) -or
        $environment.wrapper_sha256 -cne (Get-Sha256 (Join-Path $Root `
            ('Tools\TMXY.G2Aux' + 'MalformedXml' + 'Diagnostics\New-G2Aux' +
                'MalformedXmlDiagnostics.ps1')))) {
        return $false
    }
    foreach ($name in @('legacy_binary_executed', 'runtime_parity_claimed',
            'windows_crt_parity_claimed', 'null_tail_parity_claimed',
            'client_input_null_termination_proven', 'runtime_memory_tail_observed',
            'api_success_grants_disposition')) {
        if (-not (Test-ExactFalse $boundary.$name)) { return $false }
    }
    if ($boundary.source_derived_only -ne $true -or
        $boundary.probe_input_nul_appended -ne $true) { return $false }
    $consumer, $authority = $Document.consumer_boundary, $Document.authority_boundaries
    if ([int]$consumer.source_bound -ne 5 -or [int]$consumer.unresolved_no_source_literal -ne 1 -or
        -not (Test-ExactFalse $consumer.client_input_null_termination_proven) -or
        -not (Test-ExactFalse $consumer.legacy_memory_tail_observed)) { return $false }
    foreach ($name in @('legacy_runtime_executed', 'runtime_binary_parity_claimed',
            'windows_crt_text_mode_runtime_parity_claimed')) {
        if (-not (Test-ExactFalse $authority.$name)) { return $false }
    }
    foreach ($name in @('repair_applied', 'source_writes', 'deletions_authorized',
            'semantic_values_extracted', 'semantic_imports_claimed', 'approved_adapters',
            'approved_no_reference_instances', 'approved_roots', 'terminal_dispositions')) {
        if (-not (Test-ExactZero $authority.$name)) { return $false }
    }
    $paths = [ordered]@{
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
    $entries = @($Document.input_bindings.entries)
    if ($entries.Count -ne $paths.Count -or
        @($entries.role | Sort-Object -Unique).Count -ne $paths.Count) { return $false }
    for ($index = 0; $index -lt $entries.Count; ++$index) {
        $role = @($paths.Keys)[$index]
        $path = Join-Path $Root $paths[$role]
        if ($entries[$index].role -cne $role -or
            $entries[$index].sha256 -cne (Get-Sha256 $path)) { return $false }
    }
    $legacyExpected = [ordered]@{
        client_tinyxml_header = 'f8d69dc35242d9ba7132203f14122b29fb7b95798f35fc29dc4d63abfcad6d98'
        client_tinyxml_loader = '30630b58cf6e4c984fa1a692b6daadf95caeb5af444ba729f57a45c89af378fc'
        client_tinyxml_parser = 'c586adaee04634fa0d8f4063f83a7f6fe510cfb70d95401724b692676bc9859b'
        client_tinyxml_error = 'd74ff9be4a320f0933d399799220d2b2f5ff0acc9c40c951aa5694b92b9871ef'
        client_tinystr_implementation = '5c69220764ca7575abf59e062a1bf40dbc94aa20ab1989a92e5d5d0afbf86052'
        client_tinystr_header = '9045654e46ea0f1f0fae25b89768e66723fab27754baa6090df4febd732c0412'
        server_tinyxml_header = 'e4ea963af819f872750c278912c51eb0a313895256cfde7774d3a250ce56af44'
        server_tinyxml_loader = 'bd6b363b0b43c9cb059831e04978879f9d8758197e63dd9e0562406c5db96246'
        server_tinyxml_parser = 'c586adaee04634fa0d8f4063f83a7f6fe510cfb70d95401724b692676bc9859b'
        server_tinyxml_error = 'd74ff9be4a320f0933d399799220d2b2f5ff0acc9c40c951aa5694b92b9871ef'
        server_tinystr_implementation = '5c69220764ca7575abf59e062a1bf40dbc94aa20ab1989a92e5d5d0afbf86052'
        server_tinystr_header = '9045654e46ea0f1f0fae25b89768e66723fab27754baa6090df4febd732c0412'
        client_xml_load_macro = 'd1478f1e2d20030cee88b11dddc62828bfa426ef58512ef49c4b17e346f7e060'
        client_region_consumer = 'a1e5d33643d633234b2eeb07c6dc9358814d9802d4a9f43c959c1a4b155f1853'
        client_file_reader = '2541318310e369536f7c13ef1f1486dd1456b57349d703bd2b8fb4d02741ac69'
        client_array_contract = '831485b5d3392f57c6cb9a832362eb4566111e03b3b9de8225e6f0a09788617a'
        server_box_consumer = '1c01172da74aefd6ff602c4192e984c3a56b3d4076f80fbb84df526e995bc0e6'
        server_character_consumer = '79b57221f3d3a976700323e447ffad441b23362e57f87fb804698619ee77cb84'
        server_guild_consumer = '5b33d8a95c5bbec41e6545c1a708f475f38df4b27839ee0ffbddb72e7e3544c8'
        server_profession_consumer = '559466f5bc5deb58776b0d8df4e3b0e4273ff96b658c73d1bff685cac570a9b5'
    }
    $legacy = @($Document.input_bindings.legacy_sources)
    if ($legacy.Count -ne $legacyExpected.Count -or
        @($legacy.role | Sort-Object -Unique).Count -ne $legacyExpected.Count) { return $false }
    for ($index = 0; $index -lt $legacy.Count; ++$index) {
        $role = @($legacyExpected.Keys)[$index]
        if ($legacy[$index].role -cne $role -or
            $legacy[$index].sha256 -cne $legacyExpected[$role]) { return $false }
    }
    $tokens = @($entries + $legacy | ForEach-Object { "$($_.role):$($_.sha256)" })
    if (@($tokens | Sort-Object -Unique).Count -ne 37 -or
        $Document.input_bindings.aggregate_sha256 -cne
            (Get-G2A11StringSetSha256 $tokens) -or
        $Document.contracts.policy_sha256 -cne (Get-Sha256 (Join-Path $Root $paths.policy)) -or
        $Document.contracts.schema_sha256 -cne (Get-Sha256 (Join-Path $Root $paths.schema)) -or
        $Document.contracts.detail_schema_sha256 -cne
            (Get-Sha256 (Join-Path $Root $paths.detail_schema))) { return $false }
    $detail = Join-Path $Root 'Data\Exports\P2-20\p2-20a-aux-malformed-xml-diagnostics.jsonl'
    if ($Document.detail_export.tracked -ne $false -or
        $Document.detail_export.path -cne
            'Data/Exports/P2-20/p2-20a-aux-malformed-xml-diagnostics.jsonl' -or
        [int]$Document.detail_export.lines -ne 6 -or
        [int64]$Document.detail_export.bytes -ne (Get-Item $detail).Length -or
        (-not $SkipDetailHash -and
            $Document.detail_export.sha256 -cne (Get-Sha256 $detail))) { return $false }
    $rows = @([IO.File]::ReadLines($detail) | ForEach-Object {
            $_ | ConvertFrom-Json -Depth 100 -DateKind String
        })
    return $rows.Count -eq 6 -and
        @($rows.instance_sha256 | Sort-Object -Unique).Count -eq 6 -and
        @($rows.content_sha256 | Sort-Object -Unique).Count -eq 6 -and
        ($rows | Measure-Object source_bytes -Sum).Sum -eq 1082028 -and
        @($rows | Where-Object { $_.p2_05_strict.document_conformance }).Count -eq 0 -and
        @($rows | Where-Object { $_.elementtree.accepted }).Count -eq 0 -and
        @($rows | Where-Object { $_.source_derived_tinyxml.full_input_consumed }).Count -eq 5 -and
        @($rows | Where-Object { $_.source_derived_tinyxml.direct_parse_returned_null }).Count -eq 1
}

function Test-G2MalformedXmlBinding([object]$G2Report, [object]$Policy, [string]$Root) {
    if (-not (Test-G2MalformedXmlPolicy $Policy)) { return $false }
    $binding = $G2Report.input_bindings.aux_malformed_xml_diagnostics
    $path = Join-Path $Root 'Data\Reports\p2-20a-aux-malformed-xml-diagnostics-report.json'
    if ($binding.task_id -ne 'P2-20A' -or $binding.criterion_id -ne 'G2-06' -or
        $binding.evidence_revision -ne 'P2-20A.11' -or
        $binding.path -cne 'Data/Reports/p2-20a-aux-malformed-xml-diagnostics-report.json' -or
        $binding.sha256 -cne (Get-Sha256 $path) -or $binding.result -ne 'BLOCKED' -or
        $binding.review_execution_result -ne 'PASS' -or $binding.task_status -ne 'BLOCKED' -or
        $binding.diagnostic_scope_complete -ne $true -or
        -not (Test-ExactFalse $binding.completion_criteria_satisfied) -or
        -not (Test-ExactFalse $binding.scope_complete) -or
        -not (Test-ExactFalse $binding.g2_06_satisfied)) { return $false }
    $document = Get-Content -LiteralPath $path -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 100 -DateKind String
    return (Test-G2MalformedXmlDocument $document $Root) -and
        (Test-G2MalformedXmlMetrics (Get-Criterion $G2Report 'G2-06'))
}
