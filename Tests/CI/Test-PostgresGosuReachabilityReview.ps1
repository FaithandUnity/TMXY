[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$toolPath = Join-Path $root 'Tools\TMXY.SupplyChain\New-PostgresGosuReachabilityReview.ps1'
$dispositionPath = Join-Path $root 'Data\Security\p0-12-postgres-vulnerability-disposition.json'
$boundPaths = @(
    $dispositionPath,
    (Join-Path $root 'Data\Security\p0-12-postgres-official-candidate-evaluation.json'),
    (Join-Path $root 'Data\Toolchain\toolchain.lock.json'),
    (Join-Path $root 'Deploy\compose\compose.yaml')
)
$failures = [Collections.Generic.List[string]]::new()

function Assert-ReviewTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { $failures.Add($Message) }
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    $json = ($Value | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
    throw "PostgreSQL gosu reachability review tool is missing: $toolPath"
}
$beforeHashes = @($boundPaths | ForEach-Object {
        (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
    })
$disposition = Get-Content -LiteralPath $dispositionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mapping = [ordered]@{
    'CVE-2025-61726' = 'GO-2026-4341'; 'CVE-2025-61729' = 'GO-2025-4155'
    'CVE-2025-68121' = 'GO-2026-4337'; 'CVE-2026-25679' = 'GO-2026-4601'
    'CVE-2026-27145' = 'GO-2026-5037'; 'CVE-2026-32280' = 'GO-2026-4947'
    'CVE-2026-32281' = 'GO-2026-4946'; 'CVE-2026-32283' = 'GO-2026-4870'
    'CVE-2026-33811' = 'GO-2026-4981'; 'CVE-2026-33814' = 'GO-2026-4918'
    'CVE-2026-33818' = 'GO-2026-5972'; 'CVE-2026-39820' = 'GO-2026-4986'
    'CVE-2026-39821' = 'GO-2026-5026'; 'CVE-2026-39822' = 'GO-2026-4970'
    'CVE-2026-39836' = 'GO-2026-4971'; 'CVE-2026-42499' = 'GO-2026-4977'
    'CVE-2026-42504' = 'GO-2026-5038'; 'CVE-2026-56853' = 'GO-2026-6089'
    'CVE-2026-56858' = 'GO-2026-6091'; 'CVE-2026-56859' = 'GO-2026-6088'
    'CVE-2026-56860' = 'GO-2026-6218'; 'CVE-2026-56862' = 'GO-2026-6090'
}
$expectedSymbols = @(
    'OpenInRoot', 'openRootInRoot', 'Root.Create', 'Root.Open', 'Root.OpenFile',
    'Root.OpenRoot', 'Root.ReadFile', 'Root.WriteFile', 'rootFS.Open',
    'rootFS.ReadDir', 'rootFS.ReadFile', 'rootOpenFileNolog'
)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'tmxy-postgres-gosu-review-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $rules = @($mapping.GetEnumerator() | ForEach-Object {
            [pscustomobject][ordered]@{
                id = [string]$_.Value
                fullDescription = [pscustomobject]@{ text = "Fixture $($_.Key)" }
                helpUri = "https://pkg.go.dev/vuln/$($_.Value)"
                properties = [pscustomobject]@{ tags = @([string]$_.Key) }
            }
        })
    $results = @($mapping.GetEnumerator() | ForEach-Object {
            $isPackage = [string]$_.Key -eq 'CVE-2026-39822'
            [pscustomobject][ordered]@{
                ruleId = [string]$_.Value
                level = if ($isPackage) { 'warning' } else { 'note' }
                message = [pscustomobject]@{ text = if ($isPackage) {
                        "Your code imports 1 vulnerable package (os), but doesn't appear to call any of the vulnerable symbols."
                    }
                    else {
                        "Your code depends on 1 vulnerable module (stdlib), but doesn't appear to call any of the vulnerable symbols."
                    } }
            }
        })
    $sarif = [pscustomobject][ordered]@{
        version = '2.1.0'
        runs = @([pscustomobject][ordered]@{
                tool = [pscustomobject]@{ driver = [pscustomobject][ordered]@{
                        name = 'govulncheck'; semanticVersion = 'v1.7.0'
                        properties = [pscustomobject][ordered]@{
                            scanner_version = 'v1.7.0'; db = 'https://vuln.go.dev'
                            db_last_modified = '2026-08-26T14:57:44Z'
                            scan_level = 'symbol'; scan_mode = 'binary'
                        }
                        rules = $rules
                    } }
                results = $results
            })
    }
    $osv = [pscustomobject][ordered]@{
        id = 'GO-2026-4970'; modified = '2026-07-07T21:34:47Z'
        aliases = @('CVE-2026-39822')
        affected = @([pscustomobject][ordered]@{
                ranges = @([pscustomobject]@{ events = @(
                            [pscustomobject]@{ fixed = '1.25.12' },
                            [pscustomobject]@{ fixed = '1.26.5' },
                            [pscustomobject]@{ fixed = '1.27.0-rc.2' }) })
                ecosystem_specific = [pscustomobject]@{ imports = @(
                        [pscustomobject]@{ path = 'os'; symbols = $expectedSymbols }) }
            })
    }
    $observation = [pscustomobject][ordered]@{
        mode = 'fixture'
        gosu = [pscustomobject][ordered]@{
            binary_sha256 = '52c8749d0142edd234e9d6bd5237dff2d81e71f43537e2f4f66f75dd4b243dd0'
            go_version = 'go1.24.6'; module = 'github.com/tianon/gosu'; module_version = 'v1.19.0'
            dependencies = @(); goos = 'linux'; goarch = 'amd64'; cgo_enabled = '0'; vcs_revision = '1.19'
        }
        govulncheck = [pscustomobject][ordered]@{
            version_output = "Go: go1.26.6`nScanner: govulncheck@v1.7.0`nDB: https://vuln.go.dev`nDB updated: 2026-08-26 14:57:44 +0000 UTC"
            binary_sha256 = '56c0e00db28b3b3a94aab2462983de6f84c20670a5d54dbf5909bd54996c92f0'
            database_updated_utc = '2026-08-26T14:57:44Z'
            module = 'golang.org/x/vuln/cmd/govulncheck@v1.7.0'
            module_sum_sha256 = 'e0c401ba19976f3dae7a9349adfdeff9a6992c60eac35265bb061ba1e800d6a8'
            go_mod_sum_sha256 = '5f0ef3bd4dded5bb02618057bbec38c1c9f62a09f6edfdf8581093c3c2cbe54b'
            module_zip_sha256 = 'a14bf913551ac09f00ae0e903c1b358713f71af911d7ddacc3fab8ce5c149a26'
        }
        entrypoint = [pscustomobject][ordered]@{
            sha256 = '9c440299ae04a0a79d55b8bf03307036d890a40979d2fb698073c9050d4b20a5'
            gosu_invocation_count = 1; gosu_invocation_line = 343
            invocation = 'exec gosu postgres "$BASH_SOURCE" "$@"'
            guarded_by_postgres_command = $true; guarded_by_root_uid = $true
        }
        source = [pscustomobject][ordered]@{
            url = 'https://raw.githubusercontent.com/tianon/gosu/1.19/main.go'; tag = '1.19'
            tag_commit = '6456aaa0f3c854d199d0f037f068eb97515b7513'
            sha256 = '5b51466d021951038377ce7d2405087588bf86fb321299e749c73a6777865584'
            imports = @('os', 'os/exec', 'runtime', 'syscall'); contains_syscall_exec = $true
            contains_network_import = $false; contains_listener = $false
        }
    }
    $sarifPath = Join-Path $testRoot 'scan.sarif.json'
    $osvPath = Join-Path $testRoot 'GO-2026-4970.json'
    $observationPath = Join-Path $testRoot 'observation.json'
    Write-JsonFixture -Path $sarifPath -Value $sarif
    Write-JsonFixture -Path $osvPath -Value $osv
    Write-JsonFixture -Path $observationPath -Value $observation

    $baseOutput = Join-Path $testRoot 'base-output.json'
    $base = (& $toolPath -RebuildRoot $root -SarifInputPath $sarifPath `
            -OsvInputPath $osvPath -ObservationPath $observationPath `
            -SarifEvidencePath '' -OsvEvidencePath '' -OutputPath $baseOutput) | ConvertFrom-Json
    Assert-ReviewTest ([string]$base.result -eq 'PASS_DIAGNOSTIC' -and
        [string]$base.review.status -eq 'REVIEW_COMPLETE_NO_SYMBOL_REACHABILITY_STILL_BLOCKING') `
        'The complete non-symbol fixture must produce a diagnostic review that remains blocking.'
    Assert-ReviewTest ([int]$base.mapped_blocking_findings.mapped -eq 22 -and
        [int]$base.mapped_blocking_findings.symbol_reachable -eq 0 -and
        [int]$base.mapped_blocking_findings.package_only -eq 1 -and
        [int]$base.mapped_blocking_findings.module_only -eq 21) `
        'The fixture must preserve the exact 22/0/1/21 reachability counts.'
    Assert-ReviewTest ([bool]$base.review.policy_blocking -and
        [string]$base.review.waiver_state -eq 'none' -and
        -not [bool]$base.review.owner_approval -and -not [bool]$base.release_authority) `
        'Reachability evidence must not create a waiver or release authority.'

    $reachableSarif = $sarif | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    @($reachableSarif.runs)[0].results[0].message.text = 'Your code calls a vulnerable symbol.'
    Write-JsonFixture -Path (Join-Path $testRoot 'reachable.sarif.json') -Value $reachableSarif
    $reachable = (& $toolPath -RebuildRoot $root `
            -SarifInputPath (Join-Path $testRoot 'reachable.sarif.json') `
            -OsvInputPath $osvPath -ObservationPath $observationPath `
            -SarifEvidencePath '' -OsvEvidencePath '' `
            -OutputPath (Join-Path $testRoot 'reachable-output.json')) | ConvertFrom-Json
    Assert-ReviewTest ([string]$reachable.review.status -eq
        'REVIEW_COMPLETE_REACHABLE_SYMBOLS_BLOCKING' -and
        [int]$reachable.mapped_blocking_findings.symbol_reachable -eq 1 -and
        [bool]$reachable.review.policy_blocking) `
        'A reachable-symbol result must raise the diagnostic risk and remain blocking.'

    $missingSarif = $sarif | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    @($missingSarif.runs)[0].results = @(@($missingSarif.runs)[0].results | Select-Object -Skip 1)
    Write-JsonFixture -Path (Join-Path $testRoot 'missing.sarif.json') -Value $missingSarif
    $missingOutput = Join-Path $testRoot 'missing-output.json'
    $missingRejected = $false
    try {
        $null = & $toolPath -RebuildRoot $root `
            -SarifInputPath (Join-Path $testRoot 'missing.sarif.json') `
            -OsvInputPath $osvPath -ObservationPath $observationPath `
            -SarifEvidencePath '' -OsvEvidencePath '' -OutputPath $missingOutput 2>$null
    }
    catch { $missingRejected = $true }
    $missing = Get-Content -LiteralPath $missingOutput -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-ReviewTest ($missingRejected -and [string]$missing.result -eq 'FAIL' -and
        [string]$missing.review.status -eq 'REVIEW_FAILED_CLOSED') `
        'A missing blocking result must fail closed with a machine-readable report.'

    $afterHashes = @($boundPaths | ForEach-Object {
            (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    Assert-ReviewTest (($beforeHashes -join ',') -eq ($afterHashes -join ',')) `
        'Reachability regression tests must not modify bound project evidence.'
}
catch {
    $detail = ''
    if (Test-Path -LiteralPath (Join-Path $testRoot 'base-output.json') -PathType Leaf) {
        $failedReport = Get-Content -LiteralPath (Join-Path $testRoot 'base-output.json') `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $detail = ' ' + (@($failedReport.failures) -join '; ')
    }
    $failures.Add("PostgreSQL gosu reachability regression failed: $($_.Exception.Message)$detail")
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    fixture_count = 3
    source_mutation_performed = $false
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 5
if ($failures.Count -gt 0) { throw 'PostgreSQL gosu reachability regression failed.' }
