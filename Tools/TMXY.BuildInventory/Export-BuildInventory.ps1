[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\QQXYCodeDev',
    [string]$OutputDirectory = 'E:\QQXYCodeDev\Rebuild\Data\BuildInventory'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$sourceRootNames = @('ClientCode', 'ServerCode', 'ToolCode')
$binaryExtensions = @('.lib', '.dll', '.tlb')
$systemLibraries = @(
    'advapi32.lib', 'comctl32.lib', 'comdlg32.lib', 'd3d9.lib', 'd3dx9.lib',
    'delayimp.lib', 'dinput8.lib', 'dxerr.lib', 'dxguid.lib', 'gdi32.lib',
    'glu32.lib', 'imm32.lib', 'kernel32.lib', 'msimg32.lib', 'msxml2.lib',
    'odbc32.lib', 'odbccp32.lib', 'ole32.lib', 'oleaut32.lib', 'opengl32.lib',
    'rpcrt4.lib', 'shell32.lib', 'shlwapi.lib', 'strmiids.lib', 'urlmon.lib',
    'user32.lib', 'uuid.lib', 'version.lib', 'vfw32.lib', 'wininet.lib',
    'winmm.lib', 'winspool.lib', 'ws2_32.lib'
)
$legacyToolsetLibraries = @('comsupp.lib', 'comsuppd.lib', 'comsuppw.lib', 'comsuppwd.lib')

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
}

function Get-RelativeSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootPrefix = $Root.TrimEnd([char[]]'\/') + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped source root: $fullPath"
    }
    return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
}

function Get-ProjectEra {
    param([string]$Version)
    $normalized = $Version.Replace(',', '.')
    switch ($normalized) {
        '7.10' { return 'Visual Studio .NET 2003' }
        '8.00' { return 'Visual Studio 2005' }
        '9.00' { return 'Visual Studio 2008' }
        default { return "Unknown ($Version)" }
    }
}

function Get-SolutionEra {
    param([string]$FormatVersion)
    switch ($FormatVersion) {
        '8.00' { return 'Visual Studio .NET 2003' }
        '9.00' { return 'Visual Studio 2005' }
        '10.00' { return 'Visual Studio 2008' }
        default { return "Unknown ($FormatVersion)" }
    }
}

function Get-SourceClassification {
    param(
        [Parameter(Mandatory = $true)][string]$RootName,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ($RootName -eq 'ToolCode' -and $RelativePath -match '(?i)(^|/)(max8sdk|max9sdk|3ds max 2010 sdk)(/|$)') {
        return 'VendoredSdkSample'
    }

    if ($RootName -eq 'ClientCode' -and $RelativePath -match '(?i)(^|/)(dx9sdk|freetype[^/]*|lua[^/]*|tinyxml)(/|$)') {
        return 'ThirdPartySource'
    }

    if ($RootName -eq 'ServerCode' -and $RelativePath -match '(?i)(^|/)(ace|freetype[^/]*|lua|tinyxml|protocalbuffer|protobuf|gtest)(/|$)') {
        return 'ThirdPartySource'
    }

    return 'FirstParty'
}

function Split-ProjectList {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @(
        $Value -split '[;,]' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Get-XmlAttribute {
    param(
        [AllowNull()][object]$Node,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $Node -or $Node -isnot [System.Xml.XmlElement]) {
        return ''
    }
    return $Node.GetAttribute($Name)
}

function Get-LibraryTokens {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    $tokens = New-Object 'System.Collections.Generic.List[string]'
    $matches = [regex]::Matches($Value, '(?i)(?:"([^"]+\.lib)"|([^\s;,"]+\.lib))')
    foreach ($match in $matches) {
        $token = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
        $tokens.Add($token.Replace('\', '/'))
    }
    return @($tokens | Sort-Object -Unique)
}

function Read-VcProject {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$RootName,
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $parseError = $null
    $xml = $null
    try {
        $xml = [xml](Get-Content -LiteralPath $File.FullName -Raw)
    }
    catch {
        $parseError = $_.Exception.Message
    }

    $relativePath = Get-RelativeSourcePath -Root $RootPath -Path $File.FullName
    $base = [ordered]@{
        root = $RootName
        path = $relativePath
        kind = 'vcproj'
        classification = Get-SourceClassification -RootName $RootName -RelativePath $relativePath
        sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        parse_error = $parseError
    }
    if ($null -eq $xml) {
        return [pscustomobject]$base
    }

    $project = $xml.VisualStudioProject
    $configurations = @($project.Configurations.Configuration)
    $configurationRecords = New-Object 'System.Collections.Generic.List[object]'
    $allLibraries = New-Object 'System.Collections.Generic.List[string]'
    $allIncludes = New-Object 'System.Collections.Generic.List[string]'
    $allLibraryDirectories = New-Object 'System.Collections.Generic.List[string]'
    $allOutputs = New-Object 'System.Collections.Generic.List[string]'
    $platforms = New-Object 'System.Collections.Generic.List[string]'

    foreach ($configuration in $configurations) {
        if ($null -eq $configuration) { continue }
        $configurationName = Get-XmlAttribute -Node $configuration -Name 'Name'
        $platform = if ($configurationName -match '\|') { ($configurationName -split '\|', 2)[1] } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($platform)) { $platforms.Add($platform) }

        $compiler = @($configuration.Tool | Where-Object { $_.Name -eq 'VCCLCompilerTool' } | Select-Object -First 1)
        $linker = @($configuration.Tool | Where-Object { $_.Name -eq 'VCLinkerTool' } | Select-Object -First 1)
        $librarian = @($configuration.Tool | Where-Object { $_.Name -eq 'VCLibrarianTool' } | Select-Object -First 1)
        $compilerNode = if ($compiler.Count -gt 0) { $compiler[0] } else { $null }
        $linkerNode = if ($linker.Count -gt 0) { $linker[0] } else { $null }
        $librarianNode = if ($librarian.Count -gt 0) { $librarian[0] } else { $null }

        $dependencyText = Get-XmlAttribute -Node $linkerNode -Name 'AdditionalDependencies'
        $libraries = @(Get-LibraryTokens -Value $dependencyText)
        foreach ($library in $libraries) { $allLibraries.Add($library) }

        $includeDirectories = @(Split-ProjectList -Value (Get-XmlAttribute -Node $compilerNode -Name 'AdditionalIncludeDirectories'))
        foreach ($includeDirectory in $includeDirectories) { $allIncludes.Add($includeDirectory) }

        $libraryDirectories = @(Split-ProjectList -Value (Get-XmlAttribute -Node $linkerNode -Name 'AdditionalLibraryDirectories'))
        foreach ($libraryDirectory in $libraryDirectories) { $allLibraryDirectories.Add($libraryDirectory) }

        $outputs = @()
        if ($null -ne $linkerNode) {
            $outputs += Get-XmlAttribute -Node $linkerNode -Name 'OutputFile'
            $outputs += Get-XmlAttribute -Node $linkerNode -Name 'ImportLibrary'
        }
        if ($null -ne $librarianNode) {
            $outputs += Get-XmlAttribute -Node $librarianNode -Name 'OutputFile'
        }
        $outputs = @($outputs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        foreach ($output in $outputs) { $allOutputs.Add($output.Replace('\', '/')) }

        $configurationRecords.Add([pscustomobject][ordered]@{
            name = $configurationName
            platform = $platform
            configuration_type = Get-XmlAttribute -Node $configuration -Name 'ConfigurationType'
            output_directory = (Get-XmlAttribute -Node $configuration -Name 'OutputDirectory').Replace('\', '/')
            intermediate_directory = (Get-XmlAttribute -Node $configuration -Name 'IntermediateDirectory').Replace('\', '/')
            use_of_mfc = Get-XmlAttribute -Node $configuration -Name 'UseOfMFC'
            character_set = Get-XmlAttribute -Node $configuration -Name 'CharacterSet'
            include_directories = $includeDirectories
            library_directories = $libraryDirectories
            link_libraries = $libraries
            declared_outputs = $outputs
        })
    }

    $base.name = Get-XmlAttribute -Node $project -Name 'Name'
    $base.project_guid = Get-XmlAttribute -Node $project -Name 'ProjectGUID'
    $base.project_version = Get-XmlAttribute -Node $project -Name 'Version'
    $base.toolchain_era = Get-ProjectEra -Version (Get-XmlAttribute -Node $project -Name 'Version')
    $base.keyword = Get-XmlAttribute -Node $project -Name 'Keyword'
    $base.platforms = @($platforms | Sort-Object -Unique)
    $base.configuration_names = @($configurationRecords | ForEach-Object { $_.name })
    $base.include_directories = @($allIncludes | Sort-Object -Unique)
    $base.library_directories = @($allLibraryDirectories | Sort-Object -Unique)
    $base.link_libraries = @($allLibraries | Sort-Object -Unique)
    $base.declared_outputs = @($allOutputs | Sort-Object -Unique)
    $base.configurations = $configurationRecords.ToArray()
    return [pscustomobject]$base
}

function Read-CsProject {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$RootName,
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $raw = Get-Content -LiteralPath $File.FullName -Raw
    $relativePath = Get-RelativeSourcePath -Root $RootPath -Path $File.FullName
    $toolsVersion = if ($raw -match 'ToolsVersion="([^"]+)"') { $Matches[1] } else { '' }
    $targetFramework = if ($raw -match '<TargetFrameworkVersion>([^<]+)</TargetFrameworkVersion>') { $Matches[1] } else { '' }
    $projectTypeGuids = if ($raw -match '<ProjectTypeGuids>([^<]+)</ProjectTypeGuids>') { $Matches[1] } else { '' }

    return [pscustomobject][ordered]@{
        root = $RootName
        path = $relativePath
        kind = 'csproj'
        classification = Get-SourceClassification -RootName $RootName -RelativePath $relativePath
        sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        tools_version = $toolsVersion
        target_framework = $targetFramework
        project_type_guids = $projectTypeGuids
    }
}

function Read-Solution {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$RootName,
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $raw = Get-Content -LiteralPath $File.FullName -Raw
    $formatVersion = if ($raw -match 'Microsoft Visual Studio Solution File, Format Version\s+([^\r\n]+)') { $Matches[1].Trim() } else { '' }
    $projects = New-Object 'System.Collections.Generic.List[object]'
    $matches = [regex]::Matches($raw, '(?m)^Project\("\{[^}]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)",\s*"\{([^}]+)\}"')
    foreach ($match in $matches) {
        $projects.Add([pscustomobject][ordered]@{
            name = $match.Groups[1].Value
            path = $match.Groups[2].Value.Replace('\', '/')
            guid = $match.Groups[3].Value
        })
    }

    $relativePath = Get-RelativeSourcePath -Root $RootPath -Path $File.FullName
    return [pscustomobject][ordered]@{
        root = $RootName
        path = $relativePath
        classification = Get-SourceClassification -RootName $RootName -RelativePath $relativePath
        sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        format_version = $formatVersion
        toolchain_era = Get-SolutionEra -FormatVersion $formatVersion
        project_count = $projects.Count
        projects = $projects.ToArray()
    }
}

function Get-InstalledEnvironment {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRootPath)

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $visualStudio = @()
    if (Test-Path -LiteralPath $vswhere) {
        $vsJson = & $vswhere -all -products * -format json -utf8
        if (-not [string]::IsNullOrWhiteSpace(($vsJson -join ''))) {
            $visualStudio = @($vsJson -join "`n" | ConvertFrom-Json)
        }
    }

    $vsRecords = @(
        foreach ($instance in $visualStudio) {
            $msvcRoot = Join-Path ([string]$instance.installationPath) 'VC\Tools\MSVC'
            $msvcVersions = if (Test-Path -LiteralPath $msvcRoot) {
                @(Get-ChildItem -LiteralPath $msvcRoot -Directory | Select-Object -ExpandProperty Name | Sort-Object)
            } else { @() }
            [pscustomobject][ordered]@{
                display_name = [string]$instance.displayName
                version = [string]$instance.installationVersion
                path = [string]$instance.installationPath
                msvc_versions = $msvcVersions
                msbuild_path = (Join-Path ([string]$instance.installationPath) 'MSBuild\Current\Bin\MSBuild.exe')
            }
        }
    )

    $windowsKitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
    $windowsSdkVersions = if (Test-Path -LiteralPath (Join-Path $windowsKitsRoot 'Include')) {
        @(Get-ChildItem -LiteralPath (Join-Path $windowsKitsRoot 'Include') -Directory | Select-Object -ExpandProperty Name | Sort-Object)
    } else { @() }

    $ueRoot = 'C:\Program Files\Epic Games\UE_5.8'
    $ueBuildFile = Join-Path $ueRoot 'Engine\Build\Build.version'
    $ueBuild = $null
    if (Test-Path -LiteralPath $ueBuildFile) {
        $ueBuild = Get-Content -LiteralPath $ueBuildFile -Raw | ConvertFrom-Json
    }

    $pathCommands = [ordered]@{}
    foreach ($commandName in @('cl.exe', 'msbuild.exe', 'cmake.exe', 'ninja.exe', 'git.exe', 'dotnet.exe')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        $pathCommands[$commandName] = if ($null -ne $command) { [string]$command.Source } else { $null }
    }

    $dotnetVersion = $null
    if ($null -ne $pathCommands['dotnet.exe']) {
        $dotnetVersion = (& $pathCommands['dotnet.exe'] --version 2>$null | Select-Object -First 1)
    }

    return [pscustomobject][ordered]@{
        captured_utc = [DateTime]::UtcNow.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        computer_name = [Environment]::MachineName
        os_version = [Environment]::OSVersion.VersionString
        powershell_version = $PSVersionTable.PSVersion.ToString()
        visual_studio = $vsRecords
        windows_sdk_versions = $windowsSdkVersions
        unreal_engine = if ($null -ne $ueBuild) {
            [pscustomobject][ordered]@{
                path = $ueRoot
                major = [int]$ueBuild.MajorVersion
                minor = [int]$ueBuild.MinorVersion
                patch = [int]$ueBuild.PatchVersion
                changelist = [int64]$ueBuild.Changelist
                compatible_changelist = [int64]$ueBuild.CompatibleChangelist
                branch = [string]$ueBuild.BranchName
            }
        } else { $null }
        dotnet_version = $dotnetVersion
        path_commands = $pathCommands
        workspace_root = $WorkspaceRootPath
    }
}

$workspace = Get-NormalizedPath -Path $WorkspaceRoot
if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
    throw "WorkspaceRoot must be a directory: $workspace"
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$output = Get-NormalizedPath -Path $OutputDirectory

$projects = New-Object 'System.Collections.Generic.List[object]'
$solutions = New-Object 'System.Collections.Generic.List[object]'
$legacyProjectFiles = New-Object 'System.Collections.Generic.List[object]'
$binaryArtifacts = New-Object 'System.Collections.Generic.List[object]'

foreach ($rootName in $sourceRootNames) {
    $rootPath = Join-Path $workspace $rootName
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
        throw "Expected source root is missing: $rootPath"
    }
    $rootPath = Get-NormalizedPath -Path $rootPath

    foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -File -Recurse -Filter '*.vcproj')) {
        $projects.Add((Read-VcProject -File $file -RootName $rootName -RootPath $rootPath))
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -File -Recurse -Filter '*.csproj')) {
        $projects.Add((Read-CsProject -File $file -RootName $rootName -RootPath $rootPath))
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -File -Recurse -Filter '*.sln')) {
        $solutions.Add((Read-Solution -File $file -RootName $rootName -RootPath $rootPath))
    }
    foreach ($extension in @('.dsp', '.dsw')) {
        foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -File -Recurse -Filter "*$extension")) {
            $relativePath = Get-RelativeSourcePath -Root $rootPath -Path $file.FullName
            $legacyProjectFiles.Add([pscustomobject][ordered]@{
                root = $rootName
                path = $relativePath
                extension = $extension
                classification = Get-SourceClassification -RootName $rootName -RelativePath $relativePath
                sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
    }
    foreach ($extension in $binaryExtensions) {
        foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -File -Recurse -Filter "*$extension")) {
            $relativePath = Get-RelativeSourcePath -Root $rootPath -Path $file.FullName
            $binaryArtifacts.Add([pscustomobject][ordered]@{
                root = $rootName
                path = $relativePath
                name = $file.Name
                extension = $file.Extension.ToLowerInvariant()
                bytes = [int64]$file.Length
                classification = Get-SourceClassification -RootName $rootName -RelativePath $relativePath
            })
        }
    }
}

$projects = @($projects | Sort-Object root, path)
$solutions = @($solutions | Sort-Object root, path)
$legacyProjectFiles = @($legacyProjectFiles | Sort-Object root, path)
$binaryArtifacts = @($binaryArtifacts | Sort-Object root, path)

$bundledNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($artifact in $binaryArtifacts) { [void]$bundledNames.Add([string]$artifact.name) }
$producerNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($project in @($projects | Where-Object { $_.kind -eq 'vcproj' -and $null -eq $_.parse_error })) {
    if (-not [string]::IsNullOrWhiteSpace([string]$project.name)) {
        [void]$producerNames.Add(([string]$project.name + '.lib'))
        [void]$producerNames.Add(([string]$project.name + 'd.lib'))
        [void]$producerNames.Add(([string]$project.name + '_d.lib'))
    }
    foreach ($declaredOutput in @($project.declared_outputs)) {
        if ($declaredOutput -match '(?i)\.lib$') {
            [void]$producerNames.Add([System.IO.Path]::GetFileName($declaredOutput))
        }
    }
}
$systemNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($systemLibrary in $systemLibraries) { [void]$systemNames.Add($systemLibrary) }
$legacyToolsetNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($legacyToolsetLibrary in $legacyToolsetLibraries) { [void]$legacyToolsetNames.Add($legacyToolsetLibrary) }

$dependencyUsage = @{}
foreach ($project in @($projects | Where-Object { $_.kind -eq 'vcproj' -and $null -eq $_.parse_error })) {
    foreach ($configuration in @($project.configurations)) {
        foreach ($libraryToken in @($configuration.link_libraries)) {
            $libraryName = [System.IO.Path]::GetFileName(([string]$libraryToken).Replace('/', '\'))
            if ([string]::IsNullOrWhiteSpace($libraryName)) { continue }
            $key = $libraryName.ToLowerInvariant()
            if (-not $dependencyUsage.ContainsKey($key)) {
                $dependencyUsage[$key] = [ordered]@{
                    name = $libraryName
                    consumers = New-Object 'System.Collections.Generic.List[string]'
                    configurations = New-Object 'System.Collections.Generic.List[string]'
                    consumer_classifications = New-Object 'System.Collections.Generic.List[string]'
                }
            }
            $dependencyUsage[$key].consumers.Add("$($project.root)/$($project.path)")
            $dependencyUsage[$key].configurations.Add([string]$configuration.name)
            $dependencyUsage[$key].consumer_classifications.Add([string]$project.classification)
        }
    }
}

$linkDependencies = @(
    foreach ($key in ($dependencyUsage.Keys | Sort-Object)) {
        $entry = $dependencyUsage[$key]
        $status = if ($systemNames.Contains([string]$entry.name)) {
            'SystemSdk'
        } elseif ($legacyToolsetNames.Contains([string]$entry.name)) {
            'LegacyCompilerRuntime'
        } elseif ($bundledNames.Contains([string]$entry.name)) {
            'BundledBinary'
        } elseif ($producerNames.Contains([string]$entry.name)) {
            'ProducedByProject'
        } else {
            'MissingOrExternal'
        }
        [pscustomobject][ordered]@{
            name = [string]$entry.name
            status = $status
            consumers = @($entry.consumers | Sort-Object -Unique)
            configurations = @($entry.configurations | Sort-Object -Unique)
            consumer_classifications = @($entry.consumer_classifications | Sort-Object -Unique)
        }
    }
)

$environment = Get-InstalledEnvironment -WorkspaceRootPath $workspace
$summary = [ordered]@{
    vcproj_count = @($projects | Where-Object { $_.kind -eq 'vcproj' }).Count
    csproj_count = @($projects | Where-Object { $_.kind -eq 'csproj' }).Count
    solution_count = $solutions.Count
    dsp_count = @($legacyProjectFiles | Where-Object { $_.extension -eq '.dsp' }).Count
    dsw_count = @($legacyProjectFiles | Where-Object { $_.extension -eq '.dsw' }).Count
    project_parse_errors = @($projects | Where-Object { $_.kind -eq 'vcproj' -and $null -ne $_.parse_error }).Count
    binary_artifact_count = $binaryArtifacts.Count
    binary_artifact_bytes = [int64](($binaryArtifacts | Measure-Object -Property bytes -Sum).Sum)
    dependency_count = $linkDependencies.Count
    missing_or_external_dependency_count = @($linkDependencies | Where-Object { $_.status -eq 'MissingOrExternal' }).Count
}

$inventory = [ordered]@{
    schema_version = 1
    generated_utc = [DateTime]::UtcNow.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    source_policy = 'read-only'
    workspace_root = $workspace
    source_roots = $sourceRootNames
    summary = $summary
    projects = $projects
    solutions = $solutions
    legacy_project_files = $legacyProjectFiles
    link_dependencies = $linkDependencies
    binary_artifacts = $binaryArtifacts
}

$inventoryPath = Join-Path $output 'build-inventory.json'
$environmentPath = Join-Path $output 'toolchain-environment.json'
$inventoryJson = ($inventory | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n")
$environmentJson = ($environment | ConvertTo-Json -Depth 10).Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($inventoryPath, $inventoryJson + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText($environmentPath, $environmentJson + "`n", $utf8NoBom)

$result = [ordered]@{
    inventory_path = $inventoryPath
    inventory_sha256 = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    environment_path = $environmentPath
    environment_sha256 = (Get-FileHash -LiteralPath $environmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    summary = $summary
}
Write-Output ($result | ConvertTo-Json -Depth 6)
