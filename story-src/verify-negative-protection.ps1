$ErrorActionPreference = 'Stop'
$m = (Get-Content (Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt') -Raw).Replace("`r`n", "`n")
$stats = Get-Content (Join-Path $PSScriptRoot 'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosDamage.txt') -Raw
function Assert-Protection($ok, $message) { if (-not $ok) { throw $message } }
function Get-Rules($name) { @([regex]::Matches($m, "(?ms)^PROC\n$([regex]::Escape($name))\([^\n]*\).*?(?=^(?:PROC|IF|QRY|EXITSECTION)\b|\z)") | ForEach-Object Value) }
$families = @(
    @{ Ids = @(0,1,2); Strong = 'COS_CHAOS_WOUND_ATTACK_MINUS_3'; Boost = 'RollBonus(Attack,-3)' },
    @{ Ids = @(3,4,5); Strong = 'COS_CHAOS_WOUND_AC_MINUS_3'; Boost = 'AC(-3)' },
    @{ Ids = @(6,7,8); Strong = 'COS_CHAOS_WOUND_SAVE_MINUS_3'; Boost = 'RollBonus(SavingThrow,-3)' },
    @{ Ids = @(9,10,11); Strong = 'COS_CHAOS_WOUND_CHECK_MINUS_3'; Boost = 'RollBonus(SkillCheck,-3);RollBonus(RawAbility,-3)' },
    @{ Ids = @(12,23,24); Strong = 'COS_CHAOS_WOUND_MOVE_MINUS_9'; Boost = 'ActionResource(Movement,-9,0)' }
)
$seed = (Get-Rules 'PROC_COS_EnsureNegativeProtection') -join "`n"
foreach ($family in $families) {
    $entry = [regex]::Match($stats, "(?ms)^new entry `"$($family.Strong)`"\r?\n.*?(?=^new entry |\z)").Value
    Assert-Protection ($entry.Contains('data "Boosts" "' + $family.Boost + '"')) "最强状态定义改变: $($family.Strong)"
    foreach ($id in $family.Ids) {
        Assert-Protection ($seed.Contains("DB_COS_WoundNegativeStrong($id, `"$($family.Strong)`");")) "缺少运行时同族保护映射: $id"
    }
}
$pool = (Get-Rules 'PROC_COS_RebuildNegativeWoundPool') -join "`n"
Assert-Protection ($pool.IndexOf('PROC_COS_EnsureNegativeProtection();') -ge 0 -and $pool.IndexOf('PROC_COS_EnsureNegativeProtection();') -lt $pool.IndexOf('PROC_COS_AddEnabledNegativeWoundCandidates(_Character);')) '每次负面抽取前必须确保旧档映射已种入'
$candidate = Get-Rules 'PROC_COS_AddEnabledNegativeWoundCandidates'
Assert-Protection ($candidate.Count -eq 2) '负面候选必须有正常和受保护两个互斥分支'
$normal = @($candidate | Where-Object { $_.Contains('HasActiveStatus(_Character, _StrongStatus, 0)') })
$protected = @($candidate | Where-Object { $_.Contains('HasActiveStatus(_Character, _StrongStatus, 1)') })
Assert-Protection ($normal.Count -eq 1 -and $protected.Count -eq 1) '必须实时判断同族最强状态是否生效'
Assert-Protection ($normal[0].Contains('IntegerProduct(_Weight, 2, _EffectiveWeight)') -and $normal[0].Contains('_Layer <= _EffectiveWeight')) '正常权重必须为 2w'
Assert-Protection ($protected[0].Contains('_Layer <= _Weight')) '受保护权重必须为 w，保留原权重 1 候选'
foreach ($rule in $candidate) {
    Assert-Protection ($rule.Contains('DB_COS_ConfigWound(_Character, _Key, 1)') -and $rule.Contains('DB_COS_WoundNegativeStrong(_Outcome, _StrongStatus)')) '保护不可跳过角色设置或同族映射'
}
$apply = Get-Rules 'PROC_COS_ApplyWoundStatus'
Assert-Protection ($apply.Count -eq 3) '状态应用必须分开正面、正常负面、受保护负面'
$negative = @($apply | Where-Object { $_.Contains('DB_COS_WoundStatus(_Roll, _Status, 1)') -and $_.Contains('HasActiveStatus(_Character, _StrongStatus, 0)') })
Assert-Protection ($negative.Count -eq 1 -and $negative[0].Contains('HasActiveStatus(_Character, _StrongStatus, 0)')) '最强同族状态存在时不得刷新、覆盖或叠加'
$skip = @($apply | Where-Object { $_.Contains('HasActiveStatus(_Character, _StrongStatus, 1)') })
Assert-Protection ($skip.Count -eq 1 -and $skip[0].Contains('"COS_NEGATIVE_PROTECTED_LOG"') -and -not $skip[0].Contains('ApplyStatus(_Character, _Status,')) '受保护命中必须仅提示而不改状态'
Assert-Protection ($m.IndexOf($skip[0]) -lt $m.IndexOf($negative[0])) '保护提示须先于施加分支判断，避免首次施加强负面后再误报保护'
$resolve = (Get-Rules 'PROC_COS_ResolveWound' | Where-Object { $_.Contains('DB_COS_WoundStatus(_Roll, _Status, _Negative)') }) -join "`n"
Assert-Protection ($resolve.Contains('PROC_COS_ApplyWoundStatus(_Character, _Roll);') -and -not $resolve.Contains('ApplyStatus(_Character, _Status,')) '负面应用不得绕过保护'
foreach ($formula in @('IntegerProduct(_TuneCount, 2, _TuneCells)', 'IntegerProduct(_CorrectCount, 4, _CalmCells)', 'IntegerSum(162, _TuneCells, _PositiveEnd)', 'IntegerSum(_PositiveEnd, _CalmCells, _CalmEnd)', 'Random(300, _CategoryRoll)')) {
    Assert-Protection ($m.Contains($formula)) "类别概率公式改变: $formula"
}
Write-Host 'NEGATIVE_PROTECTION_STATIC=PASS; IN_GAME=PENDING'
