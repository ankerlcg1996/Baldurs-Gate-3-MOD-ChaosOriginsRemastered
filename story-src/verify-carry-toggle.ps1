$ErrorActionPreference = 'Stop'
$g = (Get-Content (Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt') -Raw).Replace("`r`n", "`n")
function Assert-Carry($ok, $message) { if (-not $ok) { throw $message } }
function Get-CarryRules($name) { @([regex]::Matches($g, "(?ms)^PROC\n$([regex]::Escape($name))\([^\n]*\).*?(?=^(?:PROC|IF|EXITSECTION)\b|\z)") | ForEach-Object Value) }
$seed = (Get-CarryRules 'PROC_COS_EnsureCarrySetting') -join "`n"
Assert-Carry ($seed.Contains('NOT DB_COS_CarryEnabled(_Character, _)') -and $seed.Contains('DB_COS_CarryEnabled(_Character, 1);')) '旧档必须只在缺少设置时默认开启，不得覆盖关闭值'
$sync = (Get-CarryRules 'PROC_COS_SyncGlobalPlayerBenefits') -join "`n"
Assert-Carry ($sync.Contains('DB_Players(_Character)')) '保留原 DB_Players 发放范围'
Assert-Carry ($sync.Contains('PROC_COS_EnsureCarrySetting(_Character);') -and $sync.Contains('PROC_COS_ApplyCarrySetting(_Character);')) '每次同步必须先补设置再按设置施加'
Assert-Carry ($sync.Contains('EnableTutorialEvent(_Character, (TUTORIALEVENT)COS_CFG_CARRY_7e000000-0000-4000-8000-000000000001);')) '旧档同步需启用负重开关事件'
$apply = Get-CarryRules 'PROC_COS_ApplyCarrySetting'
Assert-Carry ($apply.Count -eq 2) '开启与关闭必须是明确的两个分支'
$on = @($apply | Where-Object { $_.Contains('DB_COS_CarryEnabled(_Character, 1)') })
$off = @($apply | Where-Object { $_.Contains('DB_COS_CarryEnabled(_Character, 0)') })
Assert-Carry ($on.Count -eq 1 -and $on[0].Contains('AddPassive(_Character, "COS_GlobalCarryCapacity50x");')) '只有开启角色可以获得负重被动'
Assert-Carry ($off.Count -eq 1 -and $off[0].Contains('RemovePassive(_Character, "COS_GlobalCarryCapacity50x");') -and -not $off[0].Contains('AddPassive(')) '关闭同步必须保持本被动移除'
Assert-Carry ([regex]::Matches($g, 'RemovePassive\(').Count -eq 2) '不得移除其他来源或其他被动'
$event = [regex]::Match($g, '(?ms)^IF\nTutorialEvent\(_Character, \(TUTORIALEVENT\)COS_CFG_CARRY_7e000000-0000-4000-8000-000000000001\).*?(?=^(?:PROC|IF|EXITSECTION)\b|\z)').Value
foreach ($gate in @('DB_Players(_Character)', 'HasPassive(_Character, "COS_ChaosOriginMarker", 1)', 'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)')) { Assert-Carry ($event.Contains($gate)) "负重设置事件缺少门禁: $gate" }
$toggle = (Get-CarryRules 'PROC_COS_ToggleCarrySetting') -join "`n"
foreach ($step in @('DB_COS_CarryEnabled(_Character, _Old)', 'IntegerSubtract(1, _Old, _Enabled)', 'NOT DB_COS_CarryEnabled(_Character, _Old);', 'DB_COS_CarryEnabled(_Character, _Enabled);', 'PROC_COS_ApplyCarrySetting(_Character);')) { Assert-Carry ($toggle.Contains($step)) "切换必须保存当前角色并即时刷新: $step" }
Assert-Carry (-not $g.Contains('SetWeight') -and -not $g.Contains('AddBoosts')) '不得改写基础负重或加入其他实现'
foreach ($eventName in @('LevelGameplayStarted', 'GainedControl', 'CharacterJoinedParty', 'RespecCompleted')) { Assert-Carry ($g.Contains("$eventName(")) "原同步生命周期丢失: $eventName" }
$config = Get-Content (Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt') -Raw
Assert-Carry ($config.Replace("`r`n","`n").Contains("PROC_COS_ConfigSyncCharacter((CHARACTER)_Character)`nTHEN`nPROC_COS_SyncGlobalPlayerBenefits(_Character);")) '打开菜单必须初始化并同步负重'
$mirror = (Get-CarryRules 'PROC_COS_SyncCarryMirror') -join "`n"
Assert-Carry ($mirror.Contains('AddPassive(_Character, "COS_CFG_CARRY");') -and $mirror.Contains('RemovePassive(_Character, "COS_CFG_CARRY");')) '负重必须拥有独立的可见镜像'
foreach ($page in 'COS_ConfigMenu.xaml','COS_ConfigMenu_c.xaml') {
    $ui = Get-Content (Join-Path $PSScriptRoot "Mods/ChaosOriginsStory/GUI/Pages/$page") -Raw
    Assert-Carry ($ui.Contains('Value="COS_CFG_CARRY"') -and -not $ui.Contains('Value="COS_GlobalCarryCapacity50x"')) '勾选不得直接读取隐藏功能被动'
}
$stats = Get-Content (Join-Path $PSScriptRoot 'Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt') -Raw
$mirrorStats = [regex]::Match($stats, '(?ms)^new entry "COS_CFG_CARRY".*?(?=^new entry |\z)').Value
Assert-Carry ($mirrorStats -ne '' -and $mirrorStats -notmatch 'IsHidden|data "Boosts"') '镜像必须可见且不重复提供负重倍率'
Assert-Carry ($sync.Contains('PROC_COS_SyncCarryMirror(_Character);') -and $toggle.Contains('PROC_COS_SyncCarryMirror(_Character);')) '同步与切换均需刷新独立镜像'
Write-Host 'CARRY_TOGGLE_STATIC=PASS; IN_GAME=PENDING'
