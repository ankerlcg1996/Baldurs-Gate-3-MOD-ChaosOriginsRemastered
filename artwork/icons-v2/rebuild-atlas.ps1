#requires -Version 7.0

param(
    [string]$RepositoryRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$BaselineCommit = 'ad3c4cc',
    [string]$AtlasPath = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        'story-src\Public\ChaosOriginsStory\Assets\Textures\Icons\Icons_ChaosOrigins.dds')
)

$ErrorActionPreference = 'Stop'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-GitBlobBytes([string]$WorkingDirectory, [string]$ObjectSpec) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.ArgumentList.Add('cat-file')
    $startInfo.ArgumentList.Add('blob')
    $startInfo.ArgumentList.Add($ObjectSpec)
    $process = [Diagnostics.Process]::Start($startInfo)
    $stream = [IO.MemoryStream]::new()
    try {
        $process.StandardOutput.BaseStream.CopyTo($stream)
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "git cat-file 失败: $ObjectSpec / $stderr" }
        return $stream.ToArray()
    } finally {
        $stream.Dispose()
        $process.Dispose()
    }
}

$repositoryFull = [IO.Path]::GetFullPath($RepositoryRoot)
$atlasFull = [IO.Path]::GetFullPath($AtlasPath)
$magick = Get-Command magick -ErrorAction SilentlyContinue
Require ($null -ne $magick) '重建图标需要 ImageMagick magick'
Require (Test-Path -LiteralPath $repositoryFull -PathType Container) "仓库目录不存在: $repositoryFull"
Require (Test-Path -LiteralPath (Split-Path $atlasFull -Parent) -PathType Container) `
    "DDS输出目录不存在: $atlasFull"

$iconCells = [ordered]@{
    COS_Lost = @(2, 0)
    COS_Power = @(3, 0)
    COS_AllIn = @(0, 1)
    COS_Strike = @(2, 1)
    COS_Genesis = @(3, 1)
    COS_Finisher = @(0, 2)
    COS_Wound = @(1, 2)
    COS_Duality = @(2, 2)
    COS_FateRevision = @(3, 2)
    COS_Mastery = @(0, 3)
    COS_MasteryTune = @(1, 3)
    COS_MasteryCorrect = @(2, 3)
}
$previewOrder = @(
    'COS_Power', 'COS_Lost', 'COS_Wound', 'COS_Duality',
    'COS_AllIn', 'COS_FateRevision', 'COS_Genesis', 'COS_Strike',
    'COS_Mastery', 'COS_MasteryTune', 'COS_MasteryCorrect', 'COS_Finisher'
)
foreach ($iconKey in $iconCells.Keys) {
    Require (Test-Path -LiteralPath (Join-Path $PSScriptRoot "$iconKey.png") -PathType Leaf) `
        "缺少图标源: $iconKey.png"
}

$baselineSpec = "$BaselineCommit`:story-src/Public/ChaosOriginsStory/Assets/Textures/Icons/Icons_ChaosOrigins.dds"
$baselineBytes = Get-GitBlobBytes $repositoryFull $baselineSpec
Require ($baselineBytes.Length -eq 349680 -and `
    [Text.Encoding]::ASCII.GetString($baselineBytes, 0, 4) -eq 'DDS ' -and `
    [BitConverter]::ToInt32($baselineBytes, 12) -eq 512 -and `
    [BitConverter]::ToInt32($baselineBytes, 16) -eq 512 -and `
    [BitConverter]::ToInt32($baselineBytes, 28) -eq 10 -and `
    [Text.Encoding]::ASCII.GetString($baselineBytes, 84, 4) -eq 'DXT5') `
    "基线对象不是预期的512x512/10 mip/DXT5 DDS: $baselineSpec"

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
    [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$temp = Join-Path $tempRoot ('cos-icon-atlas-' + [guid]::NewGuid().ToString('N'))
$tempFull = [IO.Path]::GetFullPath($temp)
Require ($tempFull.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase) -and
    [IO.Path]::GetFileName($tempFull).StartsWith('cos-icon-atlas-', [StringComparison]::Ordinal)) `
    "拒绝使用未验证的临时目录: $tempFull"
[void][IO.Directory]::CreateDirectory($tempFull)

$cleanAlphaExpression = `
    '(a>0)&&(r<=0.156863)&&(g<=0.156863)&&(b<=0.156863)&&(abs(r-g)<=0.039216)&&(abs(r-b)<=0.039216)&&(abs(g-b)<=0.039216)?0:a'
$clearHiddenRgbExpression = 'a<=0?0:u'
$cleanedSources = @{}
$thumbnails = @{}
try {
    foreach ($iconKey in $iconCells.Keys) {
        $source = Join-Path $PSScriptRoot "$iconKey.png"
        $cleaned = Join-Path $tempFull "$iconKey-cleaned.png"
        $thumbnail = Join-Path $tempFull "$iconKey-64.png"
        & $magick.Source $source -alpha set -channel A -fx $cleanAlphaExpression `
            -channel RGB -fx $clearHiddenRgbExpression +channel -strip -define png:color-type=6 $cleaned
        Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $cleaned -PathType Leaf)) `
            "图标matte清理失败: $iconKey"
        & $magick.Source $cleaned -filter Lanczos -resize '64x64!' -strip -define png:color-type=6 $thumbnail
        Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $thumbnail -PathType Leaf)) `
            "图标64px缩放失败: $iconKey"
        $cleanedSources[$iconKey] = $cleaned
        $thumbnails[$iconKey] = $thumbnail
    }

    $blankAtlas = Join-Path $tempFull 'targets-512.png'
    $atlasArguments = [Collections.Generic.List[string]]::new()
    $atlasArguments.Add('-size')
    $atlasArguments.Add('512x512')
    $atlasArguments.Add('canvas:none')
    foreach ($iconKey in $iconCells.Keys) {
        $cell = $iconCells[$iconKey]
        $atlasArguments.Add($thumbnails[$iconKey])
        $atlasArguments.Add('-geometry')
        $atlasArguments.Add(('+{0}+{1}' -f ([int]$cell[0] * 64), ([int]$cell[1] * 64)))
        $atlasArguments.Add('-compose')
        $atlasArguments.Add('over')
        $atlasArguments.Add('-composite')
    }
    $atlasArguments.Add('-strip')
    $atlasArguments.Add('-define')
    $atlasArguments.Add('png:color-type=6')
    $atlasArguments.Add($blankAtlas)
    & $magick.Source @atlasArguments
    Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $blankAtlas -PathType Leaf)) `
        '目标格空白图层合成失败'

    $encodedTargets = Join-Path $tempFull 'targets-encoded.dds'
    & $magick.Source $blankAtlas -define dds:compression=dxt5 -define dds:mipmaps=10 $encodedTargets
    Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $encodedTargets -PathType Leaf)) `
        '目标格DXT5编码失败'
    $encodedBytes = [IO.File]::ReadAllBytes($encodedTargets)
    Require ($encodedBytes.Length -eq $baselineBytes.Length -and `
        [BitConverter]::ToInt32($encodedBytes, 28) -eq 10 -and `
        [Text.Encoding]::ASCII.GetString($encodedBytes, 84, 4) -eq 'DXT5') `
        '目标格DDS布局与基线不一致'

    [byte[]]$patchedBytes = $baselineBytes.Clone()
    $mipOffset = 128
    for ($mip = 0; $mip -lt 10; $mip++) {
        $mipSize = [Math]::Max(1, 512 -shr $mip)
        $blocksWide = [Math]::Max(1, [int][Math]::Ceiling($mipSize / 4.0))
        $blocksHigh = $blocksWide
        if ($mip -le 4) {
            $cellSize = 64 -shr $mip
            $cellBlocks = $cellSize / 4
            foreach ($iconKey in $iconCells.Keys) {
                $cell = $iconCells[$iconKey]
                $firstBlockX = ([int]$cell[0] * $cellSize) / 4
                $firstBlockY = ([int]$cell[1] * $cellSize) / 4
                for ($blockY = 0; $blockY -lt $cellBlocks; $blockY++) {
                    $sourceOffset = $mipOffset + ((($firstBlockY + $blockY) * $blocksWide +
                        $firstBlockX) * 16)
                    [Array]::Copy($encodedBytes, $sourceOffset, $patchedBytes, $sourceOffset,
                        $cellBlocks * 16)
                }
            }
        }
        $mipOffset += $blocksWide * $blocksHigh * 16
    }
    Require ($mipOffset -eq $patchedBytes.Length) 'DDS mip写入未覆盖完整布局'

    $preview = Join-Path $tempFull 'preview-64px.png'
    $previewArguments = [Collections.Generic.List[string]]::new()
    $previewArguments.Add('-size')
    $previewArguments.Add('320x240')
    $previewArguments.Add('xc:#808080')
    for ($previewIndex = 0; $previewIndex -lt $previewOrder.Count; $previewIndex++) {
        $previewKey = $previewOrder[$previewIndex]
        $previewX = 20 + (($previewIndex % 4) * 72)
        $previewY = 16 + ([Math]::Floor($previewIndex / 4) * 72)
        $previewArguments.Add($thumbnails[$previewKey])
        $previewArguments.Add('-geometry')
        $previewArguments.Add("+$previewX+$previewY")
        $previewArguments.Add('-compose')
        $previewArguments.Add('over')
        $previewArguments.Add('-composite')
    }
    $previewArguments.Add('-alpha')
    $previewArguments.Add('off')
    $previewArguments.Add('-strip')
    $previewArguments.Add($preview)
    & $magick.Source @previewArguments
    Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $preview -PathType Leaf)) `
        '灰底64px预览生成失败'

    foreach ($iconKey in $iconCells.Keys) {
        [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot "$iconKey.png"),
            [IO.File]::ReadAllBytes($cleanedSources[$iconKey]))
    }
    [IO.File]::WriteAllBytes($atlasFull, $patchedBytes)
    [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'preview-64px.png'),
        [IO.File]::ReadAllBytes($preview))
} finally {
    if ([IO.Directory]::Exists($tempFull)) {
        foreach ($tempFile in [IO.Directory]::GetFiles($tempFull)) { [IO.File]::Delete($tempFile) }
        [IO.Directory]::Delete($tempFull)
    }
}

Write-Host 'Rebuilt icon sources, gray preview, and baseline-preserving BC3 atlas.'
