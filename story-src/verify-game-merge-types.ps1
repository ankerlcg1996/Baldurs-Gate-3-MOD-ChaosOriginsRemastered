#requires -Version 7.0

param([string]$Root = $PSScriptRoot)

$ErrorActionPreference = 'Stop'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Required([string]$Path) {
    Require (Test-Path -LiteralPath $Path -PathType Leaf) "缺少文件: $Path"
    Get-Content -LiteralPath $Path -Raw
}

function Get-StatusEventBlocks([string]$Content) {
    @([regex]::Matches(
        $Content,
        '(?ms)^IF\r?\nStatus(?:Applied|Removed)\(_Character,[\s\S]*?(?=^IF\r?$|^PROC\r?$|^EXITSECTION\r?$)'
    ) | ForEach-Object { $_.Value })
}

$goals = Join-Path $Root 'Mods\ChaosOriginsStory\Story\RawFiles\Goals'
$base = Read-Required (Join-Path $goals 'COS_BaseAfterCreation.txt')
$config = Read-Required (Join-Path $goals 'COS_Config.txt')

$baseStatusBlocks = @(Get-StatusEventBlocks $base | Where-Object {
    $_ -match 'DB_COS_OriginIdentity(?:Toggle|Spell|Passive)'
})
Require ($baseStatusBlocks.Count -eq 6) `
    "起源身份状态事件规则数量错误: $($baseStatusBlocks.Count)"
foreach ($block in $baseStatusBlocks) {
    Require (-not [regex]::IsMatch(
        $block,
        'DB_COS_(?:ConfigCategory|Origin(?:Tag|Spell|Passive)Owned)\(_Character'
    )) '起源身份状态事件把 GUIDSTRING 直接传入 CHARACTER 数据库'
}

$fateStatusBlocks = @(Get-StatusEventBlocks $config | Where-Object {
    $_ -match 'COS_CHAOS_FATE_ENABLED'
})
Require ($fateStatusBlocks.Count -eq 2) `
    "命运改签状态事件规则数量错误: $($fateStatusBlocks.Count)"
foreach ($block in $fateStatusBlocks) {
    Require (-not $block.Contains('DB_COS_ConfigCategory(_Character')) `
        '命运改签状态事件把 GUIDSTRING 直接传入 CHARACTER 数据库'
}

$untypedPresetCalls = @([regex]::Matches(
    $config,
    'DB_COS_RuntimeDiagnosticPresetApplyFailed\([^\r\n]*, _Preset\)'
))
Require ($untypedPresetCalls.Count -eq 0) `
    "运行诊断预设失败数据库仍有未声明 STRING 的参数: $($untypedPresetCalls.Count)"

Write-Output 'GAME_MERGE_OSIRIS_TYPES=PASS'
