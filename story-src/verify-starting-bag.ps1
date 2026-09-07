$ErrorActionPreference = 'Stop'
$source = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_BaseAfterCreation.txt" -Raw
$feature = [regex]::Match($source, '(?s)// New-character adventurer bag.*?EXITSECTION').Value
if (!$feature) { throw 'Missing new-character bag feature.' }
foreach ($required in @('CharacterCreationFinished()', 'DB_Avatars(_Character)', 'HasPassive(_Character, "COS_ChaosOriginMarker", 1)', 'LevelGameplayStarted(_Level, _)', 'IsGameLevel(_Level, 1)', 'DB_COS_StartingBagPending(_Character)', 'NOT DB_COS_StartingBagHandled(_Character)', 'GetHostCharacter(_Host)', 'CharacterHasDLC(_Host', 'CharacterHasDLC(_Character', 'NOT DB_DLC_Installed', '0ae83daa-1096-4b38-9b8c-fc610a9306aa', 'DB_COS_StartingBagHandled(_Character);')) {
    if (!$feature.Contains($required)) { throw "Starting bag contract missing: $required" }
}
if ($feature -match 'SavegameLoaded|GainedControl|RespecCompleted|TemplateAddedTo|UnlockCustomDLC') { throw 'Bag must not be retroactively granted or unlock DLC.' }
if ([regex]::Matches($feature, '(?m)^DB_COS_StartingBagCreationFinished\(1\);').Count -ne 1) { throw 'Only creation may establish eligibility.' }
$creation = [regex]::Match($feature, '(?ms)^IF\r?\nCharacterCreationFinished\(\).*?(?=^IF)').Value
if ($creation.Contains('DB_Avatars') -or $creation.Contains('HasPassive')) { throw 'Creation signal must not depend on player setup that runs after the event.' }
if (!$feature.Contains('PROC_COS_CreateStartingBag((CHARACTER)_Character, 0, 0)')) { throw 'Both character and host must lack Deluxe.' }
if ([regex]::Matches($feature, 'GetHostCharacter\(').Count -ne 1) { throw 'Only the DLC eligibility check may query the host.' }
'STARTING_BAG_STATIC=PASS; IN_GAME=PENDING'
