$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$module = 'ChaosOriginsStory'
$moduleUuid = 'a5062238-0d2b-46d1-a093-cb02775b9f57'
$referenceUuids = @(
    'ca8bfe06-88ec-a4e7-b49e-44eb5658f434',
    '9010c099-c1e7-4ea8-8990-a883d6814975'
)

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Require-Unique([string]$Name, [string[]]$Values, [int]$ExpectedCount) {
    Require ($Values.Count -eq $ExpectedCount) "$Name 数量错误: expected=$ExpectedCount actual=$($Values.Count)"
    $unique = @($Values | Sort-Object -Unique)
    Require ($unique.Count -eq $Values.Count) "$Name 包含重复项"
}

$metaPath = Join-Path $PSScriptRoot "Mods\$module\meta.lsx"
[xml]$metaDocument = Get-Content -LiteralPath $metaPath -Raw
$dependencies = @($metaDocument.SelectNodes('//node[@id="Dependencies"]/children/node[@id="ModuleShortDesc"]'))
Require ($dependencies.Count -eq 1) 'Story 模块必须恰好声明一个官方运行时依赖'
$dependencyAttributes = @{}
foreach ($attribute in @($dependencies[0].SelectNodes('attribute'))) { $dependencyAttributes[[string]$attribute.id] = [string]$attribute.value }
Require ($dependencyAttributes['Folder'] -eq 'GustavX') 'Story 模块必须依赖当前官方战役模块 GustavX'
Require ($dependencyAttributes['UUID'] -eq 'cb555efe-2d9e-131f-8195-a89329d218ea') 'GustavX 依赖 UUID 错误'
$targetModes = @($metaDocument.SelectNodes('//node[@id="TargetModes"]/children/node[@id="Target"]/attribute[@id="Object"]') | ForEach-Object { [string]$_.value })
Require ($targetModes.Count -eq 1 -and $targetModes[0] -eq 'Story') '模块 TargetModes 必须唯一声明 Story'

$mechanics = @('Skills', 'Power', 'Wound', 'KillPower', 'Duality', 'AllIn', 'Echo', 'Strike')
$origins = @('Astarion', 'Gale', 'Laezel', 'Shadowheart', 'Wyll', 'Karlach', 'DarkUrge')
$originTags = @(
    'ffd08582-7396-4cac-bcd4-8f9cd0fd8ef3',
    '9b0354c0-56d9-4723-8034-918ac9abab19',
    'b5682d1d-c395-489c-9675-1f9b0c328ea5',
    '642d2aee-e3df-47e3-9f47-bbcd441bb9e0',
    '5f40def5-d3ec-4698-a367-01a339888956',
    '1a2f70d6-8ead-4eb5-a824-79ee1971764a',
    'cd611d7d-b67d-42b4-a75c-a0c6091ef8a2'
)
$woundNegatives = @(
    'Madness', 'Frightened', 'Stunned', 'Silenced', 'Prone', 'Blinded', 'Slowed',
    'Poisoned', 'Bleeding', 'Burning', 'MeleeDisadvantage', 'RangedDisadvantage',
    'SpellDisadvantage', 'RandomVulnerability', 'ExtraRandomDamage'
)
$racialPassives = @(
    'DeepGnome_StoneCamouflage',
    'Drow_DrowWeaponTraining',
    'Duergar_DuergarResilience',
    'Dwarf_DwarvenCombatTraining',
    'Dwarf_DwarvenResilience',
    'Elf_WeaponTraining',
    'FeyAncestry',
    'Gith_MartialProdigy',
    'Gnome_Cunning',
    'Halfling_Brave',
    'Halfling_LightfootStealth',
    'Halfling_Lucky',
    'Halfling_StoutResilience',
    'HumanMilitia',
    'MountainDwarf_DwarvenArmorTraining',
    'RelentlessEndurance',
    'RockGnome_ArtificersLore',
    'SavageAttacks',
    'SuperiorDarkvision',
    'Tiefling_HellishResistance'
)
$forbiddenPassives = @(
    'HumanVersatility',
    'Darkvision',
    'Dragonborn_Resistance_Acid',
    'Dragonborn_Resistance_Cold',
    'Dragonborn_Resistance_Fire',
    'Dragonborn_Resistance_Lightning',
    'Dragonborn_Resistance_Poison',
    'FearOfWolves_Shadowheart'
)

Require-Unique '机制目录' $mechanics 8
Require-Unique '起源目录' $origins 7
Require-Unique '起源标签目录' $originTags 7
Require-Unique '受击负面目录' $woundNegatives 15
Require-Unique '种族被动目录' $racialPassives 20
Require (@(Compare-Object $racialPassives $forbiddenPassives -IncludeEqual -ExcludeDifferent).Count -eq 0) '种族被动目录与禁用被动清单重叠'

$metaPath = Join-Path $root "Mods\$module\meta.lsx"
Require (Test-Path -LiteralPath $metaPath -PathType Leaf) "缺少模块元数据: $metaPath"
$meta = [IO.File]::ReadAllText($metaPath)
Require ($meta.Contains("value=`"$moduleUuid`"")) '模块 UUID 不匹配'
Require ($meta -match '<node id="Dependencies"\s*/>') 'Story 模块依赖列表必须为空'

$manifestPath = Join-Path $root 'package-files.json'
Require (Test-Path -LiteralPath $manifestPath -PathType Leaf) "缺少打包清单: $manifestPath"
$manifest = @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).files)
Require ($manifest.Count -gt 0) '打包清单为空'
Require (@($manifest | Sort-Object -Unique).Count -eq $manifest.Count) '打包清单包含重复路径'
foreach ($relative in $manifest) {
    Require (-not [IO.Path]::IsPathRooted($relative)) "打包清单包含绝对路径: $relative"
    Require (-not $relative.Contains('..')) "打包清单包含父目录跳转: $relative"
    if ($relative.EndsWith('.lsf')) {
        $resourceSource = Join-Path $root ('resource-src\' + $relative.Replace('/', '\') + '.lsx')
        Require (Test-Path -LiteralPath $resourceSource -PathType Leaf) "LSF 清单缺少源文件: $relative"
    }
}
$declaredResourceSources = @($manifest | Where-Object { $_.EndsWith('.lsf') } | ForEach-Object { $_ + '.lsx' } | Sort-Object)
$actualResourceSources = @(Get-ChildItem -LiteralPath (Join-Path $root 'resource-src') -Recurse -File -Filter '*.lsx' | ForEach-Object {
    [IO.Path]::GetRelativePath((Join-Path $root 'resource-src'), $_.FullName).Replace('\', '/')
} | Sort-Object)
Require ($declaredResourceSources.Count -eq $actualResourceSources.Count) 'LSF 源文件数量与清单不一致'
Require (@(Compare-Object $declaredResourceSources $actualResourceSources).Count -eq 0) 'LSF 源文件集合与清单不一致'

$originPath = Join-Path $root "Public\$module\Origins\Origins.lsx"
Require (Test-Path -LiteralPath $originPath -PathType Leaf) '缺少混沌起源定义'
[xml]$originDocument = Get-Content -LiteralPath $originPath -Raw
$originNode = $originDocument.SelectSingleNode('//node[@id="Origin"]')
Require ($null -ne $originNode) '混沌起源定义缺少 Origin 节点'
$originAttributes = @{}
foreach ($attribute in @($originNode.SelectNodes('attribute'))) {
    $originAttributes[[string]$attribute.id] = [string]$attribute.value
}
Require ($originAttributes['BodyShape'] -eq '0') 'Origin BodyShape 必须使用已验证的标准值 0'
Require ($originAttributes['BodyType'] -eq '0') 'Origin BodyType 必须使用已验证的标准值 0'
Require ($originAttributes['DefaultsTemplate'] -eq '782183f9-ceb5-4a96-8ac4-56af0319641d') 'Origin 缺少已验证的角色创建默认模板'
Require ($originAttributes['IntroDialogUUID'] -eq 'f015fd39-a9f2-6ee5-a77b-a28806ac1b7a') 'Origin 缺少自定义角色创建 IntroDialog'
foreach ($foreignAttribute in @('Identity', 'IsHenchman', 'Unique')) {
    Require (-not $originAttributes.ContainsKey($foreignAttribute)) "Origin 不得包含验收版本不存在的字段: $foreignAttribute"
}
Require ($null -eq $originNode.SelectSingleNode('children/node[@id="AppearanceTags"]')) 'Origin 不得包含会限制守护者外观的 AppearanceTags'
$reallyTagNodes = @($originNode.SelectNodes('children/node[@id="ReallyTags"]/attribute[@id="Object"]'))
Require ($reallyTagNodes.Count -eq 1) 'Origin 必须恰好包含一个 ReallyTags 条目'
Require ([string]$reallyTagNodes[0].value -eq '2c237035-d1a9-4469-91de-d74d8464c8d5') 'Origin ReallyTags UUID 错误'

$languagePaths = @(
    'Chinese',
    'English',
    'Japanese',
    'Korean'
) | ForEach-Object { Join-Path $root "Localization\$_\ChaosOriginsStory.xml" }
$handleSets = @()
foreach ($path in $languagePaths) {
    Require (Test-Path -LiteralPath $path -PathType Leaf) "缺少本地化源: $path"
    [xml]$document = Get-Content -LiteralPath $path -Raw
    $handles = @($document.contentList.content | ForEach-Object { [string]$_.contentuid } | Sort-Object)
    Require ($handles.Count -eq 591) "本地化 handle 数量错误: $path expected=591 actual=$($handles.Count)"
    Require (@($handles | Sort-Object -Unique).Count -eq $handles.Count) "本地化 handle 重复: $path"
    foreach ($content in @($document.contentList.content)) {
        $value = [string]$content.InnerText
        Require (-not [string]::IsNullOrWhiteSpace($value)) "本地化包含空文本: $path"
        Require (-not ($value -match '(?i)\bTODO\b|\bTBD\b')) "本地化包含占位文本: $path"
    }
    $handleSets += ,$handles
}
for ($index = 1; $index -lt $handleSets.Count; $index++) {
    $difference = @(Compare-Object $handleSets[0] $handleSets[$index])
    Require ($difference.Count -eq 0) "四语本地化 handle 集合不一致: $($languagePaths[$index])"
}

$formalRoots = @(
    (Join-Path $root 'Mods'),
    (Join-Path $root 'Public'),
    (Join-Path $root 'Localization')
)
$formalFiles = @($formalRoots | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object {
    Get-ChildItem -LiteralPath $_ -Recurse -File
})
$forbiddenPathPattern = 'ScriptExtender|MCM_blueprint|BG3MCM|NMCM_'
foreach ($file in $formalFiles) {
    Require (-not ($file.FullName -match $forbiddenPathPattern)) "正式源包含禁止路径: $($file.FullName)"
    if ($file.Extension -in @('.txt', '.lsx', '.xml', '.xaml', '.json', '.lua')) {
        $text = [IO.File]::ReadAllText($file.FullName)
        Require (-not ($text -match 'ScriptExtender|MCM_blueprint|BG3MCM')) "正式源包含禁止内容: $($file.FullName)"
        foreach ($uuid in $referenceUuids) {
            Require (-not $text.Contains($uuid)) "正式源复用了参考模块 UUID: $($file.FullName)"
        }
    }
}

$statsFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "Public\$module\Stats\Generated\Data") -File -Filter '*.txt')
foreach ($file in $statsFiles) {
    foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
        if ($line -match '^new entry "([^"]+)"') {
            Require ($matches[1] -match '(^COS_|_COS_)') "非 COS Stats 条目: $($matches[1]) ($($file.Name))"
        }
    }
}

$configGoalPath = Join-Path $root "Mods\$module\Story\RawFiles\Goals\COS_Config.txt"
if (Test-Path -LiteralPath $configGoalPath -PathType Leaf) {
    $configGoal = [IO.File]::ReadAllText($configGoalPath)
    Require ([regex]::Matches($configGoal, 'DB_COS_ConfigMechanicDefault\("').Count -eq 8) '机制默认目录必须恰好为 8 项'
    Require ([regex]::Matches($configGoal, 'DB_COS_ConfigRacialPassiveDefault\("').Count -eq 20) '种族被动默认目录必须恰好为 20 项'
    Require ([regex]::Matches($configGoal, 'DB_COS_ConfigOriginDefault\("').Count -eq 7) '起源默认目录必须恰好为 7 项'
    Require ([regex]::Matches($configGoal, 'DB_COS_ConfigWoundDefault\("').Count -eq 15) '受击默认目录必须恰好为 15 项'
    Require ([regex]::Matches($configGoal, 'DB_COS_ConfigWoundOutcome\("').Count -eq 15) '受击负面结果映射必须恰好为 15 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigMirrorMechanic\("').Count -eq 8) '机制回显目录必须恰好为 8 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigMirrorRacialPassive\("').Count -eq 20) '种族被动回显目录必须恰好为 20 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigMirrorOrigin\("').Count -eq 7) '起源回显目录必须恰好为 7 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigMirrorWound\("').Count -eq 15) '受击回显目录必须恰好为 15 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigTutorialMechanic\(\(TUTORIALEVENT\)').Count -eq 16) '机制 TutorialEvent 映射必须恰好为 16 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigTutorialRacialPassive\(\(TUTORIALEVENT\)').Count -eq 40) '种族被动 TutorialEvent 映射必须恰好为 40 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigTutorialOrigin\(\(TUTORIALEVENT\)').Count -eq 14) '起源 TutorialEvent 映射必须恰好为 14 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigTutorialWound\(\(TUTORIALEVENT\)').Count -eq 30) '受击 TutorialEvent 映射必须恰好为 30 项'
    Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigEvent\(\(TUTORIALEVENT\)').Count -eq 106) '启用的 TutorialEvent 必须恰好为 106 项'
    foreach ($key in $mechanics) {
        Require ($configGoal.Contains("DB_COS_ConfigMechanicDefault(`"$key`", 1);")) "机制默认值缺失或错误: $key"
    }
    foreach ($key in $origins) {
        Require ($configGoal.Contains("DB_COS_ConfigOriginDefault(`"$key`", 1);")) "起源默认值缺失或错误: $key"
    }
    foreach ($key in $woundNegatives) {
        Require ($configGoal.Contains("DB_COS_ConfigWoundDefault(`"$key`", 1);")) "受击默认值缺失或错误: $key"
    }
    foreach ($passive in $racialPassives) {
        Require ($configGoal.Contains("DB_COS_ConfigRacialPassiveDefault(`"$passive`", 0);")) "种族被动默认值缺失或错误: $passive"
    }
    foreach ($token in @(
        'DB_COS_ConfigMechanic(',
        'DB_COS_ConfigRacialPassive(',
        'DB_COS_ConfigOrigin(',
        'DB_COS_ConfigWound(',
        'DB_COS_ConfigBusy',
        'DB_COS_RacialPassiveGranted',
        'PROC_COS_ConfigInitialize',
        'PROC_COS_ConfigReset',
        'PROC_COS_ConfigApplyRacialPassive',
        'PROC_COS_ConfigRecordRacialGrant',
        'PROC_COS_ConfigSetRacialPassive',
        'PROC_COS_ConfigSetAllRacialPassives',
        'PROC_COS_ConfigSyncRacialPassives',
        'PROC_COS_ConfigEnsureBook',
        'TemplateIsInInventory((ITEMROOT)c05fb001-0000-4000-8000-00000000b001, _Character, 0)',
        'TemplateAddTo((ITEMROOT)c05fb001-0000-4000-8000-00000000b001, _Character, 1, 1)',
        'TemplateUseStarted(_Character, (ITEMROOT)c05fb001-0000-4000-8000-00000000b001, _Item)',
        'OpenMessageBox(_Character, "hc05fb001g0000g4000g8000g000000000002")'
    )) {
        Require ($configGoal.Contains($token)) "配置 Story 合约缺失: $token"
    }
    foreach ($key in $mechanics) {
        Require ($configGoal.Contains("DB_COS_ConfigMechanicDefault(`"$key`", 1);")) "机制配置目录缺失: $key"
    }
    foreach ($token in @(
        'DB_COS_ConfigMechanicPassive("Skills", 1, "COS_ChaosStatus")',
        'DB_COS_ConfigMechanicSpell("Power", 1, "Shout_COS_ChaosGenesis")',
        'PROC_COS_ConfigApplyMechanic',
        'PROC_COS_ConfigCleanupMechanic',
        'PROC_COS_ConfigRefreshMechanic',
        'PROC_COS_ConfigSetMechanic',
        'PROC_COS_ConfigSyncMechanics'
    )) {
        Require ($configGoal.Contains($token)) "机制设置合约缺失: $token"
    }
    foreach ($token in @(
        'DB_COS_ConfigOriginTag("Astarion", (TAG)ffd08582-7396-4cac-bcd4-8f9cd0fd8ef3)',
        'DB_COS_ConfigOriginPassive("Wyll", "BladeOfFrontiers")',
        'DB_COS_ConfigOriginPassive("Karlach", "ORI_Karlach_SweatImmune")',
        'DB_COS_ConfigOriginPassive("Karlach", "ORI_Karlach_Rage_Flames")',
        'DB_COS_ConfigOriginSpell("Astarion", "Target_VampireBite_Astarion")',
        'PROC_COS_ConfigApplyOrigin',
        'PROC_COS_ConfigCleanupOriginRewards',
        'PROC_COS_ConfigSetOrigin',
        'PROC_COS_ConfigSetAllOrigins',
        'PROC_COS_ConfigSyncOrigins'
    )) {
        Require ($configGoal.Contains($token)) "起源设置合约缺失: $token"
    }
    foreach ($token in @('DB_COS_ConfigWoundOutcome(', 'PROC_COS_ConfigSetWound')) {
        Require ($configGoal.Contains($token)) "受击设置合约缺失: $token"
    }
    foreach ($token in @(
        'PROC_COS_ConfigEnableEvents',
        'PROC_COS_ConfigSyncMirrors',
        'GetReservedUserID(_Character, _TargetUser)',
        'GetReservedUserID(_Host, _HostUser)',
        '_TargetUser == _HostUser',
        'IsInCombat(_Character, 0)',
        'NOT DB_COS_ConfigBusy(_Character)'
    )) {
        Require ($configGoal.Contains($token)) "原生事件权限合约缺失: $token"
    }
    Require ($configGoal.Contains('HasPassive(_Character, _Passive, 0)')) '种族被动开启前必须检查现有同 ID 被动'
    Require ($configGoal.Contains('DB_COS_RacialPassiveGranted(_Character, _Passive)')) '种族被动必须写入授予账本'
    Require ($configGoal.Contains('NOT DB_COS_RacialPassiveGranted(_Character, _Passive)')) '种族被动关闭必须清除授予账本'
}

$mainGoalPath = Join-Path $root "Mods\$module\Story\RawFiles\Goals\COS_ChaosOrigins.txt"
$mainGoal = [IO.File]::ReadAllText($mainGoalPath)
foreach ($goalPath in Get-ChildItem -LiteralPath (Join-Path $root "Mods\$module\Story\RawFiles\Goals") -File -Filter '*.txt') {
    $goalText = [IO.File]::ReadAllText($goalPath.FullName)
    Require ([regex]::Matches($goalText, '(?m)^ParentTargetEdge ').Count -eq 0) "常驻 Story Goal 必须保持顶层激活: $($goalPath.Name)"
}
foreach ($lifecycleEvent in @('LevelGameplayStarted(_, _)', 'LevelGameplayReady(_, _)', 'UserAvatarCreated(_, _Character, _)', 'GainedControl(_Character)', 'CharacterJoinedParty(_Character)', 'LeveledUp(_Character)')) {
    Require ($mainGoal.Contains($lifecycleEvent)) "角色同步缺少生命周期触发: $lifecycleEvent"
}
foreach ($token in @(
    'DB_COS_ConfigMechanic(_Character, "Power", 1)',
    'DB_COS_ConfigMechanic(_Character, "KillPower", 1)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Echo", 1)',
    'DB_COS_ConfigMechanic((CHARACTER)_Target, "Wound", 1)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Duality", 1)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "AllIn", 1)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Strike", 1)',
    'PROC_COS_ConfigSyncMechanics(_Character)'
)) {
    Require ($mainGoal.Contains($token)) "玩法机制未接入配置: $token"
}
foreach ($passive in @('COS_ChaosAllIn', 'COS_ChaosWound', 'COS_ChaosDuality', 'COS_ChaosEcho', 'COS_ChaosLost', 'COS_ChaosPower', 'COS_ChaosStatus', 'COS_ChaosStrike')) {
    Require (-not ($mainGoal -match ('DB_COS_Passive\(\d+,\s*"' + [regex]::Escape($passive) + '"\);'))) "可配置被动仍在无条件授予目录: $passive"
}
Require (-not $mainGoal.Contains('DB_COS_Spell(1, "Shout_COS_ChaosGenesis");')) '开天辟地仍在无条件法术目录'
foreach ($tag in $originTags) {
    Require (-not $mainGoal.Contains("DB_COS_Tag((TAG)$tag);")) "起源标签仍在无条件授予目录: $tag"
}
foreach ($token in @(
    'DB_COS_Passive(1, "BladeOfFrontiers");',
    'DB_COS_Passive(1, "ORI_Karlach_Rage_Flames");',
    'DB_COS_Passive(1, "ORI_Karlach_SweatImmune");',
    'DB_COS_Spell(1, "Target_VampireBite_Astarion");'
)) {
    Require (-not $mainGoal.Contains($token)) "起源即时能力仍在无条件授予目录: $token"
}
Require ([regex]::Matches($mainGoal, 'DB_COS_Tag\(\(TAG\)').Count -eq 32) '种族身份标签目录必须恰好保留 32 项'
foreach ($key in @('Astarion', 'Gale', 'Wyll', 'Karlach', 'DarkUrge')) {
    Require ($mainGoal.Contains("DB_COS_ConfigOrigin(_Character, `"$key`", 1)")) "剧情奖励未接入起源设置: $key"
}
Require ($mainGoal.Contains('PROC_COS_ConfigSyncOrigins(_Character)')) '角色同步未接入起源设置'
Require ([regex]::Matches($mainGoal, 'DB_COS_WoundPositive\(\d+\);').Count -eq 11) '受击固定非负面结果必须恰好为 11 项'
foreach ($token in @(
    'PROC_COS_ClearWoundPool',
    'PROC_COS_AppendWoundCandidate',
    'PROC_COS_AddPositiveWoundCandidates',
    'PROC_COS_AddEnabledWoundCandidates',
    'PROC_COS_RebuildWoundPool',
    'PROC_COS_CommitWoundRoll',
    'PROC_COS_RollWound',
    'Random(_Count, _Slot)'
)) {
    Require ($mainGoal.Contains($token)) "动态受击池合约缺失: $token"
}
Require (-not $mainGoal.Contains('Random(26, _WoundRoll)')) '受击轮盘仍使用固定 26 项随机上界'
foreach ($token in @('PROC_COS_ConfigEnableEvents(_Character)', 'PROC_COS_ConfigSyncMirrors(_Character)')) {
    Require ($mainGoal.Contains($token)) "角色同步未接入原生设置协议: $token"
}
Require ($mainGoal.Contains('PROC_COS_ConfigEnsureBook(_Character)')) '角色同步未接入设置手册唯一发放'

$configStatsPath = Join-Path $root "Public\$module\Stats\Generated\Data\ChaosConfig.txt"
Require (Test-Path -LiteralPath $configStatsPath -PathType Leaf) '缺少设置回显 Stats'
$configStats = [IO.File]::ReadAllText($configStatsPath)
$configEntries = @([regex]::Matches($configStats, '^new entry "(COS_CFG_[^"]+)"', 'Multiline') | ForEach-Object { $_.Groups[1].Value })
Require-Unique '设置回显被动' $configEntries 50
Require (-not $configStats.Contains('data "Boosts"')) '设置回显被动不得产生玩法 Boost'

$bookSourcePath = Join-Path $root "resource-src\Public\$module\RootTemplates\COS_ConfigBook.lsf.lsx"
Require (Test-Path -LiteralPath $bookSourcePath -PathType Leaf) '缺少设置手册 RootTemplate 源'
[xml]$bookDocument = Get-Content -LiteralPath $bookSourcePath -Raw
$bookMapKeys = @($bookDocument.SelectNodes('//attribute[@id="MapKey"]') | ForEach-Object { [string]$_.value })
Require-Unique '设置手册 RootTemplate MapKey' $bookMapKeys 1
Require ($bookMapKeys[0] -eq 'c05fb001-0000-4000-8000-00000000b001') '设置手册 RootTemplate UUID 错误'
$bookActionTypes = @($bookDocument.SelectNodes('//attribute[@id="ActionType"]') | ForEach-Object { [string]$_.value })
Require-Unique '设置手册使用动作' $bookActionTypes 1
Require ($bookActionTypes[0] -eq '11') '设置手册必须使用原版普通书本动作'
Require (@($bookDocument.SelectNodes('//attribute[@id="SkillID"]')).Count -eq 0) '设置手册不得引用 SpellData 技能'
$bookIds = @($bookDocument.SelectNodes('//attribute[@id="BookId"]') | ForEach-Object { [string]$_.value })
Require-Unique '设置手册 BookId' $bookIds 1
Require ($manifest -contains "Public/$module/RootTemplates/COS_ConfigBook.lsf") '设置手册 RootTemplate 未进入打包清单'
$bookLocalizationHandles = @($bookDocument.SelectNodes('//attribute[@type="TranslatedString"]') | ForEach-Object { [string]$_.handle })
Require-Unique '设置手册物品本地化引用' $bookLocalizationHandles 2
foreach ($handle in $bookLocalizationHandles) {
    Require ($handleSets[0] -contains $handle) "设置手册引用了缺失的本地化 handle: $handle"
}

$tutorialPath = Join-Path $root "Public\$module\Tutorials\TutorialEvents.lsx"
Require (Test-Path -LiteralPath $tutorialPath -PathType Leaf) '缺少 TutorialEvents.lsx'
[xml]$tutorialDocument = Get-Content -LiteralPath $tutorialPath -Raw
$tutorialNodes = @($tutorialDocument.SelectNodes('//node[@id="TutorialEvent"]'))
Require ($tutorialNodes.Count -eq 106) "TutorialEvent 数量错误: $($tutorialNodes.Count)"
$tutorialUuids = @($tutorialNodes | ForEach-Object { [string]($_.attribute | Where-Object id -eq 'UUID').value })
$tutorialNames = @($tutorialNodes | ForEach-Object { [string]($_.attribute | Where-Object id -eq 'Name').value })
Require-Unique 'TutorialEvent UUID' $tutorialUuids 106
Require-Unique 'TutorialEvent 名称' $tutorialNames 106
Require (@($tutorialNodes | Where-Object { [string]($_.attribute | Where-Object id -eq 'EventType').value -ne '8' }).Count -eq 0) '所有设置 TutorialEvent 必须为 EventType 8'

foreach ($removedGuiPath in @(
    "Mods/$module/GUI/metadata.lsf",
    "Public/$module/Content/UI/[PAK]_$module/_merged.lsf"
)) {
    Require ($manifest -notcontains $removedGuiPath) "会导致客户端 Load 阶段崩溃的 GUI 资源仍在打包清单: $removedGuiPath"
}
Require (@($manifest | Where-Object { $_ -like "Mods/$module/GUI/Pages/*" -or $_ -like "Mods/$module/GUI/StateMachines/*" }).Count -eq 0) '暂停菜单 XAML 不得进入修复包'

Write-Host 'ChaosOriginsStory source verification: ok'
