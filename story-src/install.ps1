#requires -Version 7.0
param(
    [string]$GameData = 'E:\SteamLibrary\steamapps\common\Baldurs Gate 3\Data',
    [string]$ModsDirectory = "C:\Users\ankerlcg\AppData\Local\Larian Studios\Baldur's Gate 3\Mods",
    [string]$DesktopDirectory = 'C:\Users\ankerlcg\Desktop',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content (Join-Path $repo 'dist\build-manifest.json') -Raw | ConvertFrom-Json
$pak = Join-Path $repo 'dist\ChaosOriginsStory.pak'
if ((Get-FileHash $pak -Algorithm SHA256).Hash -ne $manifest.pakSha256) { throw 'Build PAK hash does not match manifest' }
$dataRoot = [IO.Path]::GetFullPath($GameData).TrimEnd('\')
if (-not (Test-Path -LiteralPath $dataRoot -PathType Container)) { throw "Missing game Data: $dataRoot" }
$loose = @()
foreach ($relative in $manifest.files) {
    if ($relative -notmatch '^(Localization/(Chinese|English|Japanese|Korean)/ChaosOriginsStory\.loca|Mods/ChaosOriginsStory/.+|Public/ChaosOriginsStory/.+)$') { throw "Unexpected module path: $relative" }
    $path = [IO.Path]::GetFullPath((Join-Path $dataRoot $relative))
    if (-not $path.StartsWith($dataRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path outside game Data: $path" }
    if (Test-Path -LiteralPath $path -PathType Leaf) { $loose += [pscustomobject]@{Path=$path;Relative=$relative} }
}
$otherCopies = @(Get-ChildItem -LiteralPath $ModsDirectory -Filter 'ChaosOriginsStory*.pak' -File | Where-Object Name -ne 'ChaosOriginsStory.pak')
if ($otherCopies.Count) { throw ('Other ChaosOriginsStory packages require review: ' + ($otherCopies.Name -join ', ')) }
if ($CheckOnly) {
    if ($loose.Count) { throw ("Loose files override package ($($loose.Count)): " + ($loose.Relative -join ', ')) }
    Write-Output 'No loose module overrides found'
    return
}
Get-Process -Name bg3,bg3_dx11 -ErrorAction SilentlyContinue | Stop-Process -Force
$backup = Join-Path $DesktopDirectory ('ChaosOriginsStory-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup | Out-Null
foreach ($file in $loose) {
    $target = Join-Path $backup ('loose\' + $file.Relative)
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Move-Item -LiteralPath $file.Path -Destination $target
}
$installed = Join-Path $ModsDirectory 'ChaosOriginsStory.pak'
if (Test-Path -LiteralPath $installed) { Copy-Item -LiteralPath $installed -Destination (Join-Path $backup 'ChaosOriginsStory.pak') }
$desktopPak = Join-Path $DesktopDirectory ("ChaosOriginsStory-$($manifest.displayVersion).pak")
foreach ($target in @($installed, $desktopPak)) {
    Copy-Item -LiteralPath $pak -Destination $target -Force
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $manifest.pakSha256) { throw "Installed hash mismatch: $target" }
}
foreach ($file in $loose) { if (Test-Path -LiteralPath $file.Path) { throw "Loose override still present: $($file.Path)" } }
Write-Output "Installed $($manifest.displayVersion); backed up $($loose.Count) loose files to $backup"
Write-Output $desktopPak
