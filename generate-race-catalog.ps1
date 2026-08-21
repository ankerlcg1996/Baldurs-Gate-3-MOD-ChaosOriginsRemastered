param(
    [string]$CatalogPath = (Join-Path $PSScriptRoot 'official-data\race-catalog.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'source\Mods\ChaosOriginsRemastered\ScriptExtender\Lua\RaceCatalog.lua')
)

$ErrorActionPreference = 'Stop'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Lua-String([string]$Value) {
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Lua-Array([string[]]$Values, [int]$Indent) {
    if ($Values.Count -eq 0) { return '{}' }
    $padding = ' ' * $Indent
    $items = $Values | ForEach-Object { "$padding$(Lua-String $_)," }
    return "{`n$($items -join "`n")`n$(' ' * ($Indent - 4))}"
}

function Is-ExcludedPassive([string]$Passive) {
    return $Passive -in @('Darkvision', 'HumanVersatility', 'FearOfWolves_Shadowheart') `
        -or $Passive -match '^Dragonborn_Resistance_'
}

function Is-ExcludedSpell([string]$Spell) {
    return $Spell -match '^Zone_BreathWeapon_'
}

Require (Test-Path -LiteralPath $CatalogPath -PathType Leaf) "Race catalog is missing: $CatalogPath"
$catalog = Get-Content -Raw -LiteralPath $CatalogPath -Encoding UTF8 | ConvertFrom-Json
Require ($catalog.schema -eq 1) 'Unsupported race-catalog schema'
Require ($catalog.progressionOverridePolicy -eq 'later_rows_override') `
    'Race catalog must explicitly use later-row progression overrides'
Require ($catalog.playableParentRoot -eq '899d275e-9893-490a-9cd5-be856794929f') `
    'Official playable-race parent root changed'
Require ($catalog.racialSpellUnlockPolicy -eq 'fixed_sources_override_candidate_sources') `
    'Racial spell unlock conflict policy changed'
Require ($catalog.racialSpellUnlocks.Count -eq 29) `
    'Racial spell unlock catalog must contain exactly 29 rows'
$baseProvidedRacialSpells = @($catalog.baseProvidedRacialSpells | ForEach-Object { [string]$_ } |
    Sort-Object)
Require (-not (Compare-Object $baseProvidedRacialSpells @('Target_MageHand', 'Target_MinorIllusion'))) `
    'Base-provided racial spell overlap policy changed'
Require ($catalog.races.Count -eq 39) 'Race catalog must contain exactly 39 official race nodes'
Require ($catalog.progressions.Count -eq 102) 'Raw race catalog must contain exactly 102 progression rows'
Require (@($catalog.progressions | Group-Object uuid | Where-Object Count -gt 1).Count -eq 27) `
    'Race catalog must contain exactly 27 overridden progression UUIDs'

$raceIds = @($catalog.races | ForEach-Object { [string]$_.uuid })
Require (($raceIds | Select-Object -Unique).Count -eq 39) 'Race catalog contains duplicate race UUIDs'

# SharedDev 在原始数据中排在 Shared 之后；相同 UUID 必须由后者覆盖。
$progressionsByUuid = @{}
foreach ($progression in $catalog.progressions) {
    $progressionsByUuid[[string]$progression.uuid] = $progression
}
Require ($progressionsByUuid.Count -eq 75) `
    'Race progressions must contain exactly 75 UUIDs after SharedDev override'
$finalProgressionRows = @($progressionsByUuid.Values | Sort-Object uuid | ForEach-Object {
    "$($_.uuid)|$($_.table_uuid)|$([int]$_.level)|$((@($_.passives_added) | Sort-Object) -join ',')|$((@($_.spells_added) | Sort-Object) -join ',')|$((@($_.spells_selected) | Sort-Object) -join ',')"
})
$finalProgressionBytes = [Text.Encoding]::UTF8.GetBytes(($finalProgressionRows -join "`n") + "`n")
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    $finalProgressionHash = [Convert]::ToHexString(
        $sha256.ComputeHash($finalProgressionBytes)).ToLowerInvariant()
} finally {
    $sha256.Dispose()
}
Require ($finalProgressionHash -eq [string]$catalog.finalProgressionSha256) `
    'Final race progression snapshot changed after later-row overrides'
$asmodeusLevelOne = $progressionsByUuid['a8b18f0c-fe70-4f13-9dbc-23f4dbc3d648']
Require ($asmodeusLevelOne.spells_added -contains 'Shout_ProduceFlame' -and
    $asmodeusLevelOne.spells_added -notcontains 'Shout_Thaumaturgy') `
    'SharedDev did not override the obsolete Asmodeus progression row'

$allTags = [Collections.Generic.List[string]]::new()
$seenTags = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($race in $catalog.races) {
    foreach ($tag in $race.tags) {
        if ($seenTags.Add([string]$tag)) { $allTags.Add([string]$tag) }
    }
}
Require ($allTags.Count -eq 32) 'Race catalog must contain exactly 32 unique identity tags'

$featuresByLevel = @{}
foreach ($progression in $progressionsByUuid.Values) {
    $level = [int]$progression.level
    if (-not $featuresByLevel.ContainsKey($level)) {
        $featuresByLevel[$level] = @{
            Passives = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            Spells = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        }
    }
    foreach ($passive in $progression.passives_added) {
        if (-not (Is-ExcludedPassive ([string]$passive))) {
            [void]$featuresByLevel[$level].Passives.Add([string]$passive)
        }
    }
    foreach ($spell in @($progression.spells_added) + @($progression.spells_selected)) {
        if (-not (Is-ExcludedSpell ([string]$spell))) {
            [void]$featuresByLevel[$level].Spells.Add([string]$spell)
        }
    }
}

$featureLevels = @($featuresByLevel.Keys | Where-Object {
    $featuresByLevel[$_].Passives.Count -gt 0 -or $featuresByLevel[$_].Spells.Count -gt 0
} | Sort-Object)
Require (-not (Compare-Object $featureLevels @(1, 3, 5))) `
    'Racial passives and spells must unlock only at levels 1, 3, and 5'
$allPassives = @($featureLevels | ForEach-Object { $featuresByLevel[$_].Passives } | Sort-Object -Unique)
$allSpells = @($featureLevels | ForEach-Object { $featuresByLevel[$_].Spells } | Sort-Object -Unique)
Require ($allPassives.Count -eq 20) 'Race catalog must contain exactly 20 allowed passives'
Require ($allSpells.Count -eq 29) 'Race catalog must contain exactly 29 allowed spells'
$unlockBySpell = @{}
foreach ($unlock in $catalog.racialSpellUnlocks) {
    $spell = [string]$unlock.spell
    Require (-not $unlockBySpell.ContainsKey($spell)) "Duplicate racial spell unlock metadata: $spell"
    Require ([string]$unlock.boost -match ('^UnlockSpell\(' + [regex]::Escape($spell) + '(?:,|\))')) `
        "Racial spell unlock Boost does not match its spell: $spell"
    $unlockBySpell[$spell] = $unlock
}
Require (-not (Compare-Object ($unlockBySpell.Keys | Sort-Object) $allSpells)) `
    'Racial spell unlock metadata must cover exactly the 29 allowed spells'
foreach ($level in $featureLevels) {
    $levelSpells = @($featuresByLevel[$level].Spells | Sort-Object)
    $unlockSpells = @($catalog.racialSpellUnlocks | Where-Object { [int]$_.level -eq $level } |
        ForEach-Object { [string]$_.spell } | Sort-Object)
    Require (-not (Compare-Object $unlockSpells $levelSpells)) `
        "Racial spell unlock metadata has an invalid level-$level set"
}

$lines = [Collections.Generic.List[string]]::new()
$lines.Add('-- 由已审计的官方种族目录生成；请勿手工修改。')
$lines.Add('return {')
$lines.Add("    Schema = 1,")
$lines.Add('    CandidateSpellPolicy = "grant_all",')
$lines.Add("    PlayableParentRoot = $(Lua-String ([string]$catalog.playableParentRoot)),")
$lines.Add("    RaceCount = 39,")
$lines.Add("    TagCount = 32,")
$lines.Add("    PassiveCount = 20,")
$lines.Add("    SpellCount = 29,")
$lines.Add('    RacialSpellPassives = {')
$lines.Add('        [1] = "COR_RacialSpells_Level1",')
$lines.Add('        [3] = "COR_RacialSpells_Level3",')
$lines.Add('        [5] = "COR_RacialSpells_Level5",')
$lines.Add('    },')
$lines.Add('    Races = {')
foreach ($race in $catalog.races | Sort-Object uuid) {
    $tags = @($race.tags | ForEach-Object { [string]$_ })
    $lines.Add("        [$(Lua-String ([string]$race.uuid))] = {")
    $lines.Add("            Name = $(Lua-String ([string]$race.name)),")
    $lines.Add("            Parent = $(Lua-String ([string]$race.parent_uuid)),")
    $lines.Add("            Tags = $(Lua-Array $tags 16),")
    $lines.Add('        },')
}
$lines.Add('    },')
$lines.Add("    AllTags = $(Lua-Array @($allTags) 8),")
$lines.Add("    FeatureLevels = { $($featureLevels -join ', ') },")
$lines.Add('    FeaturesByLevel = {')
foreach ($level in $featureLevels) {
    $passives = @($featuresByLevel[$level].Passives | Sort-Object)
    $spells = @($featuresByLevel[$level].Spells | Sort-Object)
    $lines.Add("        [$level] = {")
    $lines.Add("            Passives = $(Lua-Array $passives 16),")
    $lines.Add("            Spells = $(Lua-Array $spells 16),")
    $lines.Add('        },')
}
$lines.Add('    },')
$lines.Add('}')

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[IO.File]::WriteAllText($OutputPath, ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Generated race catalog: $OutputPath"
