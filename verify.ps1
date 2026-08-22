param(
    [string]$ProjectRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$moduleName = 'ChaosOriginsRemastered'
$moduleUuid = '9112dfde-d843-408f-b59b-9c893f5f7d92'
$originUuid = '37914c47-d2f2-433d-9635-3e3040a4663f'
$originTag = '7bb4d001-3c7e-445d-b52b-db0507db38d4'
$displayHandle = 'h92f8d008g9421g40ebgbaeege5d2e79a239c'
$descriptionHandle = 'hc58ffe61g93ccg4b17g9265g676021109983'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$source = Join-Path $ProjectRoot 'source'
$originPath = Join-Path $source "Public\$moduleName\Origins\Origins.lsx"
$metaPath = Join-Path $source "Mods\$moduleName\meta.lsx"
$passivePath = Join-Path $source "Public\$moduleName\Stats\Generated\Data\Passive.txt"
$statusPath = Join-Path $source "Public\$moduleName\Stats\Generated\Data\Status_BOOST.txt"
$tagPath = Join-Path $ProjectRoot "resource-src\Public\$moduleName\Tags\$originTag.lsf.lsx"
$textureBankPath = Join-Path $ProjectRoot "resource-src\Public\$moduleName\Content\UI\[PAK]_$moduleName\_merged.lsf.lsx"
$configPath = Join-Path $source "Mods\$moduleName\ScriptExtender\Config.json"
$bootstrapPath = Join-Path $source "Mods\$moduleName\ScriptExtender\Lua\BootstrapServer.lua"
$packageFilesPath = Join-Path $ProjectRoot 'package-files.json'
$raceCatalogPath = Join-Path $ProjectRoot 'official-data\race-catalog.json'
$raceCatalogGeneratorPath = Join-Path $ProjectRoot 'generate-race-catalog.ps1'
foreach ($path in @($originPath, $metaPath, $passivePath, $statusPath, $tagPath, $textureBankPath, $configPath, $bootstrapPath, $packageFilesPath)) {
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Required minimal source is missing: $path"
}

$originXml = [xml](Get-Content -Raw -LiteralPath $originPath -Encoding UTF8)
$origins = @($originXml.save.region.node.children.node)
Require ($origins.Count -eq 1) 'Minimal build must register exactly one origin'
$origin = $origins[0]
$attributes = @{}
foreach ($attribute in $origin.attribute) { $attributes[$attribute.id] = $attribute }
$required = @{
    AppearanceLocked = 'false'
    AvailableInCharacterCreation = '1'
    BackgroundUUID = '20d865ea-03bd-47bf-97d3-777e1b36b073'
    BodyShape = '0'
    BodyType = '0'
    ClassUUID = '784001e2-c96d-4153-beb6-2adbef5abc92'
    DefaultsTemplate = '782183f9-ceb5-4a96-8ac4-56af0319641d'
    IntroDialogUUID = 'f015fd39-a9f2-6ee5-a77b-a28806ac1b7a'
    LockBody = 'false'
    LockClass = 'false'
    LockRace = 'false'
    Name = 'ChaosRemastered'
    Passives = 'DeathSavingThrows;COR_OriginMarker'
    RaceUUID = '45f4ac10-3c89-4fb2-b37d-f973bb9110c0'
    SubClassUUID = 'd379fdae-b401-4731-8d50-277c73919ae3'
    SubRaceUUID = '30fafb0b-7c8b-4917-bd2a-536233b35d3c'
    UUID = $originUuid
    VoiceTableUUID = '2949c570-0a52-4cfd-8434-50925e18d44b'
}
foreach ($entry in $required.GetEnumerator()) {
    Require ($attributes.ContainsKey($entry.Key) -and $attributes[$entry.Key].value -eq $entry.Value) `
        "Origin has invalid $($entry.Key)"
}
Require ($attributes.DisplayName.handle -eq $displayHandle) 'Origin display-name handle is invalid'
Require ($attributes.Description.handle -eq $descriptionHandle) 'Origin description handle is invalid'
foreach ($forbidden in @('GlobalTemplate', 'Identity', 'IsHenchman', 'ProgressionTableUUID', 'Unique')) {
    Require (-not $attributes.ContainsKey($forbidden)) "Origin must not register risky field $forbidden"
}
$appearanceTags = @($origin.children.node | Where-Object id -eq 'AppearanceTags')
$reallyTags = @($origin.children.node | Where-Object id -eq 'ReallyTags')
Require ($appearanceTags.Count -eq 0) 'Dark-Urge-style origin must not inject a mismatched race appearance tag'
Require ($reallyTags.Count -eq 1 -and $reallyTags[0].attribute.value -eq $originTag) `
    'Origin must use only its new identity tag'

$passive = (Get-Content -Raw -LiteralPath $passivePath -Encoding UTF8).Trim()
$passiveEntries = @([regex]::Matches($passive, 'new entry "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Require (-not (Compare-Object ($passiveEntries | Sort-Object) @(
    'COR_AllSkillMastery', 'COR_BaseProficiencies', 'COR_OriginMarker',
    'COR_BaseStarterSpells',
    'COR_RacialSpells_Level1', 'COR_RacialSpells_Level3', 'COR_RacialSpells_Level5',
    'COR_Origin_Astarion', 'COR_Origin_DarkUrge', 'COR_Origin_Gale',
    'COR_Origin_Karlach', 'COR_Origin_Laezel', 'COR_Origin_Shadowheart', 'COR_Origin_Wyll'
))) 'Passive.txt must contain exactly the marker, base features, three racial-spell passives, and seven origin toggles'
Require ([regex]::IsMatch($passive, 'new entry "COR_OriginMarker"\r?\ntype "PassiveData"\r?\ndata "Properties" "IsHidden"')) `
    'Origin marker must remain a hidden no-effect passive'

$originToggleNames = @('Astarion', 'Gale', 'Laezel', 'Shadowheart', 'Wyll', 'Karlach', 'DarkUrge')
$originToggleBase = [regex]::Match($passive,
    '(?ms)^new entry "COR_Origin_Astarion"\r?\n.*?(?=^new entry |\z)').Value
Require ($originToggleBase.Contains('data "Properties" "IsToggled"') `
    -and -not $originToggleBase.Contains('IsHidden')) `
    'Origin identity toggles must remain visible in the character passive panel'
foreach ($name in $originToggleNames) {
    $status = 'COR_ORIGIN_TAG_' + $name.ToUpperInvariant()
    $block = [regex]::Match($passive,
        '(?ms)^new entry "COR_Origin_' + $name + '"\r?\n.*?(?=^new entry |\z)').Value
    Require ($block -ne '' -and $block.Contains('data "ToggleOnFunctors" "ApplyStatus(' + $status + ',100,-1)"') `
        -and $block.Contains('data "ToggleOffFunctors" "RemoveStatus(' + $status + ')"')) `
        "Origin toggle functors are invalid: $name"
}

$statusText = Get-Content -Raw -LiteralPath $statusPath -Encoding UTF8
$originStatusNames = @('ASTARION', 'GALE', 'LAEZEL', 'SHADOWHEART', 'WYLL', 'KARLACH', 'DARKURGE')
foreach ($entry in $originStatusNames) {
    $block = [regex]::Match($statusText,
        '(?ms)^new entry "COR_ORIGIN_TAG_' + $entry + '"\r?\n.*?(?=^new entry |\z)').Value
    Require ($block -ne '' -and $block.Contains('data "StackId" "COR_ORIGIN_TAG_' + $entry + '"') `
        -and $block.Contains('data "Boosts" ""') -and -not $block.Contains('Tag(REALLY_')) `
        "Origin identity marker status is invalid: $entry"
}
Require (([regex]::Matches($statusText, '^new entry "COR_ORIGIN_TAG_', 'Multiline')).Count -eq 7) `
    'Status_BOOST.txt must contain exactly seven origin identity statuses'
$originStatusBase = [regex]::Match($statusText,
    '(?ms)^new entry "COR_ORIGIN_TAG_ASTARION"\r?\n.*?(?=^new entry |\z)').Value
Require ($originStatusBase.Contains('DisablePortraitIndicator')) `
    'Origin identity marker statuses must stay out of the portrait BUFF bar'

$proficiencyBoosts = 'Proficiency(LightArmor);Proficiency(MediumArmor);Proficiency(HeavyArmor);Proficiency(Shields);Proficiency(SimpleWeapons);Proficiency(MartialWeapons);Proficiency(MusicalInstrument)'
$proficiencyBlock = [regex]::Match($passive,
    '(?s)new entry "COR_BaseProficiencies".*?(?=\r?\n\r?\nnew entry|\z)').Value
Require ($proficiencyBlock -ne '' -and $proficiencyBlock.Contains('data "Properties" "IsHidden"') `
    -and $proficiencyBlock.Contains('data "Boosts" "' + $proficiencyBoosts + '"') `
    -and $proficiencyBlock.Contains('data "DisplayName"') `
    -and $proficiencyBlock.Contains('data "Description"')) `
    'Base proficiency passive has invalid boosts'

$skillBlockMatch = [regex]::Match($passive,
    '(?s)new entry "COR_AllSkillMastery".*?(?=\r?\n\r?\nnew entry|\z)')
Require ($skillBlockMatch.Success) 'All-skill passive is missing'
$skillBlock = $skillBlockMatch.Value
$expectedSkills = @(
    'Acrobatics', 'AnimalHandling', 'Arcana', 'Athletics', 'Deception', 'History',
    'Insight', 'Intimidation', 'Investigation', 'Medicine', 'Nature', 'Perception',
    'Performance', 'Persuasion', 'Religion', 'SleightOfHand', 'Stealth', 'Survival'
) | Sort-Object
$proficientSkills = @([regex]::Matches($skillBlock, 'ProficiencyBonus\(Skill,([A-Za-z]+)\)') |
    ForEach-Object { $_.Groups[1].Value }) | Sort-Object
$expertSkills = @([regex]::Matches($skillBlock, 'ExpertiseBonus\(([A-Za-z]+)\)') |
    ForEach-Object { $_.Groups[1].Value }) | Sort-Object
$fixedSkillBonuses = @([regex]::Matches($skillBlock, '\bSkill\([^)]+\)'))
Require ($proficientSkills.Count -eq 18 -and -not (Compare-Object $proficientSkills $expectedSkills)) `
    'All-skill passive must grant proficiency to exactly 18 unique skills'
Require ($expertSkills.Count -eq 18 -and -not (Compare-Object $expertSkills $expectedSkills)) `
    'All-skill passive must grant expertise to exactly 18 unique skills'
Require ($fixedSkillBonuses.Count -eq 0) `
    'All-skill passive must not grant any fixed skill bonus'

$tagXml = [xml](Get-Content -Raw -LiteralPath $tagPath -Encoding UTF8)
$tag = $tagXml.save.region.node
Require ($tag.id -eq 'Tags') 'Tag source must contain one Tags node'
$tagAttributes = @{}
foreach ($attribute in $tag.attribute) { $tagAttributes[$attribute.id] = $attribute.value }
Require ($tagAttributes.UUID -eq $originTag) 'Origin tag UUID is invalid'
Require ($tagAttributes.Name -eq 'COR_REALLY_CHAOS') 'Origin tag name is invalid'
$categories = @($tag.children.node.children.node | ForEach-Object { $_.attribute.value }) | Sort-Object
Require (-not (Compare-Object $categories @('Code', 'Dialog', 'DialogHidden'))) 'Origin tag categories are invalid'

$metaXml = [xml](Get-Content -Raw -LiteralPath $metaPath -Encoding UTF8)
$moduleInfo = @($metaXml.SelectNodes('//node[@id="ModuleInfo"]'))
Require ($moduleInfo.Count -eq 1) 'meta.lsx must contain one ModuleInfo node'
$moduleAttributes = @{}
foreach ($attribute in $moduleInfo[0].attribute) { $moduleAttributes[$attribute.id] = $attribute.value }
Require ($moduleAttributes.UUID -eq $moduleUuid) 'Module UUID is invalid'
Require ($moduleAttributes.Folder -eq $moduleName) 'Module folder is invalid'
Require ($moduleAttributes.Name -eq 'Chaos Origins Remastered') 'Module name is invalid'
Require ($moduleAttributes.Type -eq 'Add-on') 'Module type is invalid'
$dependencyUuids = @($metaXml.SelectNodes('//node[@id="Dependencies"]//node[@id="ModuleShortDesc"]/attribute[@id="UUID"]') | ForEach-Object value)
foreach ($dependencyUuid in @(
    '28ac9ce2-2aba-8cda-b3b5-6e922f71b6b8',
    '26922ba9-6018-5252-075d-7ff2ba6ed879',
    '755a8a72-407f-4f0d-9a33-274ac0f0b53d'
)) {
    Require ($dependencyUuids -contains $dependencyUuid) "Required module dependency is missing: $dependencyUuid"
}

$config = Get-Content -Raw -LiteralPath $configPath -Encoding UTF8 | ConvertFrom-Json
Require ($config.ModTable -eq $moduleName) 'Script Extender ModTable is invalid'
Require ($config.RequiredVersion -eq 20) 'Script Extender required version is invalid'
$bootstrap = Get-Content -Raw -LiteralPath $bootstrapPath -Encoding UTF8
foreach ($value in @($moduleUuid, $originUuid)) {
    Require ($bootstrap.Contains($value)) "Bootstrap identity is missing: $value"
}
foreach ($token in @('Ext.RegisterConsoleCommand("cor_power"',
    'Ext.RegisterConsoleCommand("cor_allin"',
    'saved.ChaosPower = saved.ChaosPower + amount',
    'Osi.ApplyStatus(character, "COR_CHAOS_RESTORE_ALLIN", 0.1, 100, character)',
    'Usage: !cor_power <positive integer>', 'Usage: !cor_allin')) {
    Require ($bootstrap.Contains($token)) "Test console command is missing: $token"
}

$luaRoot = Split-Path $bootstrapPath -Parent
$expectedLuaFiles = @(
    'BaseFeatures.lua', 'BootstrapClient.lua', 'BootstrapServer.lua', 'ChaosCharacter.lua',
    'ChaosDuality.lua', 'ChaosMechanics.lua', 'ChaosNativeRoll.lua', 'ChaosState.lua',
    'DebugLog.lua', 'GrantLedger.lua', 'MechanicsFeatures.lua', 'McmProtocol.lua', 'OriginFeatures.lua',
    'OriginStoryRewards.lua',
    'RaceCatalog.lua', 'RaceFeatures.lua'
) | Sort-Object
$packageFiles = Get-Content -Raw -LiteralPath $packageFilesPath -Encoding UTF8 | ConvertFrom-Json
Require ($packageFiles.schema -eq 1) 'Unsupported package-files schema'
$declaredPackageFiles = @($packageFiles.files | ForEach-Object { [string]$_ })
Require ($declaredPackageFiles.Count -eq 34 -and ($declaredPackageFiles | Select-Object -Unique).Count -eq 34) `
    'package-files.json must contain exactly 34 unique paths'
Require ($declaredPackageFiles -contains 'Public/ChaosOriginsRemastered/Content/UI/[PAK]_ChaosOriginsRemastered/_merged.lsf') `
    'Package manifest omits the custom icon TextureBank resource'
foreach ($luaName in $expectedLuaFiles) {
    Require ($declaredPackageFiles -contains "Mods/ChaosOriginsRemastered/ScriptExtender/Lua/$luaName") `
        "Package manifest omits Lua module: $luaName"
}
$actualLuaFiles = @(Get-ChildItem -LiteralPath $luaRoot -File -Filter '*.lua' | ForEach-Object Name) | Sort-Object
$luaInventoryDifference = @(Compare-Object -ReferenceObject $expectedLuaFiles -DifferenceObject $actualLuaFiles)
$luaInventoryDetail = @($luaInventoryDifference | ForEach-Object {
    if ($_.SideIndicator -eq '<=') { "missing $($_.InputObject)" } else { "unexpected $($_.InputObject)" }
}) -join '; '
Require ($luaInventoryDifference.Count -eq 0) "Server Lua module list is invalid: $luaInventoryDetail"
foreach ($luaFile in Get-ChildItem -LiteralPath $luaRoot -File -Filter '*.lua') {
    $luaContent = Get-Content -Raw -LiteralPath $luaFile.FullName -Encoding UTF8
    Require ($luaContent -match '--[^\r\n]*[一-龥]') "Lua module lacks a Chinese comment: $($luaFile.Name)"
}

$baseFeatures = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'BaseFeatures.lua') -Encoding UTF8
foreach ($passiveId in @('COR_BaseProficiencies', 'COR_AllSkillMastery')) {
    Require ($baseFeatures.Contains('"' + $passiveId + '"')) "Base feature passive is missing: $passiveId"
}
Require ($baseFeatures.Contains('M.StarterSpellPassive = "COR_BaseStarterSpells"')) `
    'Base starter-spell passive is missing'
$starterSpells = @(
    'Target_BoomingBlade_ClassSpell', 'Target_Guidance', 'Target_MageHand',
    'Target_MinorIllusion', 'Shout_FeatherFall', 'Target_Jump', 'Shout_DisguiseSelf'
)
foreach ($spellId in $starterSpells) {
    Require ($baseFeatures.Contains('"' + $spellId + '"')) "Starter spell is missing: $spellId"
}
Require (([regex]::Matches($baseFeatures, '"(?:Target|Shout)_[A-Za-z0-9_]+"')).Count -eq 7) `
    'BaseFeatures.lua must declare exactly seven spells'

$stateLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'ChaosState.lua') -Encoding UTF8
foreach ($token in @('SCHEMA_VERSION = 7', 'state.SchemaVersion == 6',
    'OriginStoryRewards', 'Claimed', 'Consumed', 'OriginStoryGranted',
    'Statuses', 'TestLevel12Experience = false')) {
    Require ($stateLua.Contains($token)) "Story reward state contract is missing: $token"
}
Require ($stateLua.Contains('OriginStoryRewards = { Claimed = {}, Consumed = {} }')) `
    'Story reward state contract is missing the OriginStoryRewards table shape'
Require ($stateLua.Contains('OriginStoryGranted = { Passives = {}, Spells = {}, Statuses = {} }')) `
    'Story reward state contract is missing the OriginStoryGranted table shape'
foreach ($token in @('state.SchemaVersion == 1', 'state.SchemaVersion == 2',
    'state.SchemaVersion == 3', 'state.SchemaVersion == 4', 'state.SchemaVersion == 5', 'NativeRaceTags',
    'RaceGranted', 'RewardItems', 'StarterRewardsVersion', 'Granted', 'Persistent = true',
    'OriginGranted', 'OriginIdentities', 'MechanicGranted', 'PendingDuality',
    'owned == "adding"', 'owned == "removing"')) {
    Require ($stateLua.Contains($token)) "Strict state implementation is missing: $token"
}
Require ($stateLua.Contains(
    'assertOnlyKeys(record.OriginIdentities, ORIGIN_IDENTITY_FIELDS, "origin identities")') `
    -and -not $stateLua.Contains(
        'assertOnlyKeys(record.OriginIdentities, expectedIdentities, "origin identities")')) `
    'Origin identity validation must use a true-valued field whitelist, not false defaults'
Require ($stateLua.Contains('for _, key in ipairs(ORIGIN_IDENTITY_KEYS) do result[key] = true end')) `
    'New Chaos characters must enable all seven origin identities by default'
$originFeaturesLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'OriginFeatures.lua') -Encoding UTF8
foreach ($token in @('definition.Tag', 'record.OriginGranted.Tags', 'GrantLedger.EnsureTag',
    'GrantLedger.RemoveTag', 'record.OriginIdentities[definition.Name]', 'function M.SetEnabled')) {
    Require ($originFeaturesLua.Contains($token)) "Origin identity tag ownership is missing: $token"
}
Require (-not $originFeaturesLua.Contains('Osi.GetLevel')) 'OriginFeatures.lua must not grant abilities by level'
Require (-not [regex]::IsMatch($originFeaturesLua, '\{\s*"[^"]+"\s*,\s*\d+\s*\}')) `
    'OriginFeatures.lua must not contain level-gated ability tuples'
$originDefinitionsMatch = [regex]::Match($originFeaturesLua,
    '(?ms)^M\.Definitions\s*=\s*\{(?<definitions>.*?)^}\r?\n\r?\n(?=local byStatus)')
Require ($originDefinitionsMatch.Success) 'OriginFeatures.lua definitions block is missing'
$originDefinitionText = $originDefinitionsMatch.Groups['definitions'].Value -replace '(?m)--[^\r\n]*', ''
$originDefinitionLiterals = @([regex]::Matches($originDefinitionText, '"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
foreach ($token in @('Target_VampireBite_Astarion', 'BladeOfFrontiers',
    'ORI_Karlach_SweatImmune', 'ORI_Karlach_Rage_Flames')) {
    Require ($originDefinitionLiterals -contains $token) "OriginFeatures.lua immediate ability is missing: $token"
}
$forbiddenOldRewards = @('UNI_DarkUrge_Stealth_Expertise_Passive',
    'UNI_DarkUrge_Bleeding_Dagger_Passive', 'Karlach_Infernal_Fury')
foreach ($token in $forbiddenOldRewards) {
    Require (-not ($originDefinitionLiterals -contains $token)) "OriginFeatures.lua contains forbidden old reward: $token"
}
$originStoryRewardsLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'OriginStoryRewards.lua') -Encoding UTF8
$bootstrapCode = $bootstrap -replace '(?s)--\[\[.*?\]\]', '' -replace '(?m)--[^\r\n]*', ''
foreach ($token in @('OriginStoryRewards.Sync', 'OriginStoryRewards.ResetRuntime',
    'OriginStoryRewards.IsTrackedFlag', 'OriginStoryRewards.HandleCastedSpell',
    'SetTestExperience', 'TestLevel12Experience', 'scheduleLevel12TestExperience')) {
    Require ($bootstrapCode.Contains($token)) "Story reward server wiring is missing: $token"
}
$syncCharacterBlock = [regex]::Match($bootstrapCode,
    '(?ms)^local\s+function\s+syncCharacter\s*\([^)]*\).*?(?=^local\s+function\s+queueCharacter)').Value
Require ($syncCharacterBlock -ne '') 'Story reward sync function is missing'
$originSync = $syncCharacterBlock.IndexOf('OriginFeatures.Sync')
$storySync = $syncCharacterBlock.IndexOf('OriginStoryRewards.Sync')
$mechanicsSync = $syncCharacterBlock.IndexOf('ChaosMechanics.Sync')
Require ($originSync -ge 0 -and $originSync -lt $storySync -and $storySync -lt $mechanicsSync) `
    'Story reward sync must run after origin sync and before mechanic sync'
$sessionLoadedBlock = [regex]::Match($bootstrapCode,
    '(?ms)^Ext\.Events\.SessionLoaded:Subscribe\(function\(\).*?(?=^local\s+function\s+handleOriginStatus)').Value
Require ($sessionLoadedBlock.Contains('OriginStoryRewards.ResetRuntime')) `
    'Story reward runtime reset is missing from SessionLoaded'
foreach ($eventName in @('FlagSet', 'FlagCleared')) {
    $listener = [regex]::Match($bootstrapCode,
        '(?ms)Ext\.Osiris\.RegisterListener\s*\(\s*"' + $eventName + '"\s*,\s*3\s*,.*?function\s*\([^)]*\)(?<body>.*?)\bend\s*\)')
    Require ($listener.Success -and [regex]::IsMatch($listener.Groups['body'].Value,
        '(?s)if\s+OriginStoryRewards\.IsTrackedFlag\s*\(\s*flag\s*\)\s+then\s+scheduleAllPlayers\s*\(\s*200\s*\)')) `
        "Story reward listener behavior is missing: $eventName/3"
}
$castedSpellListener = [regex]::Match($bootstrapCode,
    '(?ms)Ext\.Osiris\.RegisterListener\s*\(\s*"CastedSpell"\s*,\s*5\s*,.*?function\s*\([^)]*\)(?<body>.*?)\bend\s*\)')
$castedSpellBody = $castedSpellListener.Groups['body'].Value
Require ($castedSpellListener.Success -and $castedSpellBody.Contains('ChaosCharacter.IsEligible(caster)') `
    -and $castedSpellBody.Contains('State.GetCharacter(caster)') `
    -and [regex]::IsMatch($castedSpellBody,
        '(?s)if\s+OriginStoryRewards\.HandleCastedSpell\s*\(\s*caster\s*,\s*spell\s*,\s*record\s*\)\s+then\s+scheduleCharacter\s*\(\s*caster\s*,\s*200\s*\)')) `
    'Story reward listener behavior is missing: CastedSpell/5'
$grantLevel12TestExperienceBlock = [regex]::Match($bootstrapCode,
    '(?ms)^local\s+function\s+grantLevel12TestExperience\s*\(\s*character\s*,\s*record\s*\).*?(?=^local\s+function\s+scheduleLevel12TestExperience)').Value
Require ($grantLevel12TestExperienceBlock -ne '' -and [regex]::IsMatch($grantLevel12TestExperienceBlock,
    '(?ms)^local\s+function\s+grantLevel12TestExperience\s*\(\s*character\s*,\s*record\s*\)\s*if\s+not\s+record\.TestLevel12Experience\s+then\s+return\s+false\s+end')) `
    'Level-12 test experience must be explicitly default-off'
Require (-not [regex]::IsMatch($bootstrapCode, 'grantLevel12TestExperience\s*\(\s*\)')) `
    'Level-12 test experience must not use a zero-argument grant call'
$scheduleLevel12TestExperienceBlock = [regex]::Match($bootstrapCode,
    '(?ms)^local\s+function\s+scheduleLevel12TestExperience\s*\([^)]*\).*?(?=^local\s+function\s+copyBooleanMap)').Value
$schedulerPassesRecord = [regex]::IsMatch($scheduleLevel12TestExperienceBlock,
    '(?s)grantLevel12TestExperience\s*\(\s*character\s*,\s*State\.GetCharacter\s*\(\s*character\s*\)\s*\)') `
    -or [regex]::IsMatch($scheduleLevel12TestExperienceBlock,
        '(?s)local\s+(?<record>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*State\.GetCharacter\s*\(\s*character\s*\).*?grantLevel12TestExperience\s*\(\s*character\s*,\s*\k<record>\s*\)')
Require ($scheduleLevel12TestExperienceBlock.Contains('Osi.GetHostCharacter()') `
    -and $scheduleLevel12TestExperienceBlock.Contains('ChaosCharacter.CanonicalGuid') `
    -and $scheduleLevel12TestExperienceBlock.Contains('ChaosCharacter.IsEligible(character)') `
    -and $scheduleLevel12TestExperienceBlock.Contains('State.GetCharacter(character)') `
    -and $schedulerPassesRecord) 'Level-12 test experience scheduler is not host-safe'
$hostSnapshotBlock = [regex]::Match($bootstrapCode,
    '(?ms)^local\s+function\s+hostSnapshot\s*\(\).*?(?=^local\s+function\s+mcmReply)').Value
Require ($hostSnapshotBlock.Contains('TestLevel12Experience = saved.TestLevel12Experience')) `
    'MCM server snapshot omits test-experience state'
$setTestExperienceBlock = [regex]::Match($bootstrapCode,
    '(?ms)^\s*(?:elseif|if)\s+request\.Action\s*==\s*"SetTestExperience"\s+then(?<body>.*?)(?=^\s*(?:elseif|else)\b)').Value
$setTestExperienceEnableBlock = [regex]::Match($setTestExperienceBlock,
    '(?ms)\bif\s+request\.Value\s+then(?<body>.*?)(?=^\s*end\b)').Groups['body'].Value
Require ($setTestExperienceBlock -ne '' -and [regex]::IsMatch($setTestExperienceBlock,
    'assert\s*\(\s*type\s*\(\s*request\.Value\s*\)\s*==\s*"boolean"') `
    -and $setTestExperienceBlock.Contains('saved.TestLevel12Experience = request.Value') `
    -and $setTestExperienceBlock.Contains('State.MarkDirty') `
    -and $setTestExperienceEnableBlock.Contains('grantLevel12TestExperience') `
    -and -not [regex]::IsMatch($setTestExperienceBlock,
        'Osi\.(?:Remove|Subtract)[A-Za-z]*Experience|Osi\.\w*Experience\s*\([^)]*,\s*-')) `
    'MCM SetTestExperience server behavior is invalid'
$originStoryRulesMatch = [regex]::Match($originStoryRewardsLua,
    '(?ms)^M\.Rules\s*=\s*\{(?<rules>.*?)^}\r?\n\r?\n(?=^local\s+trackedFlags\s*=)')
Require ($originStoryRulesMatch.Success) 'Origin story reward rules block is missing'
Require ($originStoryRewardsLua.Contains('local FULL_CEREMORPH = "3797bfc4-8004-4a19-9578-61ce0714cc0b"')) `
    'Origin story reward raw UUID constant is missing'
$originStoryRewardsText = $originStoryRewardsLua -replace '(?m)--[^\r\n]*', ''
$originStoryRewardLiterals = @([regex]::Matches($originStoryRewardsText, '"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
foreach ($token in @(
    'ORI_Astarion_State_BecameVampireLord_c446ce94-efd8-45d5-b407-284177b6b57e',
    'LOW_Astarion_VampireAscendant', 'Shout_EPI_Astarion_TurnIntoBat',
    'ORI_Gale_Event_BombDisarmed_3d014e79-5595-9365-87bb-5cbb1f87fe5c',
    'Target_END_Gale_ActivateNethereseOrb',
    'ORI_Gale_State_AbsorbedTWNBossPower_7d08986a-5410-ccdf-fe70-aaec379a1962',
    'ORI_Gale_ShadowSpellSlots',
    'ORI_Gale_State_CraftedDarkLantern_3ddebb12-8c9f-47b4-8b6a-bb8eeac51a9b',
    'Target_ORI_Gale_ShadowSummon', 'ORI_Gale_State_IsGod_ec94f9a4-b032-ce25-f4eb-ecf4ed37d65d',
    'EPI_GALEGOD', 'EPI_GALEGOD_MINDFLAYER', '3797bfc4-8004-4a19-9578-61ce0714cc0b',
    'CAMP_MizorasJudgement_Event_Reward_eb10f6f8-cf1a-a2b2-4421-63b0fbeb7a23',
    'Shout_ORI_Wyll_FireShield_Warm',
    'COL_MizorasRescue_Event_Reward_0e2f2a09-604c-2b9d-b8c0-db2baa1e6ac8',
    'Target_ORI_Wyll_SummonCambion', 'c774d764-4a17-48dc-b470-32ace9ce447d',
    'GLO_ForgingOfTheHeart_State_KarlachUpgraded_a818e2f5-9e0c-4ab3-8c1e-00765d3b892f',
    'ORI_KARLACH_FIRSTUPGRADE',
    'GLO_ForgingOfTheHeart_State_KarlachSecondUpgrade_f6dc0de4-1089-43c0-b392-306a9a44387c',
    'ORI_KARLACH_SECONDUPGRADE',
    'ORI_DarkUrge_State_GivenSlayerForm_14aec5bc-1013-4845-96ca-20722c5219e3',
    'Shout_DarkUrge_Slayer',
    'ORI_DarkUrge_State_BhaalAccepted_904c45e0-bb06-40ed-b5d7-4f1c851b9d86',
    'Target_LOW_DarkUrge_PowerWordKill'
)) {
    Require ($originStoryRewardLiterals -contains $token) "Origin story reward catalog is missing: $token"
}
foreach ($token in $forbiddenOldRewards) {
    Require (-not ($originStoryRewardLiterals -contains $token)) "Origin story reward catalog contains forbidden old reward: $token"
}
foreach ($token in @('ORI_KARLACH_FIRSTUPGRADE', 'ORI_KARLACH_SECONDUPGRADE')) {
    $quotedStageStatus = '"' + [regex]::Escape($token) + '"'
    Require (([regex]::Matches($originStoryRulesMatch.Groups['rules'].Value,
        $quotedStageStatus)).Count -eq 1 `
        -and ([regex]::Matches($originStoryRewardsText, $quotedStageStatus)).Count -eq 1) `
        "Karlach stage status must only be declared once in M.Rules: $token"
}
Require ([regex]::IsMatch($originStoryRewardsLua,
    '(?s)local selectedStageRule = nil.*?if rule\.Mode == "Stage" then\s+if selectedStageRule == nil or rule\.Stage > selectedStageRule\.Stage then\s+selectedStageRule = rule\s+end.*?if selectedStageRule ~= nil then\s+collect\(statuses, selectedStageRule\.Statuses\)\s+end')) `
    'Origin story stage selection must collect statuses from the highest matched rule'
foreach ($token in @(
    'local claimableKeys = {}', 'local oneShotKeys = {}',
    'claimableKeys[rule.Key] = true', 'oneShotKeys[rule.Key] = true',
    'local function validateSavedRewards(record)', 'claimableKeys[key] == true',
    'oneShotKeys[key] == true', 'rewards.Claimed[key] == true'
)) {
    Require ($originStoryRewardsLua.Contains($token)) "Origin story saved-key validation is missing: $token"
}
Require ([regex]::IsMatch($originStoryRewardsLua,
    '(?s)if rule\.Mode == "Permanent" or rule\.Mode == "OneShot" then\s+claimableKeys\[rule\.Key\] = true\s+end')) `
    'Only permanent and one-shot rules may populate claimable origin story keys'
Require ([regex]::IsMatch($originStoryRewardsLua,
    '(?s)if rule\.Mode == "OneShot" then oneShotKeys\[rule\.Key\] = true end')) `
    'Only one-shot rules may populate consumable origin story keys'
Require (([regex]::Matches($originStoryRewardsLua,
    '(?m)^    validateSavedRewards\(record\)$')).Count -eq 2) `
    'Saved origin story reward keys must be validated in sync and cast handling'
$grantLedgerLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'GrantLedger.lua') -Encoding UTF8
foreach ($token in @('function M.RemoveTag', 'Osi.SetTag', 'Osi.ClearTag')) {
    Require ($grantLedgerLua.Contains($token)) "Grant ledger tag support is missing: $token"
}
foreach ($token in @('function M.EnsureStatus', 'function M.RemoveStatus',
    'Osi.HasActiveStatus', 'Osi.ApplyStatus', 'Osi.RemoveStatus')) {
    Require ($grantLedgerLua.Contains($token)) "Grant ledger status support is missing: $token"
}
foreach ($token in @('ReleasedLedgers = {}', 'transferPendingOwnership',
    'operation.ReleasedLedgers[operation.Ledger] = true', 'ledger[operation.StatId] = "adding"',
    'operation.Ledger[operation.StatId] == "removing"',
    'operation.ReleasedLedgers[ledger] == true', 'expected == 0 and ledger[statId] == "removing"',
    'for releasedLedger in pairs(operation.ReleasedLedgers) do',
    'releasedLedger[operation.StatId] = nil',
    'operation.Ledger[operation.StatId] = operation.Desired == 1 and true or nil')) {
    Require ($grantLedgerLua.Contains($token)) "Pending grant ownership transfer contract is missing: $token"
}
Require ([regex]::IsMatch($grantLedgerLua,
    '(?s)if operation\.Desired == 0 and expected == 1 then\s+transferPendingOwnership\(operation, ledger\)')) `
    'Pending grant ownership transfer must only promote a pending removal to a new ensure'
Require ([regex]::IsMatch($grantLedgerLua,
    '(?s)if operation\.Ledger == ledger then.*?if operation\.ReleasedLedgers\[ledger\] == true then.*?assert\(expected == 0')) `
    'Pending grant ownership transfer must distinguish current and released ledger calls'
$characterLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'ChaosCharacter.lua') -Encoding UTF8
foreach ($token in @('Osi.IsPlayer', 'Osi.DB_Players', $originTag, 'COR_OriginMarker')) {
    Require ($characterLua.Contains($token)) "Chaos character eligibility is missing: $token"
}
$ledgerLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'GrantLedger.lua') -Encoding UTF8
foreach ($token in @('Osi.HasPassive', 'Osi.AddPassive', 'Osi.RemovePassive', 'Osi.HasSpell',
    'Osi.AddSpell', 'Osi.RemoveSpell', 'Osi.IsTagged', 'Osi.SetTag', 'includeContainerSpells',
    'spellFamilyMatches', 'State.MarkDirty')) {
    Require ($ledgerLua.Contains($token)) "Grant ledger behavior is missing: $token"
}
foreach ($token in @('VERIFY_TIMEOUT_MS = 2000', 'scheduleVerification', 'GrantLedger.ResetRuntime',
    'sessionGeneration', 'READY_TIMEOUT_MS = 2000', 'Ext.Timer.MonotonicTime()',
    'NotBefore = notBefore', 'previous ~= nil and previous.ReadyElapsed or 0')) {
    Require (($ledgerLua + $bootstrap).Contains($token)) "Asynchronous grant verification is missing: $token"
}
foreach ($token in @('LEVEL_12_TOTAL_EXPERIENCE = 100000', 'Osi.AddExplorationExperience')) {
    Require ($bootstrap.Contains($token)) "Level-12 test experience behavior is missing: $token"
}
$mechanicsLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'ChaosMechanics.lua') -Encoding UTF8
$dualityLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'ChaosDuality.lua') -Encoding UTF8
foreach ($token in @(
    'Ext.Events.BeforeDealDamage', 'Ext.Events.DealtDamage', 'KilledBy', 'AttackedBy', 'LeftCombat',
    'Shout_COR_ChaosGenesis', 'COR_CHAOS_ALLIN_TOGGLE', 'WoundConsumedThisRound',
    'LOST_CHANCES = { 5, 10, 15, 25, 35, 50, 65, 80, 90, 100 }',
    'Duality.ResetRuntime()', 'echoPending = {}', 'processedKills = {}',
    'woundInitialized = {}', 'local function handleWoundDamage(event)',
    'Ext.Events.DealtDamage:Subscribe(function(event)', 'event.Hit.InflicterOwner',
    'GrantLedger.RemovePassive(character, saved, "COR_ChaosGenesisCharge"',
    'GrantLedger.EnsurePassive(character, saved, "COR_ChaosGenesisCharge"'
)) {
    Require ($mechanicsLua.Contains($token)) "Chaos mechanic runtime is missing: $token"
}
foreach ($token in @('function M.CaptureBeforeDamage', 'event.Hit.InflicterOwner', 'uuid(event.Target)',
    'applyingTargets[target]', 'function M.ResetRuntime()', 'function M.IsApplying',
    'source = assert(uuid(source)', 'character = assert(uuid(character)',
    'local function writeHitDamage(hit, damages)', 'hit.TotalDamageDone = total(damages)',
    'writeHitDamage(event.Hit, expanded)', 'writeHitDamage(event.Hit, fixed)')) {
    Require ($dualityLua.Contains($token)) "Correlated Duality runtime is missing: $token"
}
Require (-not $dualityLua.Contains('table.remove(captured, 1)')) `
    'Duality must not use the legacy global FIFO capture'
Require (-not $dualityLua.Contains('table.remove(queue, 1)')) `
    'Duality must correlate BeforeDealDamage and DealtDamage without a global FIFO'
Require (-not $mechanicsLua.Contains('QRY_IgnoreDamageSource')) `
    'Attack and wound wheels must not suppress valid AttackedBy events through story filters'
foreach ($luaFile in Get-ChildItem -LiteralPath $luaRoot -File -Filter '*.lua') {
    $luaContent = Get-Content -Raw -LiteralPath $luaFile.FullName -Encoding UTF8
    Require (-not $luaContent.Contains('LOC_')) "Lua contains a legacy LOC_ identifier: $($luaFile.Name)"
}
Require (-not $bootstrap.Contains('StarterRewards')) `
    'Bootstrap must not load the removed Digital Deluxe reward module'
foreach ($token in @('RaceFeatures.Sync', 'RaceFeatures.IsReady', 'RespecCompleted', 'RespecCancelled')) {
    Require ($bootstrap.Contains($token)) "Racial feature synchronization is missing: $token"
}
Require ($bootstrap.IndexOf('ChaosCharacter.IsEligible(character)') -lt
    $bootstrap.IndexOf('RaceFeatures.IsReady(character)')) `
    'Scheduled synchronization must reject ineligible objects before readiness polling'

Require (Test-Path -LiteralPath $raceCatalogPath -PathType Leaf) `
    "Audited race catalog is missing: $raceCatalogPath"
Require (Test-Path -LiteralPath $raceCatalogGeneratorPath -PathType Leaf) `
    "Race-catalog generator is missing: $raceCatalogGeneratorPath"
$generatedCatalogCheck = Join-Path $ProjectRoot 'work\generated-race-catalog-check.lua'
& $raceCatalogGeneratorPath -CatalogPath $raceCatalogPath -OutputPath $generatedCatalogCheck
$raceCatalogLuaPath = Join-Path $luaRoot 'RaceCatalog.lua'
$generatedCatalogText = (Get-Content -Raw -LiteralPath $generatedCatalogCheck -Encoding UTF8) -replace '\r\n', "`n"
$raceCatalogText = (Get-Content -Raw -LiteralPath $raceCatalogLuaPath -Encoding UTF8) -replace '\r\n', "`n"
Require ([string]::Equals($generatedCatalogText, $raceCatalogText, [StringComparison]::Ordinal)) `
    'RaceCatalog.lua is stale; regenerate it from official-data/race-catalog.json'
$raceCatalogLua = Get-Content -Raw -LiteralPath $raceCatalogLuaPath -Encoding UTF8
foreach ($token in @('CandidateSpellPolicy = "grant_all"', 'RaceCount = 39', 'TagCount = 32',
    'PassiveCount = 20', 'SpellCount = 29', 'FeatureLevels = { 1, 3, 5 }',
    'COR_RacialSpells_Level1', 'COR_RacialSpells_Level3', 'COR_RacialSpells_Level5')) {
    Require ($raceCatalogLua.Contains($token)) "Audited race-catalog invariant is missing: $token"
}
foreach ($forbidden in @('HumanVersatility', 'FearOfWolves_Shadowheart',
    'Dragonborn_Resistance_Acid', 'Dragonborn_Resistance_Cold',
    'Dragonborn_Resistance_Fire', 'Dragonborn_Resistance_Lightning',
    'Dragonborn_Resistance_Poison', 'Zone_BreathWeapon_')) {
    Require (-not $raceCatalogLua.Contains('"' + $forbidden)) `
        "Excluded racial feature remains in generated catalog: $forbidden"
}

$raceCatalog = Get-Content -Raw -LiteralPath $raceCatalogPath -Encoding UTF8 | ConvertFrom-Json
$officialCatalogSource = Join-Path $ProjectRoot 'work\official-validation\catalog-source'
Require (Test-Path -LiteralPath $officialCatalogSource -PathType Container) `
    "Extracted official race-catalog source is missing: $officialCatalogSource"
foreach ($sourceRecord in $raceCatalog.sources) {
    $officialPath = Join-Path $officialCatalogSource ([string]$sourceRecord.path)
    Require (Test-Path -LiteralPath $officialPath -PathType Leaf) `
        "Official race-catalog source file is missing: $($sourceRecord.path)"
    Require ((Get-FileHash -LiteralPath $officialPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq
        ([string]$sourceRecord.sha256).ToLowerInvariant()) `
        "Official race-catalog source hash changed: $($sourceRecord.path)"
}

$officialSharedStats = Join-Path $ProjectRoot 'work\official-validation\Shared'
$officialGustavXStats = Join-Path $ProjectRoot 'work\official-validation\GustavX'
Require (Test-Path -LiteralPath $officialSharedStats -PathType Container) `
    "Extracted official Shared stats are missing: $officialSharedStats"
Require (Test-Path -LiteralPath $officialGustavXStats -PathType Container) `
    "Extracted official GustavX stats are missing: $officialGustavXStats"
$progressionsByUuid = @{}
foreach ($progression in $raceCatalog.progressions) {
    $progressionsByUuid[[string]$progression.uuid] = $progression
}
Require ($progressionsByUuid.Count -eq 75) `
    'Race progressions must contain exactly 75 UUIDs after SharedDev override'
$racialPassives = @($progressionsByUuid.Values.passives_added | Sort-Object -Unique |
    Where-Object { $_ -and $_ -notin @('Darkvision', 'HumanVersatility', 'FearOfWolves_Shadowheart') `
        -and $_ -notmatch '^Dragonborn_Resistance_' })
$racialSpells = @((@($progressionsByUuid.Values.spells_added) +
    @($progressionsByUuid.Values.spells_selected)) | Sort-Object -Unique |
    Where-Object { $_ -and $_ -notmatch '^Zone_BreathWeapon_' })
Require ($racialPassives.Count -eq 20) 'Audited racial passive count changed'
Require ($racialSpells.Count -eq 29) 'Audited racial spell count changed'
$unlockSpellIds = @([regex]::Matches($passive, 'UnlockSpell\(([^,\)]+)') |
    ForEach-Object { $_.Groups[1].Value })
$baseOnlyStarterSpells = @(
    'Target_BoomingBlade_ClassSpell', 'Target_Guidance', 'Shout_FeatherFall',
    'Target_Jump', 'Shout_DisguiseSelf'
)
$expectedUnlockIds = @(($racialSpells + $baseOnlyStarterSpells) | Sort-Object -Unique)
Require ($unlockSpellIds.Count -eq 34 -and ($unlockSpellIds | Select-Object -Unique).Count -eq 34 `
    -and -not (Compare-Object ($unlockSpellIds | Sort-Object) $expectedUnlockIds)) `
    'Hidden passives must unlock exactly 29 racial spells and five additional starter spells'
$actualUnlockBoosts = @([regex]::Matches($passive, 'UnlockSpell\([^\)]+\)') |
    ForEach-Object { $_.Value } | Sort-Object)
$expectedUnlockBoosts = @((@($raceCatalog.racialSpellUnlocks |
    ForEach-Object { [string]$_.boost }) + @(
        'UnlockSpell(Target_BoomingBlade_ClassSpell)',
        'UnlockSpell(Target_Guidance)',
        'UnlockSpell(Shout_FeatherFall)',
        'UnlockSpell(Target_Jump)',
        'UnlockSpell(Shout_DisguiseSelf,AddChildren)'
    )) | Sort-Object)
Require (-not (Compare-Object $actualUnlockBoosts $expectedUnlockBoosts)) `
    'Passive.txt UnlockSpell metadata differs from the audited racial and starter catalogs'
$raceFeaturesLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'RaceFeatures.lua') -Encoding UTF8
foreach ($token in @('optionalRaceGuid', 'Catalog.RacialSpellPassives',
    '官方 UnlockSpell 语义')) {
    Require ($raceFeaturesLua.Contains($token)) "Racial runtime behavior is missing: $token"
}
$raceSyncBlock = [regex]::Match(
    $raceFeaturesLua,
    '(?ms)^function M\.Sync\(character, record\)(.*?)^end\r?\n\r?\nreturn M'
).Groups[1].Value
Require ($raceSyncBlock -ne '') 'RaceFeatures.Sync could not be isolated for policy verification'
Require ($raceSyncBlock.Contains(
    'desiredPassives[Catalog.RacialSpellPassives[unlockLevel]] = true'
)) 'RaceFeatures.Sync no longer grants racial spell unlock passives'
Require (-not $raceSyncBlock.Contains('features.Passives')) `
    'RaceFeatures.Sync still grants audited racial passives'
Require (-not $raceFeaturesLua.Contains('.ResourceUUID')) `
    'CharacterCreationStats race fields are GUID values, not static resource objects'
Require (-not $raceFeaturesLua.Contains('GrantLedger.EnsureSpell')) `
    'Racial spells must use UnlockSpell passives so casting ability metadata is retained'
foreach ($boost in @(
    'UnlockSpell(Projectile_FireBolt,,,,Intelligence)',
    'UnlockSpell(Shout_AstralKnowledge,AddChildren)',
    'UnlockSpell(Target_DancingLights,,,,Charisma)',
    'UnlockSpell(Target_MageHand,,,,Charisma)',
    'UnlockSpell(Shout_SpeakWithAnimals_ForestGnome,Singular,None,UntilRest,Intelligence)',
    'UnlockSpell(Target_FaerieFire_DrowMagic,Singular,None,UntilRest,Charisma)',
    'UnlockSpell(Target_Jump_Githyanki,Singular,None,UntilRest,Intelligence)',
    'UnlockSpell(Target_Smite_Branding_ZarielTiefling_Container,AddChildren,None,UntilRest,Charisma)'
)) {
    Require ($passive.Contains($boost)) "Racial UnlockSpell metadata is missing: $boost"
}
$officialStatFiles = @(Get-ChildItem -LiteralPath $officialSharedStats -Recurse -File -Filter '*.txt')
foreach ($passiveId in $racialPassives) {
    $hit = $officialStatFiles | Select-String -SimpleMatch "new entry `"$passiveId`"" |
        Select-Object -First 1
    Require ($null -ne $hit) "Official racial passive stat is missing: $passiveId"
}
foreach ($spellId in $racialSpells) {
    $hit = $officialStatFiles | Select-String -SimpleMatch "new entry `"$spellId`"" |
        Select-Object -First 1
    Require ($null -ne $hit) "Official racial spell stat is missing: $spellId"
}
$astralFileHit = $officialStatFiles |
    Select-String -SimpleMatch 'new entry "Shout_AstralKnowledge"' | Select-Object -First 1
Require ($null -ne $astralFileHit) 'Official Astral Knowledge definition is missing'
$astralFile = Get-Content -Raw -LiteralPath $astralFileHit.Path -Encoding UTF8
$astralBlock = [regex]::Match($astralFile,
    '(?ms)^new entry "Shout_AstralKnowledge"\r?\n.*?(?=^new entry |\z)').Value
Require ($astralBlock.Contains('data "ContainerSpells"')) `
    'Official Astral Knowledge must remain a container spell'
foreach ($spellId in $starterSpells | Where-Object { $_ -ne 'Target_BoomingBlade_ClassSpell' }) {
    $hit = $officialStatFiles | Select-String -SimpleMatch "new entry `"$spellId`"" |
        Select-Object -First 1
    Require ($null -ne $hit) "Official Shared spell stat is missing: $spellId"
}
$disguiseFileHit = $officialStatFiles |
    Select-String -SimpleMatch 'new entry "Shout_DisguiseSelf"' | Select-Object -First 1
Require ($null -ne $disguiseFileHit) 'Official Disguise Self definition is missing'
$disguiseFile = Get-Content -Raw -LiteralPath $disguiseFileHit.Path -Encoding UTF8
$disguiseBlock = [regex]::Match($disguiseFile,
    '(?ms)^new entry "Shout_DisguiseSelf"\r?\n.*?(?=^new entry |\z)').Value
Require ($disguiseBlock.Contains('data "ContainerSpells" "Shout_DisguiseSelf_')) `
    'Official Disguise Self must remain a container spell'
$boomingHit = Get-ChildItem -LiteralPath $officialGustavXStats -Recurse -File -Filter '*.txt' |
    Select-String -SimpleMatch 'new entry "Target_BoomingBlade_ClassSpell"' | Select-Object -First 1
Require ($null -ne $boomingHit) 'Official GustavX Booming Blade stat is missing'

$removedDeluxeTemplates = @(
    '5d66776d-0650-4512-b300-b2ac38e2be3a',
    '8a1f5dc0-3f13-47ed-b238-50fdcaa2f680',
    '0ae83daa-1096-4b38-9b8c-fc610a9306aa'
)
foreach ($templateId in $removedDeluxeTemplates) {
    $sourceHit = Get-ChildItem -LiteralPath $source -Recurse -File |
        Select-String -SimpleMatch $templateId | Select-Object -First 1
    Require ($null -eq $sourceHit) "Removed Digital Deluxe template remains in source: $templateId"
}

$localizedResourceText = @(
    Get-ChildItem -LiteralPath $source -Recurse -File |
        Where-Object { $_.Extension -in @('.txt', '.lsx', '.lua') } |
        ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName -Encoding UTF8 }
) -join "`n"
$mechanicStats = @(
    Join-Path (Split-Path $passivePath -Parent) 'ChaosCore.txt'
    Join-Path (Split-Path $passivePath -Parent) 'ChaosRuntime.txt'
    Join-Path (Split-Path $passivePath -Parent) 'Interrupt.txt'
)
$allStatEntries = @($passiveEntries)
foreach ($path in @($statusPath) + $mechanicStats) {
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Mechanic stat file is missing: $path"
    $content = Get-Content -Raw -LiteralPath $path -Encoding UTF8
    Require (-not $content.Contains('LOC_')) "Mechanic stat file contains a legacy LOC_ identifier: $path"
    $allStatEntries += @([regex]::Matches($content, 'new entry "([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value })
}
Require ($allStatEntries.Count -eq 235 -and
    ($allStatEntries | Select-Object -Unique).Count -eq 235) `
    'Mechanic stats must contain exactly 235 globally unique entries'
$foldedStatEntries = @($allStatEntries | ForEach-Object { $_.ToUpperInvariant() })
Require (($foldedStatEntries | Select-Object -Unique).Count -eq 235) `
    'Mechanic stat entries must also be unique when case is ignored'
$mechanicEntryCounts = @{}
foreach ($path in $mechanicStats) {
    $mechanicEntryCounts[[IO.Path]::GetFileName($path)] =
        ([regex]::Matches((Get-Content -Raw -LiteralPath $path -Encoding UTF8), 'new entry "')).Count
}
Require ($mechanicEntryCounts['ChaosCore.txt'] -eq 34 `
    -and $mechanicEntryCounts['ChaosRuntime.txt'] -eq 179 `
    -and $mechanicEntryCounts['Interrupt.txt'] -eq 1) `
    'Mechanic stat family counts changed'
$chaosCoreText = Get-Content -Raw -LiteralPath $mechanicStats[0] -Encoding UTF8
$genesisStatusBlock = [regex]::Match($chaosCoreText,
    '(?ms)^new entry "COR_CHAOS_GENESIS"\r?\n.*?(?=^new entry |\z)').Value
$genesisDamageTypes = @(
    'Acid', 'Cold', 'Fire', 'Force', 'Lightning',
    'Necrotic', 'Poison', 'Psychic', 'Radiant', 'Thunder'
)
foreach ($damageType in $genesisDamageTypes) {
    $lowToken = 'IF(IsMeleeAttack() and not CharacterLevelGreaterThan(5)):DamageBonus(1d3,' + $damageType + ')'
    $highToken = 'IF(IsMeleeAttack() and CharacterLevelGreaterThan(5)):DamageBonus(1d6,' + $damageType + ')'
    Require ($genesisStatusBlock.Contains($lowToken)) "Genesis level 1-5 damage is invalid: $damageType"
    Require ($genesisStatusBlock.Contains($highToken)) "Genesis level 6-12 damage is invalid: $damageType"
}
Require (([regex]::Matches($genesisStatusBlock, 'DamageBonus\(')).Count -eq 20 -and -not $genesisStatusBlock.Contains('IF(IsMeleeAttack()):DamageBonus')) 'Genesis must contain only ten low-level d3 and ten high-level d6 damage rolls'
$powerStatusBlock = [regex]::Match($chaosCoreText,
    '(?ms)^new entry "COR_CHAOS_POWER_STACK"\r?\n.*?(?=^new entry |\z)').Value
Require ($powerStatusBlock.Contains('data "StackType" "Additive"') `
    -and $powerStatusBlock.Contains('FreezeDuration') `
    -and -not $powerStatusBlock.Contains('DisablePortraitIndicator')) `
    'Chaos Power must use a visible frozen Additive stack like an official charge status'
$mechanicsFeaturesLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'MechanicsFeatures.lua') -Encoding UTF8
Require ($mechanicsFeaturesLua.Contains(
    'local displayDuration = record.ChaosPower == 0 and -1 or record.ChaosPower * 6') `
    -and $mechanicsFeaturesLua.Contains(
        'Osi.ApplyStatus(character, "COR_CHAOS_POWER_STACK", displayDuration, 100, character)') `
    -and -not $mechanicsFeaturesLua.Contains('for _ = 1, record.ChaosPower do')) `
    'Chaos Power display must remain visible at zero and convert each point to one six-second turn'
$allInPassiveBlock = [regex]::Match($chaosCoreText,
    '(?ms)^new entry "COR_ChaosAllIn"\r?\n.*?(?=^new entry |\z)').Value
Require ($allInPassiveBlock.Contains('data "StatsFunctorContext" "OnCreate;OnShortRest"') `
    -and $allInPassiveBlock.Contains('data "StatsFunctors" "RestoreResource(COR_ChaosAllInUse,100%,0)"')) `
    'Chaos All-In resource must explicitly refill on creation and short rest'

$resourcePath = Join-Path $source "Public\$moduleName\ActionResourceDefinitions\ActionResourceDefinitions.lsx"
$iconMapPath = Join-Path $source "Public\$moduleName\GUI\Icons_ChaosOrigins.lsx"
$iconTexturePath = Join-Path $source "Public\$moduleName\Assets\Textures\Icons\Icons_ChaosOrigins.dds"
$iconSourcePath = Join-Path $ProjectRoot 'icon-src\Icons_ChaosOrigins.png'
foreach ($path in @($resourcePath, $iconMapPath, $iconTexturePath)) {
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Mechanic resource is missing: $path"
}
Require (Test-Path -LiteralPath $iconSourcePath -PathType Leaf) `
    "Reviewable icon atlas source is missing: $iconSourcePath"
$iconSourceBytes = [IO.File]::ReadAllBytes($iconSourcePath)
Require ($iconSourceBytes.Length -gt 24 `
    -and [BitConverter]::ToString($iconSourceBytes, 0, 8) -eq '89-50-4E-47-0D-0A-1A-0A' `
    -and [BitConverter]::ToString($iconSourceBytes, 16, 4) -eq '00-00-02-00' `
    -and [BitConverter]::ToString($iconSourceBytes, 20, 4) -eq '00-00-02-00') `
    'Reviewable icon atlas source must remain a 512 x 512 PNG'
$iconTextureBytes = [IO.File]::ReadAllBytes($iconTexturePath)
Require ($iconTextureBytes.Length -eq 349680 `
    -and [Text.Encoding]::ASCII.GetString($iconTextureBytes, 0, 4) -eq 'DDS ' `
    -and [BitConverter]::ToInt32($iconTextureBytes, 12) -eq 512 `
    -and [BitConverter]::ToInt32($iconTextureBytes, 16) -eq 512 `
    -and [BitConverter]::ToInt32($iconTextureBytes, 24) -eq 1 `
    -and [BitConverter]::ToInt32($iconTextureBytes, 28) -eq 10 `
    -and [Text.Encoding]::ASCII.GetString($iconTextureBytes, 84, 4) -eq 'DXT5') `
    'Chaos icon atlas must use the BG3-compatible 512x512 DXT5 DDS header'
for ($index = 32; $index -le 75; $index++) {
    Require ($iconTextureBytes[$index] -eq 0) `
        'Chaos icon atlas DDS reserved header must remain empty'
}
$resourceXml = [xml](Get-Content -Raw -LiteralPath $resourcePath -Encoding UTF8)
$resources = @($resourceXml.save.region.node.children.node)
Require ($resources.Count -eq 3) 'Exactly three Chaos action resources are required'
$actualResources = @{}
foreach ($resource in $resources) {
    $values = @{}
    foreach ($attribute in $resource.attribute) { $values[$attribute.id] = $attribute.value }
    $actualResources[$values.Name] = $values
}
$expectedResources = [ordered]@{
    COR_ChaosStrike = @('e5c69543-0a9d-4a7f-8dc9-6c814b9e3e01', '1', 'ShortRest')
    COR_ChaosAllInUse = @('e5c69543-0a9d-4a7f-8dc9-6c814b9e3e02', '3', 'ShortRest')
    COR_ChaosPowerPoint = @('e5c69543-0a9d-4a7f-8dc9-6c814b9e3e03', '3', 'Never')
}
foreach ($entry in $expectedResources.GetEnumerator()) {
    $actual = $actualResources[$entry.Key]
    Require ($null -ne $actual -and $actual.UUID -eq $entry.Value[0] `
        -and $actual.MaxValue -eq $entry.Value[1] -and $actual.ReplenishType -eq $entry.Value[2]) `
        "Chaos action resource is invalid: $($entry.Key)"
}
foreach ($legacyUuid in @(
    '398a7f18-2242-4bd5-bdeb-bb7df05edabc',
    '9a7afbe2-b122-4fca-b899-971cad03bce7',
    'bc9a2dbe-14a5-4e90-b66b-94edb035c9db'
)) {
    Require (-not $localizedResourceText.Contains($legacyUuid)) `
        "Legacy action-resource UUID remains: $legacyUuid"
}
$iconXml = [xml](Get-Content -Raw -LiteralPath $iconMapPath -Encoding UTF8)
$textureBankXml = [xml](Get-Content -Raw -LiteralPath $textureBankPath -Encoding UTF8)
$atlasUuid = [string]$iconXml.SelectSingleNode('//node[@id="TextureAtlasPath"]/attribute[@id="UUID"]').value
$textureResource = $textureBankXml.SelectSingleNode('//region[@id="TextureBank"]//node[@id="Resource"]')
Require ($null -ne $textureResource `
    -and [string]$textureResource.SelectSingleNode('./attribute[@id="ID"]').value -eq $atlasUuid `
    -and [string]$textureResource.SelectSingleNode('./attribute[@id="SourceFile"]').value `
        -eq 'Public/ChaosOriginsRemastered/Assets/Textures/Icons/Icons_ChaosOrigins.dds') `
    'Custom icon atlas must have a matching TextureBank resource registration'
$iconKeys = @($iconXml.SelectNodes('//node[@id="IconUV"]/attribute[@id="MapKey"]') |
    ForEach-Object value)
Require ($iconKeys.Count -eq ($iconKeys | Select-Object -Unique).Count) `
    'Chaos icon atlas contains duplicate keys'
$customIconReferences = @([regex]::Matches($localizedResourceText, 'data "Icon" "(CO_[^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
foreach ($icon in $customIconReferences) {
    Require ($iconKeys -contains $icon) "Chaos icon atlas omits referenced key: $icon"
}

$mcmBlueprintPath = Join-Path $source "Mods\$moduleName\MCM_blueprint.json"
Require (Test-Path -LiteralPath $mcmBlueprintPath -PathType Leaf) 'MCM blueprint is missing'
Require ($declaredPackageFiles -contains 'Mods/ChaosOriginsRemastered/MCM_blueprint.json') `
    'Package manifest omits MCM blueprint'
$mcmBlueprint = Get-Content -Raw -LiteralPath $mcmBlueprintPath -Encoding UTF8 | ConvertFrom-Json
Require ($mcmBlueprint.SchemaVersion -eq 1 -and $mcmBlueprint.id -eq $moduleUuid `
    -and $mcmBlueprint.ModName -eq 'Chaos Origins Remastered') `
    'MCM blueprint identity is invalid'
Require ($mcmBlueprint.Tabs.Count -eq 1 -and $mcmBlueprint.Tabs[0].TabId -eq 'bootstrap' `
    -and $mcmBlueprint.Tabs[0].Settings.Count -eq 1 `
    -and $mcmBlueprint.Tabs[0].Settings[0].Id -eq 'bootstrap_visible' `
    -and $mcmBlueprint.Tabs[0].Settings[0].Default -eq $false) `
    'MCM bootstrap tab must remain hidden and contain no persisted gameplay setting'

$mcmProtocol = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'McmProtocol.lua') -Encoding UTF8
$mcmClient = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'BootstrapClient.lua') -Encoding UTF8
$mcmProtocolCode = $mcmProtocol -replace '(?s)--\[\[.*?\]\]', '' -replace '(?m)--[^\r\n]*', ''
$mcmClientCode = $mcmClient -replace '(?s)--\[\[.*?\]\]', '' -replace '(?m)--[^\r\n]*', ''
foreach ($token in @('Version = 4', 'Channel = "MCM"', 'Origins = {', 'Mechanics = {',
    'WoundEffects = {')) {
    Require ($mcmProtocol.Contains($token)) "MCM protocol is missing: $token"
}
$mcmTextBlock = [regex]::Match($mcmProtocolCode,
    '(?ms)^\s*Text\s*=\s*\{(?<body>.*?)^\s*}').Groups['body'].Value
Require ([regex]::IsMatch($mcmProtocolCode, '(?m)^\s*Version\s*=\s*4\s*,') `
    -and $mcmTextBlock.Contains('TestLevel12Experience = "h68000001g0001g4001g8001g000000000001"')) `
    'MCM protocol test-experience contract is missing'
$testExperienceControl = [regex]::Match($mcmClientCode,
    '(?ms)controls\.TestExperience\s*=\s*checkbox\s*\(\s*parent\s*,.*?,\s*false\s*,\s*function\s*\([^)]*\)(?<body>.*?)\bend\s*\)').Value
Require ($testExperienceControl -ne '' `
    -and [regex]::IsMatch($mcmClientCode,
        '(?s)controls\.TestExperience\.Checked\s*=.*?snapshot\.TestLevel12Experience') `
    -and [regex]::IsMatch($testExperienceControl,
        'request\s*\(\s*"SetTestExperience"')) `
    'MCM client test-experience wiring is missing'
foreach ($token in @('Ext.Net.IsHost()', 'uiGeneration', 'reply.Revision', 'snapshot.CharacterId',
    'SetAllOrigins', 'SetOrigin', 'SetMechanic', 'SetWoundEffect', 'MCM_Window_Opened', 'MCM_Window_Closed',
    'pollSnapshot', 'InsertModMenuTab', 'renderGeneral', 'renderOrigins', 'renderWounds',
    'Protocol.Text.OriginTab', 'Protocol.Text.AllOrigins', 'Protocol.Text.WoundTab')) {
    Require ($mcmClient.Contains($token)) "MCM client behavior is missing: $token"
}
Require (([regex]::Matches($mcmClient, 'MCM\.InsertModMenuTab\(')).Count -eq 3) `
    'MCM must register separate general, origin and wound tabs'
foreach ($forbiddenClientToken in @('Ext.Vars', 'Osi.SetTag', 'Osi.ClearTag', 'Osi.AddPassive',
    'Osi.RemovePassive')) {
    Require (-not $mcmClient.Contains($forbiddenClientToken)) `
        "MCM client must not mutate authoritative state directly: $forbiddenClientToken"
}
foreach ($token in @('SetRequestHandler', 'request.CharacterId ~= snapshot.CharacterId',
    'Osi.IsInCombat', 'OriginFeatures.SetAllEnabled', 'OriginFeatures.SetEnabled', 'ChaosMechanics.SetMechanic',
    'ChaosMechanics.SetWoundEffect', 'isHostPeer(peerId)', 'ClientControl',
    'local osirisReady = false', 'if not osirisReady then', 'osirisReady = true')) {
    Require ($bootstrap.Contains($token)) "MCM server authority is missing: $token"
}
Require (-not $mcmClient.Contains('MCM_Window_Ready')) `
    'MCM Ready event must not invalidate controls rendered during the same window build'
$mcmCloseBlock = [regex]::Match($mcmClient,
    '(?s)MCM_Window_Closed:Subscribe\(function\(\).*?end\)').Value
Require ($mcmCloseBlock -ne '' -and $mcmCloseBlock.Contains('mcmOpen = false') `
    -and -not $mcmCloseBlock.Contains('uiGeneration = uiGeneration + 1') `
    -and -not $mcmCloseBlock.Contains('controls =')) `
    'Closing MCM must stop polling without invalidating the retained UI tree'
$clientSessionBlock = [regex]::Match($mcmClient,
    '(?s)Ext.Events.SessionLoaded:Subscribe\(function\(\).*?end\)').Value
Require ($clientSessionBlock -ne '' -and -not $clientSessionBlock.Contains('request("GetSnapshot")')) `
    'Client SessionLoaded must not request MCM state before Osiris query adapters are ready'

$publicRoot = Join-Path $source "Public\$moduleName"
$modsRoot = Join-Path $source "Mods\$moduleName"
foreach ($relative in @(
    'CharacterCreation', 'CharacterCreationPresets', 'CharacterVisuals', 'Progressions', 'Races', 'RootTemplates'
)) {
    Require (-not (Test-Path -LiteralPath (Join-Path $publicRoot $relative))) `
        "Remastered build must not contain $relative"
}
Require (-not (Test-Path -LiteralPath (Join-Path $modsRoot 'Story'))) `
    'Remastered build must not contain Story resources'

$textExtensions = @('.json', '.lua', '.lsx', '.md', '.ps1', '.txt', '.xml')
$textFiles = @(
    Get-ChildItem -LiteralPath $source -Recurse -File
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'resource-src') -Recurse -File
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'localization-src') -Recurse -File
) | Where-Object { $_.Extension -in $textExtensions }
$forbiddenPatterns = @(
    'LegacyOfDeath', 'LOD_', 'LOC_Chaos', 'b60b330f-f303-4a78-ad37-b79659c63821',
    '8f7dc353-74fa-5ad9-a628-f467675b1f99'
)
foreach ($pattern in $forbiddenPatterns) {
    $hit = $textFiles | Select-String -SimpleMatch $pattern | Select-Object -First 1
    Require ($null -eq $hit) "Remastered source contains forbidden legacy identifier: $pattern"
}

$expectedHandles = @([regex]::Matches($localizedResourceText, 'h[a-z0-9]{36}') |
    ForEach-Object Value | Sort-Object -Unique)
foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $path = Join-Path $ProjectRoot "localization-src\$language\ChaosOriginsRemastered.xml"
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Localization is missing: $language"
    $xml = [xml](Get-Content -Raw -LiteralPath $path -Encoding UTF8)
    $contents = @($xml.contentList.content)
    $handles = @($contents | ForEach-Object contentuid) | Sort-Object
    Require (-not (Compare-Object $handles $expectedHandles)) "Localization handles differ: $language"
    foreach ($content in $contents) { Require (-not [string]::IsNullOrWhiteSpace($content.'#text')) "Localization is empty: $language" }
}

Write-Host 'ChaosOriginsRemastered source verification: ok'
