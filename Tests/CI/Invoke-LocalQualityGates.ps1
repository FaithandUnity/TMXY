[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild',
    [switch]$VerifyLegacyGoldenSources,
    [switch]$RunUEAutomation,
    [string]$OutputPath = 'E:\QQXYCodeDev\Rebuild\Data\BuildBaseline\p0-12-local-quality-gates.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')

function Invoke-JsonTest {
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [hashtable]$Arguments = @{}
    )
    $output = & $Script @Arguments
    return $output | ConvertFrom-Json
}

$repository = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-RepositoryLayout.ps1') `
    -Arguments @{ RebuildRoot = $root }
$secret = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-SecretPolicy.ps1') `
    -Arguments @{ RebuildRoot = $root }
$goldenArguments = @{ RebuildRoot = $root }
if ($VerifyLegacyGoldenSources) { $goldenArguments.VerifySourceFiles = $true }
$golden = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-GoldenSampleBaseline.ps1') `
    -Arguments $goldenArguments
$platformBudget = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-PlatformBudget.ps1') `
    -Arguments @{ RebuildRoot = $root }
$p1Charter = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-P1ExecutionCharter.ps1') `
    -Arguments @{ RebuildRoot = $root }
$formatCore = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-FormatCoreBaseline.ps1') `
    -Arguments @{ RebuildRoot = $root }
$packageV1 = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-PackageV1Baseline.ps1') `
    -Arguments @{ RebuildRoot = $root }
$packageV2 = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-PackageV2Baseline.ps1') `
    -Arguments @{ RebuildRoot = $root }
$packageV3 = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-PackageV3Baseline.ps1') `
    -Arguments @{ RebuildRoot = $root }
$packagePipeline = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-PackagePipelineBaseline.ps1') `
    -Arguments @{ RebuildRoot = $root }
$packageTree = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-PackageNormalizedTree.ps1') `
    -Arguments @{ RebuildRoot = $root }
$legacyTable = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-LegacyTableBaseline.ps1') `
    -Arguments @{ RebuildRoot = $root }
$currentTable = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-CurrentTableInvestigation.ps1') `
    -Arguments @{ RebuildRoot = $root }
$legacyToUE = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-LegacyToUETransform.ps1') `
    -Arguments @{ RebuildRoot = $root }
$qtxTexture = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-QtxTexture.ps1') `
    -Arguments @{ RebuildRoot = $root }
$smStaticMesh = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-SmStaticMesh.ps1') `
    -Arguments @{ RebuildRoot = $root }
$skemSkeletalMesh = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-SkemSkeletalMesh.ps1') `
    -Arguments @{ RebuildRoot = $root }
$animAnimation = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-AnimAnimation.ps1') `
    -Arguments @{ RebuildRoot = $root }
$terTerrain = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-TerTerrain.ps1') `
    -Arguments @{ RebuildRoot = $root }
$auxiliaryAssets = Invoke-JsonTest `
    -Script (Join-Path $root 'Tests\Contract\Test-AuxiliaryAssetInvestigation.ps1') `
    -Arguments @{ RebuildRoot = $root }
$assetInterchange = Invoke-JsonTest `
    -Script (Join-Path $root 'Tests\Contract\Test-AssetInterchangeContract.ps1') `
    -Arguments @{ RebuildRoot = $root }
$ue = $null
if ($RunUEAutomation) {
    $ue = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-UEProjectBaseline.ps1') `
        -Arguments @{ RebuildRoot = $root; RunAutomation = $true }
}
$goldenHostArguments = @{ RebuildRoot = $root }
if ($RunUEAutomation) { $goldenHostArguments.RequireAutomationEvidence = $true }
$ueGoldenHost = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-UEGoldenHost.ps1') `
    -Arguments $goldenHostArguments
$importerArguments = @{ RebuildRoot = $root }
if ($RunUEAutomation) { $importerArguments.RequireAutomationEvidence = $true }
$ueImporter = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-UEImporterPlugin.ps1') `
    -Arguments $importerArguments
$textureArguments = @{ RebuildRoot = $root }
if ($RunUEAutomation) { $textureArguments.RequireAutomationEvidence = $true }
$ueTextureImport = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-UETextureImport.ps1') `
    -Arguments $textureArguments
$staticMeshArguments = @{ RebuildRoot = $root }
if ($RunUEAutomation) { $staticMeshArguments.RequireAutomationEvidence = $true }
$ueStaticMeshImport = Invoke-JsonTest `
    -Script (Join-Path $root 'Tests\Contract\Test-UEStaticMeshImport.ps1') `
    -Arguments $staticMeshArguments
$skeletalMeshArguments = @{ RebuildRoot = $root }
if ($RunUEAutomation) { $skeletalMeshArguments.RequireAutomationEvidence = $true }
$ueSkeletalMeshImport = Invoke-JsonTest `
    -Script (Join-Path $root 'Tests\Contract\Test-UESkeletalMeshImport.ps1') `
    -Arguments $skeletalMeshArguments
$animationArguments = @{ RebuildRoot = $root }
if ($RunUEAutomation) { $animationArguments.RequireAutomationEvidence = $true }
$ueAnimationImport = Invoke-JsonTest `
    -Script (Join-Path $root 'Tests\Contract\Test-UEAnimationImport.ps1') `
    -Arguments $animationArguments
$terrainArguments = @{ RebuildRoot = $root }
if ($RunUEAutomation) { $terrainArguments.RequireAutomationEvidence = $true }
$ueTerrainImport = Invoke-JsonTest `
    -Script (Join-Path $root 'Tests\Contract\Test-UETerrainImport.ps1') `
    -Arguments $terrainArguments
$goldenTestMatrix = Invoke-JsonTest `
    -Script (Join-Path $root 'Tests\Contract\Test-GoldenTestMatrix.ps1') `
    -Arguments @{ RebuildRoot = $root }
$referenceFormats = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-ReferenceFormatDocs.ps1') `
    -Arguments @{ RebuildRoot = $root }
$ciAuthorityContract = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-CIAuthorityContract.ps1') `
    -Arguments @{ RebuildRoot = $root }
$uePackagingWaiver = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-UEPackagingWaiver.ps1') `
    -Arguments @{ RebuildRoot = $root }
$toolchain = Invoke-JsonTest -Script (Join-Path $root 'Tools\TMXY.Toolchain\Test-ToolchainLock.ps1') `
    -Arguments @{
        LockPath = (Join-Path $root 'Data\Toolchain\toolchain.lock.json')
        EnvironmentPath = (Join-Path $root 'Data\Toolchain\host-environment.json')
        OutputPath = (Join-Path $root 'Data\Toolchain\validation.json')
    }
$staticAnalysis = Invoke-JsonTest -Script (Join-Path $root 'Tests\Quality\Test-BackendStaticAnalysis.ps1') `
    -Arguments @{ RebuildRoot = $root }
$supplyChain = Invoke-JsonTest -Script (Join-Path $root 'Tools\TMXY.SupplyChain\Test-LocalImageEvidence.ps1') `
    -Arguments @{ RebuildRoot = $root }
$postgresMigration = Invoke-JsonTest -Script (Join-Path $root 'Tests\Integration\Test-PostgresMigration.ps1') `
    -Arguments @{ RebuildRoot = $root }
$backend = Invoke-JsonTest -Script (Join-Path $root 'Tests\Contract\Test-BackendBaseline.ps1') `
    -Arguments @{ RebuildRoot = $root }
$passed = [string]$repository.result -eq 'PASS' -and
    [string]$secret.result -eq 'PASS' -and
    [string]$golden.result -eq 'PASS' -and
    [string]$platformBudget.result -eq 'PASS' -and
    [string]$p1Charter.result -eq 'PASS' -and
    [string]$formatCore.result -eq 'PASS' -and
    [string]$packageV1.result -eq 'PASS' -and
    [string]$packageV2.result -eq 'PASS' -and
    [string]$packageV3.result -eq 'PASS' -and
    [string]$packagePipeline.result -eq 'PASS' -and
    [string]$packageTree.result -eq 'PASS' -and
    [string]$legacyTable.result -eq 'PASS' -and
    [string]$currentTable.result -eq 'PASS_DIAGNOSTIC' -and
    -not [bool]$currentTable.completion_criteria_satisfied -and
    [string]$legacyToUE.result -eq 'PASS' -and
    [bool]$legacyToUE.completion_criteria_satisfied -and
    [string]$qtxTexture.result -eq 'PASS' -and
    [bool]$qtxTexture.completion_criteria_satisfied -and
    [string]$smStaticMesh.result -eq 'PASS' -and
    [bool]$smStaticMesh.completion_criteria_satisfied -and
    [string]$skemSkeletalMesh.result -eq 'PASS' -and
    [bool]$skemSkeletalMesh.completion_criteria_satisfied -and
    [string]$animAnimation.result -eq 'PASS' -and
    [bool]$animAnimation.completion_criteria_satisfied -and
    [string]$terTerrain.result -eq 'PASS' -and
    [bool]$terTerrain.completion_criteria_satisfied -and
    [string]$auxiliaryAssets.result -eq 'PASS' -and
    [bool]$auxiliaryAssets.completion_criteria_satisfied -and
    [string]$assetInterchange.result -eq 'PASS' -and
    [bool]$assetInterchange.completion_criteria_satisfied -and
    [string]$ueGoldenHost.result -eq 'PASS' -and
    [bool]$ueGoldenHost.completion_criteria_satisfied -and
    [string]$ueImporter.result -eq 'PASS' -and
    [bool]$ueImporter.completion_criteria_satisfied -and
    [string]$ueTextureImport.result -eq 'PASS' -and
    [bool]$ueTextureImport.completion_criteria_satisfied -and
    [string]$ueStaticMeshImport.result -eq 'PASS' -and
    [bool]$ueStaticMeshImport.completion_criteria_satisfied -and
    [string]$ueSkeletalMeshImport.result -eq 'PASS' -and
    [bool]$ueSkeletalMeshImport.completion_criteria_satisfied -and
    [string]$ueAnimationImport.result -eq 'PASS' -and
    [bool]$ueAnimationImport.completion_criteria_satisfied -and
    [string]$ueTerrainImport.result -eq 'PASS' -and
    [bool]$ueTerrainImport.completion_criteria_satisfied -and
    [string]$goldenTestMatrix.result -eq 'PASS' -and
    [bool]$goldenTestMatrix.completion_criteria_satisfied -and
    [string]$referenceFormats.result -eq 'PASS' -and
    [string]$ciAuthorityContract.result -eq 'PASS' -and
    [string]$uePackagingWaiver.result -eq 'PASS' -and
    [string]$toolchain.result -eq 'PASS' -and
    [string]$staticAnalysis.result -eq 'PASS_DIAGNOSTIC' -and
    [string]$supplyChain.result -eq 'PASS_WITH_PENDING_AUTHORITY' -and
    [string]$postgresMigration.result -eq 'PASS' -and
    [string]$backend.result -eq 'PASS_DIAGNOSTIC' -and
    ($null -eq $ue -or [string]$ue.result -eq 'PASS')
$report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    result = if ($passed) { 'PASS_DIAGNOSTIC' } else { 'FAIL' }
    authoritative_release_gate = $false
    authority_note = 'Local gates and the locked Clang 21 builder are operational; hosted CI and release-authority supply-chain evidence remain pending.'
    repository = $repository
    secret = $secret
    golden = $golden
    platform_budget = $platformBudget
    p1_execution_charter = $p1Charter
    format_core = $formatCore
    package_v1 = $packageV1
    package_v2 = $packageV2
    package_v3 = $packageV3
    package_pipeline = $packagePipeline
    package_normalized_tree = $packageTree
    legacy_table = $legacyTable
    current_table_investigation = $currentTable
    legacy_to_ue_transform = $legacyToUE
    qtx_texture = $qtxTexture
    sm_static_mesh = $smStaticMesh
    skem_skeletal_mesh = $skemSkeletalMesh
    anim_animation = $animAnimation
    ter_terrain = $terTerrain
    auxiliary_assets = $auxiliaryAssets
    asset_interchange = $assetInterchange
    ue_golden_host = $ueGoldenHost
    ue_importer = $ueImporter
    ue_texture_import = $ueTextureImport
    ue_static_mesh_import = $ueStaticMeshImport
    ue_skeletal_mesh_import = $ueSkeletalMeshImport
    ue_animation_import = $ueAnimationImport
    ue_terrain_import = $ueTerrainImport
    golden_test_matrix = $goldenTestMatrix
    reference_formats = $referenceFormats
    ci_authority_contract = $ciAuthorityContract
    ue_packaging_waiver = $uePackagingWaiver
    backend_toolchain = $toolchain
    backend_static_analysis = $staticAnalysis
    supply_chain = $supplyChain
    postgres_migration = $postgresMigration
    backend_build = $backend
    ue = $ue
}
$json = ($report | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false))
$json
if (-not $passed) { throw 'Local quality gates failed.' }
