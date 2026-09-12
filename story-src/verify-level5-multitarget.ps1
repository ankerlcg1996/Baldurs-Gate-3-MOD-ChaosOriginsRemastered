$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$path = Join-Path $PSScriptRoot 'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosFeatures.txt'
$source = Get-Content -LiteralPath $path -Raw -Encoding UTF8

function Test-SpellContract([string]$block, [bool]$haste, [bool]$container) {
    $condition = 'Character() and Party() and not Dead()'
    if (-not $haste) { $condition += ' and HasWeaponInMainHand()' }
    $fields = [ordered]@{
        AmountOfTargets = '10'
        TargetRadius = '100000'
        TargetFloor = '-1'
        TargetCeiling = '-1'
        TargetConditions = $condition
        CycleConditions = $condition
        UseCosts = $(if ($haste) { 'ActionPoint:1' } else { '' })
    }
    $flags = 'HasVerbalComponent;HasSomaticComponent;'
    if ($haste) { $flags += 'IsConcentration;' }
    $flags += 'IsSpell;'
    if ($container) { $flags += 'IsLinkedSpellContainer;' }
    $flags += 'IgnorePreviouslyPickedEntities;IgnoreVisionBlock;RangeIgnoreVerticalThreshold;RangeIgnoreBlindness'
    $fields.SpellFlags = $flags
    foreach ($field in $fields.Keys) {
        $line = 'data "' + $field + '" "' + $fields[$field] + '"'
        if ($block -notmatch ('(?m)^' + [regex]::Escape($line) + '\r?$')) { return $false }
    }
    if ($block -match '(?m)^data "(SpellProperties|TooltipStatusApply)" ') { return $false }
    return $true
}

$ids = @('Target_COS_Haste', 'Target_COS_DraconicElementalWeapon')
$ids += @('Acid', 'Cold', 'Fire', 'Lightning', 'Thunder') | ForEach-Object { "Target_COS_DraconicElementalWeapon_$_" }
foreach ($id in $ids) {
    $match = [regex]::Match($source, '(?ms)^new entry "' + [regex]::Escape($id) + '"\r?\n.*?(?=^new entry |\z)')
    if (-not $match.Success) { throw "Missing spell: $id" }
    $block = $match.Value
    $haste = $id -eq 'Target_COS_Haste'
    $container = $id -eq 'Target_COS_DraconicElementalWeapon'
    if (-not (Test-SpellContract $block $haste $container)) { throw "Invalid level-five multi-target contract: $id" }
    foreach ($mutation in @(
        $block.Replace('AmountOfTargets" "10"', 'AmountOfTargets" "1"'),
        $block.Replace('TargetRadius" "100000"', 'TargetRadius" "9"'),
        $block.Replace('Party()', 'Ally()'),
        $block.Replace('IgnorePreviouslyPickedEntities;', ''),
        $block.Replace('IgnoreVisionBlock;', ''),
        $block.Replace('RangeIgnoreVerticalThreshold;', ''),
        $block.Replace('RangeIgnoreBlindness', 'IsMelee')
    )) {
        if ($mutation -ceq $block -or (Test-SpellContract $mutation $haste $container)) { throw "Mutation escaped verification: $id" }
    }
    if ($haste -and (Test-SpellContract ($block.Replace('IsConcentration;', '')) $haste $container)) {
        throw 'Haste concentration mutation escaped verification'
    }
}
Write-Host 'Level-five multi-target source contract: ok (7 spells + mutation checks)'
