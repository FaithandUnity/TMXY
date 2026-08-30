[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$toolPath = Join-Path $root 'Tools\TMXY.Table\New-AuxiliaryConfigInventory.ps1'
$evidencePath = Join-Path $root 'Data\Inventory\p2-05-auxiliary-config-inventory.json'
$p204Path = Join-Path $root 'Data\Inventory\p2-04-current-table-inventory.json'
foreach ($path in @($toolPath, $evidencePath, $p204Path)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P2-05 required artifact is missing: $path"
    }
}

$assertions = [System.Collections.Generic.List[object]]::new()
function Add-Assertion {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed
    )
    $assertions.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed })
}

function Get-Count {
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $match = @($Items | Where-Object { [string]$_.$Property -eq $Value })
    if ($match.Count -ne 1) { return -1 }
    return [int]$match[0].files
}

$toolText = Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
foreach ($fragment in @(
        'Convert-EcfBytes',
        'DtdProcessing',
        'Prohibit',
        'XmlResolver = $null',
        'ConformanceLevel',
        'decoded_content_emitted = $false',
        'ecf_assignment_values_emitted = $false',
        '[System.Array]::Clear')) {
    Add-Assertion -Name "tool contains $fragment" -Passed (
        $toolText.Contains($fragment, [System.StringComparison]::Ordinal))
}
foreach ($fragment in @('$env:', 'GetEnvironmentVariable', 'Write-Host', 'Write-Verbose')) {
    Add-Assertion -Name "tool excludes $fragment" -Passed (-not
        $toolText.Contains($fragment, [System.StringComparison]::OrdinalIgnoreCase))
}

$evidenceText = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8
$report = $evidenceText | ConvertFrom-Json
$files = @($report.files)
$xml = @($files | Where-Object kind -eq 'xml')
$ecf = @($files | Where-Object kind -eq 'ecf')
$malformed = @($xml | Where-Object { $_.structure.classification -eq 'malformed-xml' })
$fragments = @($xml | Where-Object { $_.structure.classification -eq 'xml-fragment' })
$shared = @($files | Where-Object { $_.ownership.scope -eq 'shared' })
$clientOnly = @($files | Where-Object { $_.ownership.scope -eq 'client-only' })
$evidenceSha = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
$p204Sha = (Get-FileHash -LiteralPath $p204Path -Algorithm SHA256).Hash.ToLowerInvariant()

Add-Assertion -Name 'result PASS' -Passed ([string]$report.result -eq 'PASS')
Add-Assertion -Name 'task P2-05' -Passed ([string]$report.task -eq 'P2-05')
Add-Assertion -Name 'task complete' -Passed ([string]$report.task_status -eq 'COMPLETE')
Add-Assertion -Name 'completion true' -Passed ([bool]$report.completion_criteria_satisfied)
Add-Assertion -Name '212 files' -Passed ($files.Count -eq 212)
Add-Assertion -Name '212 unique paths' -Passed (
    @($files.path | Sort-Object -Unique).Count -eq 212)
Add-Assertion -Name 'frozen population bytes' -Passed (
    [long]$report.source.population.bytes -eq 1909135L)
Add-Assertion -Name 'entry bytes reconcile' -Passed (
    [long](($files | Measure-Object bytes -Sum).Sum) -eq 1909135L)
Add-Assertion -Name '148 XML files' -Passed ($xml.Count -eq 148)
Add-Assertion -Name '64 ECF files' -Passed ($ecf.Count -eq 64)
Add-Assertion -Name 'all hashes lowercase SHA-256' -Passed (
    @($files | Where-Object { [string]$_.sha256 -notmatch '^[0-9a-f]{64}$' }).Count -eq 0)
Add-Assertion -Name 'P2-04 evidence bound' -Passed (
    [string]$report.source.p2_04_evidence_sha256 -eq $p204Sha)
Add-Assertion -Name 'frozen executable bound' -Passed (
    [long]$report.source.executable.bytes -eq 5160960L -and
    [string]$report.source.executable.sha256 -eq
        '7087dfa64bedeb8c9a5dfc4518f46261d163136b5bd97f5071f2c5a12cb29a4b')

Add-Assertion -Name '138 strict XML documents' -Passed (
    [int]$report.summary.xml.strict_documents -eq 138)
Add-Assertion -Name '4 strict XML fragments' -Passed (
    $fragments.Count -eq 4 -and [int]$report.summary.xml.strict_fragments -eq 4)
Add-Assertion -Name '6 malformed XML isolated' -Passed (
    $malformed.Count -eq 6 -and [int]$report.summary.xml.malformed_isolated -eq 6)
Add-Assertion -Name 'all XML strictly GBK' -Passed (
    (Get-Count -Items @($report.summary.xml.encodings) -Property encoding -Value gbk) -eq 148)
Add-Assertion -Name 'parsed XML metrics frozen' -Passed (
    [long]$report.summary.xml.parsed_elements -eq 6498L -and
    [long]$report.summary.xml.parsed_attributes -eq 36457L)
$expectedFragments = @(
    'CLSVShare/GuildQuest.xml',
    'CLSVShare/tiangong_charinfo.xml',
    'CLSVShare/yin_yang_pan.xml',
    'Table/help_docs.xml')
Add-Assertion -Name 'fragment paths frozen' -Passed (
    (@($fragments.path | Sort-Object) -join "`n") -ceq
        (@($expectedFragments | Sort-Object) -join "`n"))
$expectedMalformed = @(
    'CLSVShare/box_item.xml',
    'CLSVShare/default_charinfo.xml',
    'CLSVShare/guildglobals.xml',
    'CLSVShare/Professions.xml',
    'CLSVShare/westsky.xml',
    'Table/Regions/world.xml')
Add-Assertion -Name 'malformed XML paths frozen' -Passed (
    (@($malformed.path | Sort-Object) -join "`n") -ceq
        (@($expectedMalformed | Sort-Object) -join "`n"))
Add-Assertion -Name 'malformed XML has stable categories' -Passed (
    @($malformed | Where-Object {
            $_.structure.error -notin @(
                'malformed-attribute-spacing',
                'unclosed-element',
                'invalid-comment',
                'invalid-attribute-character')
        }).Count -eq 0)

Add-Assertion -Name '64 ECF round trips' -Passed (
    @($ecf | Where-Object { $_.structure.round_trip_matches_source }).Count -eq 64 -and
    [int]$report.summary.ecf.round_trip_verified -eq 64)
Add-Assertion -Name 'ECF transform frozen' -Passed (
    @($ecf | Where-Object {
            $_.structure.transform -ne 'invert-bytes-and-swap-four-byte-halves-v1' -or
            -not $_.structure.transform_is_self_inverse
        }).Count -eq 0)
Add-Assertion -Name 'ECF encodings frozen' -Passed (
    (Get-Count -Items @($report.summary.ecf.encodings) -Property encoding -Value ascii) -eq 61 -and
    (Get-Count -Items @($report.summary.ecf.encodings) -Property encoding -Value gbk) -eq 3)
Add-Assertion -Name 'ECF line metrics frozen' -Passed (
    [long]$report.summary.ecf.lines -eq 2415L -and
    [long]$report.summary.ecf.assignment_lines -eq 2065L -and
    [long]$report.summary.ecf.repeated_assignments -eq 9L)
Add-Assertion -Name 'ECF usage candidates frozen' -Passed (
    [int]$report.summary.ecf.editor_tooling_candidates -eq 28 -and
    [int]$report.summary.ecf.runtime_or_engine_candidates -eq 36)
$repeatFiles = @($report.duplicates_and_overrides.ecf_repeated_assignment_files)
Add-Assertion -Name 'ECF repeated-assignment files frozen' -Passed (
    $repeatFiles.Count -eq 3 -and
    [long](($repeatFiles | Measure-Object repeated_assignments -Sum).Sum) -eq 9L -and
    (@($repeatFiles.path | Sort-Object) -join ',') -ceq
        'ClassCfg/QClient.ecf,ClassCfg/QGameEngine.ecf,ClassCfg/QUnit.ecf')

Add-Assertion -Name 'all ownership classified' -Passed (
    [int]$report.summary.classified -eq 212 -and
    [int]$report.summary.unresolved -eq 0)
Add-Assertion -Name '201 client-only and 11 shared' -Passed (
    $clientOnly.Count -eq 201 -and $shared.Count -eq 11)
Add-Assertion -Name 'shared references complete' -Passed (
    @($shared | Where-Object {
            -not $_.ownership.client_reference -and -not $_.ownership.server_reference
        }).Count -eq 0 -and
    [int]$report.ownership.shared_with_server_literal_reference -eq 9 -and
    [int]$report.ownership.shared_with_client_literal_reference -eq 7)
Add-Assertion -Name 'client-only roles frozen' -Passed (
    [int]$report.ownership.client_only_region_runtime -eq 130 -and
    [int]$report.ownership.client_only_region_nested_shadows -eq 6 -and
    [int]$report.ownership.client_only_help -eq 1 -and
    [int]$report.ownership.client_only_ecf -eq 64)

$duplicateGroups = @($report.duplicates_and_overrides.exact_content_groups)
$basenameCollisions = @($report.duplicates_and_overrides.basename_collisions)
Add-Assertion -Name 'exact duplicates frozen' -Passed (
    $duplicateGroups.Count -eq 14 -and
    [int](($duplicateGroups | Measure-Object files -Sum).Sum) -eq 30)
Add-Assertion -Name 'duplicate classes frozen' -Passed (
    @($duplicateGroups | Where-Object {
            $_.classification -eq 'nested-path-shadow-exact-copy'
        }).Count -eq 6 -and
    @($duplicateGroups | Where-Object {
            $_.classification -eq 'same-content-distinct-logical-names'
        }).Count -eq 8)
Add-Assertion -Name 'six exact basename shadows and no divergent override' -Passed (
    $basenameCollisions.Count -eq 6 -and
    @($basenameCollisions | Where-Object {
            $_.classification -ne 'exact-shadow-copy' -or [int]$_.distinct_hashes -ne 1
        }).Count -eq 0 -and
    [int]$report.summary.divergent_override_candidates -eq 0)
Add-Assertion -Name 'inventory never authorizes deletion' -Passed (-not
    [bool]$report.duplicates_and_overrides.deletion_authorized)

Add-Assertion -Name 'region source evidence bound' -Passed (
    [string]$report.source_evidence.client_region_loader.sha256 -eq
        'a1e5d33643d633234b2eeb07c6dc9358814d9802d4a9f43c959c1a4b155f1853')
Add-Assertion -Name 'ClassCfg solution evidence bound' -Passed (
    [string]$report.source_evidence.classcfg_solution_reference.sha256 -eq
        'e702ec573eaa9f9cb175855ed67771ce92fa661f30a1786a0ffe681fd36fc2b8' -and
    -not [bool]$report.source_evidence.classcfg_solution_reference.referenced_project_present)
Add-Assertion -Name 'QGameEngine evidence bound without plaintext' -Passed (
    [string]$report.source_evidence.client_config.sha256 -eq
        '35ce22803fac775d5847fc495811a43cbaf53feadaa776c0446be930921596b1' -and
    -not [bool]$report.source_evidence.client_config.decoded_content_emitted)
Add-Assertion -Name 'complete legacy server source scan bound' -Passed (
    [int]$report.source_evidence.legacy_server_scan.files_scanned -eq 1972 -and
    [string]$report.source_evidence.legacy_server_scan.population_sha256 -eq
        '201fc1b28936be0c1cea0cc025c2115f362ab7e3ce9adf36ed56cce0b1bf7503' -and
    @($report.source_evidence.legacy_server_scan.ecf_literal_reference_files).Count -eq 0)

foreach ($property in @(
        'xml_text_emitted',
        'xml_attribute_values_emitted',
        'ecf_decoded_lines_emitted',
        'ecf_assignment_keys_emitted',
        'ecf_assignment_values_emitted')) {
    Add-Assertion -Name "$property false" -Passed (-not [bool]$report.confidentiality.$property)
}
Add-Assertion -Name 'decoded buffers cleared' -Passed (
    [bool]$report.confidentiality.decoded_byte_buffers_cleared)
foreach ($fragment in @(
        ('pass' + 'word='),
        ('worldserver' + 'addr='),
        ('192' + '.168.'),
        ('user' + 'name='))) {
    Add-Assertion -Name "evidence excludes decoded fragment $fragment" -Passed (-not
        $evidenceText.Contains($fragment, [System.StringComparison]::OrdinalIgnoreCase))
}

$failed = @($assertions | Where-Object { -not $_.passed })
$passed = $failed.Count -eq 0
$contract = [pscustomobject][ordered]@{
    result = if ($passed) { 'PASS' } else { 'FAIL' }
    task = 'P2-05'
    completion_criteria_satisfied = $passed
    evidence_path = 'Data/Inventory/p2-05-auxiliary-config-inventory.json'
    evidence_sha256 = $evidenceSha
    assertions = $assertions.Count
    failed_assertions = @($failed | ForEach-Object { $_.name })
    decoded_content_required_for_contract_test = $false
}
$contract | ConvertTo-Json -Depth 4
if (-not $passed) { throw 'P2-05 auxiliary configuration inventory contract failed.' }
