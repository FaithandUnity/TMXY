[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$dockerfilePath = Join-Path $root 'Deploy\postgres\Dockerfile'
$migrationPath = Join-Path $root 'Tests\Integration\Test-PostgresMigration.ps1'
$failures = [Collections.Generic.List[string]]::new()
$assertionCount = 0

function Assert-DerivedContract {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:assertionCount++
    if (-not $Condition) { $script:failures.Add($Message) }
}

if (-not (Test-Path -LiteralPath $dockerfilePath -PathType Leaf)) {
    throw "Derived PostgreSQL Dockerfile is missing: $dockerfilePath"
}
if (-not (Test-Path -LiteralPath $migrationPath -PathType Leaf)) {
    throw "PostgreSQL migration test is missing: $migrationPath"
}
$dockerfile = Get-Content -LiteralPath $dockerfilePath -Raw -Encoding UTF8
$migration = Get-Content -LiteralPath $migrationPath -Raw -Encoding UTF8
$fromLines = @($dockerfile -split "`n" | Where-Object { $_ -match '^FROM\s+' })

Assert-DerivedContract ($dockerfile -match [regex]::Escape(
        'golang@sha256:6ef6e30f0ea5c384f6d111cf856e024e3086bbdcb1779da3f3b3fbba0aea53d2')) `
    'The gosu builder must use the qualified Go 1.26.7 linux/amd64 digest.'
Assert-DerivedContract ($dockerfile -match [regex]::Escape(
        'postgres@sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2')) `
    'The final image must use the locked PostgreSQL 18.6 base digest.'
Assert-DerivedContract ($fromLines.Count -eq 2 -and
    $fromLines[0] -eq 'FROM ${TMXY_GOSU_BUILDER_IMAGE} AS gosu-builder' -and
    $fromLines[1] -eq 'FROM ${TMXY_POSTGRES_BASE_IMAGE}') `
    'Only the two digest-bound build stages are allowed.'
Assert-DerivedContract ($dockerfile -match
    'TMXY_GOSU_COMMIT=6456aaa0f3c854d199d0f037f068eb97515b7513') `
    'gosu source must remain pinned to the reviewed 1.19 commit.'
Assert-DerivedContract ($dockerfile -match
    'TMXY_GOSU_SOURCE_SHA256=33d7537d588ea49458b9509bcf4554bdf5ceacc66da71e5caa1058ea3b689c3b') `
    'gosu source archive must remain bound by SHA-256.'
Assert-DerivedContract ($dockerfile -match
    'ADD --checksum=sha256:\$\{TMXY_GOSU_SOURCE_SHA256\}') `
    'Remote gosu source must be verified by BuildKit before extraction.'
Assert-DerivedContract ($dockerfile -match 'GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=linux GOARCH=amd64') `
    'gosu must be a local-toolchain, static linux/amd64 build.'
Assert-DerivedContract ($dockerfile -match
    'go build -mod=readonly -trimpath -buildvcs=false') `
    'gosu dependencies and build paths must fail closed and remain reproducible.'
Assert-DerivedContract ($dockerfile -match "-ldflags='-s -w -buildid='") `
    'The variable Go build ID must remain disabled.'
Assert-DerivedContract ($dockerfile -match 'SOURCE_DATE_EPOCH=1758654578') `
    'The image creation time must remain fixed to the reviewed source commit.'
Assert-DerivedContract (@([regex]::Matches(
            $dockerfile, 'touch (?:--date=|-d )"@\$\{SOURCE_DATE_EPOCH\}"')).Count -eq 2) `
    'Both the staged and installed gosu timestamps must be normalized.'
Assert-DerivedContract ($dockerfile -match
    "1\.19 \(go1\.26\.7 on linux/amd64; gc\)") `
    'Both build stages must verify the exact gosu and Go identities.'
Assert-DerivedContract ($dockerfile -match
    'RUN --mount=type=bind,from=gosu-builder,[^\r\n]+,ro') `
    'The final stage must receive gosu through a read-only BuildKit mount.'
Assert-DerivedContract ($dockerfile -match
    'apk add --no-cache --upgrade libcrypto3=3\.5\.8-r0 libssl3=3\.5\.8-r0' -and
    $dockerfile -notmatch '(?m)^\s*RUN\s+(?:apt-get|curl|wget)\b') `
    'The final runtime may only apply the two exact Alpine OpenSSL fixes.'
Assert-DerivedContract ($dockerfile -match
    'org\.opencontainers\.image\.base\.digest="sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2"') `
    'OCI metadata must expose the exact PostgreSQL base digest.'
Assert-DerivedContract ($dockerfile -match
    'io\.tmxy\.gosu\.revision="\$\{TMXY_GOSU_COMMIT\}"') `
    'OCI metadata must expose the exact gosu source revision.'
Assert-DerivedContract ($dockerfile -notmatch '(?i)(password|token|secret|private[_ -]?key)\s*[=:]') `
    'The Dockerfile must not embed credential material.'
Assert-DerivedContract ($migration -match '\[string\]\$ImageReference\s*=\s*''''' -and
    $migration -match 'IsNullOrWhiteSpace\(\$ImageReference\)') `
    'Migration validation must support an explicit candidate without changing the lock.'

$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    assertion_count = $assertionCount
    source_mutation_performed = $false
    dockerfile = 'Deploy/postgres/Dockerfile'
    dockerfile_sha256 = (Get-FileHash -LiteralPath $dockerfilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 5
if ($failures.Count -gt 0) { throw 'Derived PostgreSQL image contract failed.' }
