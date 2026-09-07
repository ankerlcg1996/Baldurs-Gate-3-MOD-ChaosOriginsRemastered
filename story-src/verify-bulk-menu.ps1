$ErrorActionPreference = 'Stop'
$src = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt" -Raw
foreach ($group in @('Core','Race','Origin','Tag','Weapon')) {
    foreach ($mode in @('All','Invert')) {
        $name = "COS_BULK_${group}_${mode}"
        if (!$src.Contains($name)) { throw "Missing bulk action: $name" }
        foreach ($suffix in @('', '_c')) {
            [xml]$ui = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu$suffix.xaml"
            if (@($ui.SelectNodes('//*[@*[local-name()="Name"]="' + $name + '"]')).Count -ne 1) { throw "Missing unique button $name $suffix" }
        }
    }
}
if (!$src.Contains('PROC_COS_BulkGrant') -or !$src.Contains('NOT DB_COS_GrantUnresolved(_Character, _Key)')) { throw 'Bulk must retain existing ownership protections' }
$entry = [regex]::Match($src, '(?ms)^IF\r?\nTutorialEvent\(_Character, _Event\)\r?\nAND\r?\nDB_COS_BulkEvent\(.*?(?=^IF|^PROC|^EXITSECTION)').Value
foreach ($gate in @('HasPassive(_Character, "COS_ChaosOriginMarker", 1)', 'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)')) {
    if (!$entry.Contains($gate)) { throw "Missing bulk permission guard: $gate" }
}
'BULK_MENU_STATIC=PASS; IN_GAME=PENDING'
