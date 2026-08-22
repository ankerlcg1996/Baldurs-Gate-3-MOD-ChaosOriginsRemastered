param(
    [string]$SourcePath = (Join-Path $PSScriptRoot 'icon-src\Icons_ChaosOrigins.png'),
    [string]$AtlasPath = (Join-Path $PSScriptRoot 'source\Public\ChaosOriginsRemastered\Assets\Textures\Icons\Icons_ChaosOrigins.dds')
)

$ErrorActionPreference = 'Stop'
$sourceFull = [IO.Path]::GetFullPath($SourcePath)
$atlasFull = [IO.Path]::GetFullPath($AtlasPath)

if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) {
    throw "Icon atlas source is missing: $sourceFull"
}
if ($null -eq (Get-Command magick -ErrorAction SilentlyContinue)) {
    throw 'ImageMagick magick command is required to rebuild the icon atlas'
}

$geometry = & magick identify -format '%wx%h' $sourceFull
if ($LASTEXITCODE -ne 0 -or $geometry -ne '512x512') {
    throw "Icon atlas source must be a readable 512 x 512 PNG: $sourceFull"
}

$atlasDirectory = Split-Path $atlasFull -Parent
if (-not (Test-Path -LiteralPath $atlasDirectory -PathType Container)) {
    throw "Icon atlas output directory is missing: $atlasDirectory"
}

# PNG 是可审查的唯一图标源；每次打包前重新编码十级 mipmap 的 DXT5 图集。
& magick $sourceFull -define dds:compression=dxt5 -define dds:mipmaps=10 $atlasFull
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $atlasFull -PathType Leaf)) {
    throw "Icon atlas DDS encoding failed: $atlasFull"
}

& (Join-Path $PSScriptRoot 'repair-icon-atlas.ps1') -AtlasPath $atlasFull
Write-Host "Rebuilt BG3 icon atlas: $atlasFull"
