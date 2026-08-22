param([string]$DivinePath = 'C:\Users\ankerlcg\Documents\ChatGPT\博德之门3Mod\.tools\ExportTool-v1.20.4\Packed\Tools\Divine.exe')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$sourceRoot = Join-Path $root 'resource-src'
$outputRoot = Join-Path $root 'work\compiled-resources'
$manifestPath = Join-Path $root 'package-files.json'
foreach ($path in @($DivinePath, $sourceRoot, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "缺少资源编译输入: $path" }
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$manifest = @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).files)
$resourceTargets = @($manifest | Where-Object { $_.EndsWith('.lsf') } | Sort-Object)
if ($resourceTargets.Count -eq 0) { throw '打包清单没有 LSF 资源' }
$declaredSources = @($resourceTargets | ForEach-Object { $_ + '.lsx' } | Sort-Object)
$actualSources = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.lsx' | ForEach-Object {
    [IO.Path]::GetRelativePath($sourceRoot, $_.FullName).Replace('\', '/')
} | Sort-Object)
if ($declaredSources.Count -ne $actualSources.Count -or (Compare-Object $declaredSources $actualSources)) {
    throw "资源源文件与打包清单不匹配: declared=$($declaredSources.Count) actual=$($actualSources.Count)"
}
foreach ($relativeTarget in $resourceTargets) {
    $relativeSource = $relativeTarget + '.lsx'
    $source = Join-Path $sourceRoot $relativeSource.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "清单资源源文件不存在: $relativeSource" }
    $target = Join-Path $outputRoot $relativeTarget.Replace('/', '\')
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    & $DivinePath -g bg3 -a convert-resource -s $source -d $target -i lsx -o lsf
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "资源编译失败: $relativeSource" }
}
Write-Host "Story 资源编译完成: $($resourceTargets.Count)"
