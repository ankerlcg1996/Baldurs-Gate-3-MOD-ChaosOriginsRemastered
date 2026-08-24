#requires -Version 7.0

param([string]$LslibPath = 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$repo = Split-Path $root -Parent
$work = Join-Path $root 'work'
$stage = Join-Path $work 'staging'
$reverse = Join-Path $work 'reverse'
$dist = Join-Path $repo 'dist'
$baseInfoPath = Join-Path $root 'base-pak.json'
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

& (Join-Path $root 'verify.ps1')
$baseInfo = Get-Content -LiteralPath $baseInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
$basePak = Join-Path $root ('base\' + $baseInfo.fileName)
Require (Test-Path -LiteralPath $basePak -PathType Leaf) "缺少原始 EasyCheat PAK: $basePak"
$baseHash = (Get-FileHash -LiteralPath $basePak -Algorithm SHA256).Hash.ToLowerInvariant()
Require ($baseHash -eq $baseInfo.sha256) "原始 EasyCheat PAK 哈希不匹配: $baseHash"

$version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$nextBuild = [int64]$version.lastBuild + 1
Require ($nextBuild -ge 1 -and $nextBuild -le 2147483647) '末位版本号超出 BG3 Version64 范围'
$nextVersion64 = ([int64]$version.major * 36028797018963968) + `
    ([int64]$version.minor * 140737488355328) + `
    ([int64]$version.revision * 2147483648) + $nextBuild
$displayVersion = '{0}.{1}.{2}.{3}' -f $version.major, $version.minor, $version.revision, $nextBuild

Reset-WorkChild $stage
Reset-WorkChild $reverse
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$selectedLslibPath = [IO.Path]::GetFullPath($LslibPath)
Require (Test-Path -LiteralPath $selectedLslibPath -PathType Leaf) "缺少 LSLib: $selectedLslibPath"
Add-Type -Path $selectedLslibPath
$packager = [LSLib.LS.Packager]::new()
$packager.UncompressPackage($basePak, $stage)

$serverInitPath = Join-Path $stage 'Mods\EasyCheat\ScriptExtender\Lua\Server\_Init.lua'
Require (Test-Path -LiteralPath $serverInitPath -PathType Leaf) '原始包缺少 Server/_Init.lua'
$serverInit = Get-Content -LiteralPath $serverInitPath -Raw -Encoding UTF8
$anchor = "})`r`n`r`n-- When the game is started, load the MCM settings"
Require ($serverInit.Contains($anchor, [StringComparison]::Ordinal)) 'Server/_Init.lua 注入锚点不匹配'
Require (-not $serverInit.Contains('Ext.Require("Server/DailyBuffPersistence.lua")', [StringComparison]::Ordinal)) `
    '原始包已包含日常增益持久化加载语句'
$patchedServerInit = $serverInit.Replace(
    $anchor,
    "})`r`n`r`nExt.Require(`"Server/DailyBuffPersistence.lua`")`r`n`r`n-- When the game is started, load the MCM settings",
    [StringComparison]::Ordinal)
[IO.File]::WriteAllText($serverInitPath, $patchedServerInit, [Text.UTF8Encoding]::new($false))

$persistenceSource = Join-Path $root 'Mods\EasyCheat\ScriptExtender\Lua\Server\DailyBuffPersistence.lua'
$persistenceTarget = Join-Path $stage 'Mods\EasyCheat\ScriptExtender\Lua\Server\DailyBuffPersistence.lua'
Copy-Item -LiteralPath $persistenceSource -Destination $persistenceTarget -Force

$metaPath = Join-Path $stage 'Mods\EasyCheat\meta.lsx'
[xml]$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$moduleVersion = $meta.SelectSingleNode('//node[@id="ModuleInfo"]/attribute[@id="Version64"]')
$publishVersion = $meta.SelectSingleNode('//node[@id="ModuleInfo"]/children/node[@id="PublishVersion"]/attribute[@id="Version64"]')
Require ($null -ne $moduleVersion -and $null -ne $publishVersion) 'meta.lsx 缺少版本字段'
$moduleVersion.value = [string]$nextVersion64
$publishVersion.value = [string]$nextVersion64
[IO.File]::WriteAllText($metaPath, $meta.OuterXml, [Text.UTF8Encoding]::new($false))

$outputPak = Join-Path $dist $baseInfo.fileName
if (Test-Path -LiteralPath $outputPak) { Remove-Item -LiteralPath $outputPak -Force }
$build = [LSLib.LS.PackageBuildData]::new()
$build.Version = [LSLib.LS.Enums.PackageVersion]::V18
$build.Compression = [LSLib.LS.CompressionMethod]::LZ4
$build.CompressionLevel = [LSLib.LS.LSCompressionLevel]::Fast
$build.Flags = [LSLib.LS.PackageFlags]0
$build.Hash = $true
$build.ExcludeHidden = $true
$build.Priority = 0
$packager.CreatePackage($outputPak, $stage, $build).GetAwaiter().GetResult()
Require (Test-Path -LiteralPath $outputPak -PathType Leaf) 'EasyCheat PAK 创建失败'

$packager.UncompressPackage($outputPak, $reverse)
$stageFiles = @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/')
} | Sort-Object)
$reverseFiles = @(Get-ChildItem -LiteralPath $reverse -Recurse -File | ForEach-Object {
    [IO.Path]::GetRelativePath($reverse, $_.FullName).Replace('\', '/')
} | Sort-Object)
Require ($stageFiles.Count -eq $reverseFiles.Count -and -not (Compare-Object $stageFiles $reverseFiles)) `
    "反向解包清单不匹配: stage=$($stageFiles.Count) reverse=$($reverseFiles.Count)"
foreach ($relative in $stageFiles) {
    $nativeRelative = $relative.Replace('/', '\')
    $stageHash = (Get-FileHash -LiteralPath (Join-Path $stage $nativeRelative) -Algorithm SHA256).Hash
    $reverseHash = (Get-FileHash -LiteralPath (Join-Path $reverse $nativeRelative) -Algorithm SHA256).Hash
    Require ($stageHash -eq $reverseHash) "反向解包哈希不匹配: $relative"
}

$version.lastBuild = $nextBuild
$version | ConvertTo-Json | Set-Content -LiteralPath $versionPath -Encoding UTF8
$manifest = [ordered]@{
    schema = 1
    displayVersion = $displayVersion
    version64 = $nextVersion64
    moduleName = 'EasyCheat'
    moduleUuid = '5b5ad5b6-ce37-4a63-8dea-a1fee4cee156'
    basePakSha256 = $baseHash
    pakSha256 = (Get-FileHash -LiteralPath $outputPak -Algorithm SHA256).Hash.ToLowerInvariant()
    files = $stageFiles
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dist 'easycheat-build-manifest.json') -Encoding UTF8
Write-Host "EasyCheat 构建并反向校验完成: $displayVersion ($nextVersion64), $outputPak ($($stageFiles.Count) files)"
