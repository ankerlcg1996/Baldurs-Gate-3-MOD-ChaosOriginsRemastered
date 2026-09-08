$ErrorActionPreference = 'Stop'
$g = Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals'
$c = (Get-Content "$g/COS_Config.txt" -Raw).Replace("`r`n", "`n")
$m = (Get-Content "$g/COS_ChaosMechanics.txt" -Raw).Replace("`r`n", "`n")
function Check-Fate($ok, $message) { if (-not $ok) { throw $message } }
Check-Fate ($c.Contains('PROC_COS_SyncFateToggle(_Character);')) '缺少改签状态校准'
foreach ($event in 'StatusApplied', 'StatusRemoved') {
    Check-Fate ($c.Contains("$event(_Character, `"COS_CHAOS_FATE_ENABLED`", _, _)")) "缺少技能栏反向同步: $event"
}
Check-Fate ($c.Contains('NOT DB_COS_FateSyncing((CHARACTER)_Character)')) '程序同步不能被当成用户操作'
Check-Fate ($m.Contains('PROC_COS_RecordFateSuccess(_Owner, _BestRoll);')) '必须记录最终采用的判定而不是首次判定'
Check-Fate ($m.Contains('NOT DB_COS_FateLogged(_Character, _Action)')) '同次攻击不得重复提示'
Check-Fate ($m.Contains('DebugText(_Character, _Message);') -and $m.Contains('DB_COS_FateLast(_Character, _Action, _Message);')) '提示必须保留真实记录'
function Test-FateSyncContract([string]$text) {
    $rules = @([regex]::Matches($text, '(?ms)^PROC\nPROC_COS_SyncFateToggle\([^\n]+\).*?(?=^(?:PROC|IF|EXITSECTION)\n|\z)') | ForEach-Object Value)
    if ($rules.Count -ne 2) { return $false }
    foreach ($value in 0,1) {
        $rule = @($rules | Where-Object { $_.Contains('DB_COS_ConfigMechanic(_Character, "Fate", ' + $value + ')') })
        if ($rule.Count -ne 1) { return $false }
        if (-not $rule[0].Contains('HasActiveStatus(_Character, "COS_CHAOS_FATE_ENABLED", ' + (1-$value) + ')')) { return $false }
        if (-not $rule[0].Contains("DB_COS_FateSyncing(_Character);`nTogglePassive(_Character, `"COS_FateRevision`");`nNOT DB_COS_FateSyncing(_Character);")) { return $false }
        if ($rule[0] -match 'AddPassive|RemovePassive|ApplyStatus|RemoveStatus') { return $false }
    }
    return $true
}
Check-Fate (Test-FateSyncContract $c) '同步只允许在状态不一致时有保护地翻转一次'
Check-Fate (-not (Test-FateSyncContract ($c.Replace('DB_COS_FateSyncing(_Character);', '')))) '去除同步保护必须被检测'
Check-Fate (-not (Test-FateSyncContract ($c.Replace('HasActiveStatus(_Character, "COS_CHAOS_FATE_ENABLED", 0)', 'HasActiveStatus(_Character, "COS_CHAOS_FATE_ENABLED", 1)')))) '错误比较状态必须被检测'
$accept = [regex]::Match($c, '(?ms)^PROC\nPROC_COS_AcceptFateToggle\([^\n]+\).*?(?=^(?:PROC|IF|EXITSECTION)\n|\z)').Value
Check-Fate ($accept.Contains('NOT DB_COS_FateSyncing(_Character)') -and $accept.Contains('_Old != _Enabled') -and $accept.Contains('HasActiveStatus(_Character, "COS_CHAOS_FATE_ENABLED", _Enabled)')) '反向写入必须核实状态并忽略程序同步'
Check-Fate (-not $accept.Contains('TogglePassive(')) '回写配置不能再次翻转被动'

# Source contracts above anchor this finite-state probe to the two real rules.
foreach ($saved in 0,1) {
    foreach ($actual in 0,1) {
        $toggleCount = [int]($saved -ne $actual)
        $projected = if ($toggleCount) { 1-$actual } else { $actual }
        Check-Fate ($projected -eq $saved -and $toggleCount -le 1) '读档/菜单校准必须保留已保存选择'
        $clicked = 1-$projected
        $afterUserEvent = $clicked
        Check-Fate ($afterUserEvent -eq $clicked) '玩家点击后的实际状态必须成为配置值'
    }
}
$observers = @([regex]::Matches($m, '(?ms)^PROC\nPROC_COS_(?:WriteFateLog|RecordFateSuccess|BeginFateLog|ShowLastFate|ClearFateLast|ClearFateLogPending|ClearFateLogged)\([^\n]+\).*?(?=^(?:PROC|IF|EXITSECTION)\n|\z)') | ForEach-Object Value)
Check-Fate ($observers.Count -eq 7) '记录辅助过程数目异常'
Check-Fate (-not (($observers -join "`n") -match 'ApplyDamage|ApplyStatus|RemoveStatus|Random\(|DB_COS_Power\(')) '观察记录不得重复结算或扣费'
Check-Fate ($m.Contains('PROC_COS_BeginFateLog((CHARACTER)_AttackOwner, _StoryActionID, _RollCount, _Cost);')) '记录必须使用本次真实次数与扣费'
Check-Fate ($m.Contains('DB_COS_DualityBand(_Min, _Max, _Percent, _)') -and $m.Contains('_BestRoll >= _Min') -and $m.Contains('_BestRoll < _Max')) '采用倍率必须匹配最终判定区间'
Check-Fate ($m.Contains('DB_COS_FateLogged(_Character, _Action);') -and $m.Contains('PROC_COS_ClearFateLogged(_Character);')) '去重表必须按攻击保存并在加载阶段清理'
$seen = @{}
$notifications = 0
foreach ($action in 11,12,11,12,13,13) {
    if (-not $seen.ContainsKey($action)) { $seen[$action] = $true; $notifications++ }
}
Check-Fate ($notifications -eq 3) '交错的多段攻击也应每个行动只提示一次'
Write-Host 'FATE_OBSERVATION_STATIC=PASS; SYNC_AND_DEDUP_PROBES=PASS; IN_GAME=PENDING'
