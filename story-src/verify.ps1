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

$mechanics = @('Skills', 'Power', 'Wound', 'KillPower', 'Duality', 'AllIn', 'Echo', 'Strike')
$origins = @('Astarion', 'Gale', 'Laezel', 'Shadowheart', 'Wyll', 'Karlach', 'DarkUrge')
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
    Require ($handles.Count -gt 0) "本地化没有 handle: $path"
    Require (@($handles | Sort-Object -Unique).Count -eq $handles.Count) "本地化 handle 重复: $path"
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
        'PROC_COS_ConfigSyncRacialPassives'
    )) {
        Require ($configGoal.Contains($token)) "配置 Story 合约缺失: $token"
    }
    Require ($configGoal.Contains('HasPassive(_Character, _Passive, 0)')) '种族被动开启前必须检查现有同 ID 被动'
    Require ($configGoal.Contains('DB_COS_RacialPassiveGranted(_Character, _Passive)')) '种族被动必须写入授予账本'
    Require ($configGoal.Contains('NOT DB_COS_RacialPassiveGranted(_Character, _Passive)')) '种族被动关闭必须清除授予账本'
}

Write-Host 'ChaosOriginsStory source verification: ok'
