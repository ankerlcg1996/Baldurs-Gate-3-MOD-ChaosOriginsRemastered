param([switch]$SeedOnly, [ValidateSet('SeedOnly', 'CaptureApply')][string]$Partition = 'SeedOnly')
$ErrorActionPreference = 'Stop'
$goal = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_BaseAfterCreation.txt" -Raw
$config = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt" -Raw
if ($goal -match 'AddPassive\(_Character, "COS_BaseProficiencies"\)') { throw 'Legacy all-proficiencies grant bypasses individual switches.' }
$entries = @(Get-Content "$PSScriptRoot/grant-menu.json" -Raw | ConvertFrom-Json)
if ($entries.Count -ne 75) { throw 'Expected 75 individual options.' }
foreach ($expected in @(@('origin',7), @('tag',32), @('proficiency',36))) {
    if (@($entries | Where-Object {$_.kind -eq $expected[0]}).Count -ne $expected[1]) { throw "Wrong category coverage: $($expected[0])" }
}
if (@($entries.key | Select-Object -Unique).Count -ne 75 -or @($entries.event | Select-Object -Unique).Count -ne 75) { throw 'Duplicate grant keys or events.' }
$stats = Get-Content "$PSScriptRoot/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt" -Raw
[xml]$events = Get-Content "$PSScriptRoot/Public/ChaosOriginsStory/Tutorials/TutorialEvents.lsx" -Raw
foreach ($entry in $entries) {
    $mirrorBlock = [regex]::Match($stats, '(?ms)^new entry "' + [regex]::Escape($entry.mirror) + '"\r?\n.*?(?=^new entry |\z)').Value
    $mirrorHandle = $entry.handle.Replace('h76000000', 'h78000000')
    if (!$mirrorBlock -or $mirrorBlock -match 'IsHidden' -or !$mirrorBlock.Contains('data "DisplayName" "' + $mirrorHandle + '"')) { throw "Menu mirror must use its separate stable display key: $($entry.key)" }
    if (!$config.Contains($entry.event)) { throw "Missing event: $($entry.key)" }
    $eventNodes = @($events.SelectNodes('//node[@id="TutorialEvent"]') | Where-Object {$_.SelectSingleNode('attribute[@id="UUID"]').value -eq $entry.event})
    if ($eventNodes.Count -ne 1 -or $eventNodes[0].SelectSingleNode('attribute[@id="EventType"]').value -ne '8') { throw "Unregistered event: $($entry.key)" }
    if ($entry.kind -eq 'proficiency' -and !$stats.Contains("Proficiency($($entry.value))")) { throw "Missing proficiency: $($entry.key)" }
    foreach ($suffix in @('', '_c')) {
        $ui = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu$suffix.xaml" -Raw
        [xml]$null = $ui
        if (!$ui.Contains($entry.event) -or !$ui.Contains($entry.handle)) { throw "Missing menu option $($entry.key) $suffix" }
    }
    foreach ($language in @('Chinese','English','Japanese','Korean')) {
        [xml]$loc = Get-Content "$PSScriptRoot/Localization/$language/ChaosOriginsStory.xml" -Raw
        if (@($loc.contentList.content | Where-Object {$_.contentuid -eq $entry.handle}).Count -ne 1) { throw "Missing/duplicate localization $language $($entry.key)" }
    }
}
if ($SeedOnly) {
    if (!$config.Contains('PROC_COS_SeedGrantMap()') -or $config.Contains('PROC_COS_SyncOriginGrantMirrors(')) { throw 'Invalid partial-grant isolation boundary' }
    if ($config.Contains('PROC_COS_CaptureNativeGrantTags(') -ne ($Partition -eq 'CaptureApply')) { throw 'Wrong capture-rule partition' }
    "GRANT_MENU_RESOURCE_STATIC=PASS; PARTITION=$Partition; GAMEPLAY_DISABLED"
    return
}
if (!$config.Contains('PROC_COS_SeedGrantMap();') -or !$config.Contains('DB_COS_NativeGrantTag') -or !$config.Contains('DB_COS_GrantTagOwned')) { throw 'Runtime seeding or ownership protection missing.' }
if ($config -notmatch 'NOT DB_COS_NativeGrantTag\(_Character, _Tag\)') { throw 'Native tags are not protected.' }
if ($config -notmatch 'NOT DB_COS_GrantSetting\(_Character, _Key, _\)') { throw 'Missing-only configuration initialization required.' }
if ($goal -match '(?s)DB_COS_RaceIdentityTag\(_Tag\)\s*AND\s*IsTagged\(_Character, _Tag, 0\)\s*THEN\s*SetTag') { throw 'Unconditional legacy tag restoration remains.' }
$removal = [regex]::Match($config, '(?ms)^PROC\r?\nPROC_COS_ApplyGrantOptions\(.*?DB_COS_GrantSetting\(_Character, _Key, 0\).*?ClearTag\(_Character, _Tag\);').Value
foreach ($guard in @('DB_COS_GrantTagOwned(_Character, _Tag)', 'NOT DB_COS_NativeGrantTag(_Character, _Tag)')) {
    if (!$removal.Contains($guard)) { throw "Missing removal guard: $guard" }
}
if (!$config.Contains('NOT DB_COS_GrantUnresolved(_Character, _Key)') -or !$config.Contains('DebugText(_Character,')) { throw 'Unknown legacy identity must be reported, not silently removed.' }
if (!$config.Contains('DB_COS_GrantSetting(_Character, _Key, 1);') -or !$config.Contains('TogglePassive(_Character, _Passive);')) { throw 'Default or origin toggle synchronization missing.' }
'GRANT_MENU_STATIC=PASS; OPTIONS=75; IN_GAME=PENDING'
foreach ($action in @('SetTag', 'ClearTag')) {
    $syncPattern = 'DB_COS_OriginIdentityToggle\(_, _Status, _Tag\)\s*THEN\s*' + $action + '\(_Character, _Tag\);\s*PROC_COS_SyncOriginGrantMirrors\(\(CHARACTER\)_Character\);'
    if ($goal -notmatch $syncPattern) { throw "Origin status handler does not sync menu: $action" }
}
