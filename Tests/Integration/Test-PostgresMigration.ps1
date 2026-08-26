[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p0-12-postgres-migration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$lock = Get-Content -LiteralPath (Join-Path $root 'Data\Toolchain\toolchain.lock.json') -Raw |
    ConvertFrom-Json
$image = [string]$lock.database.development_image.digest_reference
$expectedVersion = [string]$lock.database.qualified_minor
$migrationRoot = Join-Path $root 'Backend\adapters\persistence_postgres\migrations'
$migrationFile = Join-Path $migrationRoot 'V0001__runtime_contract.sql'
$containerName = "tmxy-p0-12-migration-$([Guid]::NewGuid().ToString('N').Substring(0, 12))"
$started = $false

function Invoke-Docker {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & docker @Arguments 2>&1
    return [pscustomobject][ordered]@{
        exit_code = $LASTEXITCODE
        output = ($output -join "`n").Trim()
    }
}

try {
    $start = Invoke-Docker -Arguments @(
        'run', '--rm', '-d', '--name', $containerName, '--network', 'none',
        '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', '--tmpfs', '/var/lib/postgresql',
        '--mount', "type=bind,src=$migrationRoot,dst=/migrations,readonly", $image)
    if ($start.exit_code -ne 0) { throw 'PostgreSQL migration container did not start.' }
    $started = $true

    $ready = $false
    $initializationComplete = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $logs = Invoke-Docker -Arguments @('logs', $containerName)
        if ($logs.output -match 'PostgreSQL init process complete; ready for start up') {
            $initializationComplete = $true
        }
        if ($initializationComplete) {
            $probe = Invoke-Docker -Arguments @(
                'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
                '-Atc', 'SELECT 1;')
            if ($probe.exit_code -eq 0 -and $probe.output -eq '1') {
                $ready = $true
                break
            }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'PostgreSQL did not become ready within 30 seconds.' }

    $apply = Invoke-Docker -Arguments @(
        'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
        '-v', 'ON_ERROR_STOP=1', '-f', '/migrations/V0001__runtime_contract.sql')
    if ($apply.exit_code -ne 0) { throw "Migration V0001 failed: $($apply.output)" }

    $serverVersion = Invoke-Docker -Arguments @(
        'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
        '-Atc', 'SHOW server_version;')
    $contract = Invoke-Docker -Arguments @(
        'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
        '-Atc', "SELECT component || ':' || schema_version FROM tmxy_system.runtime_contract;")
    $schemaOwner = Invoke-Docker -Arguments @(
        'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
        '-Atc', "SELECT schema_owner FROM information_schema.schemata WHERE schema_name='tmxy_system';")

    $passed = $serverVersion.exit_code -eq 0 -and $serverVersion.output -eq $expectedVersion -and
        $contract.exit_code -eq 0 -and $contract.output -eq 'foundation:1' -and
        $schemaOwner.exit_code -eq 0 -and $schemaOwner.output -eq 'postgres'
    $report = [pscustomobject][ordered]@{
        schema_version = 1
        captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
        result = if ($passed) { 'PASS' } else { 'FAIL' }
        image = $image
        database_version = $serverVersion.output
        source_mount = 'read-only'
        network = 'none'
        data_storage = 'tmpfs'
        authentication = 'ephemeral_trust_inside_networkless_container'
        migration = [pscustomobject][ordered]@{
            file = 'Backend/adapters/persistence_postgres/migrations/V0001__runtime_contract.sql'
            sha256 = (Get-FileHash -LiteralPath $migrationFile -Algorithm SHA256).Hash.ToLowerInvariant()
            runtime_contract = $contract.output
            schema_owner = $schemaOwner.output
        }
    }
    $json = ($report | ConvertTo-Json -Depth 6).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText(
        [System.IO.Path]::GetFullPath($OutputPath),
        $json + "`n",
        [System.Text.UTF8Encoding]::new($false))
    $json
    if (-not $passed) { throw 'PostgreSQL migration validation failed.' }
}
finally {
    if ($started) { $null = Invoke-Docker -Arguments @('rm', '-f', $containerName) }
}
