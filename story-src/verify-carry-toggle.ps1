$ErrorActionPreference = 'Stop'
$g = (Get-Content (Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt') -Raw).Replace("`r`n", "`n")
function Assert-Carry($ok, $message) { if (-not $ok) { throw $message } }
function Get-CarryRules($name) { @([regex]::Matches($g, "(?ms)^PROC\n$([regex]::Escape($name))\([^\n]*\).*?(?=^(?:PROC|IF|EXITSECTION)\b|\z)") | ForEach-Object Value) }
$seedRules = @(Get-CarryRules 'PROC_COS_EnsureCarrySetting')
Assert-Carry ($seedRules.Count -eq 2) '负重默认初始化必须精确拆分为混沌新角色与非混沌玩家两个分支'
$newChaosSeed = @($seedRules | Where-Object { $_.Contains('DB_COS_ConfigInitializationKind(_Character, "New")') })
Assert-Carry ($newChaosSeed.Count -eq 1 -and $newChaosSeed[0].Contains('NOT DB_COS_CarryEnabled(_Character, _)') -and $newChaosSeed[0].Contains('DB_COS_CarryEnabled(_Character, 1);')) '混沌新角色必须只在缺少设置时默认开启负重'
$nonChaosSeed = @($seedRules | Where-Object { $_.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 0)') })
Assert-Carry ($nonChaosSeed.Count -eq 1 -and $nonChaosSeed[0].Contains('DB_Players(_Character)') -and $nonChaosSeed[0].Contains('NOT DB_COS_CarryEnabled(_Character, _)') -and $nonChaosSeed[0].Contains('DB_COS_CarryEnabled(_Character, 1);') -and -not $nonChaosSeed[0].Contains('DB_COS_ConfigInitializationKind(')) '非混沌玩家必须不依赖混沌配置分类并默认获得负重设置'
$sync = (Get-CarryRules 'PROC_COS_SyncGlobalPlayerBenefits') -join "`n"
Assert-Carry ($sync.Contains('DB_Players(_Character)')) '保留原 DB_Players 发放范围'
Assert-Carry ($sync.Contains('PROC_COS_EnsureCarrySetting(_Character);') -and $sync.Contains('PROC_COS_ApplyCarrySetting(_Character);')) '每次同步必须先补设置再按设置施加'
Assert-Carry ($sync.Contains('EnableTutorialEvent(_Character, (TUTORIALEVENT)COS_CFG_CARRY_7e000000-0000-4000-8000-000000000001);')) '旧档同步需启用负重开关事件'
$apply = Get-CarryRules 'PROC_COS_ApplyCarrySetting'
Assert-Carry ($apply.Count -eq 4) '混沌开启、非混沌默认、child关闭与分类暂停必须是明确的四个分支'
$on = @($apply | Where-Object { $_.Contains('DB_COS_CarryEnabled(_Character, 1)') -and $_.Contains('DB_COS_ConfigCategory(_Character, "Convenience", 1)') })
$nonChaosOn = @($apply | Where-Object { $_.Contains('DB_COS_CarryEnabled(_Character, 1)') -and $_.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 0)') })
$off = @($apply | Where-Object { $_.Contains('DB_COS_CarryEnabled(_Character, 0)') })
$paused = @($apply | Where-Object { $_.Contains('DB_COS_ConfigCategory(_Character, "Convenience", 0)') })
Assert-Carry ($on.Count -eq 1 -and $on[0].Contains('AddPassive(_Character, "COS_GlobalCarryCapacity50x");')) '只有分类与 child 均开启的角色可以获得负重被动'
Assert-Carry ($nonChaosOn.Count -eq 1 -and $nonChaosOn[0].Contains('DB_Players(_Character)') -and $nonChaosOn[0].Contains('AddPassive(_Character, "COS_GlobalCarryCapacity50x");') -and -not $nonChaosOn[0].Contains('DB_COS_ConfigCategory(')) '非混沌玩家必须不依赖混沌分类并获得默认负重被动'
Assert-Carry ($off.Count -eq 1 -and $off[0].Contains('RemovePassive(_Character, "COS_GlobalCarryCapacity50x");') -and -not $off[0].Contains('AddPassive(')) 'child 关闭同步必须保持本被动移除'
Assert-Carry ($paused.Count -eq 1 -and $paused[0].Contains('RemovePassive(_Character, "COS_GlobalCarryCapacity50x");') -and -not $paused[0].Contains('DB_COS_CarryEnabled(_Character,')) '分类暂停必须移除实际负重效果但保留 child DB'
Assert-Carry ([regex]::Matches($g, 'RemovePassive\(').Count -eq 3) '不得移除其他来源或其他被动'
$event = [regex]::Match($g, '(?ms)^IF\nTutorialEvent\(_Character, \(TUTORIALEVENT\)COS_CFG_CARRY_7e000000-0000-4000-8000-000000000001\).*?(?=^(?:PROC|IF|EXITSECTION)\b|\z)').Value
foreach ($gate in @('DB_Players(_Character)', 'DB_COS_ConfigCategory(_Character, "Convenience", 1)', 'HasPassive(_Character, "COS_ChaosOriginMarker", 1)', 'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)')) { Assert-Carry ($event.Contains($gate)) "负重设置事件缺少门禁: $gate" }
$toggle = (Get-CarryRules 'PROC_COS_ToggleCarrySetting') -join "`n"
foreach ($step in @('DB_COS_CarryEnabled(_Character, _Old)', 'IntegerSubtract(1, _Old, _Enabled)', 'NOT DB_COS_CarryEnabled(_Character, _Old);', 'DB_COS_CarryEnabled(_Character, _Enabled);', 'PROC_COS_ApplyCarrySetting(_Character);')) { Assert-Carry ($toggle.Contains($step)) "切换必须保存当前角色并即时刷新: $step" }
Assert-Carry (-not $g.Contains('SetWeight') -and -not $g.Contains('AddBoosts')) '不得改写基础负重或加入其他实现'
foreach ($eventName in @('LevelGameplayStarted', 'GainedControl', 'CharacterJoinedParty', 'RespecCompleted')) { Assert-Carry ($g.Contains("$eventName(")) "原同步生命周期丢失: $eventName" }
$config = (Get-Content (Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt') -Raw).Replace("`r`n","`n")
$configSync = [regex]::Match($config, '(?ms)^PROC\nPROC_COS_ConfigSyncCharacter\(\(CHARACTER\)_Character\).*?(?=^(?:PROC|IF|EXITSECTION)\b|\z)').Value
$expectedCarrySyncPrefix = "PROC`nPROC_COS_ConfigSyncCharacter((CHARACTER)_Character)`nTHEN`nPROC_COS_ConfigInitializeCategories(_Character);`nPROC_COS_SeedGrantMap();`nPROC_COS_PresetSeed();`nPROC_COS_CaptureLegacyOriginOwnership(_Character);`nPROC_COS_ConfigSyncCategoryMirrors(_Character);`nPROC_COS_SyncBaseAfterCreation(_Character);`nPROC_COS_SyncGlobalPlayerBenefits(_Character);"
Assert-Carry ($configSync.StartsWith($expectedCarrySyncPrefix, [System.StringComparison]::Ordinal)) '打开菜单必须先初始化分类，再按固定顺序同步分类镜像、基础效果与负重'
Assert-Carry ([regex]::Matches($configSync, '(?m)^PROC_COS_SyncGlobalPlayerBenefits\(_Character\);$').Count -eq 1) '统一角色同步必须且只能调用一次负重同步'
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
