#requires -Version 7.0
$ErrorActionPreference = 'Stop'
function Require([bool]$ok, [string]$message) { if (-not $ok) { throw $message } }
$goalPath = "$PSScriptRoot/src/Mods/ExplorationBenefitsStory/Story/RawFiles/Goals/EBS_Exploration.txt"
Require (Test-Path -LiteralPath $goalPath) 'Missing exploration Story implementation'
$goal = (Get-Content -LiteralPath $goalPath -Raw).Replace("`r`n", "`n")
$stats = Get-Content "$PSScriptRoot/src/Public/ExplorationBenefitsStory/Stats/Generated/Data/Exploration.txt" -Raw
function Test-StoryContract([string]$source) {
    $rules = @($source -split '(?m)(?=^(?:PROC|IF)$)')
    $apply = @($rules | Where-Object { $_ -match 'ApplyStatus\(_Character, "EBS_EXPLORING"' })
    Require ($apply.Count -eq 1) 'Exactly one benefit application rule is required'
    foreach ($guard in @('DB_EBS_Enabled(_Character, 1)','IsInCombat(_Character, 0)','IsDead(_Character, 0)','IsPartyMember(_Character, 0, 1)','IsSummon(_Character, 0)','HasActiveStatus(_Character, "EBS_EXPLORING", 0)')) {
        Require ($apply[0].Contains($guard)) "Apply guard missing: $guard"
    }
    $seed = @($rules | Where-Object { $_ -match 'DB_EBS_Enabled\(_Character, 1\);' -and $_ -match 'PROC_EBS_EnsureSetting' })
    Require ($seed.Count -eq 1 -and $seed[0].Contains('NOT DB_EBS_Enabled(_Character, _)')) 'Default must not overwrite saved settings'
    foreach ($event in @('EnteredCombat','LeftCombat','LevelGameplayStarted','CharacterJoinedParty','CharacterLeftParty','Resurrected','RespecCompleted','LongRestFinished','GainedControl')) {
        Require ($source -match "(?m)^$event\(") "Lifecycle event missing: $event"
    }
    $enter = @($rules | Where-Object { $_ -match '^IF\nEnteredCombat\(' })
    Require ($enter.Count -eq 1 -and $enter[0].Contains('PROC_EBS_ClearBenefits((CHARACTER)_Character);') -and $enter[0] -notmatch 'DB_Players') 'Combat must clear only the entering character'
    foreach ($m in [regex]::Matches($source, 'RemoveStatus\([^,]+, "([^"]+)"')) {
        Require ($m.Groups[1].Value -in @('EBS_EXPLORING','EBS_ENABLED')) 'Removing a foreign/native status is forbidden'
    }
    Require ($source -notmatch 'COS_|ChaosOrigins|TimerLaunch') 'No old mod dependency or polling'
    foreach ($event in @('StatusApplied','StatusRemoved')) {
        $rule = @($rules | Where-Object { $_ -match "^IF\n$event\(" })
        Require ($rule.Count -eq 1 -and $rule[0].Contains('NOT DB_EBS_Syncing(_Character)')) 'Toggle callbacks must ignore synchronization changes'
    }
}
Test-StoryContract $goal
foreach ($guard in @('IsInCombat(_Character, 0)','NOT DB_EBS_Enabled(_Character, _)','NOT DB_EBS_Syncing(_Character)')) {
    $rejected = $false
    try { Test-StoryContract ($goal.Replace($guard, '// removed by mutation test')) } catch { $rejected = $true }
    Require $rejected "Mutation not rejected: $guard"
}
foreach ($boost in @('JumpMaxDistanceMultiplier(3)','IgnoreFallDamage()','Tag(PETPAL)','DarkvisionRangeMin(12)','Attribute(SlippingImmunity)','StatusImmunity(SG_DifficultTerrain)')) {
    Require ($stats.Contains($boost)) "Missing exploration effect: $boost"
}
Require ($stats -notmatch 'StatusImmunity\(PRONE|StatusImmunity\(KNOCKED_DOWN') 'Do not replace anti-slip with general prone immunity'
Require ($stats.Contains('IsToggled;ToggledDefaultOn')) 'Passive must default on'
Require ($stats.Contains('ToggleOffFunctors" "RemoveStatus(EBS_ENABLED);RemoveStatus(EBS_EXPLORING)')) 'Toggle off must immediately remove only own benefits'
foreach ($lang in @('Chinese','English')) {
    [xml]$loc = Get-Content "$PSScriptRoot/src/Localization/$lang/ExplorationBenefitsStory.xml" -Raw
    $handles = @($loc.contentList.content | ForEach-Object {$_.contentuid})
    Require (($handles | Select-Object -Unique).Count -eq $handles.Count) 'Duplicate localization handles'
    foreach ($m in [regex]::Matches($stats, '"(h[0-9a-fg]{36});1"')) {
        Require ($m.Groups[1].Value -in $handles) "Missing $lang localization: $($m.Groups[1].Value)"
    }
}
[xml]$meta = Get-Content "$PSScriptRoot/src/Mods/ExplorationBenefitsStory/meta.lsx" -Raw
$uuid = $meta.SelectSingleNode('//node[@id="ModuleInfo"]/attribute[@id="UUID"]').value
Require ($uuid -eq '7f2cfe6b-cab7-4da7-a46d-31b535c53c68') 'Module identity must be independent and stable'
'PASS: source contracts, guard mutations, six boosts, localization, independent module identity. Gameplay not tested.'
