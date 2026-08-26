[CmdletBinding()]
param(
    [string]$RebuildRoot = 'E:\QQXYCodeDev\Rebuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RebuildRoot).TrimEnd([char[]]'\/')
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

$requiredFiles = @(
    '.gitignore',
    '.gitattributes',
    '.github/CODEOWNERS',
    '.github/actionlint.yaml',
    '.github/workflows/p0-required-checks.yml',
    '.github/workflows/p0-release-provenance.yml',
    'Apps/UEClient/TMXY.uproject',
    'Apps/UEClient/Source/TMXY.Target.cs',
    'Apps/UEClient/Source/TMXYEditor.Target.cs',
    'Apps/UEClient/Source/TMXYGoldenTests/TMXYGoldenTests.Build.cs',
    'Apps/UEClient/Source/TMXYGoldenTests/Private/TMXYGoldenTestsModule.cpp',
    'Apps/UEClient/Source/TMXYGoldenTests/Private/Tests/TMXYGoldenHostTest.cpp',
    'Apps/UEClient/Scripts/CreateGoldenHostMap.py',
    'Apps/UEClient/Content/TMXY/Golden/Maps/TMXYGoldenTestMap.umap',
    'Apps/UEClient/Content/TMXY/Golden/Textures/T_Golden_MultiMip_DXT1.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Textures/T_Golden_Opaque_DXT1.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Textures/T_Golden_Transparent_DXT5.uasset',
    'Apps/UEClient/Content/TMXY/Golden/StaticMeshes/SM_Golden_Minimum_Real.uasset',
    'Apps/UEClient/Content/TMXY/Golden/StaticMeshes/SM_Golden_MultiSection_Real.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Terrain/SMT_Golden_World_001_001.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Terrain/SMT_Golden_World_001_002.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Terrain/SMT_Golden_World_002_001.uasset',
    'Apps/UEClient/Content/TMXY/Golden/SkeletalMeshes/SK_Golden_Boy01_Default.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Skeletons/SKEL_Golden_Boy01.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Animations/A_Golden_Boy01_RoamIdle.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Animations/A_Golden_Boy01_RunForward.uasset',
    'Apps/UEClient/Content/TMXY/Golden/Animations/A_Golden_Boy01_SelectIdle.uasset',
    'Apps/UEClient/Scripts/CreateTextureGoldenFixtures.ps1',
    'Apps/UEClient/Scripts/CreateStaticMeshGoldenFixtures.ps1',
    'Apps/UEClient/Scripts/CreateSkeletalMeshGoldenFixtures.ps1',
    'Apps/UEClient/Scripts/CreateAnimationGoldenFixtures.ps1',
    'Apps/UEClient/Plugins/TMXYImporter/TMXYImporter.uplugin',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/TMXYImporter.Build.cs',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYImportTypes.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/ITMXYAssetImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYImporterService.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYTextureImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYStaticMeshImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYGltfImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYSkeletalMeshImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYAnimationImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYImporterModule.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYImporterService.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTextureImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYDdsDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYDdsDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYGltfDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYGltfDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYStaticMeshManifest.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYStaticMeshManifest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYStaticMeshImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYGltfImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalGltfDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalGltfDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalMeshManifest.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalMeshManifest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYSkeletalMeshImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimationManifest.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimationManifest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimGltfDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimGltfDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYAnimationImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYImporterTest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYTextureImporterTest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYStaticMeshImporterTest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYSkeletalMeshImporterTest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYAnimationImporterTest.cpp',
    'Apps/UEClient/Scripts/CreateTerrainGoldenFixtures.ps1',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Public/TMXYTerrainImporter.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainImporter.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainManifest.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainManifest.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainDecoder.h',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/TMXYTerrainDecoder.cpp',
    'Apps/UEClient/Plugins/TMXYImporter/Source/TMXYImporter/Private/Tests/TMXYTerrainImporterTest.cpp',
    'Backend/CMakeLists.txt',
    'Backend/CMakePresets.json',
    'Backend/apps/gateway/CMakeLists.txt',
    'Backend/modules/foundation/CMakeLists.txt',
    'Backend/adapters/persistence_postgres/migrations/V0001__runtime_contract.sql',
    'Contracts/proto/tmxy/system/v1/health.proto',
    'Contracts/data-schema/package-tree-v1.schema.json',
    'Data/GoldenSamples/p0-golden-selection.json',
    'Data/GoldenSamples/p0-golden-samples.json',
    'Data/Governance/p0-hosted-ci-contract.json',
    'Data/Governance/p0-github-hosting-status.json',
    'Data/Governance/p1-resourcing.json',
    'Data/BuildBaseline/p0-readiness.json',
    'Data/BuildBaseline/p0-08-ue-packaging-waiver.json',
    'Data/BuildBaseline/p1-01-format-core.json',
    'Data/BuildBaseline/p1-02-package-v1.json',
    'Data/BuildBaseline/p1-03-legacy-table.json',
    'Data/BuildBaseline/p1-04-reference-formats-v0.1.json',
    'Data/BuildBaseline/p1-05-package-v2.json',
    'Data/BuildBaseline/p1-06-package-v3.json',
    'Data/BuildBaseline/p1-07-package-pipeline.json',
    'Data/BuildBaseline/p1-08-package-normalized-tree.json',
    'Data/BuildBaseline/p1-09-current-table-investigation.json',
    'Data/BuildBaseline/p1-12-legacy-to-ue-transform.json',
    'Data/BuildBaseline/p1-13-qtx-texture.json',
    'Data/BuildBaseline/p1-14-sm-static-mesh.json',
    'Data/BuildBaseline/p1-15-skem-skeletal-mesh.json',
    'Data/BuildBaseline/p1-16-anim-animation.json',
    'Data/BuildBaseline/p1-17-ter-terrain.json',
    'Data/BuildBaseline/p1-18-auxiliary-assets.json',
    'Data/BuildBaseline/p1-19-asset-interchange.json',
    'Data/BuildBaseline/p1-20-ue-golden-host.json',
    'Data/BuildBaseline/p1-21-ue-importer-plugin.json',
    'Data/BuildBaseline/p1-22-ue-texture-import.json',
    'Data/BuildBaseline/p1-23-ue-static-mesh-import.json',
    'Data/BuildBaseline/p1-24-ue-skeletal-mesh-import.json',
    'Data/BuildBaseline/p1-25-ue-animation-import.json',
    'Data/BuildBaseline/p1-26-ue-terrain-import.json',
    'Data/BuildBaseline/p1-27-golden-test-matrix.json',
    'Data/GoldenSamples/p1-golden-test-matrix-v1.json',
    'Data/Governance/p1-local-start-waiver.json',
    'Data/Toolchain/backend-toolchain-qualification.json',
    'Data/Toolchain/debian-bookworm-slim-import.json',
    'Data/Security/tmxy-backend-builder.sbom.cdx.json',
    'Data/Performance/p0-platform-budget.json',
    'Data/Security/postgres-18.6.sbom.cdx.json',
    'Data/Security/secret-provider-binding.json',
    'Data/Toolchain/registry-preflight.json',
    'Deploy/compose/compose.yaml',
    'Deploy/toolchain/.dockerignore',
    'Deploy/toolchain/Dockerfile',
    'Deploy/toolchain/conan-requirements.txt',
    'Deploy/secret-contract/secret-contract.json',
    'Docs/Formats/GOLDEN-SAMPLE-BASELINE.md',
    'Docs/Formats/BINARY-READER-BASELINE.md',
    'Docs/Formats/PACKAGE-V1-FORMAT.md',
    'Docs/Formats/PACKAGE-V2-BASELINE.md',
    'Docs/Formats/PACKAGE-V3-BASELINE.md',
    'Docs/Formats/PACKAGE-DIRECTORY-PIPELINE.md',
    'Docs/Formats/PACKAGE-NORMALIZED-TREE.md',
    'Docs/Formats/LEGACY-TBL-BASELINE.md',
    'Docs/Formats/CURRENT-TBL-INVESTIGATION.md',
    'Docs/Formats/LEGACY-TO-UE-TRANSFORM.md',
    'Docs/Formats/REFERENCE-FORMATS-V0.1.md',
    'Docs/Testing/UE-GOLDEN-TEXTURE-IMPORT.md',
    'Docs/Testing/UE-GOLDEN-STATIC-MESH-IMPORT.md',
    'Docs/Testing/UE-GOLDEN-SKELETAL-MESH-IMPORT.md',
    'Docs/Testing/UE-GOLDEN-ANIMATION-IMPORT.md',
    'Docs/Testing/UE-GOLDEN-TERRAIN-IMPORT.md',
    'Contracts/data-schema/ue-terrain-import-report-v1.schema.json',
    'Contracts/data-schema/golden-test-matrix-v1.schema.json',
    'Docs/Testing/GOLDEN-TEST-MATRIX.md',
    'Docs/Build/CI-QUALITY-GATES.md',
    'Docs/Build/HOSTED-CI-AUTHORITY.md',
    'Docs/Build/MSVC-14.51-WAIVER.md',
    'Docs/Governance/VERSION-CONTROL-POLICY.md',
    'Docs/Governance/P0-READINESS-REVIEW.md',
    'Docs/Governance/P1-EXECUTION-CHARTER.md',
    'Docs/Waivers/WVR-0001-p1-local-start-before-g0.md',
    'Docs/Database/MIGRATION-BASELINE.md',
    'Docs/Performance/TARGET-PLATFORM-BUDGET.md',
    'Docs/ADR/ADR-003-legacy-to-ue-transform.md',
    'Docs/Security/SECRET-MANAGEMENT.md',
    'Tests/Contract/Test-SecretPolicy.ps1',
    'Tests/Contract/Test-GoldenSampleBaseline.ps1',
    'Tests/Contract/Test-FormatCoreBaseline.ps1',
    'Tests/Contract/Test-PackageV1Baseline.ps1',
    'Tests/Contract/Test-PackageV2Baseline.ps1',
    'Tests/Contract/Test-PackageV3Baseline.ps1',
    'Tests/Contract/Test-PackagePipelineBaseline.ps1',
    'Tests/Contract/Test-PackageNormalizedTree.ps1',
    'Tests/Contract/Test-LegacyTableBaseline.ps1',
    'Tests/Contract/Test-CurrentTableInvestigation.ps1',
    'Tests/Contract/Test-LegacyToUETransform.ps1',
    'Tests/Contract/Test-ReferenceFormatDocs.ps1',
    'Tests/Contract/Test-CIAuthorityContract.ps1',
    'Tests/Contract/Test-PlatformBudget.ps1',
    'Tests/Contract/Test-P1ExecutionCharter.ps1',
    'Tests/Contract/Test-UEPackagingWaiver.ps1',
    'Tests/Contract/Test-UETextureImport.ps1',
    'Tests/Contract/Test-UEStaticMeshImport.ps1',
    'Tests/Contract/Test-UESkeletalMeshImport.ps1',
    'Tests/Contract/Test-UEAnimationImport.ps1',
    'Tests/Contract/Test-UETerrainImport.ps1',
    'Tests/Contract/Test-GoldenTestMatrix.ps1',
    'Tests/CI/Invoke-LocalQualityGates.ps1',
    'Tests/CI/Test-HostedPullRequestPolicy.ps1',
    'Tests/CI/Test-HostedSupplyChainPolicy.ps1',
    'Tests/CI/Test-HostedWorkflowContract.ps1',
    'Tests/Quality/Test-BackendStaticAnalysis.ps1',
    'Tests/Review/New-P0ReadinessReport.ps1',
    'Tests/Integration/Test-PostgresMigration.ps1',
    'Tests/Integration/Test-UEPackagingQualification.ps1',
    'Tools/TMXY.Toolchain/Build-BackendToolchain.ps1',
    'Tools/CMakeLists.txt',
    'Tools/CMakePresets.json',
    'Tools/TMXY.FormatCore/CMakeLists.txt',
    'Tools/TMXY.FormatCore/include/tmxy/format/binary_reader.hpp',
    'Tools/TMXY.FormatCore/tests/binary_reader_test.cpp',
    'Tools/TMXY.Package/CMakeLists.txt',
    'Tools/TMXY.Package/include/tmxy/package/package_directory_codec.hpp',
    'Tools/TMXY.Package/include/tmxy/package/package_normalized_tree.hpp',
    'Tools/TMXY.Package/include/tmxy/package/package_v1.hpp',
    'Tools/TMXY.Package/include/tmxy/package/package_v1_reader.hpp',
    'Tools/TMXY.Package/tests/package_v1_reader_test.cpp',
    'Tools/TMXY.Package/include/tmxy/package/package_v2.hpp',
    'Tools/TMXY.Package/include/tmxy/package/package_v2_reader.hpp',
    'Tools/TMXY.Package/tests/package_v2_reader_test.cpp',
    'Tools/TMXY.Package/include/tmxy/package/package_v3.hpp',
    'Tools/TMXY.Package/include/tmxy/package/package_v3_reader.hpp',
    'Tools/TMXY.Package/tests/package_v3_reader_test.cpp',
    'Tools/TMXY.Package/tests/package_directory_codec_test.cpp',
    'Tools/TMXY.Package/tests/package_normalized_tree_test.cpp',
    'Tools/TMXY.Package/apps/package_tree_export_main.cpp',
    'Tools/TMXY.Table/CMakeLists.txt',
    'Tools/TMXY.Table/include/tmxy/table/legacy_table.hpp',
    'Tools/TMXY.Table/include/tmxy/table/legacy_table_reader.hpp',
    'Tools/TMXY.Table/tests/legacy_table_reader_test.cpp',
    'Tools/TMXY.Transform/CMakeLists.txt',
    'Tools/TMXY.Transform/include/tmxy/transform/legacy_to_ue_transform.hpp',
    'Tools/TMXY.Transform/include/tmxy/transform/transform_error.hpp',
    'Tools/TMXY.Transform/tests/legacy_to_ue_transform_test.cpp',
    'Tools/TMXY.Texture/CMakeLists.txt',
    'Tools/TMXY.Texture/include/tmxy/texture/package_texture_reader.hpp',
    'Tools/TMXY.Texture/include/tmxy/texture/qtx_reader.hpp',
    'Tools/TMXY.Texture/include/tmxy/texture/texture_export.hpp',
    'Tools/TMXY.Texture/apps/qtx_export_main.cpp',
    'Tools/TMXY.Texture/tests/texture_parser_test.cpp',
    'Tools/TMXY.Texture/tests/qtx_real_samples_test.cpp',
    'Tests/Contract/Test-QtxTexture.ps1',
    'Docs/Formats/QTX-FORMAT.md',
    'Docs/ADR/ADR-004-qtx-texture-intermediate.md',
    'Tools/TMXY.StaticMesh/CMakeLists.txt',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/package_static_mesh_reader.hpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/sm_reader.hpp',
    'Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_export.hpp',
    'Tools/TMXY.StaticMesh/apps/sm_export_main.cpp',
    'Tools/TMXY.StaticMesh/tests/static_mesh_parser_test.cpp',
    'Tools/TMXY.StaticMesh/tests/sm_real_samples_test.cpp',
    'Tests/Contract/Test-SmStaticMesh.ps1',
    'Docs/Formats/SM-FORMAT.md',
    'Docs/ADR/ADR-005-sm-static-mesh-intermediate.md',
    'Tools/TMXY.SkeletalMesh/CMakeLists.txt',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/skem_reader.hpp',
    'Tools/TMXY.SkeletalMesh/include/tmxy/skeletal_mesh/skeletal_mesh_export.hpp',
    'Tools/TMXY.SkeletalMesh/apps/skem_export_main.cpp',
    'Tools/TMXY.SkeletalMesh/tests/skeletal_mesh_parser_test.cpp',
    'Tools/TMXY.SkeletalMesh/tests/skem_real_samples_test.cpp',
    'Tests/Contract/Test-SkemSkeletalMesh.ps1',
    'Docs/Formats/SKEM-FORMAT.md',
    'Docs/ADR/ADR-006-skem-skeletal-mesh-intermediate.md',
    'Tools/TMXY.Animation/CMakeLists.txt',
    'Tools/TMXY.Animation/include/tmxy/animation/anim_reader.hpp',
    'Tools/TMXY.Animation/include/tmxy/animation/package_animation_reader.hpp',
    'Tools/TMXY.Animation/include/tmxy/animation/animation_export.hpp',
    'Tools/TMXY.Animation/include/tmxy/animation/animation_gltf.hpp',
    'Tools/TMXY.Animation/apps/anim_export_main.cpp',
    'Tools/TMXY.Animation/apps/anim_gltf_export_main.cpp',
    'Tools/TMXY.Animation/tests/animation_parser_test.cpp',
    'Tools/TMXY.Animation/tests/anim_real_samples_test.cpp',
    'Tests/Contract/Test-AnimAnimation.ps1',
    'Docs/Formats/ANIM-FORMAT.md',
    'Docs/ADR/ADR-007-anim-animation-intermediate.md',
    'Tools/TMXY.Terrain/CMakeLists.txt',
    'Tools/TMXY.Terrain/include/tmxy/terrain/ter_reader.hpp',
    'Tools/TMXY.Terrain/include/tmxy/terrain/terrain_export.hpp',
    'Tools/TMXY.Terrain/apps/ter_export_main.cpp',
    'Tools/TMXY.Terrain/tests/terrain_parser_test.cpp',
    'Tools/TMXY.Terrain/tests/ter_real_samples_test.cpp',
    'Tests/Contract/Test-TerTerrain.ps1',
    'Docs/Formats/TER-FORMAT.md',
    'Docs/ADR/ADR-014-ter-terrain-intermediate.md',
    'Docs/Formats/AUXILIARY-ASSET-INVESTIGATION.md',
    'Tests/Contract/Test-AuxiliaryAssetInvestigation.ps1',
    'Contracts/data-schema/asset-interchange-v1.schema.json',
    'Contracts/interchange/format-registry-v1.json',
    'Contracts/examples/asset-interchange-v1.example.json',
    'Docs/Formats/ASSET-INTERCHANGE-V1.md',
    'Docs/ADR/ADR-015-versioned-asset-interchange.md',
    'Tests/Contract/Test-AssetInterchangeContract.ps1',
    'Contracts/data-schema/ue-golden-import-report-v1.schema.json',
    'Contracts/data-schema/ue-static-mesh-import-report-v1.schema.json',
    'Contracts/data-schema/ue-skeletal-mesh-import-report-v1.schema.json',
    'Contracts/data-schema/ue-animation-import-report-v1.schema.json',
    'Contracts/examples/ue-golden-import-report-v1.example.json',
    'Docs/Testing/UE-GOLDEN-HOST.md',
    'Tests/Contract/Test-UEGoldenHost.ps1',
    'Docs/Testing/UE-IMPORTER-PLUGIN.md',
    'Tests/Contract/Test-UEImporterPlugin.ps1',
    'Tools/TMXY.Toolchain/Import-OfficialDebianBase.ps1',
    'Tools/TMXY.Toolchain/fetch_official_oci.py',
    'Tools/TMXY.GoldenSamples/New-GoldenSampleBaseline.ps1',
    'Tools/TMXY.Security/Test-RepositorySecrets.ps1',
    'Tools/TMXY.Security/Test-SecretStoreRotation.ps1',
    'Tools/TMXY.SupplyChain/Test-LocalImageEvidence.ps1',
    'Tools/TMXY.GitHub/Get-GitHubHostedCIStatus.ps1',
    'Tools/TMXY.GitHub/README.md',
    'Tools/TMXY.Toolchain/Test-RegistryPreflight.ps1'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure -Message "Required project file is missing: $relativePath"
    }
}

$repositoryMetadata = Join-Path $root '.git'
if (-not (Test-Path -LiteralPath $repositoryMetadata)) {
    Add-Failure -Message 'Rebuild must be an initialized Git repository.'
}

$workspaceRoot = Split-Path -Parent $root
if (Test-Path -LiteralPath (Join-Path $workspaceRoot '.git')) {
    Add-Failure -Message 'The workspace parent must not be a Git repository; legacy inputs would enter scope.'
}

$gitCommand = Get-Command 'git.exe' -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) {
    Add-Failure -Message 'Git is required to validate the repository boundary.'
}
elseif (Test-Path -LiteralPath $repositoryMetadata) {
    $gitRoot = (& $gitCommand.Source -C $root rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [System.IO.Path]::GetFullPath($gitRoot) -ne $root) {
        Add-Failure -Message "Git root must resolve exactly to $root."
    }
    $branch = (& $gitCommand.Source -C $root branch --show-current 2>$null).Trim()
    if ([string]::IsNullOrWhiteSpace($branch) -and $env:GITHUB_ACTIONS -eq 'true') {
        $branch = if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_HEAD_REF)) {
            $env:GITHUB_HEAD_REF
        }
        else { $env:GITHUB_REF_NAME }
    }
    $validBranch = $branch -eq 'main' -or
        $branch -match '^(?:feature|fix|docs|build|chore|hotfix)/[a-z0-9][a-z0-9-]*$'
    if ($LASTEXITCODE -ne 0 -or -not $validBranch) {
        Add-Failure -Message "Current branch does not follow the protected integration/development naming policy: $branch"
    }
}

$gitIgnorePath = Join-Path $root '.gitignore'
if (Test-Path -LiteralPath $gitIgnorePath -PathType Leaf) {
    $gitIgnore = Get-Content -LiteralPath $gitIgnorePath -Raw
    $requiredIgnoreRules = @(
        'Binaries/',
        'Intermediate/',
        'Saved/',
        'DerivedDataCache/',
        '.vs/',
        '*.sln',
        '*.slnx',
        'CMakeFiles/',
        'CMakeCache.txt',
        'CMakeUserPresets.json',
        'Data/Extracted/',
        'Data/Exports/',
        'Data/RawPackages/'
    )
    foreach ($rule in $requiredIgnoreRules) {
        if ($gitIgnore -notmatch "(?m)^$([regex]::Escape($rule))$") {
            Add-Failure -Message "Required .gitignore rule is missing: $rule"
        }
    }
}

$gitAttributesPath = Join-Path $root '.gitattributes'
if (Test-Path -LiteralPath $gitAttributesPath -PathType Leaf) {
    $gitAttributes = Get-Content -LiteralPath $gitAttributesPath -Raw
    $requiredAttributeRules = @(
        '* text=auto eol=lf',
        '*.uasset filter=lfs diff=lfs merge=lfs -text',
        '*.umap filter=lfs diff=lfs merge=lfs -text'
    )
    foreach ($rule in $requiredAttributeRules) {
        if ($gitAttributes -notmatch "(?m)^$([regex]::Escape($rule))$") {
            Add-Failure -Message "Required .gitattributes rule is missing: $rule"
        }
    }
    foreach ($forbiddenExtension in @('pak', 'qtx', 'sm', 'skem', 'anim', 'ter', 'zif', 'tbl')) {
        if ($gitAttributes -match "(?im)^\s*\*\.$forbiddenExtension\s+.*filter=lfs") {
            Add-Failure -Message "Raw or bulk format must not be routed to Git LFS: *.$forbiddenExtension"
        }
    }
}

$checkedTextFiles = 0
if ($null -ne $gitCommand -and (Test-Path -LiteralPath $repositoryMetadata)) {
    $candidateFiles = @(& $gitCommand.Source -C $root ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        Add-Failure -Message 'Git could not enumerate repository candidate files.'
    }
    else {
        $textExtensions = @(
            '.c', '.cc', '.cmake', '.cpp', '.cs', '.editorconfig', '.gitattributes',
            '.gitignore', '.h', '.hpp', '.ini', '.json', '.jsonl', '.md', '.proto',
            '.ps1', '.py', '.sql', '.txt', '.uplugin', '.uproject', '.yaml', '.yml'
        )
        $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
        foreach ($relativePath in $candidateFiles) {
            $path = Join-Path $root $relativePath
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $name = [System.IO.Path]::GetFileName($path)
            $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
            $isText = $textExtensions -contains $extension -or
                $name -in @('CMakeLists.txt', '.clang-format', '.clang-tidy',
                    '.dockerignore', 'Dockerfile')
            if (-not $isText) { continue }

            $checkedTextFiles++
            $bytes = [System.IO.File]::ReadAllBytes($path)
            try {
                $null = $strictUtf8.GetString($bytes)
            }
            catch {
                Add-Failure -Message "Text file is not valid UTF-8: $relativePath"
            }
            if ([Array]::IndexOf($bytes, [byte]13) -ge 0) {
                Add-Failure -Message "Text file contains CR/CRLF instead of LF: $relativePath"
            }
        }
    }
}

$scanRoots = @('Apps', 'Backend', 'Contracts', 'Deploy', 'Tools') | ForEach-Object { Join-Path $root $_ }
$generatedDirectoryPattern = '[\\/](?:Binaries|DerivedDataCache|Intermediate|Saved|\.vs|generated)[\\/]'
$sourceFiles = @(
    Get-ChildItem -LiteralPath $scanRoots -Recurse -File |
        Where-Object {
            $_.FullName -notmatch $generatedDirectoryPattern -and
            ($_.Name -eq 'CMakeLists.txt' -or
            $_.Extension -in @('.cmake', '.cpp', '.cs', '.h', '.hpp', '.proto', '.py', '.uplugin', '.uproject', '.yaml', '.yml'))
        }
)

$legacyReferencePattern = '(?i)(ClientCode|ServerCode|ToolCode|QQXYClient|QQXYServer|QQXYTools)'
foreach ($file in $sourceFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -match $legacyReferencePattern) {
        Add-Failure -Message "Legacy source reference found in $($file.FullName)"
    }
}

$foundationRoot = Join-Path $root 'Backend\modules\foundation'
$foundationFiles = @(Get-ChildItem -LiteralPath $foundationRoot -Recurse -File -Include '*.cpp', '*.hpp')
$forbiddenFoundationInclude = '(?im)^\s*#\s*include\s*[<"](?:windows\.h|libpq-fe\.h|asio(?:\.hpp|/)|google/protobuf|CoreMinimal\.h)'
foreach ($file in $foundationFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -match $forbiddenFoundationInclude) {
        Add-Failure -Message "Forbidden Foundation dependency found in $($file.FullName)"
    }
}

$lineLimits = @{
    '.h' = 500
    '.hpp' = 500
    '.cpp' = 1000
    '.cs' = 500
    '.cmake' = 500
    '.ps1' = 1000
    '.sql' = 1000
    '.proto' = 500
    '.py' = 500
    '.uplugin' = 500
    '.yaml' = 500
    '.yml' = 500
}
$limitFiles = @(
    Get-ChildItem -LiteralPath @(
        (Join-Path $root 'Apps'),
        (Join-Path $root 'Backend'),
        (Join-Path $root 'Contracts'),
        (Join-Path $root 'Deploy'),
        (Join-Path $root 'Docs'),
        (Join-Path $root 'Tests'),
        (Join-Path $root 'Tools')
    ) -Recurse -File |
        Where-Object { $_.FullName -notmatch $generatedDirectoryPattern }
)
foreach ($file in $limitFiles) {
    $extension = if ($file.Name -eq 'CMakeLists.txt') { '.cmake' } else { $file.Extension.ToLowerInvariant() }
    if (-not $lineLimits.ContainsKey($extension)) { continue }
    $lineCount = @(Get-Content -LiteralPath $file.FullName).Count
    if ($lineCount -gt $lineLimits[$extension]) {
        Add-Failure -Message "$($file.FullName) has $lineCount lines; hard limit is $($lineLimits[$extension])."
    }
}

$ueProjectPath = Join-Path $root 'Apps\UEClient\TMXY.uproject'
if (Test-Path -LiteralPath $ueProjectPath -PathType Leaf) {
    $ueProject = Get-Content -LiteralPath $ueProjectPath -Raw | ConvertFrom-Json
    if ([string]$ueProject.EngineAssociation -ne '5.8') {
        Add-Failure -Message 'TMXY.uproject is not associated with Unreal Engine 5.8.'
    }
    $moduleNames = @($ueProject.Modules | ForEach-Object { [string]$_.Name })
    foreach ($requiredModule in @('TMXYCore', 'TMXYClient', 'TMXYGoldenTests')) {
        if ($moduleNames -notcontains $requiredModule) {
            Add-Failure -Message "TMXY.uproject is missing module $requiredModule."
        }
    }
    $goldenModule = @($ueProject.Modules | Where-Object { [string]$_.Name -eq 'TMXYGoldenTests' })
    if ($goldenModule.Count -ne 1 -or [string]$goldenModule[0].Type -ne 'Editor' -or
        [string]$goldenModule[0].LoadingPhase -ne 'PostEngineInit') {
        Add-Failure -Message 'TMXYGoldenTests must be an Editor/PostEngineInit module.'
    }
    $androidFileServer = @($ueProject.Plugins | Where-Object { [string]$_.Name -eq 'AndroidFileServer' })
    if ($androidFileServer.Count -ne 1 -or [bool]$androidFileServer[0].Enabled) {
        Add-Failure -Message 'AndroidFileServer must be explicitly disabled in the source project descriptor.'
    }
    $importerPlugin = @($ueProject.Plugins | Where-Object { [string]$_.Name -eq 'TMXYImporter' })
    $importerDescriptorPath = Join-Path $root 'Apps\UEClient\Plugins\TMXYImporter\TMXYImporter.uplugin'
    if ($importerPlugin.Count -ne 1 -or -not [bool]$importerPlugin[0].Enabled -or
        -not (Test-Path -LiteralPath $importerDescriptorPath -PathType Leaf)) {
        Add-Failure -Message 'TMXYImporter must be explicitly enabled from its project plugin descriptor.'
    }
    else {
        $importerDescriptor = Get-Content -LiteralPath $importerDescriptorPath -Raw | ConvertFrom-Json
        $importerModules = @($importerDescriptor.Modules | Where-Object Name -eq 'TMXYImporter')
        if ($importerModules.Count -ne 1 -or [string]$importerModules[0].Type -ne 'Editor' -or
            [string]$importerModules[0].LoadingPhase -ne 'PostEngineInit' -or
            [bool]$importerDescriptor.CanContainContent) {
            Add-Failure -Message 'TMXYImporter plugin must be content-free and Editor/PostEngineInit only.'
        }
    }
    if ($moduleNames -contains 'TMXYImporter') {
        Add-Failure -Message 'TMXYImporter must remain a plugin module, not a project runtime module.'
    }
}

$ueConfigRoot = Join-Path $root 'Apps\UEClient\Config'
$ueConfigFiles = @(Get-ChildItem -LiteralPath $ueConfigRoot -Recurse -File -ErrorAction SilentlyContinue)
foreach ($file in $ueConfigFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -match '(?im)^\s*(?:SecurityToken|ApiKey|Password|PrivateKey)\s*=\s*\S+') {
        Add-Failure -Message "Possible embedded Secret found in $($file.FullName)"
    }
}

$composePath = Join-Path $root 'Deploy\compose\compose.yaml'
if (Test-Path -LiteralPath $composePath -PathType Leaf) {
    $compose = Get-Content -LiteralPath $composePath -Raw
    if ($compose -notmatch 'image:\s+postgres@sha256:[a-f0-9]{64}') {
        Add-Failure -Message 'Compose PostgreSQL image is not locked by digest.'
    }
    if ($compose -notmatch 'POSTGRES_PASSWORD_FILE:\s*/run/secrets/tmxy_postgres_password' -or
        $compose -notmatch '\$\{TMXY_POSTGRES_PASSWORD_FILE:\?') {
        Add-Failure -Message 'Compose does not require a file-mounted PostgreSQL Secret.'
    }
}

$secretScanPath = Join-Path $root 'Tools\TMXY.Security\Test-RepositorySecrets.ps1'
if (Test-Path -LiteralPath $secretScanPath -PathType Leaf) {
    $secretScan = (& $secretScanPath -ScanRoot $root) | ConvertFrom-Json
    if ([string]$secretScan.result -ne 'PASS') {
        Add-Failure -Message "Repository Secret scan failed with $($secretScan.finding_count) finding(s)."
    }
}

$report = [pscustomobject][ordered]@{
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    checked_source_files = $sourceFiles.Count
    checked_size_files = $limitFiles.Count
    checked_utf8_lf_files = $checkedTextFiles
    failure_count = $failures.Count
    failures = @($failures)
}
$report | ConvertTo-Json -Depth 4

if ($failures.Count -gt 0) {
    throw "Repository layout validation failed with $($failures.Count) error(s)."
}
