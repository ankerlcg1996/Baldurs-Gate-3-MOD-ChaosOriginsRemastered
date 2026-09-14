# ChaosOriginsStory 1.0.1.99 Category Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add seven per-character category master switches, four derived presets with preview and confirmation, first-character “Near Vanilla” initialization, legacy-save preservation, and configured-versus-actual status reporting to the pure Story `ChaosOriginsStory` package.

**Architecture:** Keep the existing child setting databases as saved configuration truth. Add a seven-row category database and schema marker per Chaos Origin character, derive the active preset from category rows plus the life-skill value, and apply `EffectiveEnabled = CategoryEnabled AND ItemConfiguredEnabled` at every runtime grant or trigger boundary. Mirror passives and hidden no-boost statuses expose Story state to both native menu pages. All mutations remain host-controlled, per-character, and non-combat-only.

**Tech Stack:** BG3 native Osiris Story, BG3 Stats text definitions, Larian XAML menu overrides, four BG3 localization XML sources, PowerShell 7 contract tests, LSLib resource/PAK tooling, Git.

---

## File map

| File | Change |
|---|---|
| `story-src/verify-category-presets.ps1` | New fail-first contract and mutation verifier for category schema, presets, ownership, UI parity, localization, and package invariants. |
| `story-src/verify.ps1` | Invoke the new verifier before Story compilation and retain the existing full-suite checks. |
| `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt` | Add category persistence, initialization classification, mirror/actual statuses, preset preview/apply/detection, category-gated grant synchronization, and diagnostics. |
| `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt` | Add the `Core` category guard to every runtime consumer of `DB_COS_ConfigMechanic`; do not change child values. |
| `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMastery.txt` | Add the same `Core` guard to mastery and mastery-option runtime consumers. |
| `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt` | Define category mirror passives plus current-preset, pending-preview, actual-state, and explicit-error statuses. |
| `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml` | Add the keyboard/mouse preset panel and category master rows; gray and block paused children. |
| `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml` | Add the controller-equivalent panel, focus graph, and read-only behavior. |
| `story-src/Localization/{Chinese,English,Japanese,Korean}/ChaosOriginsStory.xml` | Add complete native-language strings for presets, categories, preview changes, actual-state reasons, and errors. |
| `story-src/docs/RELEASE-1.0.1.99.md` | Record build proof, package hashes, installation proof, rollback commit, and the remaining in-game acceptance boundary. |

No new packaged path is added. `package-files.json` remains exactly 38 entries and the PAK remains exactly six Goals.

Run every `git` block from `C:\Users\ankerlcg\Desktop\chaos-BG3-mod-story\.worktrees\native-core-config`. Run every Story verification/build block from its `story-src` child unless the block contains an explicit `Set-Location`. Stop immediately on a nonzero command; do not continue with a guessed or partially generated artifact.

## Fixed identifiers and matrices

Use these exact category keys and mirror passives:

| Key | Enabled mirror passive | TutorialEvent UUID |
|---|---|---|
| `Core` | `COS_CFG_CATEGORY_CORE` | `7e990000-0000-4000-8000-000000000001` |
| `Origin` | `COS_CFG_CATEGORY_ORIGIN` | `7e990000-0000-4000-8000-000000000002` |
| `RaceTags` | `COS_CFG_CATEGORY_RACETAGS` | `7e990000-0000-4000-8000-000000000003` |
| `WeaponProficiencies` | `COS_CFG_CATEGORY_WEAPON` | `7e990000-0000-4000-8000-000000000004` |
| `ArmorProficiencies` | `COS_CFG_CATEGORY_ARMOR` | `7e990000-0000-4000-8000-000000000005` |
| `RacialAbilities` | `COS_CFG_CATEGORY_RACIAL` | `7e990000-0000-4000-8000-000000000006` |
| `Convenience` | `COS_CFG_CATEGORY_CONVENIENCE` | `7e990000-0000-4000-8000-000000000007` |

Use these preset events:

| Action | TutorialEvent UUID |
|---|---|
| Select `NearVanilla` | `7e990000-0000-4000-8000-000000000011` |
| Select `PureChaos` | `7e990000-0000-4000-8000-000000000012` |
| Select `Balanced` | `7e990000-0000-4000-8000-000000000013` |
| Select `AllConvenience` | `7e990000-0000-4000-8000-000000000014` |
| Apply pending preset | `7e990000-0000-4000-8000-000000000015` |
| Cancel pending preset | `7e990000-0000-4000-8000-000000000016` |

Seed the exact preset rows below. `-1` means preserve and ignore that field during detection.

```text
DB_COS_PresetCategory("NearVanilla", "Core", 0);
DB_COS_PresetCategory("NearVanilla", "Origin", 1);
DB_COS_PresetCategory("NearVanilla", "RaceTags", 0);
DB_COS_PresetCategory("NearVanilla", "WeaponProficiencies", 0);
DB_COS_PresetCategory("NearVanilla", "ArmorProficiencies", 0);
DB_COS_PresetCategory("NearVanilla", "RacialAbilities", 0);
DB_COS_PresetCategory("NearVanilla", "Convenience", 0);
DB_COS_PresetLife("NearVanilla", 0);

DB_COS_PresetCategory("PureChaos", "Core", 1);
DB_COS_PresetCategory("PureChaos", "Origin", -1);
DB_COS_PresetCategory("PureChaos", "RaceTags", 0);
DB_COS_PresetCategory("PureChaos", "WeaponProficiencies", 0);
DB_COS_PresetCategory("PureChaos", "ArmorProficiencies", 0);
DB_COS_PresetCategory("PureChaos", "RacialAbilities", 0);
DB_COS_PresetCategory("PureChaos", "Convenience", 0);
DB_COS_PresetLife("PureChaos", 0);

DB_COS_PresetCategory("Balanced", "Core", 1);
DB_COS_PresetCategory("Balanced", "Origin", 1);
DB_COS_PresetCategory("Balanced", "RaceTags", 0);
DB_COS_PresetCategory("Balanced", "WeaponProficiencies", 0);
DB_COS_PresetCategory("Balanced", "ArmorProficiencies", 0);
DB_COS_PresetCategory("Balanced", "RacialAbilities", 0);
DB_COS_PresetCategory("Balanced", "Convenience", 0);
DB_COS_PresetLife("Balanced", 5);

DB_COS_PresetCategory("AllConvenience", "Core", 1);
DB_COS_PresetCategory("AllConvenience", "Origin", 1);
DB_COS_PresetCategory("AllConvenience", "RaceTags", 1);
DB_COS_PresetCategory("AllConvenience", "WeaponProficiencies", 1);
DB_COS_PresetCategory("AllConvenience", "ArmorProficiencies", 1);
DB_COS_PresetCategory("AllConvenience", "RacialAbilities", 1);
DB_COS_PresetCategory("AllConvenience", "Convenience", 1);
DB_COS_PresetLife("AllConvenience", 20);
```

Detection priority is exactly `AllConvenience`, `Balanced`, `NearVanilla`, `PureChaos`, `Custom`.

### Task 1: Add the fail-first category/preset contract verifier

**Files:**

- Create: `story-src/verify-category-presets.ps1`
- Modify: `story-src/verify.ps1:602-614`

- [ ] Create a verifier with explicit paths, exact sets, and a single assertion helper:

```powershell
#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    Require (Test-Path -LiteralPath $path -PathType Leaf) "缺少分类预设文件: $RelativePath"
    Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

$categories = [ordered]@{
    Core = 'COS_CFG_CATEGORY_CORE'
    Origin = 'COS_CFG_CATEGORY_ORIGIN'
    RaceTags = 'COS_CFG_CATEGORY_RACETAGS'
    WeaponProficiencies = 'COS_CFG_CATEGORY_WEAPON'
    ArmorProficiencies = 'COS_CFG_CATEGORY_ARMOR'
    RacialAbilities = 'COS_CFG_CATEGORY_RACIAL'
    Convenience = 'COS_CFG_CATEGORY_CONVENIENCE'
}
$legacyTables = @(
    'DB_COS_ConfigMechanic', 'DB_COS_ConfigLifeSkill', 'DB_COS_ConfigCost',
    'DB_COS_ConfigRacial', 'DB_COS_GrantSetting', 'DB_COS_TagSpellsSetting',
    'DB_COS_VoloEyeSetting', 'DB_COS_CarryEnabled'
)
$presetOrder = @('AllConvenience', 'Balanced', 'NearVanilla', 'PureChaos', 'Custom')
$forbiddenPresetWrites = @(
    'DB_COS_ConfigMechanic', 'DB_COS_ConfigRacial', 'DB_COS_GrantSetting',
    'DB_COS_TagSpellsSetting', 'DB_COS_VoloEyeSetting', 'DB_COS_CarryEnabled',
    'DB_COS_ConfigCost'
)

$story = Read-Required 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt'
$mechanics = Read-Required 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt'
$mastery = Read-Required 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMastery.txt'
$stats = Read-Required 'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt'
$keyboard = Read-Required 'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml'
$controller = Read-Required 'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml'

foreach ($key in $categories.Keys) {
    Require ($story.Contains("DB_COS_ConfigCategoryMap(`"$key`", `"$($categories[$key])`"")) "缺少分类映射: $key"
    Require ($stats.Contains("new entry `"$($categories[$key])`"")) "缺少分类镜像被动: $key"
}
Require ($story.Contains('DB_COS_ConfigCategorySchema(_Character, 1);')) '缺少分类结构版本提交'
foreach ($table in $legacyTables) {
    Require ($story.Contains("$table(_Character")) "旧档识别缺少表: $table"
}
foreach ($preset in $presetOrder) {
    Require ($story.Contains("DB_COS_PresetDetectionOrder(")) "缺少固定预设检测顺序"
    Require ($story.Contains("`"$preset`"")) "缺少预设检测项: $preset"
}
foreach ($page in @($keyboard, $controller)) {
    foreach ($event in 11..16) {
        $uuid = '7e990000-0000-4000-8000-{0:D12}' -f $event
        Require ($page.Contains($uuid)) "菜单缺少预设事件: $uuid"
    }
}
Write-Host '分类总开关与预设静态契约验证通过。'
```

- [ ] Extend this same script before integration with exact regex checks for all 28 preset category rows, four life rows, the five-item detection order, seven category events, six preset events, seven category mirrors, allowed preset writes, both-page XML parsing, four-language handle parity, no Chinese-copy fallback, six Goal paths, and 38 package paths.

- [ ] Add internal mutation probes. Each probe clones source text in memory, performs one exact mutation, calls the relevant assertion, and requires that it throws. Cover: delete one category, change one preset value, insert a child DB write in `PROC_COS_PresetApply`, remove a legacy table check, remove a combat guard, bypass preview, duplicate schema commit, alter one controller event, and replace one Japanese/Korean string with Chinese.

- [ ] Run the new verifier against the `.98` source before integrating it:

```powershell
Set-Location 'C:\Users\ankerlcg\Desktop\chaos-BG3-mod-story\.worktrees\native-core-config\story-src'
pwsh -NoProfile -File .\verify-category-presets.ps1
```

Expected: nonzero exit with `缺少分类映射: Core`. This proves the test detects the missing feature.

- [ ] Commit the fail-first verifier without wiring it into `verify.ps1` yet:

```powershell
git add story-src/verify-category-presets.ps1
git commit -m "test(story): define category preset contract"
```

### Task 2: Define category, preset, preview, actual-state, and error Stats

**Files:**

- Modify: `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt`
- Modify: `story-src/Localization/Chinese/ChaosOriginsStory.xml`
- Modify: `story-src/Localization/English/ChaosOriginsStory.xml`
- Modify: `story-src/Localization/Japanese/ChaosOriginsStory.xml`
- Modify: `story-src/Localization/Korean/ChaosOriginsStory.xml`

- [ ] Add seven no-boost mirror passives. Each entry uses its own display/description handles and no gameplay Boosts:

```text
new entry "COS_CFG_CATEGORY_CORE"
type "PassiveData"
data "DisplayName" "h7e990000g0000g4000g8000g000000000101"
data "Description" "h7e990000g0000g4000g8000g000000000102"
data "Properties" "Highlighted"
```

Create the exact set `CORE`, `ORIGIN`, `RACETAGS`, `WEAPON`, `ARMOR`, `RACIAL`, `CONVENIENCE`; allocate their name/description handles consecutively from `h7e990000g0000g4000g8000g000000000101` through `h7e990000g0000g4000g8000g000000000114` in that order. Do not add `Boosts`, `StatsFunctorContext`, spells, resources, or interrupts.

- [ ] Add five current-preset statuses:

```text
COS_PRESET_CURRENT_NEAR_VANILLA
COS_PRESET_CURRENT_PURE_CHAOS
COS_PRESET_CURRENT_BALANCED
COS_PRESET_CURRENT_ALL_CONVENIENCE
COS_PRESET_CURRENT_CUSTOM
```

All five use `StackId "COS_PRESET_CURRENT"` and `StatusPropertyFlags "DisableOverhead;DisableCombatlog;DisablePortraitIndicator;IgnoreResting"`.

- [ ] Add four pending statuses with `StackId "COS_PRESET_PENDING"`, fourteen category preview statuses using the seven exact stack IDs `COS_PRESET_PREVIEW_CORE`, `COS_PRESET_PREVIEW_ORIGIN`, `COS_PRESET_PREVIEW_RACETAGS`, `COS_PRESET_PREVIEW_WEAPON`, `COS_PRESET_PREVIEW_ARMOR`, `COS_PRESET_PREVIEW_RACIAL`, and `COS_PRESET_PREVIEW_CONVENIENCE`, and three life preview statuses for `0`, `5`, and `20` with `StackId "COS_PRESET_PREVIEW_LIFE"`:

```text
COS_PRESET_PENDING_NEAR_VANILLA
COS_PRESET_PENDING_PURE_CHAOS
COS_PRESET_PENDING_BALANCED
COS_PRESET_PENDING_ALL_CONVENIENCE

COS_PRESET_PREVIEW_CORE_ON
COS_PRESET_PREVIEW_CORE_OFF
COS_PRESET_PREVIEW_ORIGIN_ON
COS_PRESET_PREVIEW_ORIGIN_OFF
COS_PRESET_PREVIEW_RACETAGS_ON
COS_PRESET_PREVIEW_RACETAGS_OFF
COS_PRESET_PREVIEW_WEAPON_ON
COS_PRESET_PREVIEW_WEAPON_OFF
COS_PRESET_PREVIEW_ARMOR_ON
COS_PRESET_PREVIEW_ARMOR_OFF
COS_PRESET_PREVIEW_RACIAL_ON
COS_PRESET_PREVIEW_RACIAL_OFF
COS_PRESET_PREVIEW_CONVENIENCE_ON
COS_PRESET_PREVIEW_CONVENIENCE_OFF

COS_PRESET_PREVIEW_LIFE_0
COS_PRESET_PREVIEW_LIFE_5
COS_PRESET_PREVIEW_LIFE_20
```

- [ ] Add five actual-state statuses for each of the seven categories. Use one category-specific StackId per row and these suffixes:

```text
ACTIVE
PAUSED
WAITING_CONDITION
MISSING_CONFIG
SYNC_FAILED
```

For example, Core defines `COS_CATEGORY_ACTUAL_CORE_ACTIVE` through `COS_CATEGORY_ACTUAL_CORE_SYNC_FAILED`, all using `StackId "COS_CATEGORY_ACTUAL_CORE"`. Repeat with exact category tokens `ORIGIN`, `RACETAGS`, `WEAPON`, `ARMOR`, `RACIAL`, `CONVENIENCE`.

- [ ] Add four explicit-error statuses using `StackId "COS_PRESET_ERROR"`:

```text
COS_PRESET_ERROR_NO_SELECTION
COS_PRESET_ERROR_COMBAT_READONLY
COS_PRESET_ERROR_CONFIG_INCOMPLETE
COS_PRESET_ERROR_SYNC_FAILED
```

- [ ] For every status in this task, require empty Boosts and the same hidden diagnostic flags. Add semantically complete Chinese, English, Japanese, and Korean strings; do not copy Chinese into non-Chinese sources.

- [ ] Run the focused verifier. Expected: it advances past Stats/localization checks and fails on missing Story category initialization.

```powershell
pwsh -NoProfile -File .\verify-category-presets.ps1
```

- [ ] Commit:

```powershell
git add story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt story-src/Localization
git commit -m "feat(story): define category preset states"
```

### Task 3: Add per-character category initialization and mirrors

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt`
- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt`
- Test: `story-src/verify-category-presets.ps1`
- Test: `story-src/verify-carry-toggle.ps1`

- [ ] Seed the seven category maps and events idempotently in `PROC_COS_ConfigSeedCategories()`. Every seed rule must use a matching `NOT DB_...` guard.

```text
DB_COS_ConfigCategoryMap("Core", "COS_CFG_CATEGORY_CORE");
DB_COS_ConfigCategoryMap("Origin", "COS_CFG_CATEGORY_ORIGIN");
DB_COS_ConfigCategoryMap("RaceTags", "COS_CFG_CATEGORY_RACETAGS");
DB_COS_ConfigCategoryMap("WeaponProficiencies", "COS_CFG_CATEGORY_WEAPON");
DB_COS_ConfigCategoryMap("ArmorProficiencies", "COS_CFG_CATEGORY_ARMOR");
DB_COS_ConfigCategoryMap("RacialAbilities", "COS_CFG_CATEGORY_RACIAL");
DB_COS_ConfigCategoryMap("Convenience", "COS_CFG_CATEGORY_CONVENIENCE");
```

- [ ] Implement exact legacy detection. `PROC_COS_ConfigDetectPreexisting(_Character)` clears `DB_COS_ConfigPreexisting(_Character)` and calls eight dedicated probes. Each probe adds the flag when that character has any row in exactly one approved table:

```text
DB_COS_ConfigMechanic
DB_COS_ConfigLifeSkill
DB_COS_ConfigCost
DB_COS_ConfigRacial
DB_COS_GrantSetting
DB_COS_TagSpellsSetting
DB_COS_VoloEyeSetting
DB_COS_CarryEnabled
```

Do not inspect mirror passives, resources, tags, statuses, level, party membership, or runtime diagnostic DBs to classify the save.

- [ ] Implement new-character initialization. When no schema and no preexisting flag exist, insert this exact state before any existing ensure procedure runs:

```text
Core=0
Origin=1
RaceTags=0
WeaponProficiencies=0
ArmorProficiencies=0
RacialAbilities=0
Convenience=0
DB_COS_ConfigLifeSkill(_Character, 0)
```

- [ ] Implement legacy initialization. When no schema but a preexisting flag exists, insert all seven category values as `1` and do not write any existing child or life-skill row.

- [ ] Commit the schema only in a rule whose conditions bind all seven exact rows:

```text
PROC
PROC_COS_ConfigCommitCategorySchema((CHARACTER)_Character)
AND DB_COS_ConfigCategory(_Character, "Core", _)
AND DB_COS_ConfigCategory(_Character, "Origin", _)
AND DB_COS_ConfigCategory(_Character, "RaceTags", _)
AND DB_COS_ConfigCategory(_Character, "WeaponProficiencies", _)
AND DB_COS_ConfigCategory(_Character, "ArmorProficiencies", _)
AND DB_COS_ConfigCategory(_Character, "RacialAbilities", _)
AND DB_COS_ConfigCategory(_Character, "Convenience", _)
AND NOT DB_COS_ConfigCategorySchema(_Character, _)
THEN
DB_COS_ConfigCategorySchema(_Character, 1);
```

- [ ] Make `PROC_COS_ConfigInitializeCategories(_Character)` the first action in `PROC_COS_ConfigSyncCharacter`. Only after it returns may existing ensure procedures seed missing child settings.

- [ ] Apply the same first-action rule at every lifecycle-reachable boundary that can seed any of the eight legacy-probe tables: the legacy-writing `PROC_COS_Sync` rule in `COS_ChaosMechanics.txt`, `PROC_COS_SyncGlobalPlayerBenefits`, `PROC_COS_ConfigSyncGrants`, and `PROC_COS_SyncVoloEye`. Together with `PROC_COS_ConfigSyncCharacter`, these are the exact five guarded entry points. Verify all five explicitly and mutation-test removal or downshifting at each newly guarded boundary so a new character cannot be misclassified as a legacy save.

- [ ] Implement `PROC_COS_ConfigSyncCategoryMirrors`. Add a category mirror passive only for value `1`; remove it for value `0`. Missing rows are errors and must not be treated as enabled or disabled.

- [ ] Implement category toggle handlers for the seven fixed TutorialEvents. Every handler must include:

```text
HasPassive(_Character, "COS_ChaosOriginMarker", 1)
IsControlled(_Character, 1)
IsInCombat(_Character, 0)
DB_COS_ConfigCategorySchema(_Character, 1)
```

At this stage, toggle only the matching `DB_COS_ConfigCategory` row, call one unified sync, and refresh diagnostics. Task 4 inserts actual-state recalculation after the sync; Task 5 then inserts preset recalculation before actual-state recalculation. The final order remains unified sync, preset detection, actual-state refresh, diagnostics.

- [ ] Add all seven events to `PROC_COS_ConfigEnableEvents` and verify repeat calls remain idempotent.

- [ ] Extend mutation tests to prove: a partial legacy save is classified as legacy; existing life value is untouched; new-character life is exactly `0`; schema cannot be committed with six rows; a second initialization cannot rewrite any category.

- [ ] Run:

```powershell
pwsh -NoProfile -File .\verify-category-presets.ps1 -Focus Task3
pwsh -NoProfile -File .\verify-carry-toggle.ps1
pwsh -NoProfile -File .\compile-story.ps1
```

Expected: focused verifier passes initialization checks; Story compiler exits `0`.

- [ ] Commit:

```powershell
git add story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt story-src/verify-category-presets.ps1 story-src/verify-carry-toggle.ps1
git commit -m "feat(story): persist category master switches"
```

### Task 4: Gate runtime effects without overwriting child choices

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_BaseAfterCreation.txt`
- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt`
- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMastery.txt`
- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt`
- Test: `story-src/verify-category-presets.ps1`
- Test: `story-src/verify-grant-menu.ps1`
- Test: `story-src/verify-carry-toggle.ps1`

- [ ] Add `DB_COS_ConfigCategory((CHARACTER)_Character, "Core", 1)` beside every gameplay-time enabled `DB_COS_ConfigMechanic` condition in `COS_ChaosMechanics.txt` and `COS_ChaosMastery.txt`. Do not add the guard to default seeding, configuration mutation, diagnostics, or mirror synchronization.

- [ ] Split grant options by their existing `grant-menu.json` group without modifying `DB_COS_GrantSetting`:

```text
Origin -> Origin
Tag -> RaceTags
Weapon -> WeaponProficiencies
Armor -> ArmorProficiencies
```

`Instrument` remains outside the seven new category masters in `.99`; preserve its existing behavior and configuration exactly.

- [ ] Change grant application to collect effective desired rows first. Only an enabled category and an enabled child row may create a desired row. Removal remains ownership-protected:

```text
DB_COS_GrantTagOwned(_Character, _Tag)
NOT DB_COS_NativeGrantTag(_Character, _Tag)
```

Never clear a tag or passive without the module’s existing ownership/mirror proof.

- [ ] Gate racial passive synchronization with `RacialAbilities=1`. When paused, remove only passives recorded as module-owned; never remove a captured native racial passive.

- [ ] Gate all four `Convenience` consumers while preserving child settings:

```text
DB_COS_TagSpellsSetting
DB_COS_CarryEnabled
DB_COS_VoloEyeSetting
COS_FIXED_GUIDANCE_30
```

The starting adventurer bag remains excluded: do not regrant, reclaim, or alter its one-time marker.

- [ ] Add the owning category guard to every individual and bulk mutation event, so direct TutorialEvent dispatch cannot change a child while its category is paused. Keep combat, origin-marker, and controlled-character guards.

- [ ] Implement actual-state resolution with deterministic priority for each category:

```text
missing category/required child record -> MISSING_CONFIG
category value 0 -> PAUSED
eligible desired effect missing or module-owned undesired effect present -> SYNC_FAILED
all enabled children currently blocked by level/task/character conditions -> WAITING_CONDITION
otherwise -> ACTIVE
```

Apply exactly one actual-state status per category StackId.

- [ ] Extend `PROC_COS_ConfigToggleCategory` by inserting `PROC_COS_ConfigSyncCategoryActual(_Character)` after the unified sync and before diagnostics. Do not add preset detection in this task.

- [ ] Extend tests to parse all runtime `DB_COS_ConfigMechanic(..., 1)` consumers and require the Core guard, prove category-off child DB text remains byte-for-byte unchanged, prove `Instrument` is unchanged, and prove unowned tags/passives cannot enter a removal action.

- [ ] Run focused verifier, existing ownership verifiers, and Story compiler:

```powershell
pwsh -NoProfile -File .\verify-category-presets.ps1
pwsh -NoProfile -File .\verify-grant-menu.ps1
pwsh -NoProfile -File .\verify-volo-eye.ps1
pwsh -NoProfile -File .\verify-tag-spells.ps1
pwsh -NoProfile -File .\verify-carry-toggle.ps1
pwsh -NoProfile -File .\compile-story.ps1
```

Expected: all commands exit `0`.

- [ ] Commit:

```powershell
git add story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals story-src/verify-category-presets.ps1
git commit -m "feat(story): gate effects by category"
```

### Task 5: Implement derived presets, preview, apply, cancel, and errors

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- Test: `story-src/verify-category-presets.ps1`

- [ ] Seed the fixed preset matrix and detection order from the tables at the top of this plan. Guard every seed row against duplicates.

- [ ] Implement current-preset detection without saving a preset name. Clear candidate scratch rows, test in the exact order `AllConvenience`, `Balanced`, `NearVanilla`, `PureChaos`, then `Custom`, and apply exactly one `COS_PRESET_CURRENT_*` status.

- [ ] Treat `PureChaos/Origin=-1` as a wildcard in both detection and apply. It must never change the current `Origin` category value.

- [ ] Implement `PROC_COS_PresetClearPreview(_Character)` to clear only:

```text
DB_COS_PresetPending(_Character, _)
DB_COS_PresetPreviewCategory(_Character, _, _)
DB_COS_PresetPreviewLife(_Character, _)
COS_PRESET_PENDING_*
COS_PRESET_PREVIEW_*
COS_PRESET_ERROR_*
```

It must not write categories, life value, child settings, costs, resources, statuses from other systems, or ownership records.

- [ ] Implement four select handlers. Each validates origin marker, control, non-combat, and schema; clears the previous preview; records one pending preset; compares each non-wildcard target with the current category; records only differences; compares the preset life value; and emits only the corresponding preview statuses. Selecting does not call unified sync.

- [ ] Implement cancel with the same mutation guards. Cancel calls only `PROC_COS_PresetClearPreview` and current-preset/diagnostic refresh.

- [ ] Implement apply with this fixed order:

```text
validate pending selection
validate non-combat controlled Chaos Origin
validate schema and all seven category rows
validate DB_COS_ConfigLifeSkill exists
rewrite only changed non-wildcard category rows
rewrite life skill to preset target
call PROC_COS_ConfigSyncCharacter once
derive current preset and category actual states
validate target fields
clear preview only after successful validation
refresh runtime diagnostics
```

- [ ] Apply explicit errors. No pending preset produces `COS_PRESET_ERROR_NO_SELECTION`; combat attempts produce `COS_PRESET_ERROR_COMBAT_READONLY`; missing required records produce `COS_PRESET_ERROR_CONFIG_INCOMPLETE`; a post-sync mismatch produces `COS_PRESET_ERROR_SYNC_FAILED` and retains the mismatch scratch row for diagnostics.

- [ ] In `PROC_COS_ConfigSyncCharacter`, menu-open handling, category toggles, and life-skill changes, recalculate the current preset after the effective state is synchronized. For `PROC_COS_ConfigToggleCategory`, insert `PROC_COS_PresetDetect(_Character)` between the unified sync and the Task 4 actual-state call, yielding the final fixed order: unified sync, preset detection, actual-state refresh, diagnostics. Reopening the menu and `GainedControl` clear stale pending preview before presenting the new controlled character.

- [ ] Extend verifier AST/block checks so every `PROC_COS_Preset*` action is on an allowlist. Preset application may mutate only category rows, life rows, preset scratch/status rows, actual-state rows, and runtime diagnostic rows. Reject writes to the seven forbidden child/config-cost tables listed in Task 1.

- [ ] Run:

```powershell
pwsh -NoProfile -File .\verify-category-presets.ps1
pwsh -NoProfile -File .\compile-story.ps1
```

Expected: both exit `0`; mutation probes report that every injected violation was rejected.

- [ ] Commit:

```powershell
git add story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt story-src/verify-category-presets.ps1
git commit -m "feat(story): add previewed configuration presets"
```

### Task 6: Build matching keyboard and controller native menu layouts

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml`
- Modify: `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml`
- Modify: four files under `story-src/Localization/*/ChaosOriginsStory.xml`
- Test: `story-src/verify-category-presets.ps1`

- [ ] Insert a `COSPresetPanel` immediately after `COSRuntimeDiagnosticPanel` and before `COSConfigOverview` on both pages. Use the existing gold `LSButton` template. Layout the four preset buttons in a centered two-column grid and the apply/cancel buttons in a centered two-column grid.

- [ ] Bind current configuration to `CurrentPlayer.SelectedCharacter.StatusEffects`. Show exactly one localized name for the five `COS_PRESET_CURRENT_*` statuses.

- [ ] Bind preview rows to the 17 approved `COS_PRESET_PREVIEW_*` statuses. The panel is absent when no preview status exists. Include one fixed line: “逐项选择不会被删除。” in all four languages.

- [ ] Give all six preset buttons the fixed TutorialEvent UUIDs from this plan. Keyboard buttons receive pointer click actions; controller buttons use `BoundEvent="UIAccept"`, `ls:MoveFocus.Focusable="True"`, and an explicit left/right/up/down focus chain with no dead end.

- [ ] Before each existing category section, add one category master row containing localized name, category toggle, configured state, and actual-state text. The toggle checkmark is driven only by its `COS_CFG_CATEGORY_*` mirror passive.

- [ ] Overlay each paused category’s child grid with a hit-testable gray panel created from its corresponding paused status: `COS_CATEGORY_ACTUAL_CORE_PAUSED`, `COS_CATEGORY_ACTUAL_ORIGIN_PAUSED`, `COS_CATEGORY_ACTUAL_RACETAGS_PAUSED`, `COS_CATEGORY_ACTUAL_WEAPON_PAUSED`, `COS_CATEGORY_ACTUAL_ARMOR_PAUSED`, `COS_CATEGORY_ACTUAL_RACIAL_PAUSED`, or `COS_CATEGORY_ACTUAL_CONVENIENCE_PAUSED`. The overlay text is “分类已暂停，选择仍已保存。” The overlay must not cover the category master toggle or actual-state text. Story guards remain authoritative even if UI events are injected directly.

- [ ] Retain existing child “全部开启/全部取消” buttons. Do not restore the deleted summary dropdown. Do not move Fate/Genesis cost sliders, and do not place Genesis under life-skill controls.

- [ ] Retain the current combat read-only layer and extend it over preset selection, apply/cancel, category masters, and all child mutation controls. Diagnostic and actual-state text remains readable.

- [ ] Parse both XAML files as XML in the verifier and compare exact named-node sets, event UUID sets, status ID sets, panel order, button order, preview order, and focus graph. Do not compare raw bytes because keyboard/controller attributes legitimately differ.

- [ ] Compile localization and GUI resources:

```powershell
pwsh -NoProfile -File .\verify-category-presets.ps1
pwsh -NoProfile -File .\compile-resources.ps1
```

Expected: both exit `0`; no missing handle, duplicate handle, XML, XAML, or focus-graph error.

- [ ] Commit:

```powershell
git add story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu*.xaml story-src/Localization story-src/verify-category-presets.ps1
git commit -m "feat(ui): add native category preset controls"
```

### Task 7: Integrate diagnostics and the full verification suite

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- Modify: `story-src/verify-runtime-diagnostics.ps1`
- Modify: `story-src/verify-category-presets.ps1`
- Modify: `story-src/verify.ps1`

- [ ] Extend runtime diagnostics with deterministic checks after the existing eight legacy configuration families:

```text
category schema missing
first missing category row in fixed seven-key order
first category mirror mismatch in fixed seven-key order
preset apply failed
first post-apply category mismatch in fixed seven-key order
post-apply life mismatch
```

Do not use database enumeration order or random selection. Diagnostics remain read-only except their own scratch/status rows.

- [ ] Add the new focused verifier to the main suite immediately after `verify-runtime-diagnostics.ps1` dependencies are available and before full Story compilation:

```powershell
& (Join-Path $PSScriptRoot 'verify-category-presets.ps1')
```

- [ ] Add full-suite regression assertions for the two necessary extra Goal edits: all gameplay-time Core consumers are guarded, while config seeding and diagnostic blocks remain unguarded and readable.

- [ ] Run focused and full verification from a clean worktree:

```powershell
git status --short
pwsh -NoProfile -File .\verify-category-presets.ps1
pwsh -NoProfile -File .\verify.ps1
```

Expected: `git status --short` lists only the current task’s intended files before commit; both verifiers exit `0`; package manifest still reports `38` paths and six Goal paths.

- [ ] Commit:

```powershell
git add story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt story-src/verify-runtime-diagnostics.ps1 story-src/verify-category-presets.ps1 story-src/verify.ps1
git commit -m "test(story): verify category preset runtime"
```

### Task 8: Review against the confirmed specification

**Files:**

- Review: all files changed by Tasks 1-7
- Review: `docs/superpowers/specs/2026-09-14-category-presets-design.md`

- [ ] Compare every design section with the diff. Record a checkbox result for: seven categories, four preset matrices, PureChaos wildcard, new/legacy classification, per-character ownership, child preservation, preview-only selection, combat lock, actual state, four-language parity, package invariants, and explicit failures.

- [ ] Search for unfinished or guessed implementation text:

```powershell
$unfinished = @('TO' + 'DO', 'TB' + 'D', 'place' + 'holder', '临时兼容', '猜测默认') -join '|'
rg -n -i $unfinished story-src docs/superpowers
```

Expected: no new unfinished marker and no silent fallback path.

- [ ] Inspect the diff and confirm no unrelated user changes were modified:

```powershell
git diff --check
git diff --stat 9dd2e37..HEAD
git status --short
```

Expected: no whitespace error; only the approved files appear.

- [ ] Run final pre-build verification one more time:

```powershell
Set-Location 'C:\Users\ankerlcg\Desktop\chaos-BG3-mod-story\.worktrees\native-core-config\story-src'
pwsh -NoProfile -File .\verify.ps1
```

Expected: exit `0` with Story compile, IR attestation, Stats/resource compile, localization, GUI, package-path, and mutation checks passing.

- [ ] Commit any review-only verifier correction, then ensure the tree is clean:

```powershell
git status --short
```

Expected: no output.

### Task 9: Build exactly one 1.0.1.99 release candidate

**Files:**

- Modify automatically after successful build: `story-src/version.json`
- Modify automatically after successful build: `story-src/Mods/ChaosOriginsStory/meta.lsx`
- Create: `dist/ChaosOriginsStory.pak`
- Create: `dist/build-manifest.json`
- Create: `story-src/docs/RELEASE-1.0.1.99.md`

- [ ] Confirm the build input is `.98`, the worktree is clean, and the expected Version64 is `36028799166447715`:

```powershell
Get-Content .\version.json
git status --short
```

Expected: `lastBuild` is `98`; no status output.

- [ ] Run the build once:

```powershell
pwsh -NoProfile -File .\build.ps1
```

Expected: `Story 最终候选 PAK 构建并反向校验完成: 1.0.1.99 (36028799166447715)` and exactly `38 files`.

- [ ] Verify the produced version, manifest, reverse-unpacked file count, and hashes:

```powershell
Get-Content .\version.json
Get-Content ..\dist\build-manifest.json
(Get-FileHash -Algorithm SHA256 ..\dist\ChaosOriginsStory.pak).Hash
git status --short
```

Expected: source version is `.99`; manifest version and Version64 match; only build-produced version/meta files plus release documentation remain to commit.

- [ ] Write `story-src/docs/RELEASE-1.0.1.99.md` with: source commit, Version64, 38-file/six-Goal proof, focused/full verifier results, Story IR hash, PAK SHA-256, rollback baseline `.98`, install target, and “game acceptance pending.”

- [ ] Commit and push the source and release record to the authorized branch:

```powershell
git add story-src/version.json story-src/Mods/ChaosOriginsStory/meta.lsx story-src/docs/RELEASE-1.0.1.99.md dist/ChaosOriginsStory.pak dist/build-manifest.json
git commit -m "release(story): build 1.0.1.99"
git push github codex/native-core-config
git rev-parse HEAD
git ls-remote github refs/heads/codex/native-core-config
```

Expected: local HEAD equals the remote branch hash. If push fails, report the error; do not claim a backup exists.

### Task 10: Export and install the verified candidate

**Files:**

- Export: `C:\Users\ankerlcg\Desktop\博德之门3mod\ChaosOriginsStory-1.0.1.99.pak`
- Install: `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak`
- Modify only this module’s version field in: `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\PlayerProfiles\Public\modsettings.lsx`

- [ ] Read process state. If `bg3.exe` or `bg3_dx11.exe` is running, close the game before replacing the PAK; preserve Steam, launchers, drivers, security tools, Explorer, and Codex.

- [ ] Resolve the three exact source/export/install paths and calculate the source hash before copying. Create only the requested `博德之门3mod` directory if absent; do not create a backup directory on Desktop.

- [ ] Copy the same verified PAK to export and install targets, then update only ChaosOriginsStory’s `Version64` to `36028799166447715` in `modsettings.lsx`. Preserve every other module and the existing load order.

- [ ] Verify uniqueness and equality:

```powershell
Get-FileHash -Algorithm SHA256 'C:\Users\ankerlcg\Desktop\chaos-BG3-mod-story\.worktrees\native-core-config\dist\ChaosOriginsStory.pak'
Get-FileHash -Algorithm SHA256 'C:\Users\ankerlcg\Desktop\博德之门3mod\ChaosOriginsStory-1.0.1.99.pak'
Get-FileHash -Algorithm SHA256 "$env:LOCALAPPDATA\Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak"
```

Expected: all three hashes are identical; exactly one installed `ChaosOriginsStory.pak` exists; exactly one active `a5062238-0d2b-46d1-a093-cb02775b9f57` entry exists with the new version.

- [ ] Do not launch the game automatically unless the user asks. Report source/build/hash/install evidence separately from in-game acceptance.

### Task 11: In-game acceptance handoff

- [ ] Ask the user to test the exact ten acceptance cases in the confirmed design: new character default, `.98` legacy preservation, four preset preview/cancel/apply paths, category pause/restore, derived Custom state, combat read-only, persistence across lifecycle events, keyboard/controller parity, and clean logs.

- [ ] Mark `1.0.1.99` as “installed test candidate” until the user reports those behaviors. Static checks, compilation, hashes, and installation are not evidence of runtime acceptance.

- [ ] If a runtime defect appears, preserve `.98` as the rollback baseline, first add a regression that fails for the observed defect, make the smallest Story/UI change, rerun the full suite, and increment the build number again. Never rebuild a different artifact under `1.0.1.99`.
