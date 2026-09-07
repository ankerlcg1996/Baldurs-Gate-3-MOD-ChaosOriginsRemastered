$ErrorActionPreference = 'Stop'
$g = Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals'
$c = (Get-Content "$g/COS_Config.txt" -Raw).Replace("`r`n","`n")
$m = (Get-Content "$g/COS_ChaosMechanics.txt" -Raw).Replace("`r`n","`n")
function Assert-Cost($ok,$message) { if(-not $ok){throw $message} }
Assert-Cost ($c.Contains('DB_COS_ConfigCostDefault("Genesis", 10, "COS_ConfigGenesisCost");')) '缺少开天辟地独立消耗默认值'
Assert-Cost ($c.Contains('NOT DB_COS_ConfigCost(_Character, _Key, _)')) '不得覆盖已有设置'
Assert-Cost ($c.Contains('IntegerMax(_RawValue, 0, _FloorValue)') -and $c.Contains('IntegerMin(_FloorValue, 20, _Value)')) '消耗范围必须限制为 0–20'
Assert-Cost ($m.Contains('IntegerSubtract(_OldPower, _Cost, _NewPower)')) '必须扣除当前成本'
Assert-Cost ($m.Contains('DB_COS_ConfigCost(_Character, "Genesis", _Cost)') -and $m.Contains('_Power >= _Cost')) '开天辟地门槛必须同步成本'
Assert-Cost (-not $m.Contains('IntegerSubtract(_OldPower, 10, _NewPower)') -and -not $m.Contains('IntegerSubtract(_OldPower, 1, _NewPower)')) '不允许残留固定扣费'
Assert-Cost ($m.Contains('PROC_COS_ConfigEnsureCosts(_Character);')) '旧档同步必须初始化独立设置'
foreach($page in @('COS_ConfigMenu.xaml','COS_ConfigMenu_c.xaml')){
    [xml]$x = Get-Content (Join-Path $PSScriptRoot "Mods/ChaosOriginsStory/GUI/Pages/$page") -Raw
    $raw = Get-Content (Join-Path $PSScriptRoot "Mods/ChaosOriginsStory/GUI/Pages/$page") -Raw
    Assert-Cost ($raw.IndexOf('x:Name="COSConfigGenesisCostRow"') -gt $raw.IndexOf('x:Name="COSConfigRowGenesis"') -and $raw.IndexOf('x:Name="COSConfigGenesisCostRow"') -lt $raw.IndexOf('x:Name="COSConfigRowStrike"')) '开天辟地消耗必须紧随核心开关，不得放入熟练项区'
    foreach($key in @('GenesisCost')){
        $bars=@($x.SelectNodes('//*[local-name()="ItemsControl"]') | Where-Object { $_.GetAttribute('x:Name') -eq "COSConfig$($key)Value" })
        Assert-Cost ($bars.Count -eq 1) "缺少独立成本滑条: $key/$page"
        $pbar=$bars[0].SelectSingleNode('.//*[local-name()="LSProgressBar"]')
        Assert-Cost ($pbar.GetAttribute('Minimum') -eq '0' -and $pbar.GetAttribute('Maximum') -eq '20') '滑条范围错误'
    }
}
$setter = [regex]::Match($c, '(?ms)^PROC\nPROC_COS_ConfigSetCost\([^\n]+\).*?(?=^PROC\n)').Value
Assert-Cost ($setter.Contains('NOT DB_COS_ConfigCost(_Character, _Key, _Old);') -and $setter.Contains('DB_COS_ConfigCost(_Character, _Key, _Value);')) '修改必须仅针对当前角色当前键'
Assert-Cost (-not $setter.Contains('DB_COS_Power(')) '调节成本不得增减余额'
Assert-Cost ($setter.Contains('PROC_COS_SyncPowerFromDatabase(_Character);')) '成本改变必须刷新施放门槛'
foreach($cost in 0..20){foreach($power in 0..21){
    $can=$power -ge $cost; $cannot=$power -lt $cost
    Assert-Cost ($can -ne $cannot) '扣费分支应互斥且完整'
    if($can){Assert-Cost (($power-$cost) -ge 0) '不得负余额'}
}}
Write-Host 'POWER_COSTS_STATIC=PASS; IN_GAME=PENDING'
