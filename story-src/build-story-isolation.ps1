param(
    [Parameter(Mandatory)][string]$BaselinePak,
    [Parameter(Mandatory)][string]$CandidatePak,
    [Parameter(Mandatory)][string]$OutputPak,
    [Parameter(Mandatory)][long]$Version64,
    [string]$LslibPath = 'C:/Users/ankerlcg/Documents/ChatGPT/博德之门3Mod/.tools/lslib-duplication-fix/StoryCompiler/bin/Release/net8.0/LSLib.dll'
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPak) { throw "Output already exists: $OutputPak" }
if ((Get-FileHash -LiteralPath $BaselinePak).Hash -ne 'AFFC19B0275D1DF2A497704E03C3C7A81AFEE9071003405E1B060D7C7178511A') {
    throw 'Expected game-tested 1.0.1.71 baseline'
}
if ((Get-FileHash -LiteralPath $CandidatePak).Hash -ne '7EDD0E631188F7BCD98E23563ADE936BA704D9547AF929F774974FCE60BB09B9') {
    throw 'Expected failing 1.0.1.72 candidate'
}
Add-Type -Path $LslibPath
$stage = Join-Path $PSScriptRoot ('work/story-isolation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$packager = [LSLib.LS.Packager]::new()
$packager.UncompressPackage($CandidatePak, $stage)
$baseline = ([LSLib.LS.PackageReader]::new()).Read($BaselinePak, $false)
try {
    foreach ($entry in $baseline.Files | Where-Object Name -match '/Story/') {
        $target = [IO.Path]::GetFullPath((Join-Path $stage $entry.Name))
        if (-not $target.StartsWith([IO.Path]::GetFullPath($stage) + [IO.Path]::DirectorySeparatorChar)) {
            throw "Package path escapes stage: $($entry.Name)"
        }
        $inputStream = $entry.CreateContentReader()
        $outputStream = [IO.File]::Create($target)
        try { $inputStream.CopyTo($outputStream) }
        finally { $outputStream.Dispose(); $inputStream.Dispose() }
    }
} finally { $baseline.Dispose() }
$metaPath = Join-Path $stage 'Mods/ChaosOriginsStory/meta.lsx'
[xml]$meta = Get-Content -LiteralPath $metaPath -Raw
$versions = $meta.SelectNodes('//node[@id="ModuleInfo"]//attribute[@id="Version64"]')
if ($versions.Count -ne 2) { throw 'Expected module and publish versions' }
foreach ($node in $versions) { $node.value = [string]$Version64 }
$meta.PSBase.Save($metaPath)
$build = [LSLib.LS.PackageBuildData]::new()
$build.Version = [LSLib.LS.Enums.PackageVersion]::V18
$build.Compression = [LSLib.LS.CompressionMethod]::LZ4
$build.CompressionLevel = [LSLib.LS.LSCompressionLevel]::Fast
$build.Flags = [LSLib.LS.PackageFlags]0
$build.Hash = $true
$build.ExcludeHidden = $true
$build.Priority = 0
foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName) {
    $entry = [LSLib.LS.PackageBuildInputFile]::new()
    $entry.Path = [IO.Path]::GetRelativePath($stage, $file.FullName).Replace('\', '/')
    $entry.FilesystemPath = $file.FullName
    $build.Files.Add($entry)
}
$packager.CreatePackage($OutputPak, $stage, $build).GetAwaiter().GetResult()
& "$PSScriptRoot/verify-story-isolation.ps1" -Path $OutputPak -BaselinePak $BaselinePak `
    -CandidatePak $CandidatePak -Version64 $Version64 -LslibPath $LslibPath
& "$PSScriptRoot/verify-story-binary.ps1" -Path $OutputPak -LslibPath $LslibPath
Get-FileHash -LiteralPath $OutputPak
