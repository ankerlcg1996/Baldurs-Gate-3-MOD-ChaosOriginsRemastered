#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$PakPath,
    [string]$LslibPath = 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll'
)
$ErrorActionPreference = 'Stop'
Add-Type -Path $LslibPath
$module = 'ExplorationBenefitsStory'
$required = @(
    "Mods/$module/Story/RawFiles/Goals/EBS_Exploration.txt",
    "Mods/$module/Story/RawFiles/story_header.div",
    "Mods/$module/meta.lsx",
    "Mods/$module/Story/story.div.osi",
    "Public/$module/Stats/Generated/Data/Exploration.txt",
    "Localization/Chinese/$module.loca",
    "Localization/English/$module.loca"
)
$package = ([LSLib.LS.PackageReader]::new()).Read($PakPath, $false)
try {
    foreach ($path in $required) {
        if (@($package.Files | Where-Object Name -CEQ $path).Count -ne 1) {
            throw "Missing or duplicate required package entry: $path"
        }
    }
    if ($package.Files.Count -ne $required.Count) { throw 'Unexpected package files' }
    $inputs = @{
        "Mods/$module/Story/RawFiles/Goals/EBS_Exploration.txt" = "$PSScriptRoot/src/Mods/$module/Story/RawFiles/Goals/EBS_Exploration.txt"
        "Mods/$module/Story/RawFiles/story_header.div" = "$(Split-Path $PSScriptRoot -Parent)/story-src/Mods/ChaosOriginsStory/Story/RawFiles/story_header.div"
    }
    foreach ($path in $inputs.Keys) {
        $stream = ($package.Files | Where-Object Name -CEQ $path).CreateContentReader()
        try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) }
        finally { $stream.Dispose() }
        if ($hash -ne (Get-FileHash -LiteralPath $inputs[$path]).Hash) {
            throw "Runtime Story source differs from approved source: $path"
        }
    }
} finally { $package.Dispose() }
'PASS: package contains native Story goal and unmodified runtime header, plus compiled Story; seven files total.'
