[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [Parameter(Mandatory = $true)][string]$SarifInputPath,
    [Parameter(Mandatory = $true)][string]$OsvInputPath,
    [string]$GosuBinaryPath = '',
    [string]$GovulncheckPath = '',
    [string]$EntrypointScriptPath = '',
    [string]$GosuSourcePath = '',
    [string]$ObservationPath = '',
    [string]$SarifEvidencePath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-postgres-gosu-govulncheck.sarif.json',
    [string]$OsvEvidencePath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-postgres-gosu-GO-2026-4970.osv.json',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\Security\p0-12-postgres-gosu-reachability-review.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$dispositionPath = Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'
$candidatePath = Join-Path $root 'Data\Security\p0-12-postgres-official-candidate-evaluation.json'
$lockPath = Join-Path $root 'Data\Toolchain\toolchain.lock.json'
$composePath = Join-Path $root 'Deploy\compose\compose.yaml'
$failures = [Collections.Generic.List[string]]::new()

$expectedGosuSha = '52c8749d0142edd234e9d6bd5237dff2d81e71f43537e2f4f66f75dd4b243dd0'
$expectedGovulncheckSha = '56c0e00db28b3b3a94aab2462983de6f84c20670a5d54dbf5909bd54996c92f0'
$expectedEntrypointSha = '9c440299ae04a0a79d55b8bf03307036d890a40979d2fb698073c9050d4b20a5'
$expectedSourceSha = '5b51466d021951038377ce7d2405087588bf86fb321299e749c73a6777865584'
$expectedOsSymbols = @(
    'OpenInRoot', 'openRootInRoot', 'Root.Create', 'Root.Open', 'Root.OpenFile',
    'Root.OpenRoot', 'Root.ReadFile', 'Root.WriteFile', 'rootFS.Open',
    'rootFS.ReadDir', 'rootFS.ReadFile', 'rootOpenFileNolog'
)

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Required evidence file is missing: $Path"
        return ''
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Copy-Evidence {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Destination
    )
    if ([string]::IsNullOrWhiteSpace($Destination)) { return }
    $resolved = [IO.Path]::GetFullPath($Destination)
    $directory = Split-Path -Parent $resolved
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }
    [IO.File]::WriteAllBytes($resolved, [IO.File]::ReadAllBytes($Source))
}

function Convert-H1ChecksumToHex {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '^h1:(?<base64>[A-Za-z0-9+/]+={0,2})$') {
        throw 'Go module checksum is not a valid h1 value.'
    }
    return [Convert]::ToHexString(
        [Convert]::FromBase64String($Matches.base64)).ToLowerInvariant()
}

function Read-LiveObservation {
    foreach ($required in @($GosuBinaryPath, $GovulncheckPath, $EntrypointScriptPath, $GosuSourcePath)) {
        if ([string]::IsNullOrWhiteSpace($required) -or
            -not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw 'Live review requires the gosu binary, govulncheck, entrypoint, and gosu source files.'
        }
    }
    $goCommand = Get-Command 'go.exe' -ErrorAction SilentlyContinue
    if ($null -eq $goCommand) { throw 'Go is required to inspect the locked gosu build metadata.' }
    $buildLines = @(& $goCommand.Source version -m $GosuBinaryPath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'go version -m failed for the locked gosu binary.' }
    $buildText = $buildLines -join "`n"
    $goVersion = [regex]::Match($buildText, '(?m)^.+:\s*(?<value>go[0-9.]+)$').Groups['value'].Value
    $module = [regex]::Match($buildText, '(?m)^\s*path\s+(?<value>\S+)$').Groups['value'].Value
    $moduleVersion = [regex]::Match(
        $buildText, '(?m)^\s*mod\s+\S+\s+(?<value>\S+)').Groups['value'].Value
    $dependencies = @($buildLines | ForEach-Object {
            $match = [regex]::Match([string]$_, '^\s*dep\s+(?<path>\S+)\s+(?<version>\S+)\s+(?<sum>\S+)$')
            if ($match.Success) {
                [pscustomobject][ordered]@{
                    path = $match.Groups['path'].Value
                    version = $match.Groups['version'].Value
                    sum_sha256 = Convert-H1ChecksumToHex -Value $match.Groups['sum'].Value
                }
            }
        })
    $govulncheckVersionText = (@(& $GovulncheckPath -version 2>&1) -join "`n")
    if ($LASTEXITCODE -ne 0) { throw 'govulncheck -version failed.' }
    $scannerDatabaseMatch = [regex]::Match(
        $govulncheckVersionText, '(?m)^DB updated:\s+(?<value>.+?)\s+UTC$')
    $scannerDatabaseUpdated = [DateTimeOffset]::MinValue
    if (-not $scannerDatabaseMatch.Success -or -not [DateTimeOffset]::TryParse(
            $scannerDatabaseMatch.Groups['value'].Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$scannerDatabaseUpdated)) {
        throw 'govulncheck did not report a valid vulnerability database timestamp.'
    }
    $entrypointLines = @(Get-Content -LiteralPath $EntrypointScriptPath -Encoding UTF8)
    $invocations = @($entrypointLines | Select-String -SimpleMatch 'exec gosu postgres "$BASH_SOURCE" "$@"')
    $sourceText = Get-Content -LiteralPath $GosuSourcePath -Raw -Encoding UTF8
    return [pscustomobject][ordered]@{
        mode = 'live_locked_binary_and_official_sources'
        gosu = [pscustomobject][ordered]@{
            binary_sha256 = Get-Sha256 -Path $GosuBinaryPath
            go_version = $goVersion
            module = $module
            module_version = $moduleVersion
            dependencies = $dependencies
            goos = [regex]::Match($buildText, '(?m)^\s*build\s+GOOS=(?<value>\S+)$').Groups['value'].Value
            goarch = [regex]::Match($buildText, '(?m)^\s*build\s+GOARCH=(?<value>\S+)$').Groups['value'].Value
            cgo_enabled = [regex]::Match(
                $buildText, '(?m)^\s*build\s+CGO_ENABLED=(?<value>\S+)$').Groups['value'].Value
            vcs_revision = [regex]::Match(
                $buildText, '(?m)^\s*build\s+vcs\.revision=(?<value>\S+)$').Groups['value'].Value
        }
        govulncheck = [pscustomobject][ordered]@{
            version_output = $govulncheckVersionText
            binary_sha256 = Get-Sha256 -Path $GovulncheckPath
            database_updated_utc = $scannerDatabaseUpdated.ToUniversalTime().ToString('o')
            module = 'golang.org/x/vuln/cmd/govulncheck@v1.7.0'
            module_sum_sha256 = 'e0c401ba19976f3dae7a9349adfdeff9a6992c60eac35265bb061ba1e800d6a8'
            go_mod_sum_sha256 = '5f0ef3bd4dded5bb02618057bbec38c1c9f62a09f6edfdf8581093c3c2cbe54b'
            module_zip_sha256 = 'a14bf913551ac09f00ae0e903c1b358713f71af911d7ddacc3fab8ce5c149a26'
        }
        entrypoint = [pscustomobject][ordered]@{
            sha256 = Get-Sha256 -Path $EntrypointScriptPath
            gosu_invocation_count = $invocations.Count
            gosu_invocation_line = if ($invocations.Count -eq 1) { [int]$invocations[0].LineNumber } else { 0 }
            invocation = if ($invocations.Count -eq 1) { [string]$invocations[0].Line.Trim() } else { '' }
            guarded_by_postgres_command = $sourceText.Length -ge 0 -and
                ($entrypointLines -join "`n") -match '\[\s+"\$1"\s+=\s+''postgres''\s+\]'
            guarded_by_root_uid = ($entrypointLines -join "`n") -match '\[\s+"\$\(id -u\)"\s+=\s+''0''\s+\]'
        }
        source = [pscustomobject][ordered]@{
            url = 'https://raw.githubusercontent.com/tianon/gosu/1.19/main.go'
            tag = '1.19'
            tag_commit = '6456aaa0f3c854d199d0f037f068eb97515b7513'
            sha256 = Get-Sha256 -Path $GosuSourcePath
            imports = @('os', 'os/exec', 'runtime', 'syscall')
            contains_syscall_exec = $sourceText.Contains('syscall.Exec(')
            contains_network_import = $sourceText -match '"net(?:/[^\"]+)?"'
            contains_listener = $sourceText -match '(?m)\bListen(?:Packet|TCP|UDP)?\s*\('
        }
    }
}

function Test-Observation {
    param([Parameter(Mandatory = $true)][object]$Value)
    $observationDatabaseUpdated = [DateTimeOffset]::MinValue
    $observationDatabaseValid = [DateTimeOffset]::TryParse(
        [string]$Value.govulncheck.database_updated_utc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$observationDatabaseUpdated)
    if ([string]$Value.gosu.binary_sha256 -ne $expectedGosuSha -or
        [string]$Value.gosu.go_version -ne 'go1.24.6' -or
        [string]$Value.gosu.module -ne 'github.com/tianon/gosu' -or
        [string]$Value.gosu.module_version -ne 'v1.19.0' -or
        [string]$Value.gosu.goos -ne 'linux' -or [string]$Value.gosu.goarch -ne 'amd64' -or
        [string]$Value.gosu.cgo_enabled -ne '0' -or [string]$Value.gosu.vcs_revision -ne '1.19') {
        Add-Failure 'Locked gosu build identity does not match the reviewed linux/amd64 v1.19 binary.'
    }
    if ([string]$Value.govulncheck.binary_sha256 -ne $expectedGovulncheckSha -or
        [string]$Value.govulncheck.version_output -notmatch 'Scanner:\s+govulncheck@v1\.7\.0' -or
        [string]$Value.govulncheck.version_output -notmatch 'DB:\s+https://vuln\.go\.dev' -or
        -not $observationDatabaseValid -or
        [string]$Value.govulncheck.module_sum_sha256 -ne
            'e0c401ba19976f3dae7a9349adfdeff9a6992c60eac35265bb061ba1e800d6a8' -or
        [string]$Value.govulncheck.go_mod_sum_sha256 -ne
            '5f0ef3bd4dded5bb02618057bbec38c1c9f62a09f6edfdf8581093c3c2cbe54b' -or
        [string]$Value.govulncheck.module_zip_sha256 -ne
            'a14bf913551ac09f00ae0e903c1b358713f71af911d7ddacc3fab8ce5c149a26') {
        Add-Failure 'govulncheck identity does not match the pinned official v1.7.0 scanner.'
    }
    if ([string]$Value.entrypoint.sha256 -ne $expectedEntrypointSha -or
        [int]$Value.entrypoint.gosu_invocation_count -ne 1 -or
        [string]$Value.entrypoint.invocation -ne 'exec gosu postgres "$BASH_SOURCE" "$@"' -or
        -not [bool]$Value.entrypoint.guarded_by_postgres_command -or
        -not [bool]$Value.entrypoint.guarded_by_root_uid) {
        Add-Failure 'PostgreSQL entrypoint does not match the reviewed root-only postgres gosu invocation.'
    }
    if ([string]$Value.source.sha256 -ne $expectedSourceSha -or
        [string]$Value.source.tag_commit -ne '6456aaa0f3c854d199d0f037f068eb97515b7513' -or
        (@($Value.source.imports) -join ',') -ne 'os,os/exec,runtime,syscall' -or
        -not [bool]$Value.source.contains_syscall_exec -or
        [bool]$Value.source.contains_network_import -or [bool]$Value.source.contains_listener) {
        Add-Failure 'Official gosu v1.19 source identity or one-shot exec behavior does not match the review.'
    }
}

$bindingPaths = [ordered]@{
    vulnerability_disposition = $dispositionPath
    official_candidate = $candidatePath
    toolchain_lock = $lockPath
    compose = $composePath
}
$bindingHashes = [ordered]@{}
foreach ($entry in $bindingPaths.GetEnumerator()) {
    $bindingHashes[$entry.Key] = Get-Sha256 -Path $entry.Value
}

$disposition = $null
$candidate = $null
$sarif = $null
$osv = $null
$observation = $null
$sarifInput = [IO.Path]::GetFullPath($SarifInputPath)
$osvInput = [IO.Path]::GetFullPath($OsvInputPath)
$sarifSha = Get-Sha256 -Path $sarifInput
$osvSha = Get-Sha256 -Path $osvInput
try {
    $disposition = Get-Content -LiteralPath $dispositionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $candidate = Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sarif = Get-Content -LiteralPath $sarifInput -Raw -Encoding UTF8 | ConvertFrom-Json
    $osv = Get-Content -LiteralPath $osvInput -Raw -Encoding UTF8 | ConvertFrom-Json
    $observation = if ([string]::IsNullOrWhiteSpace($ObservationPath)) {
        Read-LiveObservation
    }
    else {
        Get-Content -LiteralPath ([IO.Path]::GetFullPath($ObservationPath)) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}
catch { Add-Failure "Could not load reachability evidence: $($_.Exception.Message)" }

if ($null -ne $observation) { Test-Observation -Value $observation }
if ($null -ne $disposition -and $null -ne $candidate) {
    if ([string]$disposition.result -ne 'BLOCKED' -or
        [string]$disposition.policy_effect -ne 'blocking' -or
        [string]$disposition.review.waiver_state -ne 'none' -or
        [bool]$disposition.review.automatic_policy_exception -or
        [bool]$disposition.release_authority -or
        [string]$candidate.locked_probe.gosu_sha256 -ne $expectedGosuSha -or
        -not [bool]$candidate.comparison.same_gosu_binary_sha256) {
        Add-Failure 'Disposition or candidate evidence no longer describes the unresolved locked gosu blocker.'
    }
}

$osvPackages = @()
$osvSymbols = @()
$osvFixed = @()
if ($null -ne $osv) {
    $osvPackages = @($osv.affected | ForEach-Object { $_.ecosystem_specific.imports } |
        Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.path } | Sort-Object -Unique)
    $osvSymbols = @($osv.affected | ForEach-Object { $_.ecosystem_specific.imports } |
        Where-Object { $null -ne $_ } | ForEach-Object { $_.symbols } |
        Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $osvFixed = @($osv.affected | ForEach-Object { $_.ranges } |
        ForEach-Object { $_.events } | ForEach-Object {
            $fixedProperty = $_.PSObject.Properties['fixed']
            if ($null -ne $fixedProperty) { [string]$fixedProperty.Value }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ([string]$osv.id -ne 'GO-2026-4970' -or
        @($osv.aliases | ForEach-Object { [string]$_ }) -notcontains 'CVE-2026-39822' -or
        ($osvPackages -join ',') -ne 'os' -or
        (($osvSymbols | Sort-Object) -join ',') -ne (($expectedOsSymbols | Sort-Object) -join ',')) {
        Add-Failure 'Official GO-2026-4970 OSV package or symbol metadata does not match the reviewed record.'
    }
}

$driver = $null
$databaseUpdated = [DateTimeOffset]::MinValue
$results = @()
$rules = @()
if ($null -ne $sarif) {
    $runs = @($sarif.runs)
    if ([string]$sarif.version -ne '2.1.0' -or $runs.Count -ne 1) {
        Add-Failure 'govulncheck SARIF must be version 2.1.0 with exactly one run.'
    }
    else {
        $driver = $runs[0].tool.driver
        $rules = @($driver.rules)
        $results = @($runs[0].results)
        $databaseTimestampValid = [DateTimeOffset]::TryParse(
            [string]$driver.properties.db_last_modified,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$databaseUpdated)
        if ([string]$driver.name -ne 'govulncheck' -or
            [string]$driver.semanticVersion -ne 'v1.7.0' -or
            [string]$driver.properties.scanner_version -ne 'v1.7.0' -or
            [string]$driver.properties.db -ne 'https://vuln.go.dev' -or
            [string]$driver.properties.scan_level -ne 'symbol' -or
            [string]$driver.properties.scan_mode -ne 'binary' -or
            -not $databaseTimestampValid) {
            Add-Failure 'SARIF is not a pinned official govulncheck v1.7.0 symbol-level binary scan.'
        }
        elseif ($null -ne $observation -and
            ([DateTimeOffset]$observation.govulncheck.database_updated_utc).ToUniversalTime() -ne
                $databaseUpdated.ToUniversalTime()) {
            Add-Failure 'govulncheck executable and SARIF report use different database timestamps.'
        }
    }
}

$mappedFindings = [Collections.Generic.List[object]]::new()
if ($null -ne $disposition -and $rules.Count -gt 0) {
    foreach ($cve in @($disposition.blocking_findings.vulnerability_ids | ForEach-Object { [string]$_ })) {
        $matchingRules = @($rules | Where-Object {
                @($_.properties.tags | ForEach-Object { [string]$_ } | Sort-Object -Unique) -contains $cve
            })
        if ($matchingRules.Count -ne 1) {
            Add-Failure "Blocking vulnerability $cve must map to exactly one govulncheck rule."
            continue
        }
        $rule = $matchingRules[0]
        $matchingResults = @($results | Where-Object { [string]$_.ruleId -eq [string]$rule.id })
        if ($matchingResults.Count -ne 1) {
            Add-Failure "govulncheck rule $($rule.id) must have exactly one result."
            continue
        }
        $message = ([string]$matchingResults[0].message.text).Replace([char]0x2019, "'")
        $precision = if ($message -match "imports\s+1\s+vulnerable\s+package.+doesn't appear to call") {
            'package_only'
        }
        elseif ($message -match "depends on\s+1\s+vulnerable\s+module.+doesn't appear to call") {
            'module_only'
        }
        else { 'symbol_reachable' }
        $mappedFindings.Add([pscustomobject][ordered]@{
                cve = $cve
                go_id = [string]$rule.id
                precision = $precision
                level = [string]$matchingResults[0].level
                summary = [string]$rule.fullDescription.text
                reference = [string]$rule.helpUri
            })
    }
}

$symbolCount = @($mappedFindings | Where-Object precision -eq 'symbol_reachable').Count
$packageCount = @($mappedFindings | Where-Object precision -eq 'package_only').Count
$moduleCount = @($mappedFindings | Where-Object precision -eq 'module_only').Count
if ($null -ne $disposition -and
    ($mappedFindings.Count -ne [int]$disposition.blocking_findings.total -or
        $mappedFindings.Count -ne 22)) {
    Add-Failure 'The review must account for all 22 hosted HIGH/CRITICAL findings.'
}
if ($failures.Count -eq 0) {
    Copy-Evidence -Source $sarifInput -Destination $SarifEvidencePath
    Copy-Evidence -Source $osvInput -Destination $OsvEvidencePath
}

$reviewStatus = if ($failures.Count -gt 0) {
    'REVIEW_FAILED_CLOSED'
}
elseif ($symbolCount -gt 0) {
    'REVIEW_COMPLETE_REACHABLE_SYMBOLS_BLOCKING'
}
else { 'REVIEW_COMPLETE_NO_SYMBOL_REACHABILITY_STILL_BLOCKING' }
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS_DIAGNOSTIC' } else { 'FAIL' }
    release_authority = $false
    source_mutation_performed = $false
    review = [pscustomobject][ordered]@{
        status = $reviewStatus
        scope = 'locked postgres runtime gosu binary'
        policy_blocking = $true
        risk_assessment = if ($symbolCount -eq 0) {
            'reduced_reachability_not_zero_risk'
        }
        else { 'reachable_symbol_risk_requires_remediation' }
        waiver_state = 'none'
        owner_approval = $false
        automatic_policy_exception = $false
        lock_update_performed = $false
    }
    binary = if ($null -ne $observation) { $observation.gosu } else { $null }
    scanner = [pscustomobject][ordered]@{
        name = 'govulncheck'
        version = if ($null -ne $driver) { [string]$driver.semanticVersion } else { '' }
        binary_sha256 = if ($null -ne $observation) { [string]$observation.govulncheck.binary_sha256 } else { '' }
        module = if ($null -ne $observation) { [string]$observation.govulncheck.module } else { '' }
        module_sum_sha256 = if ($null -ne $observation) {
            [string]$observation.govulncheck.module_sum_sha256
        }
        else { '' }
        go_mod_sum_sha256 = if ($null -ne $observation) {
            [string]$observation.govulncheck.go_mod_sum_sha256
        }
        else { '' }
        module_zip_sha256 = if ($null -ne $observation) { [string]$observation.govulncheck.module_zip_sha256 } else { '' }
        database = if ($null -ne $driver) { [string]$driver.properties.db } else { '' }
        database_updated_utc = if ($databaseUpdated -ne [DateTimeOffset]::MinValue) {
            $databaseUpdated.ToUniversalTime().ToString('o')
        }
        else { '' }
        scan_level = if ($null -ne $driver) { [string]$driver.properties.scan_level } else { '' }
        scan_mode = if ($null -ne $driver) { [string]$driver.properties.scan_mode } else { '' }
        sarif_sha256 = $sarifSha
        total_findings = $results.Count
    }
    official_osv = [pscustomobject][ordered]@{
        database = 'https://vuln.go.dev'
        source = 'https://vuln.go.dev/ID/GO-2026-4970.json'
        sha256 = $osvSha
        id = if ($null -ne $osv) { [string]$osv.id } else { '' }
        modified_utc = if ($null -ne $osv) {
            ([DateTimeOffset]$osv.modified).ToUniversalTime().ToString('o')
        }
        else { '' }
        alias = 'CVE-2026-39822'
        affected_packages = $osvPackages
        vulnerable_symbols = $osvSymbols
        fixed_versions = $osvFixed
    }
    threat_model = [pscustomobject][ordered]@{
        entrypoint = if ($null -ne $observation) { $observation.entrypoint } else { $null }
        official_source = if ($null -ne $observation) { $observation.source } else { $null }
        runtime_contract = 'root-only postgres entrypoint privilege drop followed by one-shot exec'
        network_listener = $false
        untrusted_network_parser = $false
        os_package_imported = $packageCount -gt 0
        vulnerable_os_symbols_reported_reachable = @($mappedFindings | Where-Object {
                $_.cve -eq 'CVE-2026-39822' -and $_.precision -eq 'symbol_reachable'
            }).Count -gt 0
    }
    mapped_blocking_findings = [pscustomobject][ordered]@{
        expected = if ($null -ne $disposition) { [int]$disposition.blocking_findings.total } else { 0 }
        mapped = $mappedFindings.Count
        symbol_reachable = $symbolCount
        package_only = $packageCount
        module_only = $moduleCount
        findings = @($mappedFindings)
    }
    limitations = @(
        'Binary mode reports packages and symbols present in the binary but cannot produce a call graph.',
        'Package-only and module-only findings can be false positives when vulnerable symbols are unreachable.',
        'Zero reported reachable symbols is not proof of absence and does not supersede the hosted severity policy.',
        'Repeat the review whenever the gosu bytes, Go build, scanner version, or vulnerability database changes.'
    )
    bindings = [pscustomobject][ordered]@{
        vulnerability_disposition = 'Data/Security/p0-12-postgres-vulnerability-disposition.json'
        vulnerability_disposition_sha256 = $bindingHashes.vulnerability_disposition
        official_candidate = 'Data/Security/p0-12-postgres-official-candidate-evaluation.json'
        official_candidate_sha256 = $bindingHashes.official_candidate
        toolchain_lock = 'Data/Toolchain/toolchain.lock.json'
        toolchain_lock_sha256 = $bindingHashes.toolchain_lock
        compose = 'Deploy/compose/compose.yaml'
        compose_sha256 = $bindingHashes.compose
        sarif = if ([string]::IsNullOrWhiteSpace($SarifEvidencePath)) { '' } else {
            'Data/Security/p0-12-postgres-gosu-govulncheck.sarif.json'
        }
        official_osv = if ([string]::IsNullOrWhiteSpace($OsvEvidencePath)) { '' } else {
            'Data/Security/p0-12-postgres-gosu-GO-2026-4970.osv.json'
        }
    }
    failure_count = $failures.Count
    failures = @($failures)
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    [IO.File]::WriteAllText($resolvedOutput, $json + "`n", [Text.UTF8Encoding]::new($false))
}
$json
if ($failures.Count -gt 0) { throw 'PostgreSQL gosu reachability review failed closed.' }
