$ErrorActionPreference='Stop'
$g=Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals'
$m=(Get-Content "$g/COS_ChaosMechanics.txt" -Raw).Replace("`r`n","`n")
$c=(Get-Content "$g/COS_Config.txt" -Raw).Replace("`r`n","`n")
$b=(Get-Content "$g/COS_BaseAfterCreation.txt" -Raw).Replace("`r`n","`n")
function Check-Retired($ok,$message){if(-not $ok){throw $message}}
$ifs=@([regex]::Matches($m,'(?ms)^IF\n.*?(?=^(?:IF|PROC|EXITSECTION)\n|\z)') | ForEach-Object Value)
Check-Retired (-not (($ifs -join "`n") -match 'Fate|FATE')) '攻击事件仍包含命运改签'
$duality=@($ifs | Where-Object { $_.Contains('AttackedBy(') -and $_.Contains('HasPassive(_AttackOwner, "COS_ChaosDuality", 1)') })
Check-Retired ($duality.Count -eq 1) '普通两仪应只保留一个攻击入口'
Check-Retired ($duality[0].Contains('Random(100, _DualityRoll)') -and $duality[0].Contains('PROC_COS_ResolveDuality((CHARACTER)_AttackOwner, (CHARACTER)_Target, _Damage, _DualityRoll);')) '普通两仪应单次随机并保留原结算'
Check-Retired (-not ($b -match '(?m)^DB_COS_CorePassive\(1, "COS_FateRevision"\);')) '不得向新角色发放改签'
foreach($token in @('RemovePassive(_Character, "COS_FateRevision");','RemoveStatus(_Character, "COS_CHAOS_FATE_ENABLED", _Character);','PROC_COS_ClearFateAction(_Character);')){
 Check-Retired ($c.Contains($token)) "缺少旧档清理: $token"
}
Check-Retired ($c.Contains('PROC_COS_RetireFate(_Character);')) '角色同步必须执行旧功能清理'
foreach($page in @('COS_ConfigMenu.xaml','COS_ConfigMenu_c.xaml')){
 $s=Get-Content (Join-Path $PSScriptRoot "Mods/ChaosOriginsStory/GUI/Pages/$page") -Raw
 Check-Retired ($s -notmatch 'COSConfig(?:ToggleFate|RowFate|FateCost)') '菜单不得残留改签入口'
 Check-Retired ($s.Contains('COSConfigGenesisCostValue')) '必须保留开天辟地消耗调节'
}
Check-Retired (-not $m.Contains('PROC_COS_ContinueFateDuality')) '应删除重投递归'
Write-Host 'FATE_RETIRED_STATIC=PASS; IN_GAME=PENDING'
