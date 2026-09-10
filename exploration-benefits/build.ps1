#requires -Version 7.0
param(
    [string]$StoryCompilerPath = 'C:\Users\ankerlcg\Documents\ChatGPT\博德之门3Mod\.tools\lslib-duplication-fix\StoryCompiler\bin\Release\net8.0\StoryCompiler.exe',
    [string]$DependencyVfsPath = 'C:\Users\ankerlcg\Documents\ChatGPT\博德之门3Mod\.story-vfs',
    [string]$LslibPath = 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll'
)
$ErrorActionPreference = 'Stop'
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$module = 'ExplorationBenefitsStory'
$src = Join-Path $PSScriptRoot 'src'
$sourceMod = Join-Path $src "Mods/$module"
$sourceHeader = Join-Path (Split-Path $PSScriptRoot -Parent) 'story-src/Mods/ChaosOriginsStory/Story/RawFiles/story_header.div'
foreach ($path in @($StoryCompilerPath, $LslibPath, $sourceHeader, "$sourceMod/meta.lsx")) {
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Missing build input: $path"
}
& "$PSScriptRoot/verify.ps1"
$work = Join-Path $PSScriptRoot ('work/build-' + [Guid]::NewGuid().ToString('N'))
$vfs = Join-Path $work 'vfs'
$stage = Join-Path $work 'package'
$reverse = Join-Path $work 'reverse'
$dist = Join-Path $PSScriptRoot 'dist'
$binary = Join-Path $work 'story.div.osi'
New-Item -ItemType Directory -Path "$vfs/Mods", $stage, $reverse, $dist -Force | Out-Null
foreach ($dependency in @('Shared', 'SharedDev', 'Gustav', 'GustavDev', 'GustavX')) {
    $target = Join-Path $DependencyVfsPath "Mods/$dependency"
    Require (Test-Path -LiteralPath $target -PathType Container) "Missing dependency: $target"
    New-Item -ItemType Junction -Path "$vfs/Mods/$dependency" -Target $target | Out-Null
}
Copy-Item -LiteralPath $sourceMod -Destination "$vfs/Mods/$module" -Recurse
$lines = [IO.File]::ReadAllLines($sourceHeader)
$aliasTargets = @{}
foreach ($line in $lines) {
    if ($line -match '^alias_type \{[^,]+,\s*(\d+),\s*(\d+)\}') { $aliasTargets[[int]$matches[1]] = [int]$matches[2] }
}
function Resolve-IntrinsicAlias([int]$TypeId) {
    $seen = @{}
    while ($TypeId -gt 5) {
        Require (-not $seen.ContainsKey($TypeId) -and $aliasTargets.ContainsKey($TypeId)) "Unresolved alias chain: $TypeId"
        $seen[$TypeId] = $true
        $TypeId = $aliasTargets[$TypeId]
    }
    return $TypeId
}
$flattened = foreach ($line in $lines) {
    if ($line -match '^enum_type \{([^,]+),\s*(\d+),') {
        'alias_type {' + $matches[1] + ', ' + $matches[2] + ', 1}'
    } elseif ($line -match '^alias_type \{([^,]+),\s*(\d+),\s*(\d+)\}') {
        'alias_type {' + $matches[1] + ', ' + $matches[2] + ', ' + (Resolve-IntrinsicAlias ([int]$matches[3])) + '}'
    } else { $line }
}
[IO.File]::WriteAllLines("$vfs/Mods/$module/Story/RawFiles/story_header.div", $flattened, [Text.UTF8Encoding]::new($false))
& $StoryCompilerPath --game bg3 --game-data-path $vfs --no-packages --allow-type-coercion --mod $module --output $binary --debug-info "$work/story.debug-info.pb" --json
Require ($LASTEXITCODE -eq 0) "StoryCompiler failed with exit code $LASTEXITCODE; work: $work"
Require (Test-Path -LiteralPath $binary -PathType Leaf) 'Compiler did not produce story.div.osi'
$reportPath = Join-Path $work 'story-verification.json'
& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File "$PSScriptRoot/verify-build.ps1" -StoryPath $binary -LslibPath (Join-Path (Split-Path $StoryCompilerPath -Parent) 'LSLib.dll') -ReportPath $reportPath
Require ($LASTEXITCODE -eq 0) "Story binary verification failed: $LASTEXITCODE"
$storyReport = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
Require ($storyReport.sha256 -eq (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash) 'Story verification report hash mismatch'
$selectedLibrary = [IO.Path]::GetFullPath($LslibPath)
foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    if ($assembly.GetName().Name -eq 'LSLib') {
        Require ($assembly.Location -eq $selectedLibrary) 'A different LSLib is loaded; run build.ps1 in a fresh PowerShell 7 process'
    }
}
Add-Type -Path $selectedLibrary
$expected = @(
    "Mods/$module/meta.lsx",
    "Mods/$module/Story/story.div.osi",
    "Mods/$module/Story/RawFiles/Goals/EBS_Exploration.txt",
    "Mods/$module/Story/RawFiles/story_header.div",
    "Public/$module/Stats/Generated/Data/Exploration.txt",
    "Localization/Chinese/$module.loca",
    "Localization/English/$module.loca"
) | Sort-Object
foreach ($relative in $expected) {
    $destination = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    if ($relative.EndsWith('.loca')) {
        $localization = [LSLib.LS.LocaUtils]::Load((Join-Path $src ($relative -replace '\.loca$', '.xml')))
        [LSLib.LS.LocaUtils]::Save($localization, $destination)
    } elseif ($relative.EndsWith('story.div.osi')) {
        Copy-Item -LiteralPath $binary -Destination $destination
    } elseif ($relative.EndsWith('story_header.div')) {
        # Ship the native header, not the alias-flattened compiler-only copy.
        Copy-Item -LiteralPath $sourceHeader -Destination $destination
    } else { Copy-Item -LiteralPath (Join-Path $src $relative) -Destination $destination }
}
[xml]$meta = Get-Content -LiteralPath "$stage/Mods/$module/meta.lsx" -Raw
$versionNodes = @($meta.SelectNodes('//node[@id="ModuleInfo"]//attribute[@id="Version64"]'))
Require ($versionNodes.Count -ge 1) 'Meta lacks module version'
foreach ($node in $versionNodes) { Require ($node.value -eq '36028797018963970') 'Expected Version64 36028797018963970 for release 1.0.0.2' }
$actual = @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/') } | Sort-Object)
Require ($actual.Count -eq $expected.Count -and -not (Compare-Object $expected $actual)) 'Package staging file list mismatch'
$build = [LSLib.LS.PackageBuildData]::new()
$build.Version = [LSLib.LS.Enums.PackageVersion]::V18
$build.Compression = [LSLib.LS.CompressionMethod]::LZ4
$build.CompressionLevel = [LSLib.LS.LSCompressionLevel]::Fast
$build.Flags = [LSLib.LS.PackageFlags]0
$build.Hash = $true
$build.ExcludeHidden = $true
# CreatePackage enumerates this directory itself; do not also prefill Files.
$candidate = Join-Path $work 'ExplorationBenefitsStory.pak'
$packager = [LSLib.LS.Packager]::new()
$packager.CreatePackage($candidate, $stage, $build).GetAwaiter().GetResult()
& "$PSScriptRoot/verify-package.ps1" -PakPath $candidate -LslibPath $selectedLibrary
$packager.UncompressPackage($candidate, $reverse)
$unpacked = @(Get-ChildItem -LiteralPath $reverse -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($reverse, $_.FullName).Replace('\', '/') } | Sort-Object)
Require ($unpacked.Count -eq $expected.Count -and -not (Compare-Object $expected $unpacked)) 'Unpacked file list mismatch'
$fileHashes = foreach ($relative in $expected) {
    $original = (Get-FileHash -LiteralPath (Join-Path $stage $relative) -Algorithm SHA256).Hash
    $decoded = (Get-FileHash -LiteralPath (Join-Path $reverse $relative) -Algorithm SHA256).Hash
    Require ($original -eq $decoded) "Unpacked hash mismatch: $relative"
    [ordered]@{ path = $relative; sha256 = $original.ToLowerInvariant() }
}
$pak = Join-Path $dist '战斗外探索增益-1.0.0.2.pak'
Copy-Item -LiteralPath $candidate -Destination $pak -Force
$pakHash = (Get-FileHash -LiteralPath $pak -Algorithm SHA256).Hash
Require ($pakHash -eq (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash) 'Final package copy hash mismatch'
$manifest = [ordered]@{
    schema = 1; moduleName = $module; moduleUuid = '7f2cfe6b-cab7-4da7-a46d-31b535c53c68'
    displayVersion = '1.0.0.2'; version64 = '36028797018963970'; pakSha256 = $pakHash.ToLowerInvariant()
    compiledGoals = @($storyReport.goals); compiledNodes = $storyReport.nodes; validConstants = $storyReport.validConstants
    files = @($fileHashes); buildDirectory = $work; gameplayVerified = $false
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$dist/build-manifest.json" -Encoding utf8
Write-Host "PASS: native Story compiled and read back; seven unique package files verified byte-for-byte. Gameplay not tested. $pak"
