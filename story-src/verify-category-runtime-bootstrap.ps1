#requires -Version 7.0

$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot 'Mods\ChaosOriginsStory\Story\RawFiles\Goals\COS_Config.txt'
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8

function Get-RuleBlock {
    param(
        [Parameter(Mandatory)][string]$HeadPattern,
        [Parameter(Mandatory)][string]$Context
    )

    $matches = @([regex]::Matches(
        $source,
        '(?ms)^(?:PROC|IF)\r?\n' + $HeadPattern + '.*?(?=^(?:PROC|IF|EXITSECTION)\s*$|\z)'
    ))
    if ($matches.Count -ne 1) {
        throw "$Context 规则缺失或重复: $($matches.Count)"
    }
    $matches[0].Value
}

$sync = Get-RuleBlock -HeadPattern 'PROC_COS_ConfigSyncCharacter\(\(CHARACTER\)_Character\)\r?\n' -Context '统一配置同步'
$timerLaunch = 'RealtimeObjectTimerLaunch(_Character, "COS_ConfigPostSeedRefresh", 100);'
$seedIndex = $sync.IndexOf('PROC_COS_PresetSeed();', [System.StringComparison]::Ordinal)
$launchIndex = $sync.IndexOf($timerLaunch, [System.StringComparison]::Ordinal)
if ($seedIndex -lt 0) {
    throw '统一配置同步未写入预设/分类运行时映射'
}
if ($launchIndex -le $seedIndex) {
    throw '运行时映射写入后没有排队下一轮事件启用与状态刷新'
}

$refresh = Get-RuleBlock -HeadPattern 'ObjectTimerFinished\(_Object, "COS_ConfigPostSeedRefresh"\)\r?\n' -Context '映射写入后刷新'
foreach ($required in @(
    'HasPassive(_Object, "COS_ChaosOriginMarker", 1)',
    'PROC_COS_ConfigEnableEvents((CHARACTER)_Object);',
    'PROC_COS_PresetDetect((CHARACTER)_Object);',
    'PROC_COS_ConfigSyncCategoryActual((CHARACTER)_Object);',
    'PROC_COS_RuntimeDiagnosticUpdate((CHARACTER)_Object);'
)) {
    if (-not $refresh.Contains($required, [System.StringComparison]::Ordinal)) {
        throw "映射写入后刷新缺少动作: $required"
    }
}

$enableIndex = $refresh.IndexOf('PROC_COS_ConfigEnableEvents((CHARACTER)_Object);', [System.StringComparison]::Ordinal)
$actualIndex = $refresh.IndexOf('PROC_COS_ConfigSyncCategoryActual((CHARACTER)_Object);', [System.StringComparison]::Ordinal)
if ($enableIndex -lt 0 -or $actualIndex -le $enableIndex) {
    throw '映射写入后刷新顺序错误：必须先启用按钮事件，再投影分类实际状态'
}

Write-Output 'CATEGORY_RUNTIME_BOOTSTRAP=PASS; IN_GAME=PENDING'
