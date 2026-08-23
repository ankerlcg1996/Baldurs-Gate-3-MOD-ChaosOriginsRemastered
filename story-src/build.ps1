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
& (Join-Path $root 'compile-resources.ps1')
Require (Test-Path -LiteralPath $LslibPath -PathType Leaf) "缺少 LSLib: $LslibPath"

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
    if ($relative.EndsWith('.lsf')) {
        $source = Join-Path $work ('compiled-resources\' + $nativeRelative)
    } elseif ($relative.EndsWith('.loca')) {
        continue
    } else {
        $source = Join-Path $root $nativeRelative
    }
    Require (Test-Path -LiteralPath $source -PathType Leaf) "清单源文件不存在: $relative -> $source"
    Copy-Item -LiteralPath $source -Destination $target -Force
}

Add-Type -Path $LslibPath
foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $xml = Join-Path $root "Localization\$language\ChaosOriginsStory.xml"
    $target = Join-Path $stage "Localization\$language\ChaosOriginsStory.loca"
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    $localization = [LSLib.LS.LocaUtils]::Load($xml)
    [LSLib.LS.LocaUtils]::Save($localization, $target)
    Require (Test-Path -LiteralPath $target -PathType Leaf) "本地化编译失败: $language"
}

$actual = @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/')
} | Sort-Object)
$expected = @($manifest | Sort-Object)
Require ($actual.Count -eq $expected.Count -and -not (Compare-Object $expected $actual)) `
    "打包清单不匹配: expected=$($expected.Count) actual=$($actual.Count)"
Require (-not ($actual | Where-Object { $_ -match '/Story/|ScriptExtender|MCM|GUI/|ActionResourceDefinitions' })) `
    '最小起源包夹带了 Story、SE、设置、图标或动作资源'

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

Write-Host "Story 最小起源 PAK 构建并反向校验完成: $pak ($($actual.Count) files)"

