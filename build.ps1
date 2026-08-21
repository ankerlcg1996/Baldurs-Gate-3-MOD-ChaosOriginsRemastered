param(
    [string]$LslibPath = $env:BG3_LSLIB_PATH
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$moduleName = 'ChaosOriginsRemastered'
$sourceRoot = Join-Path $projectRoot 'source'
$resourceRoot = Join-Path $projectRoot 'resource-src'
$localizationRoot = Join-Path $projectRoot 'localization-src'
$workRoot = Join-Path $projectRoot 'work'
$stageRoot = Join-Path $workRoot 'staging'
$reverseRoot = Join-Path $workRoot 'reverse'
$distRoot = Join-Path $projectRoot 'dist'
$pakPath = Join-Path $distRoot "$moduleName.pak"
$versionPath = Join-Path $projectRoot 'version.json'
$packageFilesPath = Join-Path $projectRoot 'package-files.json'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Reset-WorkDirectory([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
        $resolvedWork = [IO.Path]::GetFullPath($workRoot).TrimEnd('\')
        if (-not $resolvedPath.StartsWith($resolvedWork + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean outside the remastered work directory: $resolvedPath"
        }
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Relative-Path([string]$Root, [string]$Child) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $childFull = [IO.Path]::GetFullPath($Child)
    Require ($childFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) `
        "Path is outside expected root: $childFull"
    return $childFull.Substring($rootFull.Length)
}

& (Join-Path $projectRoot 'verify.ps1') -ProjectRoot $projectRoot
Require (-not [string]::IsNullOrWhiteSpace($LslibPath)) `
    'Pass -LslibPath or set BG3_LSLIB_PATH to LSLib.dll'
Require (Test-Path -LiteralPath $LslibPath -PathType Leaf) "LSLib is missing: $LslibPath"
Require (Test-Path -LiteralPath $versionPath -PathType Leaf) 'version.json is missing'
Require (Test-Path -LiteralPath $packageFilesPath -PathType Leaf) 'package-files.json is missing'
Add-Type -Path $LslibPath

$version = Get-Content -Raw -LiteralPath $versionPath -Encoding UTF8 | ConvertFrom-Json
Require ($version.schema -eq 1 -and $version.major -eq 1 -and $version.minor -eq 0) 'Unsupported version state'
Require ($version.lastBuild -is [int] -or $version.lastBuild -is [long]) 'lastBuild must be an integer'
$nextBuild = [int64]$version.lastBuild + 1
Require ($nextBuild -ge 1 -and $nextBuild -le 2147483647) 'Build number is outside BG3 Version64 range'
$displayVersion = '1.0.{0:D2}' -f $nextBuild
$version64 = [int64]36028797018963968 + $nextBuild
$packageFiles = Get-Content -Raw -LiteralPath $packageFilesPath -Encoding UTF8 | ConvertFrom-Json
Require ($packageFiles.schema -eq 1) 'Unsupported package-files schema'
$expectedFiles = @($packageFiles.files | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object)
Require ($expectedFiles.Count -eq 16 -and ($expectedFiles | Select-Object -Unique).Count -eq 16) `
    'package-files.json must contain exactly 16 unique paths'

Reset-WorkDirectory $stageRoot
Reset-WorkDirectory $reverseRoot
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceRoot 'Mods') -Destination $stageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $sourceRoot 'Public') -Destination $stageRoot -Recurse

$loadParameters = [LSLib.LS.ResourceLoadParameters]::new()
$conversionParameters = [LSLib.LS.ResourceConversionParameters]::new()
$resourceSources = @(Get-ChildItem -LiteralPath $resourceRoot -Recurse -File -Filter '*.lsf.lsx')
Require ($resourceSources.Count -eq 1) 'Minimal build must compile exactly one binary resource source'
foreach ($source in $resourceSources) {
    $relative = Relative-Path $resourceRoot $source.FullName
    $targetRelative = $relative.Substring(0, $relative.Length - 4)
    $target = Join-Path $stageRoot $targetRelative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    $resource = [LSLib.LS.ResourceUtils]::LoadResource(
        $source.FullName, [LSLib.LS.Enums.ResourceFormat]::LSX, $loadParameters)
    [LSLib.LS.ResourceUtils]::SaveResource(
        $resource, $target, [LSLib.LS.Enums.ResourceFormat]::LSF, $conversionParameters)
    Require (Test-Path -LiteralPath $target -PathType Leaf) "Resource compilation failed: $relative"
}

foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $xmlPath = Join-Path $localizationRoot "$language\$moduleName.xml"
    $locaPath = Join-Path $stageRoot "Localization\$language\$moduleName.loca"
    New-Item -ItemType Directory -Path (Split-Path $locaPath -Parent) -Force | Out-Null
    $localization = [LSLib.LS.LocaUtils]::Load($xmlPath)
    [LSLib.LS.LocaUtils]::Save($localization, $locaPath)
    Require (Test-Path -LiteralPath $locaPath -PathType Leaf) "Localization compilation failed: $language"
}

$stagedMetaPath = Join-Path $stageRoot "Mods\$moduleName\meta.lsx"
$stagedMeta = [xml](Get-Content -Raw -LiteralPath $stagedMetaPath -Encoding UTF8)
$stagedVersion = $stagedMeta.SelectSingleNode('//node[@id="ModuleInfo"]/attribute[@id="Version64"]')
Require ($null -ne $stagedVersion) 'Staged ModuleInfo Version64 is missing'
$stagedVersion.value = [string]$version64
$stagedPublishVersion = $stagedMeta.SelectSingleNode('//node[@id="ModuleInfo"]/children/node[@id="PublishVersion"]/attribute[@id="Version64"]')
Require ($null -ne $stagedPublishVersion) 'Staged PublishVersion Version64 is missing'
$stagedPublishVersion.value = [string]$version64
$stagedMeta.OuterXml | Set-Content -LiteralPath $stagedMetaPath -Encoding UTF8

if (Test-Path -LiteralPath $pakPath) { Remove-Item -LiteralPath $pakPath -Force }
$build = [LSLib.LS.PackageBuildData]::new()
$build.Version = [LSLib.LS.Enums.PackageVersion]::V18
$build.Compression = [LSLib.LS.CompressionMethod]::LZ4
$build.CompressionLevel = [LSLib.LS.LSCompressionLevel]::Fast
$build.Flags = [LSLib.LS.PackageFlags]0
$build.Hash = $true
$build.ExcludeHidden = $true
$build.Priority = 0
$packager = [LSLib.LS.Packager]::new()
$packager.CreatePackage($pakPath, $stageRoot, $build).GetAwaiter().GetResult()
Require (Test-Path -LiteralPath $pakPath -PathType Leaf) 'PAK creation failed'
$packager.UncompressPackage($pakPath, $reverseRoot)

$stagedFiles = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -File | ForEach-Object {
    (Relative-Path $stageRoot $_.FullName).Replace('\', '/')
} | Sort-Object)
$reverseFiles = @(Get-ChildItem -LiteralPath $reverseRoot -Recurse -File | ForEach-Object {
    (Relative-Path $reverseRoot $_.FullName).Replace('\', '/')
} | Sort-Object)
Require (-not (Compare-Object $expectedFiles $stagedFiles)) `
    'Staging file list differs from package-files.json'
Require (-not (Compare-Object $stagedFiles $reverseFiles)) 'Reverse-unpacked file list differs from staging'
foreach ($relative in $stagedFiles) {
    $nativeRelative = $relative.Replace('/', '\')
    $stagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stageRoot $nativeRelative)).Hash
    $reverseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $reverseRoot $nativeRelative)).Hash
    Require ($stagedHash -eq $reverseHash) "Reverse-unpacked file differs: $relative"
}

$sourceMetaPath = Join-Path $sourceRoot "Mods\$moduleName\meta.lsx"
$sourceMeta = [xml](Get-Content -Raw -LiteralPath $sourceMetaPath -Encoding UTF8)
$sourceVersion = $sourceMeta.SelectSingleNode('//node[@id="ModuleInfo"]/attribute[@id="Version64"]')
$sourceVersion.value = [string]$version64
$sourcePublishVersion = $sourceMeta.SelectSingleNode('//node[@id="ModuleInfo"]/children/node[@id="PublishVersion"]/attribute[@id="Version64"]')
$sourcePublishVersion.value = [string]$version64
$sourceMeta.OuterXml | Set-Content -LiteralPath $sourceMetaPath -Encoding UTF8
$version.lastBuild = $nextBuild
$version | ConvertTo-Json | Set-Content -LiteralPath $versionPath -Encoding UTF8

$manifest = [ordered]@{
    schema = 1
    displayVersion = $displayVersion
    version64 = $version64
    moduleName = $moduleName
    moduleUuid = '9112dfde-d843-408f-b59b-9c893f5f7d92'
    originUuid = '37914c47-d2f2-433d-9635-3e3040a4663f'
    originTagUuid = '7bb4d001-3c7e-445d-b52b-db0507db38d4'
    pakSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $pakPath).Hash.ToLowerInvariant()
    files = $stagedFiles
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $distRoot 'build-manifest.json') -Encoding UTF8
Write-Host "ChaosOriginsRemastered built and reverse-verified: $displayVersion ($version64)"
Write-Host $pakPath
