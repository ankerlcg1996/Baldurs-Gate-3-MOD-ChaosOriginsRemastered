$ErrorActionPreference = 'Stop'
$goals = Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals'
$mastery = (Get-Content "$goals/COS_ChaosMastery.txt" -Raw).Replace("`r`n", "`n")
$mechanics = (Get-Content "$goals/COS_ChaosMechanics.txt" -Raw).Replace("`r`n", "`n")
$config = (Get-Content "$goals/COS_Config.txt" -Raw).Replace("`r`n", "`n")
$stats = Get-Content (Join-Path $PSScriptRoot 'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosDamage.txt') -Raw
function Check($ok, $message) { if (-not $ok) { throw $message } }
$rows = [regex]::Matches($mastery, 'DB_COS_OverviewRow\((\d+), (\d+), "([^"]+)"\);')
Check ($rows.Count -eq 91) '总览必须覆盖 91 种合法分配，不能缺失或重复'
$seen = @{}
$translations = @{}
foreach ($lang in @('Chinese','English','Japanese','Korean')) {
    [xml]$xml = Get-Content (Join-Path $PSScriptRoot "Localization/$lang/ChaosOriginsStory.xml") -Raw
    $translations[$lang] = $xml
}
foreach ($row in $rows) {
    $t = [int]$row.Groups[1].Value; $c = [int]$row.Groups[2].Value
    Check ($t + $c -le 12 -and -not $seen.ContainsKey("$t,$c")) '总览映射重复或超出 12 点'
    $seen["$t,$c"] = 1
    $id = $row.Groups[3].Value
    $block = [regex]::Match($stats, '(?s)new entry "' + $id + '".*?(?=new entry|\z)').Value
    Check ($block -ne '' -and $block -notmatch 'data "(Boosts|OnApplyFunctors|OnRemoveFunctors)"') '总览不得影响数值或事件'
    $handle = [regex]::Match($block, 'data "Description" "([^;]+);1"').Groups[1].Value
    foreach ($lang in @('Chinese','English','Japanese','Korean')) {
        $xml = $translations[$lang]
        $content = @($xml.contentList.content | Where-Object contentuid -eq $handle)
        Check ($content.Count -eq 1) "总览翻译缺失: $lang $t/$c"
        $s = $content[0].InnerText
        foreach ($n in @((162+2*$t), (138-2*$t-4*$c), (4*$c))) {
            Check ($s.Contains("$n/300")) "总览权重与实际抽签不一致: $lang $t/$c"
        }
    }
}
Check ($mastery.Contains('DB_COS_ConfigMechanic(_Character, "Wound", 0)')) '轮盘关闭必须单独显示'
Check ($mastery.Contains('DB_COS_ConfigMechanic(_Character, "Mastery", 0)')) '掌控关闭必须显示基础概率'
Check ($mastery.Contains('HasActiveStatus(_Character, _Status, 0)')) '已有总览不能重复应用'
Check ($config.Contains('PROC_COS_SyncOverview(_Character);')) '设置更改必须刷新总览'
Check ($mastery.Contains('PROC_COS_SyncOverview(_Character);')) '路线分配必须刷新总览'
$finish = [regex]::Match($mechanics, '(?ms)^PROC\nPROC_COS_FinishWoundTrials\([^\n]+\).*?(?=^PROC\n)').Value
Check ($finish.Contains('PROC_COS_RecordWoundResult(_Character, _BestOutcome);')) '只能记录最终选择，不能丢失最终记录'
Check ([regex]::Matches($mechanics, 'PROC_COS_RecordWoundResult\(_Character, _BestOutcome\);').Count -eq 1) '不得在候选判定中反复记录'
$logs = [regex]::Matches($mechanics, 'DB_COS_RecentWound\((\d+), "([^"]+)"\);')
Check ($logs.Count -eq 28) '最近结果必须覆盖 0-26 和平息 38'
foreach ($row in $logs) {
    $block = [regex]::Match($stats, '(?s)new entry "' + $row.Groups[2].Value + '".*?(?=new entry|\z)').Value
    Check ($block.Contains('data "StackId" "COS_RECENT_WOUND"')) '最近结果必须互相覆盖'
    Check ($block -notmatch 'data "(Boosts|OnApplyFunctors|OnRemoveFunctors)"') '最近结果不能再次发放效果'
}
foreach ($token in @(
    'IntegerProduct(_TuneCount, 2, _TuneCells)',
    'IntegerProduct(_CorrectCount, 4, _CalmCells)',
    'IntegerSum(162, _TuneCells, _PositiveEnd)',
    'IntegerSum(_PositiveEnd, _CalmCells, _CalmEnd)',
    'Random(300, _CategoryRoll)'
)) { Check ($mechanics.Contains($token)) "实际抽签公式改变，请同步检查总览: $token" }
$overviewBlock = [regex]::Match($mastery, '(?s)// Read-only overview.*?EXITSECTION').Value
Check ($overviewBlock -notmatch 'Random\(|SetHitpoints\(|ApplyDamage\(|AddPassive\(|NOT DB_COS_Mastery') '总览不能写入战斗或成长状态'
$recordBlock = [regex]::Match($mechanics, '(?s)// Snapshot of the adopted draw.*?EXITSECTION').Value
Check ($recordBlock -notmatch 'Random\(|SetHitpoints\(|ApplyDamage\(') '记录不能再次结算'
$ids = @($logs | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
Check (-not (Compare-Object (@(0..26) + @(38)) $ids)) '抽签结果编号缺失'
Write-Host 'PASS: 91 probability combinations, disabled states and 28 final wound records.'
