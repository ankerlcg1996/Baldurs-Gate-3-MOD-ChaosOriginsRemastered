#requires -Version 7.0

param([string]$LslibPath = 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$repo = Split-Path $root -Parent
$work = Join-Path $root 'work'
$stage = Join-Path $work 'staging'
$reverse = Join-Path $work 'reverse'
$dist = Join-Path $repo 'dist'
$pak = Join-Path $dist 'ChaosOriginsStory.pak'
$manifestPath = Join-Path $root 'package-files.json'
$versionPath = Join-Path $root 'version.json'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Reset-WorkChild([string]$Path) {
    $workFull = [IO.Path]::GetFullPath($work).TrimEnd('\')
    $pathFull = [IO.Path]::GetFullPath($Path)
    Require ($pathFull.StartsWith($workFull + '\', [StringComparison]::OrdinalIgnoreCase)) `
        "拒绝清理工作目录外路径: $pathFull"
    if (Test-Path -LiteralPath $pathFull) {
        Remove-Item -LiteralPath $pathFull -Recurse -Force
    }
    New-Item -ItemType Directory -Path $pathFull -Force | Out-Null
}

. (Join-Path $root 'build-process.ps1')
. (Join-Path $root 'story-ir-attestation.ps1')

& (Join-Path $root 'verify.ps1')
$compileStoryScript = Join-Path $root 'compile-story.ps1'
$compiledStoryPath = Join-Path $work 'compiled-story\story.div.osi'
$storyDebugInfoPath = Join-Path $work 'compiled-story\story.debug-info.pb'
$storyIrAttestationPath = Join-Path $work 'compiled-story\story-ir-attestation.json'
if (Test-Path -LiteralPath $storyIrAttestationPath -PathType Leaf) {
    [IO.File]::Delete([IO.Path]::GetFullPath($storyIrAttestationPath))
}
Invoke-BuildScriptProcess -ScriptPath $compileStoryScript
$storyIrAttestation = Assert-StoryIrAttestation -StoryPath $compiledStoryPath `
    -DebugInfoPath $storyDebugInfoPath -AttestationPath $storyIrAttestationPath
Require ($storyIrAttestation.validated -eq $true) 'Story IR 证明未通过构建进程校验'
& (Join-Path $root 'compile-resources.ps1')

$selectedLslibPath = [IO.Path]::GetFullPath($LslibPath)
Require (Test-Path -LiteralPath $selectedLslibPath -PathType Leaf) "缺少 LSLib: $selectedLslibPath"
Require (Test-Path -LiteralPath $versionPath -PathType Leaf) '缺少 version.json'

$version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($version.schema -eq 1) '不支持的版本文件格式'
foreach ($field in @('major', 'minor', 'revision', 'lastBuild')) {
    Require ($version.$field -is [int] -or $version.$field -is [long]) "版本字段必须为整数: $field"
}
$nextBuild = [int64]$version.lastBuild + 1
Require ($nextBuild -ge 1 -and $nextBuild -le 2147483647) '末位版本号超出 BG3 Version64 范围'
$nextVersion64 = ([int64]$version.major * 36028797018963968) + `
    ([int64]$version.minor * 140737488355328) + `
    ([int64]$version.revision * 2147483648) + $nextBuild
$displayVersion = '{0}.{1}.{2}.{3}' -f $version.major, $version.minor, $version.revision, $nextBuild

$manifestDocument = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($manifestDocument.schema -eq 1) '不支持的打包清单格式'
$manifest = @($manifestDocument.files)

Reset-WorkChild $stage
Reset-WorkChild $reverse
New-Item -ItemType Directory -Path $dist -Force | Out-Null

foreach ($relative in $manifest) {
    $nativeRelative = $relative.Replace('/', '\')
    $target = Join-Path $stage $nativeRelative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    if ($relative -eq 'Mods/ChaosOriginsStory/Story/story.div.osi') {
        $source = Join-Path $work 'compiled-story\story.div.osi'
    } elseif ($relative.EndsWith('.lsf')) {
        $source = Join-Path $work ('compiled-resources\' + $nativeRelative)
    } elseif ($relative.EndsWith('.loca')) {
        continue
    } else {
        $source = Join-Path $root $nativeRelative
    }
    Require (Test-Path -LiteralPath $source -PathType Leaf) "清单源文件不存在: $relative -> $source"
    Copy-Item -LiteralPath $source -Destination $target -Force
}

$loadedLslibAssemblies = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
    $_.GetName().Name -eq 'LSLib'
})
$differentLslibAssemblies = @($loadedLslibAssemblies | Where-Object {
    [string]::IsNullOrWhiteSpace($_.Location) -or
        -not [IO.Path]::GetFullPath($_.Location).Equals(
            $selectedLslibPath, [StringComparison]::OrdinalIgnoreCase)
})
$loadedLslibLocations = @($differentLslibAssemblies | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_.Location)) { '<无加载路径>' } else { $_.Location }
}) -join ', '
Require ($differentLslibAssemblies.Count -eq 0) `
    "当前构建进程已加载其他路径的 LSLib: $loadedLslibLocations；所选路径: $selectedLslibPath"

Add-Type -Path $selectedLslibPath
$activeLslibAssemblies = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
    $_.GetName().Name -eq 'LSLib'
})
Require ($activeLslibAssemblies.Count -eq 1) `
    "当前构建进程中的 LSLib 程序集数量错误: $($activeLslibAssemblies.Count)"
$actualLslibPath = [IO.Path]::GetFullPath($activeLslibAssemblies[0].Location)
Require ($actualLslibPath.Equals($selectedLslibPath, [StringComparison]::OrdinalIgnoreCase)) `
    "当前 LSLib 实际加载路径与所选路径不一致: actual=$actualLslibPath selected=$selectedLslibPath"
foreach ($requiredLslibType in @(
    'LSLib.LS.LocaUtils', 'LSLib.LS.Packager', 'LSLib.LS.PackageBuildData',
    'LSLib.LS.Enums.PackageVersion', 'LSLib.LS.CompressionMethod',
    'LSLib.LS.LSCompressionLevel', 'LSLib.LS.PackageFlags'
)) {
    Require ($null -ne $activeLslibAssemblies[0].GetType($requiredLslibType, $false)) `
        "所选 LSLib 缺少构建所需类型: $requiredLslibType"
}
foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $xml = Join-Path $root "Localization\$language\ChaosOriginsStory.xml"
    $target = Join-Path $stage "Localization\$language\ChaosOriginsStory.loca"
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    $localization = [LSLib.LS.LocaUtils]::Load($xml)
    [LSLib.LS.LocaUtils]::Save($localization, $target)
    Require (Test-Path -LiteralPath $target -PathType Leaf) "本地化编译失败: $language"
}

$stagedMetaPath = Join-Path $stage 'Mods\ChaosOriginsStory\meta.lsx'
[xml]$stagedMeta = Get-Content -LiteralPath $stagedMetaPath -Raw -Encoding UTF8
$stagedModuleVersion = $stagedMeta.SelectSingleNode('//node[@id="ModuleInfo"]/attribute[@id="Version64"]')
$stagedPublishVersion = $stagedMeta.SelectSingleNode('//node[@id="ModuleInfo"]/children/node[@id="PublishVersion"]/attribute[@id="Version64"]')
Require ($null -ne $stagedModuleVersion -and $null -ne $stagedPublishVersion) '暂存 meta.lsx 缺少版本字段'
$stagedModuleVersion.value = [string]$nextVersion64
$stagedPublishVersion.value = [string]$nextVersion64
$stagedMeta.OuterXml | Set-Content -LiteralPath $stagedMetaPath -Encoding UTF8

$actual = @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/')
} | Sort-Object)
$expected = @($manifest | Sort-Object)
Require ($actual.Count -eq $expected.Count -and -not (Compare-Object $expected $actual)) `
    "打包清单不匹配: expected=$($expected.Count) actual=$($actual.Count)"
$expectedStoryFiles = @(
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_BaseAfterCreation.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMastery.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_OriginStoryRewards.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/story_header.div',
    'Mods/ChaosOriginsStory/Story/story.div.osi'
) | Sort-Object
$actualStoryFiles = @($actual | Where-Object { $_ -match '/Story/' } | Sort-Object)
Require (-not (Compare-Object $expectedStoryFiles $actualStoryFiles)) `
    '原生 Story 包装必须同时包含四个 Goal、当前原始头和编译 Story'
Require (-not ($actual | Where-Object { $_ -match 'ScriptExtender|MCM' })) `
    '原生 Story 最终包夹带了 SE 或 MCM 依赖'

if (Test-Path -LiteralPath $pak) { Remove-Item -LiteralPath $pak -Force }
$build = [LSLib.LS.PackageBuildData]::new()
$build.Version = [LSLib.LS.Enums.PackageVersion]::V18
$build.Compression = [LSLib.LS.CompressionMethod]::LZ4
$build.CompressionLevel = [LSLib.LS.LSCompressionLevel]::Fast
$build.Flags = [LSLib.LS.PackageFlags]0
$build.Hash = $true
$build.ExcludeHidden = $true
$build.Priority = 0
$packager = [LSLib.LS.Packager]::new()
$packager.CreatePackage($pak, $stage, $build).GetAwaiter().GetResult()
Require (Test-Path -LiteralPath $pak -PathType Leaf) 'PAK 创建失败'
$packager.UncompressPackage($pak, $reverse)

$reverseFiles = @(Get-ChildItem -LiteralPath $reverse -Recurse -File | ForEach-Object {
    [IO.Path]::GetRelativePath($reverse, $_.FullName).Replace('\', '/')
} | Sort-Object)
Require ($actual.Count -eq $reverseFiles.Count -and -not (Compare-Object $actual $reverseFiles)) `
    "反向解包清单不匹配: stage=$($actual.Count) reverse=$($reverseFiles.Count)"
foreach ($relative in $actual) {
    $nativeRelative = $relative.Replace('/', '\')
    $stageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stage $nativeRelative)).Hash
    $reverseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $reverse $nativeRelative)).Hash
    Require ($stageHash -eq $reverseHash) "反向解包哈希不匹配: $relative"
}

$sourceMetaPath = Join-Path $root 'Mods\ChaosOriginsStory\meta.lsx'
[xml]$sourceMeta = Get-Content -LiteralPath $sourceMetaPath -Raw -Encoding UTF8
$sourceModuleVersion = $sourceMeta.SelectSingleNode('//node[@id="ModuleInfo"]/attribute[@id="Version64"]')
$sourcePublishVersion = $sourceMeta.SelectSingleNode('//node[@id="ModuleInfo"]/children/node[@id="PublishVersion"]/attribute[@id="Version64"]')
Require ($null -ne $sourceModuleVersion -and $null -ne $sourcePublishVersion) '源 meta.lsx 缺少版本字段'
$sourceModuleVersion.value = [string]$nextVersion64
$sourcePublishVersion.value = [string]$nextVersion64
$sourceMeta.OuterXml | Set-Content -LiteralPath $sourceMetaPath -Encoding UTF8
$version.lastBuild = $nextBuild
$version | ConvertTo-Json | Set-Content -LiteralPath $versionPath -Encoding UTF8

$buildManifest = [ordered]@{
    schema = 1
    displayVersion = $displayVersion
    version64 = $nextVersion64
    moduleName = 'ChaosOriginsStory'
    moduleUuid = 'a5062238-0d2b-46d1-a093-cb02775b9f57'
    pakSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $pak).Hash.ToLowerInvariant()
    files = $actual
}
$buildManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dist 'build-manifest.json') -Encoding UTF8
Write-Host "Story 最终候选 PAK 构建并反向校验完成: $displayVersion ($nextVersion64), $pak ($($actual.Count) files)"
