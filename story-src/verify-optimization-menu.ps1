$ErrorActionPreference = 'Stop'
foreach ($name in 'COS_ConfigMenu.xaml','COS_ConfigMenu_c.xaml') {
    $raw = Get-Content (Join-Path $PSScriptRoot "Mods/ChaosOriginsStory/GUI/Pages/$name") -Raw
    [xml]$xml = $raw
    foreach ($field in 'COSConfigOverview','COSConfigRemainingMastery','COSConfigEnabledExtras') {
        if (-not $raw.Contains("x:Name=`"$field`"")) { throw "缺少只读总览: $field" }
    }
    $extras = $xml.SelectSingleNode('//*[@*[name()="x:Name"]="COSConfigEnabledExtras"]')
    if ($extras.SelectNodes('.//*[local-name()="InvokeCommandAction"]').Count -ne 0) { throw '总览不可写入设置' }
    $grantMenu = Get-Content (Join-Path $PSScriptRoot 'grant-menu.json') -Raw | ConvertFrom-Json
    foreach ($grant in $grantMenu) {
        if ($extras.OuterXml -notmatch [regex]::Escape('Value="' + $grant.mirror + '"')) { throw "总览缺少设置: $($grant.key)" }
    }
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
