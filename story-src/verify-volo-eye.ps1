$ErrorActionPreference = 'Stop'
$config = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt" -Raw
$stats = Get-Content "$PSScriptRoot/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt" -Raw
$feature = [regex]::Match($config, '(?s)// Volo eye configuration.*?EXITSECTION').Value
if (!$feature) { throw 'Volo eye feature is missing' }
$blocks = @([regex]::Matches($feature, '(?ms)^(?:PROC|IF)\r?\n.*?(?=^(?:PROC|IF|EXITSECTION)\r?\n|\z)') | ForEach-Object Value)
$grant = @($blocks | Where-Object { $_.Contains('ApplyStatus(_Character, "COS_VOLO_EYE", -1.0, 1, _Character);') })
if ($grant.Count -ne 1) { throw 'Volo reward must have exactly one grant path' }
$grantGates = $grant[0].Split('THEN')[0]
foreach ($gate in @('DB_COS_VoloEyeSetting(_Character, 1)', 'GetFlag((FLAG)GOB_VoloBallad_State_VoloEscaped_13ae819f-b0b7-434d-9ebb-cee412b1a407, NULL_00000000-0000-0000-0000-000000000000, 1)', 'HasPassive(_Character, "CAMP_Volo_ErsatzEye", 0)', 'HasActiveStatus(_Character, "COS_VOLO_EYE", 0)')) {
    if (!$grantGates.Contains($gate)) { throw "Missing grant gate in grant rule: $gate" }
}
foreach ($required in @('NOT DB_COS_VoloEyeSetting(_Character, _)', 'DB_COS_VoloEyeSetting(_Character, 1);', 'GOB_VoloBallad_State_VoloEscaped_13ae819f-b0b7-434d-9ebb-cee412b1a407', 'GetFlag(', 'HasPassive(_Character, "CAMP_Volo_ErsatzEye", 0)', 'RemoveStatus(_Character, "COS_VOLO_EYE", _Character);', 'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)', 'Resurrected(_Character)')) {
    if (!$feature.Contains($required)) { throw "Volo eye contract missing: $required" }
}
if ($feature -match '(?m)^(SetFlag|ClearFlag|AddCustomMaterialOverride|TeleportTo|PROC_DisappearOutOfSight)\(' -or $feature -match 'RemoveStatus\([^\n]*"(?:CAMP_VOLO_ERSATZEYE|MAG_SEE_INVISIBILITY_HIDDEN_IGNORE_RESTING)"') { throw 'Volo eye may not modify official quest, appearance, NPC or native reward' }
if ($stats -notmatch 'using "MAG_SEE_INVISIBILITY_HIDDEN_IGNORE_RESTING"' -or $stats -notmatch 'data "StackId" "COS_VOLO_EYE"') { throw 'Volo eye must inherit native detection with isolated stack' }
$mirror = [regex]::Match($stats, '(?ms)^new entry "COS_CFG_VOLO_EYE".*?(?=^new entry |\z)').Value
if (!$mirror -or $mirror.Contains('IsHidden')) { throw 'Volo menu mirror must be enumerable' }
foreach ($suffix in @('', '_c')) {
    [xml]$ui = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu$suffix.xaml" -Raw
    if (@($ui.SelectNodes('//*[@CommandParameter="77000000-0000-4000-8000-000000000001"]')).Count -ne 1) { throw "Volo menu action missing/duplicated: $suffix" }
    if ($ui.OuterXml -notmatch 'COS_CFG_VOLO_EYE') { throw 'Volo checked state missing' }
}
foreach ($language in @('Chinese','English','Japanese','Korean')) {
    [xml]$loc = Get-Content "$PSScriptRoot/Localization/$language/ChaosOriginsStory.xml" -Raw
    foreach ($handle in @('h77000000g0000g4000g8000g000000000001','h77000000g0000g4000g8000g000000000002')) {
        if (@($loc.contentList.content | Where-Object contentuid -eq $handle).Count -ne 1) { throw "Missing Volo localization: $language $handle" }
    }
}
'VOLO_EYE_STATIC=PASS; IN_GAME=PENDING'
