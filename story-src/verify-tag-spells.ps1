$ErrorActionPreference = 'Stop'
$config = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt" -Raw
if (!$config.Contains('PROC_COS_SyncTagSpells')) { throw 'Missing level-gated race spell delivery.' }
$feature = [regex]::Match($config, '(?s)// Tag spell delivery.*?EXITSECTION').Value
foreach ($required in @('DB_COS_TagSpellsSetting(_Character, 0);', 'GetLevel(_Character, _Level)', '_Level >= _Minimum', 'DB_COS_GrantSetting(_Character, _Key, 1)', 'NOT DB_COS_TagSpellDesired(_Character, _Passive)', 'HasPassive(_Character, "COS_ChaosOriginMarker", 1)', 'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)')) {
    if (!$feature.Contains($required)) { throw "Tag spells contract missing: $required" }
}
if ($feature -match '(?m)^(RemoveSpell|ClearTag)\(') { throw 'Do not revoke native spells or identity tags.' }
$catalog = @(Get-Content "$PSScriptRoot/tag-spells.json" -Raw | ConvertFrom-Json)
if ($catalog.Count -ne 22) { throw 'Expected 22 fixed original progression grants.' }
$stats = Get-Content "$PSScriptRoot/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt" -Raw
foreach ($grant in $catalog) {
    if (!$stats.Contains($grant.spells)) { throw "Missing original spell $($grant.spells)" }
    $args = $grant.selector.Split(',')
    $cooldown = if ($args.Count -gt 5) { $args[5] } else { '' }
    $ability = if ($args.Count -gt 2) { $args[2] } else { '' }
    if (!$stats.Contains("UnlockSpell($($grant.spells),AddChildren,,$cooldown,$ability)")) { throw "Original spell metadata changed: $($grant.spells)" }
    if ($grant.selector -match 'SelectSpells') { throw 'Choice grants are outside scope.' }
}
foreach ($suffix in @('', '_c')) {
    $ui = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu$suffix.xaml" -Raw
    if ($ui.IndexOf('x:Name="COSConfigRowTagSpells"') -lt 0 -or $ui.IndexOf('x:Name="COSConfigRowTagSpells"') -gt $ui.IndexOf('x:Name="COSConfigRowVoloEye"')) { throw 'Race spell switch must precede Volo eye.' }
}
'TAG_SPELLS_STATIC=PASS; IN_GAME=PENDING'
