$ErrorActionPreference = 'Stop'
$skills = 'SleightOfHand,Stealth,Arcana,History,Investigation,Nature,Religion,AnimalHandling,Insight,Medicine,Perception,Survival,Deception,Intimidation,Performance,Persuasion' -split ','
foreach ($pair in @(@('Passive.txt','BONUS'), @('Status_BOOST.txt','STATUS'))) {
    $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot "Public/ChaosOriginsStory/Stats/Generated/Data/$($pair[0])") -Raw
    $entries = [regex]::Matches($text, '(?ms)^new entry "COS_CFG_LIFE_SKILL_' + $pair[1] + '_(\d{2})".*?(?=^new entry |\z)')
    if ($entries.Count -ne 20) { throw "Expected twenty life skill entries: $($pair[0])" }
    foreach ($entry in $entries) {
        $value = [int]$entry.Groups[1].Value
        $boosts = [regex]::Match($entry.Value, '(?m)^data "Boosts" "([^"]*)"').Groups[1].Value
        $expected = ($skills | ForEach-Object { "Skill($_,$value)" }) -join ';'
        if ($boosts -cne $expected) { throw "Life skill bonus must contain exactly 16 skills without Athletics/Acrobatics: $($pair[0]) / $value" }
        foreach ($excluded in @('Athletics','Acrobatics')) {
            if (($boosts + ";Skill($excluded,$value)") -ceq $expected) { throw 'Exclusion mutation escaped' }
        }
    }
}
Write-Host 'PASS: all 40 life-skill entries grant only the 16 approved skills'
