param(
    [string]$GameDataPath = $env:BG3_DATA_PATH,
    [string]$LslibPath = $env:BG3_LSLIB_PATH
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$workRoot = Join-Path $projectRoot 'work'
$outputRoot = Join-Path $workRoot 'official-validation'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Require (-not [string]::IsNullOrWhiteSpace($GameDataPath)) `
    'Pass -GameDataPath or set BG3_DATA_PATH to the Baldurs Gate 3 Data directory'
Require (-not [string]::IsNullOrWhiteSpace($LslibPath)) `
    'Pass -LslibPath or set BG3_LSLIB_PATH to LSLib.dll'
Require (Test-Path -LiteralPath $GameDataPath -PathType Container) "BG3 Data directory is missing: $GameDataPath"
Require (Test-Path -LiteralPath $LslibPath -PathType Leaf) "LSLib is missing: $LslibPath"

foreach ($pakName in @('Shared.pak', 'GustavX.pak', 'Gustav.pak')) {
    Require (Test-Path -LiteralPath (Join-Path $GameDataPath $pakName) -PathType Leaf) `
        "Official game package is missing: $pakName"
}

if (Test-Path -LiteralPath $outputRoot) {
    $resolvedOutput = (Resolve-Path -LiteralPath $outputRoot).Path
    $resolvedWork = [IO.Path]::GetFullPath($workRoot).TrimEnd('\')
    Require ($resolvedOutput.StartsWith($resolvedWork + '\', [StringComparison]::OrdinalIgnoreCase)) `
        "Refusing to clean outside the project work directory: $resolvedOutput"
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

Add-Type -Path $LslibPath
$packager = [LSLib.LS.Packager]::new()

function Expand-Stats([string]$PakName, [string]$OutputName) {
    $target = Join-Path $outputRoot $OutputName
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $filter = [Func[LSLib.LS.PackagedFileInfo, bool]]{
        param($file)
        $name = $file.Name.Replace('\', '/')
        return $name -like '*/Stats/Generated/Data/*'
    }
    $packager.UncompressPackage((Join-Path $GameDataPath $PakName), $target, $filter)
}

Expand-Stats 'Shared.pak' 'Shared'
Expand-Stats 'GustavX.pak' 'GustavX'

$gustavTarget = Join-Path $outputRoot 'Gustav'
New-Item -ItemType Directory -Path $gustavTarget -Force | Out-Null
$rootTemplateFilter = [Func[LSLib.LS.PackagedFileInfo, bool]]{
    param($file)
    return $file.Name.Replace('\', '/') -eq 'Public/GustavDev/RootTemplates/_merged.lsf'
}
$packager.UncompressPackage((Join-Path $GameDataPath 'Gustav.pak'), $gustavTarget, $rootTemplateFilter)

$rootTemplateLsf = Join-Path $gustavTarget 'Public\GustavDev\RootTemplates\_merged.lsf'
$rootTemplateLsx = "$rootTemplateLsf.lsx"
Require (Test-Path -LiteralPath $rootTemplateLsf -PathType Leaf) `
    'Gustav root-template extraction did not produce _merged.lsf'
$loadParameters = [LSLib.LS.ResourceLoadParameters]::new()
$conversionParameters = [LSLib.LS.ResourceConversionParameters]::new()
$resource = [LSLib.LS.ResourceUtils]::LoadResource(
    $rootTemplateLsf, [LSLib.LS.Enums.ResourceFormat]::LSF, $loadParameters)
[LSLib.LS.ResourceUtils]::SaveResource(
    $resource, $rootTemplateLsx, [LSLib.LS.Enums.ResourceFormat]::LSX, $conversionParameters)
Require (Test-Path -LiteralPath $rootTemplateLsx -PathType Leaf) `
    'Gustav root-template conversion did not produce _merged.lsf.lsx'

$sourcePackages = foreach ($pakName in @('Shared.pak', 'GustavX.pak', 'Gustav.pak')) {
    $pak = Get-Item -LiteralPath (Join-Path $GameDataPath $pakName)
    [ordered]@{
        name = $pak.Name
        length = $pak.Length
        lastWriteTimeUtc = $pak.LastWriteTimeUtc.ToString('O')
    }
}
[ordered]@{
    schema = 1
    gameDataPath = [IO.Path]::GetFullPath($GameDataPath)
    sourcePackages = $sourcePackages
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputRoot 'fixture-manifest.json') -Encoding UTF8

Write-Host "Official validation data prepared: $outputRoot"
