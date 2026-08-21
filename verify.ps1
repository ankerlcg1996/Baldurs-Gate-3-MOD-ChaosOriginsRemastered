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
$tagPath = Join-Path $ProjectRoot "resource-src\Public\$moduleName\Tags\$originTag.lsf.lsx"
$configPath = Join-Path $source "Mods\$moduleName\ScriptExtender\Config.json"
$bootstrapPath = Join-Path $source "Mods\$moduleName\ScriptExtender\Lua\BootstrapServer.lua"
$packageFilesPath = Join-Path $ProjectRoot 'package-files.json'
$raceCatalogPath = Join-Path $ProjectRoot 'official-data\race-catalog.json'
$raceCatalogGeneratorPath = Join-Path $ProjectRoot 'generate-race-catalog.ps1'
foreach ($path in @($originPath, $metaPath, $passivePath, $tagPath, $configPath, $bootstrapPath, $packageFilesPath)) {
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
    'COR_RacialSpells_Level1', 'COR_RacialSpells_Level3', 'COR_RacialSpells_Level5'
))) 'Passive.txt must contain exactly the marker, base features, and three racial-spell passives'
Require ($passive.Contains("new entry `"COR_OriginMarker`"`ntype `"PassiveData`"`ndata `"Properties`" `"IsHidden`"")) `
    'Origin marker must remain a hidden no-effect passive'

$proficiencyBoosts = 'Proficiency(LightArmor);Proficiency(MediumArmor);Proficiency(HeavyArmor);Proficiency(Shields);Proficiency(SimpleWeapons);Proficiency(MartialWeapons);Proficiency(MusicalInstrument)'
Require ($passive.Contains("new entry `"COR_BaseProficiencies`"`ntype `"PassiveData`"`ndata `"Properties`" `"IsHidden`"`ndata `"Boosts`" `"$proficiencyBoosts`"")) `
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
$fixedBonusSkills = @([regex]::Matches($skillBlock, 'Skill\(([A-Za-z]+),5\)') |
    ForEach-Object { $_.Groups[1].Value }) | Sort-Object
Require ($proficientSkills.Count -eq 18 -and -not (Compare-Object $proficientSkills $expectedSkills)) `
    'All-skill passive must grant proficiency to exactly 18 unique skills'
Require ($expertSkills.Count -eq 18 -and -not (Compare-Object $expertSkills $expectedSkills)) `
    'All-skill passive must grant expertise to exactly 18 unique skills'
Require ($fixedBonusSkills.Count -eq 18 -and -not (Compare-Object $fixedBonusSkills $expectedSkills)) `
    'All-skill passive must grant fixed +5 to exactly 18 unique skills'

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

$luaRoot = Split-Path $bootstrapPath -Parent
$expectedLuaFiles = @(
    'BaseFeatures.lua', 'BootstrapServer.lua', 'ChaosCharacter.lua',
    'ChaosState.lua', 'GrantLedger.lua', 'RaceCatalog.lua', 'RaceFeatures.lua'
) | Sort-Object
$actualLuaFiles = @(Get-ChildItem -LiteralPath $luaRoot -File -Filter '*.lua' | ForEach-Object Name) | Sort-Object
Require (-not (Compare-Object $actualLuaFiles $expectedLuaFiles)) 'Server Lua module list is invalid'
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
foreach ($token in @('SCHEMA_VERSION = 2', 'state.SchemaVersion == 1', 'NativeRaceTags',
    'RaceGranted', 'RewardItems', 'StarterRewardsVersion', 'Granted', 'Persistent = true',
    'owned == "adding"', 'owned == "removing"')) {
    Require ($stateLua.Contains($token)) "Strict state implementation is missing: $token"
}
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
Require ((Get-FileHash -LiteralPath $generatedCatalogCheck -Algorithm SHA256).Hash -eq
    (Get-FileHash -LiteralPath $raceCatalogLuaPath -Algorithm SHA256).Hash) `
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

$packageFiles = Get-Content -Raw -LiteralPath $packageFilesPath -Encoding UTF8 | ConvertFrom-Json
Require ($packageFiles.schema -eq 1) 'Unsupported package-files schema'
$declaredPackageFiles = @($packageFiles.files | ForEach-Object { [string]$_ })
Require ($declaredPackageFiles.Count -eq 16 -and ($declaredPackageFiles | Select-Object -Unique).Count -eq 16) `
    'package-files.json must contain exactly 16 unique paths'
foreach ($luaName in $expectedLuaFiles) {
    Require ($declaredPackageFiles -contains "Mods/ChaosOriginsRemastered/ScriptExtender/Lua/$luaName") `
        "Package manifest omits Lua module: $luaName"
}

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

$expectedHandles = @($descriptionHandle, $displayHandle) | Sort-Object
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
