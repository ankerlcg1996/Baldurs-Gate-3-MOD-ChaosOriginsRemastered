param([string]$LslibPath = 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$repo = Split-Path $root -Parent
$work = Join-Path $root 'work'
$stage = Join-Path $work 'staging'
$reverse = Join-Path $work 'reverse'
$dist = Join-Path $repo 'dist'
$pak = Join-Path $dist 'ChaosOriginsStory.pak'
$manifest = (Get-Content -LiteralPath (Join-Path $root 'package-files.json') -Raw | ConvertFrom-Json).files
if (-not (Test-Path -LiteralPath $LslibPath -PathType Leaf)) { throw "缺少 LSLib: $LslibPath" }

& (Join-Path $root 'compile-story.ps1')
& (Join-Path $root 'compile-resources.ps1')

foreach ($path in @($stage, $reverse)) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $resolvedWork = (Resolve-Path -LiteralPath $work).Path
    if (-not $resolved.StartsWith($resolvedWork + [IO.Path]::DirectorySeparatorChar)) { throw "拒绝清理工作目录外路径: $resolved" }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Path $stage, $reverse, $dist -Force | Out-Null

foreach ($relative in $manifest) {
    $target = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    if ($relative -eq 'Mods/ChaosOriginsStory/Story/story.div.osi') {
        $source = Join-Path $work 'compiled-story\story.div.osi'
    } elseif ($relative.EndsWith('.lsf')) {
        $source = Join-Path $work ('compiled-resources\' + $relative.Replace('/', '\'))
    } elseif ($relative.EndsWith('.loca')) {
        continue
    } else {
        $source = Join-Path $root $relative.Replace('/', '\')
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "清单源文件不存在: $relative -> $source" }
    Copy-Item -LiteralPath $source -Destination $target -Force
}

Add-Type -Path $LslibPath
foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $xml = Join-Path $root "Localization\$language\ChaosOriginsStory.xml"
    $target = Join-Path $stage "Localization\$language\ChaosOriginsStory.loca"
    $resource = [LSLib.LS.LocaUtils]::Load($xml)
    [LSLib.LS.LocaUtils]::Save($resource, $target)
}

$actual = @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/') } | Sort-Object)
$expected = @($manifest | Sort-Object)
if ($actual.Count -ne $expected.Count -or (Compare-Object $expected $actual)) { throw "打包清单不匹配: expected=$($expected.Count) actual=$($actual.Count)" }
if (Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.FullName -match 'ScriptExtender|MCM_blueprint|BG3MCM' }) { throw 'Story 包含 SE 或 MCM 文件' }

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
$packager.UncompressPackage($pak, $reverse)

$reverseFiles = @(Get-ChildItem -LiteralPath $reverse -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($reverse, $_.FullName).Replace('\', '/') } | Sort-Object)
if ($actual.Count -ne $reverseFiles.Count -or (Compare-Object $actual $reverseFiles)) { throw "反向解包清单不匹配: stage=$($actual.Count) reverse=$($reverseFiles.Count)" }
foreach ($relative in $actual) {
    $stageHash = (Get-FileHash -LiteralPath (Join-Path $stage $relative)).Hash
    $reverseHash = (Get-FileHash -LiteralPath (Join-Path $reverse $relative)).Hash
    if ($stageHash -ne $reverseHash) { throw "反向解包哈希不匹配: $relative" }
}
Write-Host "Story PAK 构建并反向校验完成: $pak ($($actual.Count) files)"

