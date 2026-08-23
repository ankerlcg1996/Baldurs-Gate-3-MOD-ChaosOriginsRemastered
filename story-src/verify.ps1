$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$module = 'ChaosOriginsStory'
$moduleUuid = 'a5062238-0d2b-46d1-a093-cb02775b9f57'
$originUuid = 'b751ba19-8aeb-4da5-a515-cf853e4c459c'
$originTagUuid = '2c237035-d1a9-4469-91de-d74d8464c8d5'
$displayHandle = 'hcd7a5c95gbdd1g5784gac8bg86b0dcd0e16a'
$descriptionHandle = 'h50753d28gdf41g50dfgb648gd2f4f9635fec'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$versionPath = Join-Path $root 'version.json'
Require (Test-Path -LiteralPath $versionPath -PathType Leaf) '缺少 version.json'
$version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($version.schema -eq 1) '不支持的版本文件格式'
foreach ($field in @('major', 'minor', 'revision', 'lastBuild')) {
    Require ($version.$field -is [int] -or $version.$field -is [long]) "版本字段必须为整数: $field"
    Require ([int64]$version.$field -ge 0) "版本字段不得为负数: $field"
}
Require ([int64]$version.lastBuild -le 2147483647) '末位版本号超出 BG3 Version64 范围'
$expectedVersion64 = ([int64]$version.major * 36028797018963968) + `
    ([int64]$version.minor * 140737488355328) + `
    ([int64]$version.revision * 2147483648) + [int64]$version.lastBuild

$masteryPassiveListPath = Join-Path $root "Public\$module\Lists\PassiveLists.lsx"
$masteryProgressionDescriptionPath = Join-Path $root "Public\$module\Progressions\ProgressionDescriptions.lsx"
$masteryProgressionPath = Join-Path $root "Public\$module\Progressions\Progressions.lsx"
$masteryStatsPath = Join-Path $root "Public\$module\Stats\Generated\Data\ChaosMastery.txt"
$masteryTableUuid = '1d20a825-9a5b-4b4a-b87c-ac1c73b8987b'
$masteryProgressionDescriptionUuid = 'fea09ff8-cfda-47cc-960b-34b5646f2465'
$masteryProgressionUuid = '07cad9c2-d3fa-4c2f-b9e1-f0397b3dad1e'
$masteryPassiveListUuid = '2737ff48-0c92-4f09-b8f1-bf831ce1533e'
$masteryDisplayHandle = 'h1253cd25g6db6g4704g90e7gadf6ad0df3ed'
$masteryDescriptionHandle = 'h11f157e4g81c1g4dc8gbd3eg20fbb820812f'
Require (Test-Path -LiteralPath $masteryPassiveListPath -PathType Leaf) '缺少 PassiveLists.lsx'
Require (Test-Path -LiteralPath $masteryProgressionDescriptionPath -PathType Leaf) '缺少 ProgressionDescriptions.lsx'
Require (Test-Path -LiteralPath $masteryProgressionPath -PathType Leaf) '缺少 Progressions.lsx'
Require (Test-Path -LiteralPath $masteryStatsPath -PathType Leaf) '缺少 ChaosMastery.txt'

$expectedPackageFiles = @(
    'Localization/Chinese/ChaosOriginsStory.loca',
    'Localization/English/ChaosOriginsStory.loca',
    'Localization/Japanese/ChaosOriginsStory.loca',
    'Localization/Korean/ChaosOriginsStory.loca',
    'Mods/ChaosOriginsStory/meta.lsx',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_BaseAfterCreation.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_OriginStoryRewards.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/story_header.div',
    'Mods/ChaosOriginsStory/Story/story.div.osi',
    'Public/ChaosOriginsStory/Origins/Origins.lsx',
    'Public/ChaosOriginsStory/ActionResourceDefinitions/ActionResourceDefinitions.lsx',
    'Public/ChaosOriginsStory/Assets/Textures/Icons/Icons_ChaosOrigins.dds',
    'Public/ChaosOriginsStory/Assets/Textures/Icons/UIOrigin_Portraits_Chaos.dds',
    'Public/ChaosOriginsStory/Content/UI/[PAK]_ChaosOriginsStory/_merged.lsf',
    'Public/ChaosOriginsStory/GUI/Icons_ChaosOrigins.lsx',
    'Public/ChaosOriginsStory/GUI/UIOrigin_Portraits_Chaos.lsx',
    'Public/ChaosOriginsStory/Lists/PassiveLists.lsx',
    'Public/ChaosOriginsStory/Progressions/ProgressionDescriptions.lsx',
    'Public/ChaosOriginsStory/Progressions/Progressions.lsx',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosDamage.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosFeatures.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosMastery.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosRuntime.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Interrupt.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt',
    'Public/ChaosOriginsStory/Tags/2c237035-d1a9-4469-91de-d74d8464c8d5.lsf'
) | Sort-Object

$manifestPath = Join-Path $root 'package-files.json'
Require (Test-Path -LiteralPath $manifestPath -PathType Leaf) '缺少 package-files.json'
$manifestDocument = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($manifestDocument.schema -eq 1) '不支持的打包清单格式'
$manifest = @($manifestDocument.files | Sort-Object)
Require ($manifest.Count -eq 28 -and @($manifest | Select-Object -Unique).Count -eq 28) `
    '原生 Story 打包清单必须恰好包含 28 个唯一文件'
Require (-not (Compare-Object $expectedPackageFiles $manifest)) '原生 Story 打包清单内容错误'

$metaPath = Join-Path $root "Mods\$module\meta.lsx"
Require (Test-Path -LiteralPath $metaPath -PathType Leaf) '缺少模块 meta.lsx'
[xml]$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$moduleInfo = $meta.SelectSingleNode('//node[@id="ModuleInfo"]')
Require ($null -ne $moduleInfo) 'meta.lsx 缺少 ModuleInfo'
$moduleAttributes = @{}
foreach ($attribute in @($moduleInfo.SelectNodes('attribute'))) { $moduleAttributes[[string]$attribute.id] = [string]$attribute.value }
Require ($moduleAttributes.UUID -eq $moduleUuid) '模块 UUID 错误'
Require ($moduleAttributes.Folder -eq $module) '模块目录名错误'
Require ($moduleAttributes.Type -eq 'Add-on') '模块类型必须为 Add-on'
Require ([int64]$moduleAttributes.Version64 -eq $expectedVersion64) 'meta.lsx Version64 与 version.json 不一致'
$publishVersion = $moduleInfo.SelectSingleNode('children/node[@id="PublishVersion"]/attribute[@id="Version64"]')
Require ($null -ne $publishVersion -and [int64]$publishVersion.value -eq $expectedVersion64) `
    'meta.lsx PublishVersion 与 version.json 不一致'
$dependencies = @($meta.SelectNodes('//node[@id="Dependencies"]/children/node[@id="ModuleShortDesc"]'))
Require ($dependencies.Count -eq 0) '原生 Story 包装必须与已运行 MOD 一致，不声明模块依赖'
$scripts = @($moduleInfo.SelectNodes('children/node[@id="Scripts"]/children/node[@id="Script"]'))
Require ($scripts.Count -eq 2) '原生 Story 包装必须声明两个固定脚本入口'
$scriptUuids = @($scripts | ForEach-Object { [string]$_.SelectSingleNode('attribute[@id="UUID"]').value } | Sort-Object)
Require (-not (Compare-Object $scriptUuids @('0d6510f5-50a3-4ecd-83d8-134c9a640324', '1953f77d-a201-45d7-a194-9b84c34b8461'))) `
    '原生 Story 脚本 UUID 未与已运行 MOD 对齐'
Require ($null -eq $moduleInfo.SelectSingleNode('children/node[@id="TargetModes"]')) `
    '原生 Story 包装不得额外声明 TargetModes'

$originPath = Join-Path $root "Public\$module\Origins\Origins.lsx"
Require (Test-Path -LiteralPath $originPath -PathType Leaf) '缺少 Origins.lsx'
[xml]$originDocument = Get-Content -LiteralPath $originPath -Raw -Encoding UTF8
$origins = @($originDocument.SelectNodes('//node[@id="Origin"]'))
Require ($origins.Count -eq 1) '最小包必须恰好注册一个起源'
$origin = $origins[0]
$originAttributes = @{}
foreach ($attribute in @($origin.SelectNodes('attribute'))) { $originAttributes[[string]$attribute.id] = [string]$attribute.value }
$requiredOrigin = @{
    AppearanceLocked = 'false'
    AvailableInCharacterCreation = '1'
    BackgroundUUID = '76925f0b-3ec8-4f42-86a9-cd4f745af2ac'
    BodyShape = '0'
    BodyType = '0'
    ClassUUID = '784001e2-c96d-4153-beb6-2adbef5abc92'
    DefaultsTemplate = '782183f9-ceb5-4a96-8ac4-56af0319641d'
    IntroDialogUUID = 'f015fd39-a9f2-6ee5-a77b-a28806ac1b7a'
    LockBody = 'false'
    LockClass = 'false'
    LockRace = 'false'
    Name = 'ChaosStoryMinimal'
    Passives = 'DeathSavingThrows;COS_ChaosOriginMarker;COS_Origin_Astarion;COS_Origin_Gale;COS_Origin_Laezel;COS_Origin_Shadowheart;COS_Origin_Wyll;COS_Origin_Karlach;COS_Origin_DarkUrge'
    RaceUUID = '45f4ac10-3c89-4fb2-b37d-f973bb9110c0'
    SubClassUUID = 'd379fdae-b401-4731-8d50-277c73919ae3'
    SubRaceUUID = '30fafb0b-7c8b-4917-bd2a-536233b35d3c'
    UUID = $originUuid
    VoiceTableUUID = '2949c570-0a52-4cfd-8434-50925e18d44b'
}
foreach ($entry in $requiredOrigin.GetEnumerator()) {
    Require ($originAttributes[$entry.Key] -eq $entry.Value) "Origin 字段错误: $($entry.Key)"
}
Require ([string]$origin.SelectSingleNode('attribute[@id="DisplayName"]').handle -eq $displayHandle) '起源名称 handle 错误'
Require ([string]$origin.SelectSingleNode('attribute[@id="Description"]').handle -eq $descriptionHandle) '起源说明 handle 错误'
foreach ($forbidden in @('GlobalTemplate', 'Identity', 'IsHenchman', 'ProgressionTableUUID', 'Unique')) {
    Require (-not $originAttributes.ContainsKey($forbidden)) "Origin 包含风险字段: $forbidden"
}
Require ($null -eq $origin.SelectSingleNode('children/node[@id="AppearanceTags"]')) 'Origin 不得包含 AppearanceTags'
$reallyTags = @($origin.SelectNodes('children/node[@id="ReallyTags"]/attribute[@id="Object"]'))
Require ($reallyTags.Count -eq 1 -and [string]$reallyTags[0].value -eq $originTagUuid) `
    'Origin 必须只包含新的混沌 ReallyTag'

[xml]$masteryProgressionDescriptionDocument = Get-Content -LiteralPath $masteryProgressionDescriptionPath -Raw -Encoding UTF8
$masteryProgressionDescriptions = @($masteryProgressionDescriptionDocument.SelectNodes('//node[@id="ProgressionDescription"]'))
Require ($masteryProgressionDescriptions.Count -eq 1) '一级切片必须恰好包含一个 ProgressionDescription'
$masteryProgressionDescriptionAttributes = @{}
foreach ($attribute in @($masteryProgressionDescriptions[0].SelectNodes('attribute'))) {
    $masteryProgressionDescriptionAttributes[[string]$attribute.id] = [string]$attribute.value
}
Require (-not $masteryProgressionDescriptionAttributes.ContainsKey('Hidden')) `
    '包含 SelectPassives 的混沌起源成长入口不得隐藏'
Require ([string]$masteryProgressionDescriptions[0].SelectSingleNode('attribute[@id="DisplayName"]').handle -eq $masteryDisplayHandle) `
    '掌控混沌成长入口名称 handle 错误'
Require ([string]$masteryProgressionDescriptions[0].SelectSingleNode('attribute[@id="Description"]').handle -eq $masteryDescriptionHandle) `
    '掌控混沌成长入口说明 handle 错误'
Require ($masteryProgressionDescriptionAttributes.Type -eq 'Origin_ChaosStoryMinimal') `
    '混沌起源成长说明 Type 必须匹配 Origin Name'
Require ($masteryProgressionDescriptionAttributes.ProgressionTableId -eq $masteryTableUuid) `
    '混沌起源成长说明表 UUID 错误'
Require ($masteryProgressionDescriptionAttributes.UUID -eq $masteryProgressionDescriptionUuid) `
    '混沌起源成长说明节点 UUID 错误'

[xml]$masteryProgressionDocument = Get-Content -LiteralPath $masteryProgressionPath -Raw -Encoding UTF8
$masteryProgressions = @($masteryProgressionDocument.SelectNodes('//node[@id="Progression"]'))
Require ($masteryProgressions.Count -eq 1) '一级切片必须恰好包含一个 Progression'
$masteryProgressionAttributes = @{}
foreach ($attribute in @($masteryProgressions[0].SelectNodes('attribute'))) {
    $masteryProgressionAttributes[[string]$attribute.id] = [string]$attribute.value
}
Require ($masteryProgressionAttributes.Level -eq '1') '一级切片 Progression 等级必须为 1'
Require ($masteryProgressionAttributes.Name -eq 'Origin_ChaosStoryMinimal') `
    '一级切片 Progression Name 必须匹配 Origin Name'
Require ($masteryProgressionAttributes.ProgressionType -eq '0') '一级切片 ProgressionType 必须为 0'
Require ($masteryProgressionAttributes.TableUUID -eq $masteryTableUuid) `
    '一级切片 Progression 与说明未复用同一 TableUUID'
$expectedMasterySelector = "SelectPassives($masteryPassiveListUuid,1,ChaosMasteryLevel1)"
Require ($masteryProgressionAttributes.Selectors -eq $expectedMasterySelector) `
    '一级切片必须使用固定三选一 SelectPassives'
Require ($masteryProgressionAttributes.UUID -eq $masteryProgressionUuid) '一级 Progression 节点 UUID 错误'

[xml]$masteryPassiveListDocument = Get-Content -LiteralPath $masteryPassiveListPath -Raw -Encoding UTF8
$masteryPassiveLists = @($masteryPassiveListDocument.SelectNodes('//node[@id="PassiveList"]'))
Require ($masteryPassiveLists.Count -eq 1) '一级切片必须恰好包含一个 PassiveList'
$masteryPassiveListAttributes = @{}
foreach ($attribute in @($masteryPassiveLists[0].SelectNodes('attribute'))) {
    $masteryPassiveListAttributes[[string]$attribute.id] = [string]$attribute.value
}
$expectedMasteryPassives = @(
    'COS_ChaosMastery_Tune_L01',
    'COS_ChaosMastery_Correct_L01',
    'COS_ChaosMastery_Buff_L01'
)
Require ($masteryPassiveListAttributes.Name -eq 'Chaos Mastery Level 1') '一级 PassiveList 名称错误'
Require ($masteryPassiveListAttributes.Passives -eq ($expectedMasteryPassives -join ',')) `
    '一级 PassiveList 必须严格按调律、纠偏、新BUFF排列'
Require ($masteryPassiveListAttributes.UUID -eq $masteryPassiveListUuid) '一级 PassiveList UUID 错误'
$masteryIdentifiers = @(
    $masteryTableUuid,
    $masteryProgressionDescriptionUuid,
    $masteryProgressionUuid,
    $masteryPassiveListUuid
)
Require (@($masteryIdentifiers | Select-Object -Unique).Count -eq 4) '掌控混沌 LSX 固定 UUID 不得重复'

$masteryStats = (Get-Content -LiteralPath $masteryStatsPath -Raw -Encoding UTF8).Trim()
$masteryEntryNames = @([regex]::Matches($masteryStats, 'new entry "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$expectedMasteryStatuses = @(
    'COS_CHAOS_MASTERY_POSITIVE_INFO',
    'COS_CHAOS_MASTERY_NEGATIVE_INFO',
    'COS_CHAOS_MASTERY_CALM_INFO',
    'COS_CHAOS_MASTERY_RESULT_L01'
)
$expectedMasteryEntries = @($expectedMasteryPassives) + $expectedMasteryStatuses
Require ($masteryEntryNames.Count -eq 7 -and -not (Compare-Object $expectedMasteryEntries $masteryEntryNames)) `
    '一级 ChaosMastery.txt 必须且只能包含3个成长被动和4个说明状态'
$masteryPassiveSpecs = @{
    COS_ChaosMastery_Tune_L01 = @('hbfabec61g3070g4e70g8e71gc20633da5d52', 'h0cf72805gf1e4g4f89gbc8fgb4eb4561d859', 'COS_Power')
    COS_ChaosMastery_Correct_L01 = @('h03a4fec8gb0efg45f9g8c5fgfd91d085f127', 'h0a9761a0g8ebeg4517ga88bgc9605641ea43', 'COS_Lost')
    COS_ChaosMastery_Buff_L01 = @('h1d501940gbda0g4737g8fecg66e1bbc85fe4', 'h09c3063egc130g48c2g8414g0535ea4196eb', 'COS_Echo')
}
foreach ($entry in $expectedMasteryPassives) {
    $pattern = '(?ms)^new entry "' + [regex]::Escape($entry) + '"\s*.*?(?=^new entry |\z)'
    $block = [regex]::Match($masteryStats, $pattern).Value
    $spec = $masteryPassiveSpecs[$entry]
    Require ($block.Contains('type "PassiveData"')) "成长选择必须是 PassiveData: $entry"
    Require ($block.Contains("data `"DisplayName`" `"$($spec[0]);1`"") -and `
        $block.Contains("data `"Description`" `"$($spec[1]);1`"")) `
        "成长选择缺少固定名称或说明: $entry"
    Require ($block.Contains("data `"Icon`" `"$($spec[2])`"")) "成长选择图标错误: $entry"
    Require ($block.Contains('data "Properties" "Highlighted"') -and -not $block.Contains('IsHidden')) `
        "成长选择必须可见且不得隐藏: $entry"
    Require (-not ($block -match '(?m)^data "(Boosts|StatsFunctors|ToggleOnFunctors|ToggleOffFunctors)"')) `
        "一级选择只能保存选择并提供说明，不得提前改变轮盘: $entry"
}
$masteryStatusSpecs = @{
    COS_CHAOS_MASTERY_POSITIVE_INFO = @('h5a27b995g2d15g4a0ega6a1g0e3a96807685', 'hfb12183cg2eefg4c66g88cbg1d4452ea0277', 'COS_Power')
    COS_CHAOS_MASTERY_NEGATIVE_INFO = @('h4cb49a94g6cdag4be4g87eag95893020d052', 'h6a7fc261g0307g46aeg9efcgea4e9d2add92', 'COS_Lost')
    COS_CHAOS_MASTERY_CALM_INFO = @('h0f888c08ge96ag4ac4ga02fgd41297ea527e', 'hb04f8bb6g8fceg4b25gaf0egb62b3a9f1b0e', 'COS_Echo')
    COS_CHAOS_MASTERY_RESULT_L01 = @('h7f3cf979gec23g46b4g87a5g17724ad407e7', 'hdb91fe36gf912g4c6bga223g06a6647455f7', 'COS_Echo')
}
foreach ($entry in $expectedMasteryStatuses) {
    $pattern = '(?ms)^new entry "' + [regex]::Escape($entry) + '"\s*.*?(?=^new entry |\z)'
    $block = [regex]::Match($masteryStats, $pattern).Value
    $spec = $masteryStatusSpecs[$entry]
    Require ($block.Contains('type "StatusData"') -and $block.Contains('using "COS_CHAOS_RACE_TEMPLATE"')) `
        "T键说明目标必须是只读 StatusData: $entry"
    Require ($block.Contains("data `"DisplayName`" `"$($spec[0]);1`"") -and `
        $block.Contains("data `"Description`" `"$($spec[1]);1`"")) `
        "T键说明状态缺少固定名称或说明: $entry"
    Require ($block.Contains("data `"Icon`" `"$($spec[2])`"") -and `
        $block.Contains("data `"StackId`" `"$entry`"")) `
        "T键说明状态图标或 StackId 错误: $entry"
    Require (-not ($block -match '(?m)^data "Boosts"')) "一级说明状态不得提前产生效果: $entry"
}
[xml]$masteryIconDocument = Get-Content -LiteralPath (Join-Path $root "Public\$module\GUI\Icons_ChaosOrigins.lsx") -Raw -Encoding UTF8
$registeredMasteryIcons = @($masteryIconDocument.SelectNodes('//node[@id="IconUV"]/attribute[@id="MapKey"]') | ForEach-Object { [string]$_.value })
foreach ($icon in @('COS_Power', 'COS_Lost', 'COS_Echo')) {
    Require ($registeredMasteryIcons -contains $icon) "掌控混沌复用了未注册图标: $icon"
}

$passivePath = Join-Path $root "Public\$module\Stats\Generated\Data\Passive.txt"
$passive = (Get-Content -LiteralPath $passivePath -Raw -Encoding UTF8).Trim()
$passiveEntries = @([regex]::Matches($passive, 'new entry "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$expectedPassiveEntries = @(
    'COS_ChaosOriginMarker',
    'COS_BaseProficiencies',
    'COS_BaseStarterSpells',
    'COS_Origin_Astarion',
    'COS_Origin_Gale',
    'COS_Origin_Laezel',
    'COS_Origin_Shadowheart',
    'COS_Origin_Wyll',
    'COS_Origin_Karlach',
    'COS_Origin_DarkUrge'
)
Require ($passiveEntries.Count -eq $expectedPassiveEntries.Count -and -not (Compare-Object $expectedPassiveEntries $passiveEntries)) `
    '静态包必须且只能定义三个基础被动和七个起源身份开关'
Require ([regex]::Matches($passive, 'data "Properties" "IsHidden"').Count -eq 3) '三项基础被动必须全部隐藏'
Require ([regex]::Matches($passive, 'data "Properties" "IsToggled;ToggledDefaultOn"').Count -eq 1) `
    '七个继承同一基类的起源身份开关必须在获得时默认开启'
Require ([regex]::Matches($passive, 'data "ToggleOnFunctors" "ApplyStatus\(COS_ORIGIN_TAG_').Count -eq 7) `
    '七个起源身份被动必须各自应用一个隐藏状态'
Require ([regex]::Matches($passive, 'data "ToggleOffFunctors" "RemoveStatus\(COS_ORIGIN_TAG_').Count -eq 7) `
    '七个起源身份被动必须各自移除一个隐藏状态'
Require ($passive.Contains('Proficiency(LightArmor);Proficiency(MediumArmor);Proficiency(HeavyArmor);Proficiency(Shields);Proficiency(SimpleWeapons);Proficiency(MartialWeapons);Proficiency(MusicalInstrument)')) `
    '基础熟练清单未与 ChaosOriginsRemastered 1.0.25 对齐'
Require (-not ($passive -match 'ProficiencyBonus\(Skill,|ExpertiseBonus\(')) `
    'Story 版不得额外授予任何技能熟练或专精'
foreach ($spellGrant in @('Target_BoomingBlade_ClassSpell','Target_Guidance','Target_MageHand,,,,Charisma','Target_MinorIllusion,,,,Intelligence','Shout_FeatherFall','Target_Jump','Shout_DisguiseSelf,AddChildren')) {
    Require ($passive.Contains("UnlockSpell($spellGrant)")) "缺少初始法术授予: $spellGrant"
}
Require ([regex]::Matches($passive, 'UnlockSpell\(').Count -eq 7) `
    '静态包必须严格只包含七个基础法术，不得授予种族主动能力'
Require (-not ($passive -match 'COR_|COS_Racial')) '静态被动不得夹带 SE 命名空间或种族主动开关'
foreach ($deferredPassive in @('COS_BaseProficiencies', 'COS_BaseStarterSpells')) {
    Require (-not $originAttributes.Passives.Split(';').Contains($deferredPassive)) `
        "创建阶段不得授予延迟能力: $deferredPassive"
}
$creationIdentityPassives = @($expectedPassiveEntries | Where-Object { $_.StartsWith('COS_Origin_') })
foreach ($identityPassive in $creationIdentityPassives) {
    Require ($originAttributes.Passives.Split(';').Contains($identityPassive)) `
        "创建阶段必须直接授予起源身份开关: $identityPassive"
}

$tagPath = Join-Path $root "resource-src\Public\$module\Tags\$originTagUuid.lsf.lsx"
Require (Test-Path -LiteralPath $tagPath -PathType Leaf) '缺少混沌起源标签源文件'
[xml]$tagDocument = Get-Content -LiteralPath $tagPath -Raw -Encoding UTF8
$tag = $tagDocument.SelectSingleNode('//region[@id="Tags"]/node[@id="Tags"]')
Require ($null -ne $tag) '标签源必须使用 Remastered 的单 Tags 节点结构'
$tagAttributes = @{}
foreach ($attribute in @($tag.SelectNodes('attribute'))) { $tagAttributes[[string]$attribute.id] = [string]$attribute.value }
Require ($tagAttributes.UUID -eq $originTagUuid) '起源标签 UUID 错误'
Require ($tagAttributes.Name -eq 'COS_REALLY_CHAOS') '起源标签名称错误'
$categories = @($tag.SelectNodes('children/node[@id="Categories"]/children/node[@id="Category"]/attribute[@id="Name"]') | ForEach-Object { [string]$_.value } | Sort-Object)
Require (-not (Compare-Object $categories @('Code', 'Dialog', 'DialogHidden'))) `
    '起源标签分类必须严格为 Code、Dialog、DialogHidden'
Require ($categories -notcontains 'Race' -and $categories -notcontains 'PlayerRace') `
    '起源身份标签绝不能注册成 Race 或 PlayerRace'

$identityHandles = @(
    'hfa05cce9gef4dg570bgbc1fg7187d154129d',
    'h4bf4229cg4ca7g5b86ga678g71397f548bd6',
    'hc53c9c68g2e77g5942gb976gef3da865ae2f',
    'h8e938e08g4ff5g5681gab82gc0174825c89b',
    'hbb2cc0a8gfdcdg5a4ag9783gf62a2527e686',
    'hcf23c2c6ga9a3g55bega9c4g60781e86156a',
    'h47aa1ba3g2956g5ba5gb309g7e66f6e19d84',
    'hdc7f2089gaa8bg493bg910fg96d1eae6ce0e'
)
$masteryLocalizationHandles = @(
    'h1253cd25g6db6g4704g90e7gadf6ad0df3ed',
    'h11f157e4g81c1g4dc8gbd3eg20fbb820812f',
    'hbfabec61g3070g4e70g8e71gc20633da5d52',
    'h0cf72805gf1e4g4f89gbc8fgb4eb4561d859',
    'h03a4fec8gb0efg45f9g8c5fgfd91d085f127',
    'h0a9761a0g8ebeg4517ga88bgc9605641ea43',
    'h1d501940gbda0g4737g8fecg66e1bbc85fe4',
    'h09c3063egc130g48c2g8414g0535ea4196eb',
    'h5a27b995g2d15g4a0ega6a1g0e3a96807685',
    'hfb12183cg2eefg4c66g88cbg1d4452ea0277',
    'h4cb49a94g6cdag4be4g87eag95893020d052',
    'h6a7fc261g0307g46aeg9efcgea4e9d2add92',
    'h0f888c08ge96ag4ac4ga02fgd41297ea527e',
    'hb04f8bb6g8fceg4b25gaf0egb62b3a9f1b0e',
    'h7f3cf979gec23g46b4g87a5g17724ad407e7',
    'hdb91fe36gf912g4c6bga223g06a6647455f7'
)
$expectedHandles = (@($descriptionHandle, $displayHandle) + $identityHandles + $masteryLocalizationHandles) | Sort-Object
$masteryTooltipSpecs = @{
    h0cf72805gf1e4g4f89gbc8fgb4eb4561d859 = @('COS_CHAOS_MASTERY_NEGATIVE_INFO', 'COS_CHAOS_MASTERY_POSITIVE_INFO')
    h0a9761a0g8ebeg4517ga88bgc9605641ea43 = @('COS_CHAOS_MASTERY_CALM_INFO', 'COS_CHAOS_MASTERY_NEGATIVE_INFO')
    h09c3063egc130g48c2g8414g0535ea4196eb = @('COS_CHAOS_MASTERY_CALM_INFO', 'COS_CHAOS_MASTERY_NEGATIVE_INFO', 'COS_CHAOS_MASTERY_RESULT_L01')
}
$referenceLocalizationHandles = $null
foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $path = Join-Path $root "Localization\$language\ChaosOriginsStory.xml"
    Require (Test-Path -LiteralPath $path -PathType Leaf) "缺少本地化源: $language"
    [xml]$localization = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $contents = @($localization.contentList.content)
    $handles = @($contents | ForEach-Object { [string]$_.contentuid } | Sort-Object)
    Require ($handles.Count -eq 642 -and @($handles | Select-Object -Unique).Count -eq 642) `
        "完整本地化必须包含 642 个唯一文本: $language"
    Require (-not ($expectedHandles | Where-Object { $handles -notcontains $_ })) `
        "完整本地化缺少起源、身份或掌控混沌文本: $language"
    if ($null -eq $referenceLocalizationHandles) {
        $referenceLocalizationHandles = $handles
    } else {
        Require (-not (Compare-Object $referenceLocalizationHandles $handles)) `
            "四语本地化 handle 集合不一致: $language"
    }
    $contentsByHandle = @{}
    foreach ($content in $contents) {
        Require (-not [string]::IsNullOrWhiteSpace([string]$content.InnerText)) "本地化包含空文本: $language"
        $contentsByHandle[[string]$content.contentuid] = $content
    }
    foreach ($description in $masteryTooltipSpecs.Keys) {
        $tooltips = @([regex]::Matches([string]$contentsByHandle[$description].InnerText, 'Tooltip="([^"]+)"') | `
            ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        $expectedTooltips = @($masteryTooltipSpecs[$description] | Sort-Object)
        Require ($tooltips.Count -eq $expectedTooltips.Count -and -not (Compare-Object $expectedTooltips $tooltips)) `
            "掌控混沌 T键链接结构错误: $language / $description"
        foreach ($tooltip in $tooltips) {
            Require ($expectedMasteryStatuses -contains $tooltip) `
                "掌控混沌 T键链接指向不存在的 StatusData: $language / $tooltip"
        }
    }
}

$storyPath = Join-Path $root "Mods\$module\Story"
$headerPath = Join-Path $storyPath 'RawFiles\story_header.div'
$goalPath = Join-Path $storyPath 'RawFiles\Goals\COS_BaseAfterCreation.txt'
Require (Test-Path -LiteralPath $headerPath -PathType Leaf) '缺少 Story 编译头文件'
$headerText = Get-Content -LiteralPath $headerPath -Raw -Encoding UTF8
Require ($headerText.Replace("`r`n", "`n").Length -eq 126581) `
    'Story 编译头未与本机已运行原生 Story MOD 的当前头对齐'
Require ([regex]::Matches($headerText, '(?m)^enum_type ').Count -eq 14) `
    'Story 编译必须使用含 14 个 enum_type 的原始头文件，不能使用已转换的暂存头'
Require ([regex]::Matches($headerText, '(?m)^alias_type ').Count -eq 25) `
    'Story 原始头文件 alias_type 数量错误'
$rewardGoalPath = Join-Path $storyPath 'RawFiles\Goals\COS_OriginStoryRewards.txt'
$mechanicsGoalPath = Join-Path $storyPath 'RawFiles\Goals\COS_ChaosMechanics.txt'
$goals = @(Get-ChildItem -LiteralPath (Split-Path $goalPath -Parent) -File -Filter '*.txt')
Require ($goals.Count -eq 3 -and ($goals.FullName -contains $goalPath) -and `
    ($goals.FullName -contains $rewardGoalPath) -and ($goals.FullName -contains $mechanicsGoalPath)) `
    '当前 Story 必须且只能包含基础同步、混沌机制和起源剧情奖励三个 Goal'
$goal = Get-Content -LiteralPath $goalPath -Raw -Encoding UTF8
$expectedRaceTags = @(
    '60f6b464-752f-4970-a855-f729565b5e07','78adf3cd-4741-47a8-94f6-f3d322432591',
    '534098fa-601d-4f6e-8c4e-b3a8d4b1f141','1dc20a7a-00e7-4126-80ad-aa1152a2136c',
    '4fa13243-199d-4c9a-b455-d844276a98f5','eae44d86-3321-4a0a-811d-4fd8e48b5723',
    '52b71dea-9d4e-402d-9700-fb9c360a44c9','5ffb703c-3ef4-493b-966d-749bc038f6bd',
    'ef9c5b74-56a8-48cc-b0b9-169ee16bf026','6e913b6e-58b1-41bf-8751-89250dd17bff',
    '492c3200-1226-4114-bad1-f6b1ba737f3d','889e0db5-d03e-4b63-86d7-13418f69729f',
    '57a00605-9e74-477c-bd9d-53c721e25e56','8d545fa1-8416-493f-8325-7d112bceced8',
    '02e5e9ed-b6b2-4524-99cd-cb2bc84c754a','a672ac1d-d088-451a-9537-3da4bf74466c',
    '486a2562-31ae-437b-bf63-30393e18cbdd','50e7beca-4e90-43cd-b7c5-c235e236077f',
    '351f4e42-1217-4c06-b47a-443dcf69b111','677ffa76-2562-4217-873e-2253d4720ba4',
    '1f0551f3-d769-47a9-b02b-5d3a8c51978c','34317158-8e6e-45a2-bd1e-6604d82fdda2',
    '3311a9a9-cdbc-4b05-9bf6-e02ba1fc72a3','b99b6a5d-8445-44e4-ac58-81b2ee88aab1',
    '69fd1443-7686-4ca9-9516-72ec0b9d94d7','aaef5d43-c6f3-434d-b11e-c763290dbe0c',
    'c3fd1fc3-2edf-4d17-935d-44ab92406df1','ec5bea6b-26f1-4917-919c-375f67ac13d1',
    'ab677895-e08a-479f-a043-eac2d8447188','2bbc3217-3d8c-46e6-b599-a0f1c9063f9a',
    '09518377-4ea1-4ce2-b8e8-61477c26ebdd','664cc044-a0ea-43a1-b21f-d8cad7721102'
) | Sort-Object
$actualRaceTags = @([regex]::Matches($goal, 'DB_COS_RaceIdentityTag\(\(TAG\)([0-9a-f-]{36})\);') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Require ($actualRaceTags.Count -eq 32 -and @($actualRaceTags | Select-Object -Unique).Count -eq 32 -and -not (Compare-Object $expectedRaceTags $actualRaceTags)) `
    'Story Goal 必须且只能包含 32 个官方可选种族身份标签'
$expectedOriginTags = @(
    'ffd08582-7396-4cac-bcd4-8f9cd0fd8ef3',
    '9b0354c0-56d9-4723-8034-918ac9abab19',
    'b5682d1d-c395-489c-9675-1f9b0c328ea5',
    '642d2aee-e3df-47e3-9f47-bbcd441bb9e0',
    '5f40def5-d3ec-4698-a367-01a339888956',
    '1a2f70d6-8ead-4eb5-a824-79ee1971764a',
    'cd611d7d-b67d-42b4-a75c-a0c6091ef8a2'
) | Sort-Object
$actualOriginTags = @([regex]::Matches($goal, 'DB_COS_OriginIdentityToggle\("[^"]+", "[^"]+", \(TAG\)([0-9a-f-]{36})\);') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Require ($actualOriginTags.Count -eq 7 -and @($actualOriginTags | Select-Object -Unique).Count -eq 7 -and -not (Compare-Object $expectedOriginTags $actualOriginTags)) `
    'Story Goal 必须且只能包含阿斯代伦、盖尔、莱埃泽尔、影心、威尔、卡菈克和邪念七个官方身份标签'
$expectedOriginToggleMappings = @(
    'COS_Origin_Astarion|COS_ORIGIN_TAG_ASTARION|ffd08582-7396-4cac-bcd4-8f9cd0fd8ef3',
    'COS_Origin_Gale|COS_ORIGIN_TAG_GALE|9b0354c0-56d9-4723-8034-918ac9abab19',
    'COS_Origin_Laezel|COS_ORIGIN_TAG_LAEZEL|b5682d1d-c395-489c-9675-1f9b0c328ea5',
    'COS_Origin_Shadowheart|COS_ORIGIN_TAG_SHADOWHEART|642d2aee-e3df-47e3-9f47-bbcd441bb9e0',
    'COS_Origin_Wyll|COS_ORIGIN_TAG_WYLL|5f40def5-d3ec-4698-a367-01a339888956',
    'COS_Origin_Karlach|COS_ORIGIN_TAG_KARLACH|1a2f70d6-8ead-4eb5-a824-79ee1971764a',
    'COS_Origin_DarkUrge|COS_ORIGIN_TAG_DARKURGE|cd611d7d-b67d-42b4-a75c-a0c6091ef8a2'
) | Sort-Object
$actualOriginToggleMappings = @([regex]::Matches($goal, 'DB_COS_OriginIdentityToggle\("([^"]+)", "([^"]+)", \(TAG\)([0-9a-f-]{36})\);') | ForEach-Object {
    "$($_.Groups[1].Value)|$($_.Groups[2].Value)|$($_.Groups[3].Value)"
} | Sort-Object)
Require ($actualOriginToggleMappings.Count -eq 7 -and -not (Compare-Object $expectedOriginToggleMappings $actualOriginToggleMappings)) `
    '七个起源身份被动、隐藏状态与官方标签映射错误'
foreach ($requiredGoalText in @(
    'LevelGameplayStarted(_, _)',
    'GainedControl(_Character)',
    'GetHostCharacter(_Character)',
    'IsTagged(_Character, _Tag, 0)',
    'SetTag(_Character, _Tag)',
    'ClearTag(_Character, _Tag)',
    'StatusApplied(_Character, _Status, _, _)',
    'StatusRemoved(_Character, _Status, _, _)',
    'DB_COS_OriginIdentityToggle(_Passive, _Status, _Tag)',
    'AddPassive(_Character, _Passive)',
    'HasActiveStatus(_Character, _Status, 1)',
    'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
    'AddPassive(_Character, "COS_BaseProficiencies")',
    'AddPassive(_Character, "COS_BaseStarterSpells")'
)) {
    Require ($goal.Contains($requiredGoalText)) "基础同步 Goal 缺少: $requiredGoalText"
}
$forbiddenRacialPassives = @(
    'DeepGnome_StoneCamouflage','Drow_DrowWeaponTraining','Duergar_DuergarResilience',
    'Dwarf_DwarvenCombatTraining','Dwarf_DwarvenResilience','Elf_WeaponTraining','FeyAncestry',
    'Gith_MartialProdigy','Gnome_Cunning','Halfling_Brave','Halfling_LightfootStealth',
    'Halfling_Lucky','Halfling_StoutResilience','HumanMilitia','MountainDwarf_DwarvenArmorTraining',
    'RelentlessEndurance','RockGnome_ArtificersLore','SavageAttacks','SuperiorDarkvision',
    'Tiefling_HellishResistance'
)
foreach ($racialPassive in $forbiddenRacialPassives) {
    Require (-not $passive.Contains($racialPassive) -and -not $goal.Contains($racialPassive)) `
        "默认关闭的种族被动不得被静态定义或 Story 授予: $racialPassive"
}
$originSpellMappings = @([regex]::Matches($goal, 'DB_COS_OriginIdentitySpell\("([^"]+)", "([^"]+)"\);') | ForEach-Object {
    "$($_.Groups[1].Value)|$($_.Groups[2].Value)"
})
Require ($originSpellMappings.Count -eq 1 -and $originSpellMappings[0] -eq 'COS_ORIGIN_TAG_ASTARION|Target_VampireBite_Astarion') `
    '阿斯代伦身份必须且只能授予吸血'
$originPassiveMappings = @([regex]::Matches($goal, 'DB_COS_OriginIdentityPassive\("([^"]+)", "([^"]+)"\);') | ForEach-Object {
    "$($_.Groups[1].Value)|$($_.Groups[2].Value)"
} | Sort-Object)
$expectedOriginPassiveMappings = @(
    'COS_ORIGIN_TAG_WYLL|BladeOfFrontiers',
    'COS_ORIGIN_TAG_KARLACH|ORI_Karlach_SweatImmune',
    'COS_ORIGIN_TAG_KARLACH|ORI_Karlach_Rage_Flames'
) | Sort-Object
Require ($originPassiveMappings.Count -eq 3 -and -not (Compare-Object $expectedOriginPassiveMappings $originPassiveMappings)) `
    '威尔与卡菈克身份即时被动映射错误'
foreach ($requiredOriginFeatureRule in @('AddSpell((CHARACTER)_Character, _Spell, 0, 0)', 'RemoveSpell((CHARACTER)_Character, _Spell, 0)', 'AddPassive(_Character, _FeaturePassive)', 'RemovePassive(_Character, _FeaturePassive)')) {
    Require ($goal.Contains($requiredOriginFeatureRule)) "缺少身份即时能力同步规则: $requiredOriginFeatureRule"
}
foreach ($runtimeSensitiveCast in @(
    'HasSpell((CHARACTER)_Character, _Spell, 0)',
    'HasSpell((CHARACTER)_Character, _Spell, 1)'
)) {
    Require ($goal.Contains($runtimeSensitiveCast)) "基础同步缺少当前游戏 Story 头要求的类型转换: $runtimeSensitiveCast"
}
foreach ($forbiddenGoalText in @('UserAvatarCreated', 'DB_Avatars', 'COS_AllSkillMastery', 'ProficiencyBonus(Skill', 'ExpertiseBonus', 'MCM', 'TutorialEvent', 'COS_RacialSpells_', 'DB_COS_RacialSpellPassive', 'TogglePassive(')) {
    Require (-not $goal.Contains($forbiddenGoalText)) "基础同步 Goal 包含禁用行为: $forbiddenGoalText"
}
Require (-not $goal.Contains('DB_COS_CorePassive(1, "COS_ChaosEcho")')) `
    '基础同步不得再授予混沌回响'
Require ($goal.Contains('RemovePassive(_Character, "COS_ChaosEcho")')) `
    '基础同步必须移除旧存档残留的混沌回响被动'
$rewardGoal = Get-Content -LiteralPath $rewardGoalPath -Raw -Encoding UTF8
Require ([regex]::Matches($rewardGoal, 'DB_COS_OriginStoryFlag\(\(FLAG\)').Count -eq 11) `
    '起源剧情奖励必须严格监听 11 个已审核官方 Flag'
foreach ($rewardToken in @(
    'LOW_Astarion_VampireAscendant','Shout_EPI_Astarion_TurnIntoBat',
    'Target_END_Gale_ActivateNethereseOrb','ORI_Gale_ShadowSpellSlots','Target_ORI_Gale_ShadowSummon','EPI_GALEGOD',
    'Shout_ORI_Wyll_FireShield_Warm','Target_ORI_Wyll_SummonCambion',
    'ORI_KARLACH_FIRSTUPGRADE','ORI_KARLACH_SECONDUPGRADE',
    'Shout_DarkUrge_Slayer','Target_LOW_DarkUrge_PowerWordKill'
)) {
    Require ($rewardGoal.Contains($rewardToken)) "起源剧情奖励缺少: $rewardToken"
}
foreach ($forbiddenRewardText in @('TemplateAddTo','TemplateAddedTo','ProficiencyBonus(Skill','ExpertiseBonus','UserAvatarCreated','DB_Avatars','ScriptExtender','MCM')) {
    Require (-not $rewardGoal.Contains($forbiddenRewardText)) "起源剧情奖励包含禁用行为: $forbiddenRewardText"
}
foreach ($runtimeSensitiveRewardCast in @(
    'PROC_COS_SyncOriginStoryRewards((CHARACTER)_Character)',
    'HasSpell((CHARACTER)_Character, "Shout_DarkUrge_Slayer", 1)',
    'DB_COS_PowerWordKillConsumed((CHARACTER)_Character)'
)) {
    Require ($rewardGoal.Contains($runtimeSensitiveRewardCast)) "剧情奖励缺少当前游戏 Story 头要求的类型转换: $runtimeSensitiveRewardCast"
}
$mechanicsGoal = Get-Content -LiteralPath $mechanicsGoalPath -Raw -Encoding UTF8
Require (-not $mechanicsGoal.Contains('COS_ChaosMastery')) `
    '一级原生选择切片不得提前修改两仪或受击轮盘逻辑'
foreach ($requiredMechanicsText in @(
    'PROC_COS_RollWound', 'PROC_COS_ResolveDuality', 'PROC_COS_AddPower', 'PROC_COS_AddLost',
    'Shout_COS_ChaosGenesis', 'AttackedBy(', 'TurnStarted(', 'EnteredCombat(', 'LeftCombat(',
    'UsingSpell(_Character, "Shout_COS_TestPower100"', 'PROC_COS_AddPower((CHARACTER)_Character, 100)',
    'RestorePartyFinished()', 'COS_CHAOS_RESTORE_ALLIN', 'Random(100, _DualityRoll)',
    'PROC_COS_QueueDualityDamage', 'RealtimeObjectTimerLaunch(_Target, "COS_DualityApplyDamage", 50)',
    'ObjectTimerFinished(_Target, "COS_DualityApplyDamage")', 'DB_COS_DualityDamagePending',
    'PROC_COS_QueueDelayedDualityDamage', 'DB_COS_DualityDelayed', 'DB_COS_DualityDelaySerial',
    'SetHitpoints(_Target, _FinalHitpoints, "Guaranteed")',
    'COS_CHAOS_DUALITY_LOG_RETURN', 'COS_CHAOS_DUALITY_LOG_ELEMENTAL',
    'COS_CHAOS_DUALITY_LOG_BOOST_80', 'COS_CHAOS_DUALITY_LOG_DEVOUR_40'
)) {
    Require ($mechanicsGoal.Contains($requiredMechanicsText)) "混沌核心机制缺少: $requiredMechanicsText"
}
foreach ($forbiddenMechanicsText in @(
    'UserAvatarCreated', 'LevelGameplayReady', 'TemplateAddTo', 'TemplateAddedTo', 'TutorialEvent',
    'PROC_COS_ConfigEnsureBook', 'PROC_COS_ConfigSyncOrigins', 'PROC_COS_ConfigSyncRacialPassives',
    'PROC_COS_StarterRewards', 'PROC_COS_GrantFeatures', 'PROC_COS_GrantTags', 'PROC_COS_RemoveForbidden',
    'DB_COS_Spell(', 'DB_COS_Passive(', 'DB_COS_ConfigOrigin(', 'ProficiencyBonus(Skill', 'ExpertiseBonus',
    'PROC_COS_Echo', 'COS_CHAOS_ECHO_LOG_', 'COS_CHAOS_SENTINEL_ECHO_', '"Echo", 1'
)) {
    Require (-not $mechanicsGoal.Contains($forbiddenMechanicsText)) "混沌核心机制包含禁用旧逻辑: $forbiddenMechanicsText"
}
Require ([regex]::Matches($mechanicsGoal, 'DB_COS_WoundLog\(\d+, "COS_CHAOS_WOUND_LOG_').Count -eq 24) `
    '受击轮盘必须为 24 个状态结果提供具名战斗日志'
$dualityBands = @([regex]::Matches($mechanicsGoal, 'DB_COS_DualityBand\((\d+), (\d+), (\d+), "([^"]+)"\);'))
Require ($dualityBands.Count -eq 8) '两仪必须包含八档连续伤害倍率'
$expectedDualityBands = @('0,2,70','2,9,85','9,23,95','23,53,100','53,75,105','75,90,115','90,98,130','98,100,150')
$actualDualityBands = @($dualityBands | ForEach-Object { '{0},{1},{2}' -f $_.Groups[1].Value,$_.Groups[2].Value,$_.Groups[3].Value })
Require (($actualDualityBands -join '|') -eq ($expectedDualityBands -join '|')) `
    '两仪倍率必须覆盖 100 格且保持确认的递减极端概率'
foreach ($timingBoundary in @('_TimingRoll < _ImmediateEnd','_TimingRoll >= _ImmediateEnd','_TimingRoll < _SplitEnd','_TimingRoll >= _SplitEnd','IntegerSum(_Percent, _SplitBonus','IntegerSum(_Percent, _DelayBonus')) {
    Require ($mechanicsGoal.Contains($timingBoundary)) "两仪缺少确认的立即、分期或延迟边界: $timingBoundary"
}
foreach ($timingTier in @(
    'DB_COS_DualityTiming(1, 90, 98, 5, 15, 80);',
    'DB_COS_DualityTiming(2, 75, 90, 10, 25, 65);',
    'DB_COS_DualityTiming(3, 60, 85, 15, 35, 50);'
)) {
    Require ($mechanicsGoal.Contains($timingTier)) "两仪缺少等级成长时机档: $timingTier"
}
foreach ($postLevelMechanic in @(
    'IntegerMin(_Level, 30, _CappedLevel)',
    'IntegerProduct(_PostLevels, 2, _SplitGrowth)',
    'IntegerProduct(_PostLevels, 3, _DelayGrowth)',
    'IntegerMin(_AdjustedPercentRaw, 200, _AdjustedPercent)',
    'IntegerProduct(_PostLevels, 5, _PositiveThreshold)'
)) {
    Require ($mechanicsGoal.Contains($postLevelMechanic)) "13至30级逐级成长缺少: $postLevelMechanic"
}
$woundWeights = @{}
foreach ($match in [regex]::Matches($mechanicsGoal, 'DB_COS_WoundWeight\((\d+), (\d+)\);')) {
    $woundWeights[[int]$match.Groups[1].Value] = [int]$match.Groups[2].Value
}
Require ($woundWeights.Count -eq 26) '受击轮盘必须为全部 26 个结果声明独立权重'
$positiveWoundWeight = (13,14,15,16,17,18,19,20,21,22,25 | ForEach-Object { $woundWeights[$_] } | Measure-Object -Sum).Sum
$negativeWoundWeight = (0..12 + 23,24 | ForEach-Object { $woundWeights[$_] } | Measure-Object -Sum).Sum
Require ($positiveWoundWeight -eq 41 -and $negativeWoundWeight -eq 35) `
    '1至4级受击轮盘权重必须为正面 41 格、负面 35 格'
$woundGrowth5 = ([regex]::Matches($mechanicsGoal, 'DB_COS_WoundGrowthWeight\(5, \d+, (\d+)\);') | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Sum).Sum
$woundGrowth9 = ([regex]::Matches($mechanicsGoal, 'DB_COS_WoundGrowthWeight\(9, \d+, (\d+)\);') | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Sum).Sum
Require ($woundGrowth5 -eq 8 -and $woundGrowth9 -eq 12) `
    '受击轮盘必须在5级增至49个正面格、9级增至61个正面格'
Require ($woundWeights[14] -eq 1 -and $woundWeights[17] -eq 1 -and $woundWeights[25] -eq 1) `
    '加速、隐形和嗜血必须保持稀有权重'
Require (-not [regex]::IsMatch($mechanicsGoal, 'DB_COS_WoundStatus\([^\r\n]+"(MADNESS|FRIGHTENED|STUNNED|PRONE|SILENCED|BLINDED|SLOW|POISONED|BLEEDING|BURNING)"')) `
    '受击轮盘不得包含夺取控制或可能造成失控死亡的原版负面状态'
Require (-not [regex]::IsMatch($mechanicsGoal, '_Roll == (23|24)[\s\S]{0,700}(ApplyDamage|WOUND_VULNERABILITY)')) `
    '受击轮盘不得通过随机易伤或额外伤害制造突然死亡'
Require ([regex]::Matches($mechanicsGoal, 'NOT DB_COS_WoundConsumed\(\(CHARACTER\)_Character\);').Count -eq 3) `
    '受击轮盘锁必须在回合开始、进入战斗和离开战斗时清除'
Require (-not $mechanicsGoal.Contains('IsInCombat(_Target, 1)')) `
    '受击轮盘不得把非战斗状态下的角色攻击错误过滤掉'
$iconAtlasPath = Join-Path $root "Public\$module\Assets\Textures\Icons\Icons_ChaosOrigins.dds"
Require ((Get-FileHash -Algorithm SHA256 -LiteralPath $iconAtlasPath).Hash -eq `
    'E35B45C4C4BCAE74FEFF1B8EF74E6BD4FA7767EA124196B11C80BD1775921B87') `
    '技能图标必须使用 ChaosOriginsRemastered 1.0.25 的 8-bit Alpha DDS 原文件'
$allStats = (Get-ChildItem -LiteralPath (Join-Path $root "Public\$module\Stats\Generated\Data") -File -Filter '*.txt' | `
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
Require (-not ($allStats -match 'ProficiencyBonus\(Skill|ExpertiseBonus\(')) `
    '完整 Stats 不得额外授予任何技能熟练或专精'
Require ([regex]::Matches($mechanicsGoal, 'DB_COS_LifeSkillLevel\(\d+, \d+, "COS_CHAOS_LIFE_SKILL_BONUS_\d"\);').Count -eq 7) `
    '生活检定成长必须严格包含 5 至 30 级的 7 个阶段'
foreach ($lifeSkillBonus in 1..7) {
    $lifeSkillEntry = "COS_CHAOS_LIFE_SKILL_BONUS_$lifeSkillBonus"
    $lifeSkillPattern = 'new entry "{0}"[\s\S]*?(?=\r?\nnew entry|\z)' -f [regex]::Escape($lifeSkillEntry)
    $lifeSkillBlock = [regex]::Match($allStats, $lifeSkillPattern).Value
    Require ($lifeSkillBlock.Contains("RollBonus(SkillCheck,$lifeSkillBonus);RollBonus(RawAbility,$lifeSkillBonus)")) `
        "生活检定成长档位错误: $lifeSkillEntry"
}
Require ($mechanicsGoal.Contains('IntegerMin(_Level, 30, _CappedLevel)') -and `
    $mechanicsGoal.Contains('PROC_COS_ClearLifeSkillBonus(_Character);') -and `
    $mechanicsGoal.Contains('PROC_COS_ApplyLifeSkillBonus(_Character);')) `
    '生活检定成长必须封顶 30 级并在同步时替换旧档位'
Require (-not ($allStats -match 'COS_ChaosEcho|COS_CHAOS_ECHO_LOG_|COS_CHAOS_SENTINEL_ECHO_')) `
    '完整 Stats 不得保留混沌回响定义'
$featuresPath = Join-Path $root "Public\$module\Stats\Generated\Data\ChaosFeatures.txt"
$featuresText = Get-Content -LiteralPath $featuresPath -Raw -Encoding UTF8
Require ($featuresText.Contains('new entry "Shout_COS_TestPower100"') -and `
    $featuresText.Contains('data "UseCosts" ""')) `
    '测试阶段必须提供无消耗的100点混沌之力技能'
Require ($featuresText.Contains('new entry "Shout_COS_TestRestoreAllIn"') -and `
    $featuresText.Contains('ApplyStatus(SELF,COS_CHAOS_RESTORE_ALLIN,100,0.1)')) `
    '测试阶段必须提供恢复全部孤注充能的技能'
Require ($featuresText.Contains('data "StackType" "Additive"') -and `
    $featuresText.Contains('StatusImmunity(COS_CHAOS_SENTINEL_POWER)') -and `
    $featuresText.Contains('IgnoreResting;FreezeDuration')) `
    '混沌之力必须使用可显示当前点数的冻结持续时间状态'
Require ($mechanicsGoal.Contains('IntegerProduct(_Power, 6, _DurationSeconds)') -and `
    $mechanicsGoal.Contains('IntegerToReal(_DurationSeconds, _Duration)') -and `
    $mechanicsGoal.Contains('ApplyStatus(_Character, "COS_CHAOS_POWER_STACK", _Duration, 100, _Character)')) `
    '混沌之力显示必须把当前点数换算成冻结的回合数字'
Require ($mechanicsGoal.Contains('_OldPower >= 10') -and `
    $mechanicsGoal.Contains('IntegerSubtract(_OldPower, 10, _NewPower)') -and `
    $mechanicsGoal.Contains('_Power >= 10')) `
    '混沌开天辟地必须需要并消耗 10 点混沌之力'
Require ($featuresText.Contains('new entry "Shout_COS_FateRevision"') -and `
    $featuresText.Contains("HasStatus('COS_CHAOS_FATE_READY',context.Source) and not HasStatus('COS_CHAOS_FATE_PENDING',context.Source)") -and `
    $featuresText.Contains('ApplyStatus(SELF,COS_CHAOS_FATE_PENDING,100,-1)')) `
    '命运改签必须是只能挂起一次的待结算能力'
Require ($mechanicsGoal.Contains('UsingSpell(_Character, "Shout_COS_FateRevision", _, _, _)') -and `
    $mechanicsGoal.Contains('IntegerSubtract(_OldPower, 1, _NewPower)')) `
    '命运改签必须消耗 1 点混沌之力'
Require ([regex]::Matches($mechanicsGoal, 'DB_COS_WoundFateRank\(\d+, \d+\);').Count -eq 26 -and `
    $mechanicsGoal.Contains('Random(_Count, _FirstSlot)') -and `
    $mechanicsGoal.Contains('PROC_COS_ContinueFateWound') -and `
    $mechanicsGoal.Contains('_NextRank > _BestRank')) `
    '命运改签必须为受击轮盘递归判定并保留评级最高的结果'
Require ($mechanicsGoal.Contains('Random(100, _FirstDualityRoll)') -and `
    $mechanicsGoal.Contains('PROC_COS_ContinueFateDuality') -and `
    $mechanicsGoal.Contains('IntegerMax(_BestRoll, _NextRoll, _NextBestRoll)')) `
    '命运改签必须为两仪递归判定并保留更高的倍率结果'
$expectedFateTiers = @(
    'DB_COS_FateRolls(1, 5, 2);',
    'DB_COS_FateRolls(5, 9, 3);',
    'DB_COS_FateRolls(9, 13, 4);',
    'DB_COS_FateRolls(13, 17, 5);',
    'DB_COS_FateRolls(17, 21, 6);',
    'DB_COS_FateRolls(21, 25, 7);',
    'DB_COS_FateRolls(25, 100, 8);'
)
foreach ($fateTier in $expectedFateTiers) {
    Require ($mechanicsGoal.Contains($fateTier)) "命运改签等级判定次数缺少: $fateTier"
}
foreach ($powerChance in @(
    'DB_COS_LostChance(1, 15);',
    'DB_COS_LostChance(6, 100);',
    'DB_COS_KillChance(1, 10, 5);',
    'DB_COS_KillChance(31, 39, 35);',
    'DB_COS_KillChance(40, 40, 100);'
)) {
    Require ($mechanicsGoal.Contains($powerChance)) "混沌之力降低获取难度缺少: $powerChance"
}
Require (-not $mechanicsGoal.Contains('PROC_COS_ApplyPowerStacks')) `
    '混沌之力不得继续使用不可见数字的永久状态递归叠层'
Require ($featuresText.Contains('data "StatsFunctorContext" "OnCreate;OnShortRest"') -and `
    $featuresText.Contains('data "StatsFunctors" "RestoreResource(COS_ChaosAllInUse,100%,0)"')) `
    '混沌孤注必须在创建和短休时恢复当前等级的全部充能'
foreach ($allInPenalty in @('RollBonus(Attack,-8)', 'RollBonus(Attack,-6)', 'RollBonus(Attack,-4)')) {
    Require ($featuresText.Contains($allInPenalty)) "混沌孤注缺少命中惩罚: $allInPenalty"
}
foreach ($allInEntry in @('COS_CHAOS_ALLIN_L1', 'COS_CHAOS_ALLIN_L3', 'COS_CHAOS_ALLIN_L7')) {
    $allInPattern = 'new entry "{0}"[\s\S]*?(?=\r?\nnew entry|\z)' -f [regex]::Escape($allInEntry)
    $allInBlock = [regex]::Match($featuresText, $allInPattern).Value
    Require (-not $allInBlock.Contains('CriticalHit(')) "混沌孤注不得强制命中或暴击: $allInEntry"
}
$genesisBlock = [regex]::Match($featuresText, 'new entry "COS_CHAOS_GENESIS"[\s\S]*?(?=\r?\nnew entry|\z)').Value
Require (-not $genesisBlock.Contains('ActionResource(ActionPoint')) `
    '混沌开天辟地状态不得额外增加行动点'
Require ($featuresText.Contains('RestoreResource(ActionPoint,100%,0)')) `
    '混沌开天辟地施放时必须保留行动点恢复'
$formalFiles = @(
    (Join-Path $root "Mods\$module\meta.lsx"),
    $goalPath,
    $mechanicsGoalPath,
    $rewardGoalPath,
    (Join-Path $root "Public\$module\Origins\Origins.lsx"),
    $masteryPassiveListPath,
    $masteryProgressionDescriptionPath,
    $masteryProgressionPath,
    $masteryStatsPath,
    (Join-Path $root "Public\$module\Stats\Generated\Data\Passive.txt"),
    (Join-Path $root "Public\$module\Stats\Generated\Data\Status_BOOST.txt")
) | ForEach-Object { Get-Item -LiteralPath $_ }
foreach ($file in $formalFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    Require (-not ($text -match 'ScriptExtender|MCM|TutorialEvent|COS_ChaosIdentity|COS_ChaosStatus')) `
        "创建后同步源夹带了后续系统: $($file.FullName)"
}

$textureBankSourcePath = Join-Path $root 'resource-src\Public\ChaosOriginsStory\Content\UI\[PAK]_ChaosOriginsStory\_merged.lsf.lsx'
$resourceSources = @(Get-ChildItem -LiteralPath (Join-Path $root 'resource-src') -Recurse -File -Filter '*.lsx')
Require ($resourceSources.Count -eq 2 -and $resourceSources.FullName -contains $tagPath -and `
    $resourceSources.FullName -contains $textureBankSourcePath) `
    '资源源目录必须只包含起源标签和技能图标 TextureBank'
[xml]$textureBank = Get-Content -LiteralPath $textureBankSourcePath -Raw -Encoding UTF8
$atlasUuid = [string]([xml](Get-Content -LiteralPath (Join-Path $root "Public\$module\GUI\Icons_ChaosOrigins.lsx") -Raw -Encoding UTF8)).SelectSingleNode('//node[@id="TextureAtlasPath"]/attribute[@id="UUID"]').value
$textureResource = $textureBank.SelectSingleNode('//region[@id="TextureBank"]//node[@id="Resource"]')
Require ($null -ne $textureResource -and `
    [string]$textureResource.SelectSingleNode('./attribute[@id="ID"]').value -eq $atlasUuid -and `
    [string]$textureResource.SelectSingleNode('./attribute[@id="SourceFile"]').value -eq `
        'Public/ChaosOriginsStory/Assets/Textures/Icons/Icons_ChaosOrigins.dds') `
    '技能图集必须有 UUID 和 DDS 路径一致的 TextureBank 注册'

$statusPath = Join-Path $root "Public\$module\Stats\Generated\Data\Status_BOOST.txt"
$statusText = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8
$statusEntries = @([regex]::Matches($statusText, 'new entry "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$expectedStatusEntries = @($expectedOriginToggleMappings | ForEach-Object { $_.Split('|')[1] })
Require ($statusEntries.Count -eq 7 -and -not (Compare-Object $expectedStatusEntries $statusEntries)) `
    '必须且只能定义七个起源身份隐藏状态'
Require ([regex]::Matches($statusText, 'DisableOverhead;DisablePortraitIndicator;IgnoreResting;ApplyToDead').Count -eq 1) `
    '起源身份状态基类必须隐藏头顶和肖像提示并跨休息保留'

Write-Host 'ChaosOriginsStory final native Story source verification: ok'
