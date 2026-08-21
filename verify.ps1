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
foreach ($path in @($originPath, $metaPath, $passivePath, $tagPath, $configPath, $bootstrapPath)) {
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
    'COR_AllSkillMastery', 'COR_BaseProficiencies', 'COR_OriginMarker'
))) 'Passive.txt must contain exactly the marker and two base-feature passives'
Require ($passive.Contains("new entry `"COR_OriginMarker`"`ntype `"PassiveData`"`ndata `"Properties`" `"IsHidden`"")) `
    'Origin marker must remain a hidden no-effect passive'

$proficiencyBoosts = 'Proficiency(LightArmor);Proficiency(MediumArmor);Proficiency(HeavyArmor);Proficiency(Shields);Proficiency(SimpleWeapons);Proficiency(MartialWeapons);Proficiency(MusicalInstrument)'
Require ($passive.Contains("new entry `"COR_BaseProficiencies`"`ntype `"PassiveData`"`ndata `"Properties`" `"IsHidden`"`ndata `"Boosts`" `"$proficiencyBoosts`"")) `
    'Base proficiency passive has invalid boosts'

$skillBlockMatch = [regex]::Match($passive, '(?s)new entry "COR_AllSkillMastery".*\z')
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
    'ChaosState.lua', 'GrantLedger.lua', 'StarterRewards.lua'
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
$starterSpells = @(
    'Target_BoomingBlade_ClassSpell', 'Target_Guidance', 'Target_MageHand',
    'Target_MinorIllusion', 'Shout_FeatherFall', 'Target_Jump'
)
foreach ($spellId in $starterSpells) {
    Require ($baseFeatures.Contains('"' + $spellId + '"')) "Starter spell is missing: $spellId"
}
Require (([regex]::Matches($baseFeatures, '"(?:Target|Shout)_[A-Za-z0-9_]+"')).Count -eq 6) `
    'BaseFeatures.lua must declare exactly six spells'

$stateLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'ChaosState.lua') -Encoding UTF8
foreach ($token in @('SchemaVersion', 'RewardItems', 'StarterRewardsVersion', 'Granted', 'Persistent = true')) {
    Require ($stateLua.Contains($token)) "Strict state implementation is missing: $token"
}
$characterLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'ChaosCharacter.lua') -Encoding UTF8
foreach ($token in @('Osi.IsPlayer', 'Osi.DB_Players', $originTag, 'COR_OriginMarker')) {
    Require ($characterLua.Contains($token)) "Chaos character eligibility is missing: $token"
}
$ledgerLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'GrantLedger.lua') -Encoding UTF8
foreach ($token in @('Osi.HasPassive', 'Osi.AddPassive', 'Osi.HasSpell', 'Osi.AddSpell', 'State.MarkDirty')) {
    Require ($ledgerLua.Contains($token)) "Grant ledger behavior is missing: $token"
}
$rewardsLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'StarterRewards.lua') -Encoding UTF8
foreach ($token in @('TemplateAddedTo', 'TemplateAddTo', 'RewardItems', 'Osi.Equip', 'Osi.IsEquipped')) {
    Require ($rewardsLua.Contains($token)) "Starter reward behavior is missing: $token"
}

$officialSharedStats = Join-Path $ProjectRoot 'work\official-shared-stats-20260822'
$officialGustavXStats = Join-Path $ProjectRoot 'work\official-gustavx-stats-20260822'
Require (Test-Path -LiteralPath $officialSharedStats -PathType Container) `
    "Extracted official Shared stats are missing: $officialSharedStats"
Require (Test-Path -LiteralPath $officialGustavXStats -PathType Container) `
    "Extracted official GustavX stats are missing: $officialGustavXStats"
foreach ($spellId in $starterSpells | Where-Object { $_ -ne 'Target_BoomingBlade_ClassSpell' }) {
    $hit = Get-ChildItem -LiteralPath $officialSharedStats -Recurse -File -Filter '*.txt' |
        Select-String -SimpleMatch "new entry `"$spellId`"" | Select-Object -First 1
    Require ($null -ne $hit) "Official Shared spell stat is missing: $spellId"
}
$boomingHit = Get-ChildItem -LiteralPath $officialGustavXStats -Recurse -File -Filter '*.txt' |
    Select-String -SimpleMatch 'new entry "Target_BoomingBlade_ClassSpell"' | Select-Object -First 1
Require ($null -ne $boomingHit) 'Official GustavX Booming Blade stat is missing'

$officialTemplates = Join-Path $ProjectRoot 'work\official\Public\GustavDev\RootTemplates\_merged.lsf.lsx'
Require (Test-Path -LiteralPath $officialTemplates -PathType Leaf) `
    "Extracted official root templates are missing: $officialTemplates"
$templateText = Get-Content -Raw -LiteralPath $officialTemplates -Encoding UTF8
foreach ($templateId in @(
    '5d66776d-0650-4512-b300-b2ac38e2be3a',
    '8a1f5dc0-3f13-47ed-b238-50fdcaa2f680',
    '0ae83daa-1096-4b38-9b8c-fc610a9306aa'
)) {
    Require ($templateText.Contains("value=`"$templateId`"")) "Official reward template is missing: $templateId"
    Require ($rewardsLua.Contains('"' + $templateId + '"')) "Starter reward template is missing from Lua: $templateId"
}

$publicRoot = Join-Path $source "Public\$moduleName"
$modsRoot = Join-Path $source "Mods\$moduleName"
foreach ($relative in @(
    'CharacterCreation', 'CharacterCreationPresets', 'CharacterVisuals', 'Progressions', 'Races', 'RootTemplates'
)) {
    Require (-not (Test-Path -LiteralPath (Join-Path $publicRoot $relative))) `
        "Phase 1 must not contain $relative"
}
Require (-not (Test-Path -LiteralPath (Join-Path $modsRoot 'Story'))) 'Phase 1 must not contain Story resources'

$textExtensions = @('.json', '.lua', '.lsx', '.md', '.ps1', '.txt', '.xml')
$textFiles = @(
    Get-ChildItem -LiteralPath $source -Recurse -File
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'resource-src') -Recurse -File
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'localization-src') -Recurse -File
) | Where-Object { $_.Extension -in $textExtensions }
$forbiddenPatterns = @(
    'LegacyOfDeath', 'LOD_', 'LOC_Chaos', 'b60b330f-f303-4a78-ad37-b79659c63821',
    '8f7dc353-74fa-5ad9-a628-f467675b1f99', 'AddExplorationExperience',
    'LEVEL_12_TOTAL_EXPERIENCE'
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

Write-Host 'ChaosOriginsRemastered base-feature source verification: ok'
