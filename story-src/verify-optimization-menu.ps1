$ErrorActionPreference = 'Stop'
foreach ($name in 'COS_ConfigMenu.xaml','COS_ConfigMenu_c.xaml') {
    $raw = Get-Content (Join-Path $PSScriptRoot "Mods/ChaosOriginsStory/GUI/Pages/$name") -Raw
    [xml]$xml = $raw
    foreach ($field in 'COSConfigOverview','COSConfigRemainingMastery') {
        if (-not $raw.Contains("x:Name=`"$field`"")) { throw "缺少只读总览: $field" }
    }
    if ($raw.Contains('COSConfigEnabledExtras')) { throw '已开启额外设置清单应删除' }
    if ($name -eq 'COS_ConfigMenu_c.xaml' -and $raw -match '<Expander IsExpanded="False"') { throw '手柄总览不可使用无法聚焦的折叠控件' }
    $header = $raw.IndexOf('x:Name="COSConfigConvenienceHeader"')
    if ($header -lt 0) { throw "缺少额外便利分区: $name" }
    foreach ($core in 'COSConfigRowMastery','COSConfigGenesisCostRow') {
        if ($raw.IndexOf("x:Name=`"$core`"") -ge $header) { throw "核心项被混入便利: $core" }
    }
    foreach ($extra in 'COSConfigRowTagSpells','COSConfigLifeRow') {
        if ($raw.IndexOf("x:Name=`"$extra`"") -le $header) { throw "便利项仍在核心区: $extra" }
    }
}
Write-Host 'OPTIMIZATION_MENU_STATIC=PASS; IN_GAME=PENDING'
