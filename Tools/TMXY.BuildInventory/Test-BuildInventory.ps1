[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev',
    [string]$InventoryPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildInventory\build-inventory.json',
    [string]$EnvironmentPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildInventory\toolchain-environment.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Actual -ne $Expected) {
        throw "$Label expected '$Expected' but got '$Actual'."
    }
}

foreach ($path in @($InventoryPath, $EnvironmentPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required output is missing: $path"
    }
}

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]'\/')
$inventory = Get-Content -LiteralPath $InventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$environment = Get-Content -LiteralPath $EnvironmentPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-Equal -Actual ([int]$inventory.schema_version) -Expected 1 -Label 'Schema version'
Assert-Equal -Actual ([string]$inventory.source_policy) -Expected 'read-only' -Label 'Source policy'
Assert-Equal -Actual ([int]$inventory.summary.vcproj_count) -Expected 285 -Label 'VC project count'
Assert-Equal -Actual ([int]$inventory.summary.csproj_count) -Expected 1 -Label 'C# project count'
Assert-Equal -Actual ([int]$inventory.summary.solution_count) -Expected 33 -Label 'Solution count'
Assert-Equal -Actual ([int]$inventory.summary.project_parse_errors) -Expected 0 -Label 'VC project parse errors'

$checkedProjects = 0
foreach ($project in @($inventory.projects | Where-Object { $_.kind -eq 'vcproj' })) {
    $sourcePath = Join-Path (Join-Path $workspace ([string]$project.root)) (([string]$project.path).Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Inventoried project no longer exists: $sourcePath"
    }
    $actualHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne [string]$project.sha256) {
        throw "Inventoried project changed after export: $sourcePath"
    }
    $checkedProjects++
}

if ($null -eq $environment.visual_studio -or @($environment.visual_studio).Count -eq 0) {
    throw 'No installed Visual Studio instance was captured.'
}
if ($null -eq $environment.unreal_engine) {
    throw 'The UE 5.8 installation was not captured.'
}
Assert-Equal -Actual ([int]$environment.unreal_engine.major) -Expected 5 -Label 'UE major version'
Assert-Equal -Actual ([int]$environment.unreal_engine.minor) -Expected 8 -Label 'UE minor version'
Assert-Equal -Actual ([int]$environment.unreal_engine.patch) -Expected 2 -Label 'UE patch version'

[pscustomobject][ordered]@{
    result = 'PASS'
    checked_vc_projects = $checkedProjects
    solutions = [int]$inventory.summary.solution_count
    dependency_records = [int]$inventory.summary.dependency_count
    inventory_sha256 = (Get-FileHash -LiteralPath $InventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    environment_sha256 = (Get-FileHash -LiteralPath $EnvironmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json
