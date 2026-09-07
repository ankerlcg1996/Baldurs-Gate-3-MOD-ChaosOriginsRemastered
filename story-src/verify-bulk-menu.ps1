$ErrorActionPreference = 'Stop'
$src = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt" -Raw
foreach ($group in @('Core','Origin','Tag','Weapon')) {
    foreach ($mode in @('All','Invert')) {
        $name = "COS_BULK_${group}_${mode}"
        if (!$src.Contains($name)) { throw "Missing bulk action: $name" }
        foreach ($suffix in @('', '_c')) {
            [xml]$ui = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu$suffix.xaml"
            if (@($ui.SelectNodes('//*[@*[local-name()="Name"]="' + $name + '"]')).Count -ne 1) { throw "Missing unique button $name $suffix" }
            $button = $ui.SelectSingleNode('//*[@*[local-name()="Name"]="' + $name + '"]')
            if ($button.ParentNode.GetAttribute('HorizontalAlignment') -ne 'Center') { throw "Bulk buttons must be centered: $name" }
            if ($suffix -eq '' -and $button.GetAttribute('Style') -ne '{StaticResource BigBrownButtonStyle}') { throw "Missing native gold button style: $name $suffix" }
        }
    }
}
if (!$src.Contains('PROC_COS_BulkGrant') -or !$src.Contains('NOT DB_COS_GrantUnresolved(_Character, _Key)')) { throw 'Bulk must retain existing ownership protections' }
$entry = [regex]::Match($src, '(?ms)^IF\r?\nTutorialEvent\(_Character, _Event\)\r?\nAND\r?\nDB_COS_BulkEvent\(.*?(?=^IF|^PROC|^EXITSECTION)').Value
foreach ($gate in @('HasPassive(_Character, "COS_ChaosOriginMarker", 1)', 'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)')) {
    if (!$entry.Contains($gate)) { throw "Missing bulk permission guard: $gate" }
}
'BULK_MENU_STATIC=PASS; IN_GAME=PENDING'
foreach ($suffix in @('', '_c')) {
    $text = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu$suffix.xaml" -Raw
    if ($text.Contains('x:Name="COS_BULK_Race_')) { throw 'Duplicate race bulk controls.' }
}
$off = [regex]::Match($src, '(?ms)^PROC\r?\nPROC_COS_BulkGrant\(\(CHARACTER\)_Character, \(STRING\)_Group, 2\).*?(?=^PROC)').Value
if (!$off.Contains('DB_COS_GrantSetting(_Character, _Key, 1)')) { throw 'Disable all must only act on enabled options, never invert disabled ones.' }
