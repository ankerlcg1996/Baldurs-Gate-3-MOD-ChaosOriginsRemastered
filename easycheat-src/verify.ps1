#requires -Version 7.0

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$baseInfoPath = Join-Path $root 'base-pak.json'
$versionPath = Join-Path $root 'version.json'
$persistencePath = Join-Path $root 'Mods\EasyCheat\ScriptExtender\Lua\Server\DailyBuffPersistence.lua'

Require (Test-Path -LiteralPath $baseInfoPath -PathType Leaf) '缺少 base-pak.json'
Require (Test-Path -LiteralPath $versionPath -PathType Leaf) '缺少 version.json'
Require (Test-Path -LiteralPath $persistencePath -PathType Leaf) '缺少日常增益持久化模块'

$baseInfo = Get-Content -LiteralPath $baseInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($baseInfo.schema -eq 1) '不支持的基础包描述格式'
Require ($baseInfo.sha256 -match '^[0-9a-f]{64}$') '基础包 SHA256 格式错误'

$version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($version.schema -eq 1) '不支持的版本文件格式'
foreach ($field in @('major', 'minor', 'revision', 'lastBuild')) {
    Require ($version.$field -is [int] -or $version.$field -is [long]) "版本字段必须为整数: $field"
}

$source = Get-Content -LiteralPath $persistencePath -Raw -Encoding UTF8
foreach ($requiredText in @(
    'EasyCheat/DailyBuffSettings.json',
    'Ext.IO.SaveFile(SETTINGS_PATH, contents)',
    'Ext.IO.LoadFile(SETTINGS_PATH)',
    'RestoreDailyBuffSettings()',
    'originalOnLevelGameplayStarted(...)',
    'originalOnResetCompleted(...)',
    'originalOnRequestChangeDailyBuffs(...)',
    'SaveDailyBuffSettings(settings)'
)) {
    Require ($source.Contains($requiredText, [StringComparison]::Ordinal)) "持久化模块缺少关键逻辑: $requiredText"
}

$changeStart = $source.IndexOf('EHandlers.OnRequestChangeDailyBuffs = function(...)', [StringComparison]::Ordinal)
$changeCall = $source.IndexOf('originalOnRequestChangeDailyBuffs(...)', $changeStart, [StringComparison]::Ordinal)
$changeSave = $source.IndexOf('SaveDailyBuffSettings(settings)', $changeCall, [StringComparison]::Ordinal)
Require ($changeStart -ge 0 -and $changeCall -gt $changeStart -and $changeSave -gt $changeCall) `
    '必须在原勾选逻辑成功完成后立即保存日常增益设置'

Write-Host 'EasyCheat 日常增益持久化源代码校验通过。'
