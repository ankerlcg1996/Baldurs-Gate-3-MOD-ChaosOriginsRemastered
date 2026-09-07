$ErrorActionPreference = 'Stop'
$stats = (Get-Content "$PSScriptRoot/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt" -Raw) + "`n" + (Get-Content "$PSScriptRoot/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt" -Raw)
foreach ($suffix in @('', '_c')) {
    [xml]$ui = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu$suffix.xaml"
    foreach ($language in @('Chinese','English','Japanese','Korean')) {
        [xml]$loc = Get-Content "$PSScriptRoot/Localization/$language/ChaosOriginsStory.xml"
        foreach ($trigger in $ui.SelectNodes('//*[local-name()="DataTrigger" and @Binding="{Binding Name.Str}"]')) {
            $key = $trigger.GetAttribute('Value')
            $block = [regex]::Match($stats, '(?ms)^new entry "' + [regex]::Escape($key) + '"\r?\n.*?(?=^new entry |\z)').Value
            $handle = [regex]::Match($block, 'data "DisplayName" "([^"]+)"').Groups[1].Value
            $text = @($loc.contentList.content | Where-Object contentuid -eq $handle)
            if ($text.Count -ne 1 -or $text[0].InnerText -cne $key) { throw "Name.Str mismatch: $language $key resolves through $handle instead of a stable key" }
        }
    }
}
'MENU_MIRROR_KEYS=PASS'
