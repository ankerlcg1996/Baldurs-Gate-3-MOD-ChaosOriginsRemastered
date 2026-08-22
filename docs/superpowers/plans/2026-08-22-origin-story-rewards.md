# Origin Story Rewards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every level-based origin reward with official story-flag-driven rewards, add the approved Gale/Dark Urge behavior, and move the retained 100000-XP test grant behind a default-off per-character MCM switch.

**Architecture:** `OriginFeatures.lua` remains responsible only for identity toggles, official origin tags, and immediate abilities. A new `OriginStoryRewards.lua` owns declarative story rules, persistent claim/consumption state, status replacement, and spell-cast consequences; `BootstrapServer.lua` only schedules synchronization and exposes host-authoritative MCM actions. Static contracts in `verify.ps1` are written before implementation, and every independently reversible slice is committed before the next slice.

**Tech Stack:** Baldur's Gate 3 Script Extender Lua, Osiris calls/events, BG3MCM network UI, persistent `Ext.Vars`, PowerShell verification/build scripts, LSLib V18 PAK packaging, Git.

---

## File map

- Create `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/OriginStoryRewards.lua`: official Flag catalog, claim/consume synchronization, Gale god status, Karlach stage replacement, Dark Urge one-shot handling, Gale orb game-over handling.
- Modify `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/ChaosState.lua`: schema 7 migration and strict story-reward/test-XP persistence.
- Modify `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/GrantLedger.lua`: MOD-owned status application/removal with the same asynchronous verification rules as passives/spells/tags.
- Modify `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/OriginFeatures.lua`: keep only base abilities and identity tags; remove all level thresholds.
- Modify `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/BootstrapServer.lua`: synchronize story rewards, register Flag/spell listeners, and enforce the default-off XP switch.
- Modify `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/McmProtocol.lua`: protocol v4 and the test-XP localization handle.
- Modify `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/BootstrapClient.lua`: render and synchronize the test-XP checkbox.
- Modify `verify.ps1`: add exact static contracts before each implementation slice and update Lua/package counts.
- Modify `build.ps1` and `package-files.json`: package the sixteenth Lua module and require exactly 34 PAK paths.
- Modify all four `localization-src/*/ChaosOriginsRemastered.xml` files, `README.md`, and `source/Mods/ChaosOriginsRemastered/meta.lsx`: describe story-driven rewards and the default-off XP test switch.
- Modify `version.json` and `source/Mods/ChaosOriginsRemastered/meta.lsx` only through `build.ps1`: release v1.0.21 after verification succeeds.

### Task 1: Add failing schema and status-ledger contracts

**Files:**
- Modify: `verify.ps1:220-261`
- Test: `verify.ps1`

- [ ] **Step 1: Commit the current clean baseline check**

Run:

```powershell
git status --short
git log -1 --oneline
```

Expected: no status output; HEAD is `cb283de docs: design origin story rewards`.

- [ ] **Step 2: Write the failing schema-7 contracts**

Replace the schema token block and extend the ledger checks with these exact assertions:

```powershell
foreach ($token in @('SCHEMA_VERSION = 7', 'state.SchemaVersion == 6',
    'OriginStoryRewards', 'Claimed', 'Consumed', 'OriginStoryGranted',
    'Statuses', 'TestLevel12Experience = false')) {
    Require ($stateLua.Contains($token)) "Story reward state contract is missing: $token"
}
foreach ($token in @('function M.EnsureStatus', 'function M.RemoveStatus',
    'Osi.HasActiveStatus', 'Osi.ApplyStatus', 'Osi.RemoveStatus')) {
    Require ($grantLedgerLua.Contains($token)) "Grant ledger status support is missing: $token"
}
```

Keep the existing schema 1-5 tokens, but change `SCHEMA_VERSION = 6` to `SCHEMA_VERSION = 7`.

- [ ] **Step 3: Run the contracts and verify they fail for the intended reason**

Run:

```powershell
.\verify.ps1
```

Expected: failure containing `Story reward state contract is missing: SCHEMA_VERSION = 7`; no unrelated parse error.

- [ ] **Step 4: Commit only the failing contract**

```powershell
git add verify.ps1
git commit -m "test: require origin story reward persistence"
```

Expected: one commit containing only `verify.ps1`.

### Task 2: Persist story claims, consumption, statuses, and the XP switch

**Files:**
- Modify: `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/ChaosState.lua:5-279`
- Modify: `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/GrantLedger.lua:95-201`
- Test: `verify.ps1`

- [ ] **Step 1: Add strict Boolean-map validation and schema-7 fields**

Set `SCHEMA_VERSION = 7`. Add this validator next to `validateGrantMap`:

```lua
local function validateBooleanMap(value, label)
    assert(type(value) == "table", "ChaosOriginsRemastered: " .. label .. " must be a table")
    for key, enabled in pairs(value) do
        assert(type(key) == "string" and enabled == true,
            "ChaosOriginsRemastered: invalid " .. label .. " entry " .. tostring(key))
    end
end
```

Add these keys to `validateCharacter`'s `assertOnlyKeys`, then validate them exactly:

```lua
validateBooleanMap(record.OriginStoryRewards.Claimed, "claimed origin story reward")
validateBooleanMap(record.OriginStoryRewards.Consumed, "consumed origin story reward")
assertOnlyKeys(record.OriginStoryGranted,
    { Passives = true, Spells = true, Statuses = true }, "origin story grant ledger")
validateGrantMap(record.OriginStoryGranted.Passives, "origin story passive grant ledger")
validateGrantMap(record.OriginStoryGranted.Spells, "origin story spell grant ledger")
validateGrantMap(record.OriginStoryGranted.Statuses, "origin story status grant ledger")
assert(type(record.TestLevel12Experience) == "boolean",
    "ChaosOriginsRemastered: TestLevel12Experience must be boolean")
```

Add the default fields to `newCharacter()`:

```lua
OriginStoryRewards = { Claimed = {}, Consumed = {} },
OriginStoryGranted = { Passives = {}, Spells = {}, Statuses = {} },
TestLevel12Experience = false,
```

- [ ] **Step 2: Add the schema-6-to-7 migration**

Insert after the schema-5 migration:

```lua
-- schema 5 迁移完成后必须先落到 6，不能直接跳过下面的剧情奖励迁移。
-- 因此把 schema-5 分支原有的 `state.SchemaVersion = SCHEMA_VERSION` 改为：
state.SchemaVersion = 6

if state.SchemaVersion == 6 then
    -- 1.0.20 以前没有剧情奖励账本，测试经验也始终自动发放。
    for _, record in pairs(state.Characters) do
        record.OriginStoryRewards = { Claimed = {}, Consumed = {} }
        record.OriginStoryGranted = { Passives = {}, Spells = {}, Statuses = {} }
        record.TestLevel12Experience = false
    end
    state.SchemaVersion = SCHEMA_VERSION
    M.MarkDirty()
end
```

Do not alter `OriginGranted`: old level-owned entries must remain visible so the refactored `OriginFeatures.Sync` can remove only entries this MOD previously claimed.

- [ ] **Step 3: Add status operations to the generic grant ledger**

Insert before `ResetRuntime()`:

```lua
function M.EnsureStatus(character, record, status, ledger)
    assert(type(ledger) == "table", "ChaosOriginsRemastered: status ledger is unavailable")
    return start(character, status, "status", 1,
        function(target, statId, expected) return Osi.HasActiveStatus(target, statId) == expected end,
        function(target, statId, desired)
            if desired == 1 then Osi.ApplyStatus(target, statId, -1.0, 100, target)
            else Osi.RemoveStatus(target, statId, target) end
        end,
        ledger, true)
end

function M.RemoveStatus(character, record, status, ledger)
    assert(ledger[status] == true or ledger[status] == "adding"
        or ledger[status] == "removing",
        "ChaosOriginsRemastered: cannot remove unowned status " .. status)
    return start(character, status, "status", 0,
        function(target, statId, expected) return Osi.HasActiveStatus(target, statId) == expected end,
        function(target, statId, desired)
            if desired == 1 then Osi.ApplyStatus(target, statId, -1.0, 100, target)
            else Osi.RemoveStatus(target, statId, target) end
        end,
        ledger, true)
end
```

- [ ] **Step 4: Run verification**

Run:

```powershell
.\verify.ps1
```

Expected: `ChaosOriginsRemastered source verification: ok`.

- [ ] **Step 5: Commit the persistence slice**

```powershell
git add source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/ChaosState.lua source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/GrantLedger.lua
git commit -m "feat: persist origin story rewards"
```

### Task 3: Add failing runtime/catalog/package contracts

**Files:**
- Modify: `verify.ps1:190-261,601-610`
- Modify: `build.ps1:55-58`
- Modify: `package-files.json`
- Test: `verify.ps1`

- [ ] **Step 1: Require the new module and 34-file package**

Add `OriginStoryRewards.lua` to `$expectedLuaFiles`, change both exact package counts from 33 to 34, and insert this manifest entry next to `OriginFeatures.lua`:

```json
"Mods/ChaosOriginsRemastered/ScriptExtender/Lua/OriginStoryRewards.lua",
```

- [ ] **Step 2: Add exact catalog and forbidden-level contracts**

After reading `OriginFeatures.lua`, read the new module and assert every approved identifier:

```powershell
$storyRewardsLua = Get-Content -Raw -LiteralPath (Join-Path $luaRoot 'OriginStoryRewards.lua') -Encoding UTF8
$storyTokens = @(
    'ORI_Astarion_State_BecameVampireLord_c446ce94-efd8-45d5-b407-284177b6b57e',
    'LOW_Astarion_VampireAscendant', 'Shout_EPI_Astarion_TurnIntoBat',
    'ORI_Gale_Event_BombDisarmed_3d014e79-5595-9365-87bb-5cbb1f87fe5c',
    'Target_END_Gale_ActivateNethereseOrb',
    'ORI_Gale_State_AbsorbedTWNBossPower_7d08986a-5410-ccdf-fe70-aaec379a1962',
    'ORI_Gale_ShadowSpellSlots',
    'ORI_Gale_State_CraftedDarkLantern_3ddebb12-8c9f-47b4-8b6a-bb8eeac51a9b',
    'Target_ORI_Gale_ShadowSummon',
    'ORI_Gale_State_IsGod_ec94f9a4-b032-ce25-f4eb-ecf4ed37d65d',
    'EPI_GALEGOD', 'EPI_GALEGOD_MINDFLAYER',
    'FULL_CEREMORPH_3797bfc4-8004-4a19-9578-61ce0714cc0b',
    'CAMP_MizorasJudgement_Event_Reward_eb10f6f8-cf1a-a2b2-4421-63b0fbeb7a23',
    'Shout_ORI_Wyll_FireShield_Warm',
    'COL_MizorasRescue_Event_Reward_0e2f2a09-604c-2b9d-b8c0-db2baa1e6ac8',
    'Target_ORI_Wyll_SummonCambion', 'c774d764-4a17-48dc-b470-32ace9ce447d',
    'GLO_ForgingOfTheHeart_State_KarlachUpgraded_a818e2f5-9e0c-4ab3-8c1e-00765d3b892f',
    'ORI_KARLACH_FIRSTUPGRADE',
    'GLO_ForgingOfTheHeart_State_KarlachSecondUpgrade_f6dc0de4-1089-43c0-b392-306a9a44387c',
    'ORI_KARLACH_SECONDUPGRADE',
    'ORI_DarkUrge_State_GivenSlayerForm_14aec5bc-1013-4845-96ca-20722c5219e3',
    'Shout_DarkUrge_Slayer',
    'ORI_DarkUrge_State_BhaalAccepted_904c45e0-bb06-40ed-b5d7-4f1c851b9d86',
    'Target_LOW_DarkUrge_PowerWordKill'
)
foreach ($token in $storyTokens) {
    Require ($storyRewardsLua.Contains($token)) "Origin story reward catalog is missing: $token"
}
Require (-not $originFeaturesLua.Contains('Osi.GetLevel'))
    'OriginFeatures.lua must not grant abilities by level'
foreach ($forbidden in @('UNI_DarkUrge_Stealth_Expertise_Passive',
    'UNI_DarkUrge_Bleeding_Dagger_Passive', 'Karlach_Infernal_Fury')) {
    Require (-not $storyRewardsLua.Contains($forbidden)) "Forbidden origin reward remains: $forbidden"
}
```

- [ ] **Step 3: Run the contracts and verify the intended failure**

Run:

```powershell
.\verify.ps1
```

Expected: failure because `OriginStoryRewards.lua` does not exist. The package-count changes themselves must parse successfully.

- [ ] **Step 4: Commit the failing runtime/package contract**

```powershell
git add verify.ps1 build.ps1 package-files.json
git commit -m "test: require story-driven origin reward runtime"
```

### Task 4: Remove level rewards from identity synchronization

**Files:**
- Modify: `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/OriginFeatures.lua:11-64,127-175`
- Test: `verify.ps1`

- [ ] **Step 1: Replace level tuples with immediate abilities only**

Use this definition shape:

```lua
M.Definitions = {
    { Name = "Astarion", Passive = "COR_Origin_Astarion", Status = "COR_ORIGIN_TAG_ASTARION",
        Tag = "ffd08582-7396-4cac-bcd4-8f9cd0fd8ef3",
        Passives = {}, Spells = { "Target_VampireBite_Astarion" } },
    { Name = "Gale", Passive = "COR_Origin_Gale", Status = "COR_ORIGIN_TAG_GALE",
        Tag = "9b0354c0-56d9-4723-8034-918ac9abab19", Passives = {}, Spells = {} },
    { Name = "Laezel", Passive = "COR_Origin_Laezel", Status = "COR_ORIGIN_TAG_LAEZEL",
        Tag = "b5682d1d-c395-489c-9675-1f9b0c328ea5", Passives = {}, Spells = {} },
    { Name = "Shadowheart", Passive = "COR_Origin_Shadowheart", Status = "COR_ORIGIN_TAG_SHADOWHEART",
        Tag = "642d2aee-e3df-47e3-9f47-bbcd441bb9e0", Passives = {}, Spells = {} },
    { Name = "Wyll", Passive = "COR_Origin_Wyll", Status = "COR_ORIGIN_TAG_WYLL",
        Tag = "5f40def5-d3ec-4698-a367-01a339888956",
        Passives = { "BladeOfFrontiers" }, Spells = {} },
    { Name = "Karlach", Passive = "COR_Origin_Karlach", Status = "COR_ORIGIN_TAG_KARLACH",
        Tag = "1a2f70d6-8ead-4eb5-a824-79ee1971764a",
        Passives = { "ORI_Karlach_SweatImmune", "ORI_Karlach_Rage_Flames" }, Spells = {} },
    { Name = "DarkUrge", Passive = "COR_Origin_DarkUrge", Status = "COR_ORIGIN_TAG_DARKURGE",
        Tag = "cd611d7d-b67d-42b4-a75c-a0c6091ef8a2", Passives = {}, Spells = {} }
}
```

Update stat validation from `feature[1]` to `feature`.

- [ ] **Step 2: Make desired features independent of character level**

Replace the helper and call site with:

```lua
local function desiredFeatures(record)
    local passives, spells, tags = {}, {}, {}
    for _, definition in ipairs(M.Definitions) do
        if record.OriginIdentities[definition.Name] then
            tags[definition.Tag] = true
            for _, passive in ipairs(definition.Passives) do passives[passive] = true end
            for _, spell in ipairs(definition.Spells) do spells[spell] = true end
        end
    end
    return passives, spells, tags
end

local desiredPassives, desiredSpells, desiredTags = desiredFeatures(record)
```

The existing diff loops must remain. On the first schema-7 sync they remove old MOD-owned level rewards from `OriginGranted` without touching externally owned abilities.

- [ ] **Step 3: Confirm that only the absent story module still fails**

Run:

```powershell
.\verify.ps1
```

Expected: no `OriginFeatures.lua must not grant abilities by level` failure; failure remains at the missing `OriginStoryRewards.lua` contract.

- [ ] **Step 4: Commit the identity-only refactor**

```powershell
git add source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/OriginFeatures.lua
git commit -m "refactor: separate origin identities from story rewards"
```

### Task 5: Implement official-flag story reward synchronization

**Files:**
- Create: `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/OriginStoryRewards.lua`
- Test: `verify.ps1`

- [ ] **Step 1: Define the exact rule catalog and tracked-flag index**

Start the module with strict constants and rule types:

```lua
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local GrantLedger = Ext.Require("GrantLedger.lua")
local State = Ext.Require("ChaosState.lua")
local M = {}

local NULL_GUID = "00000000-0000-0000-0000-000000000000"
local WYLL_UUID = "c774d764-4a17-48dc-b470-32ace9ce447d"
local FULL_CEREMORPH = "3797bfc4-8004-4a19-9578-61ce0714cc0b"
local ORB_SPELL = "Target_END_Gale_ActivateNethereseOrb"
local POWER_WORD_KILL = "Target_LOW_DarkUrge_PowerWordKill"

M.Rules = {
    { Key = "AstarionAscended", Identity = "Astarion", Scope = "Global",
      Flag = "ORI_Astarion_State_BecameVampireLord_c446ce94-efd8-45d5-b407-284177b6b57e",
      Mode = "Permanent", Passives = { "LOW_Astarion_VampireAscendant" },
      Spells = { "Shout_EPI_Astarion_TurnIntoBat" } },
    { Key = "GaleOrb", Identity = "Gale", Scope = "Global",
      Flag = "ORI_Gale_Event_BombDisarmed_3d014e79-5595-9365-87bb-5cbb1f87fe5c",
      Mode = "Permanent", Spells = { ORB_SPELL } },
    { Key = "GaleShadowSlots", Identity = "Gale", Scope = "Global",
      Flag = "ORI_Gale_State_AbsorbedTWNBossPower_7d08986a-5410-ccdf-fe70-aaec379a1962",
      Mode = "Permanent", Passives = { "ORI_Gale_ShadowSpellSlots" } },
    { Key = "GaleShadowSummon", Identity = "Gale", Scope = "Global",
      Flag = "ORI_Gale_State_CraftedDarkLantern_3ddebb12-8c9f-47b4-8b6a-bb8eeac51a9b",
      Mode = "Permanent", Spells = { "Target_ORI_Gale_ShadowSummon" } },
    { Key = "GaleGod", Identity = "Gale", Scope = "Global",
      Flag = "ORI_Gale_State_IsGod_ec94f9a4-b032-ce25-f4eb-ecf4ed37d65d",
      Mode = "Permanent", God = true },
    { Key = "WyllFireShield", Identity = "Wyll", Scope = "CharacterEither",
      Flag = "CAMP_MizorasJudgement_Event_Reward_eb10f6f8-cf1a-a2b2-4421-63b0fbeb7a23",
      Mode = "Permanent", Spells = { "Shout_ORI_Wyll_FireShield_Warm" } },
    { Key = "WyllCambion", Identity = "Wyll", Scope = "CharacterEither",
      Flag = "COL_MizorasRescue_Event_Reward_0e2f2a09-604c-2b9d-b8c0-db2baa1e6ac8",
      Mode = "Permanent", Spells = { "Target_ORI_Wyll_SummonCambion" } },
    { Key = "KarlachFirstUpgrade", Identity = "Karlach", Scope = "Global",
      Flag = "GLO_ForgingOfTheHeart_State_KarlachUpgraded_a818e2f5-9e0c-4ab3-8c1e-00765d3b892f",
      Mode = "Stage", Stage = 1, Statuses = { "ORI_KARLACH_FIRSTUPGRADE" } },
    { Key = "KarlachSecondUpgrade", Identity = "Karlach", Scope = "Global",
      Flag = "GLO_ForgingOfTheHeart_State_KarlachSecondUpgrade_f6dc0de4-1089-43c0-b392-306a9a44387c",
      Mode = "Stage", Stage = 2, Statuses = { "ORI_KARLACH_SECONDUPGRADE" } },
    { Key = "DarkUrgeSlayer", Identity = "DarkUrge", Scope = "Global",
      Flag = "ORI_DarkUrge_State_GivenSlayerForm_14aec5bc-1013-4845-96ca-20722c5219e3",
      Mode = "Revocable", Spells = { "Shout_DarkUrge_Slayer" } },
    { Key = "DarkUrgePowerWordKill", Identity = "DarkUrge", Scope = "Global",
      Flag = "ORI_DarkUrge_State_BhaalAccepted_904c45e0-bb06-40ed-b5d7-4f1c851b9d86",
      Mode = "OneShot", Spells = { POWER_WORD_KILL } }
}

local trackedFlags = {}
for _, rule in ipairs(M.Rules) do
    assert(trackedFlags[rule.Flag] == nil, "ChaosOriginsRemastered: duplicate story flag " .. rule.Flag)
    trackedFlags[rule.Flag] = true
end
```

- [ ] **Step 2: Add strict flag queries, stat validation, and claim semantics**

Use exact scope logic; do not treat a missing or unrecognized scope as false:

```lua
local function flagIsSet(rule, character)
    if rule.Scope == "Global" then return Osi.GetFlag(rule.Flag, NULL_GUID) == 1 end
    if rule.Scope == "CharacterEither" then
        return Osi.GetFlag(rule.Flag, character) == 1 or Osi.GetFlag(rule.Flag, WYLL_UUID) == 1
    end
    error("ChaosOriginsRemastered: unknown story flag scope " .. tostring(rule.Scope))
end

local function validateCatalog()
    for _, rule in ipairs(M.Rules) do
        for _, passive in ipairs(rule.Passives or {}) do
            assert(Ext.Stats.Get(passive) ~= nil, "ChaosOriginsRemastered: missing story passive " .. passive)
        end
        for _, spell in ipairs(rule.Spells or {}) do
            assert(Ext.Stats.Get(spell) ~= nil, "ChaosOriginsRemastered: missing story spell " .. spell)
        end
        for _, status in ipairs(rule.Statuses or {}) do
            assert(Ext.Stats.Get(status) ~= nil, "ChaosOriginsRemastered: missing story status " .. status)
        end
    end
    assert(Ext.Stats.Get("EPI_GALEGOD") ~= nil, "ChaosOriginsRemastered: missing Gale god status")
    assert(Ext.Stats.Get("EPI_GALEGOD_MINDFLAYER") ~= nil,
        "ChaosOriginsRemastered: missing mind-flayer Gale god status")
end

local function shouldOwn(rule, character, record)
    local enabled = record.OriginIdentities[rule.Identity] == true
    local set = flagIsSet(rule, character)
    if rule.Mode == "Permanent" then
        if enabled and set and not record.OriginStoryRewards.Claimed[rule.Key] then
            record.OriginStoryRewards.Claimed[rule.Key] = true
            State.MarkDirty()
        end
        return record.OriginStoryRewards.Claimed[rule.Key] == true
    end
    if rule.Mode == "Revocable" or rule.Mode == "Stage" then return enabled and set end
    if rule.Mode == "OneShot" then
        if enabled and set and not record.OriginStoryRewards.Claimed[rule.Key] then
            record.OriginStoryRewards.Claimed[rule.Key] = true
            State.MarkDirty()
        end
        return record.OriginStoryRewards.Claimed[rule.Key] == true
            and record.OriginStoryRewards.Consumed[rule.Key] ~= true
    end
    error("ChaosOriginsRemastered: unknown story reward mode " .. tostring(rule.Mode))
end
```

- [ ] **Step 3: Compute desired rewards and synchronize owned differences**

The implementation must give stage 2 priority and choose exactly one Gale god status:

```lua
function M.Sync(character, record)
    validateCatalog()
    character = ChaosCharacter.CanonicalGuid(character, "origin story reward character")
    local passives, spells, statuses = {}, {}, {}
    local karlachStage = 0
    for _, rule in ipairs(M.Rules) do
        if shouldOwn(rule, character, record) then
            for _, passive in ipairs(rule.Passives or {}) do passives[passive] = true end
            for _, spell in ipairs(rule.Spells or {}) do spells[spell] = true end
            if rule.Stage ~= nil then karlachStage = math.max(karlachStage, rule.Stage) end
            if rule.God then
                local godStatus = Osi.IsTagged(character, FULL_CEREMORPH) == 1
                    and "EPI_GALEGOD_MINDFLAYER" or "EPI_GALEGOD"
                statuses[godStatus] = true
                Osi.SetImmortal(character, 1)
                Osi.PROC_SetInvulnerable(character, 1)
            end
        end
    end
    if karlachStage == 1 then statuses.ORI_KARLACH_FIRSTUPGRADE = true end
    if karlachStage == 2 then statuses.ORI_KARLACH_SECONDUPGRADE = true end

    for passive in pairs(record.OriginStoryGranted.Passives) do
        if not passives[passive] then
            GrantLedger.RemovePassive(character, record, passive, record.OriginStoryGranted.Passives)
        end
    end
    for spell in pairs(record.OriginStoryGranted.Spells) do
        if not spells[spell] then
            GrantLedger.RemoveSpell(character, record, spell, record.OriginStoryGranted.Spells)
        end
    end
    for status in pairs(record.OriginStoryGranted.Statuses) do
        if not statuses[status] then
            GrantLedger.RemoveStatus(character, record, status, record.OriginStoryGranted.Statuses)
        end
    end
    for passive in pairs(passives) do
        GrantLedger.EnsurePassive(character, record, passive, record.OriginStoryGranted.Passives)
    end
    for spell in pairs(spells) do
        GrantLedger.EnsureSpell(character, record, spell, record.OriginStoryGranted.Spells)
    end
    for status in pairs(statuses) do
        GrantLedger.EnsureStatus(character, record, status, record.OriginStoryGranted.Statuses)
    end
end
```

Do not call a level API and do not set level 20. Permanent godhood intentionally keeps immortality/invulnerability after the original Flag has been claimed.

- [ ] **Step 4: Add event predicates and one-shot spell consequences**

```lua
function M.IsTrackedFlag(flag)
    return trackedFlags[flag] == true
end

function M.HandleCastedSpell(character, spell, record)
    character = ChaosCharacter.CanonicalGuid(character, "origin story spell caster")
    if spell == ORB_SPELL then
        if record.OriginStoryRewards.Claimed.GaleOrb == true
            and record.OriginStoryGranted.Spells[ORB_SPELL] ~= nil then
            Osi.ShowGameOverMenu("GameOver_Default")
            return true
        end
        return false
    end
    if spell == POWER_WORD_KILL then
        if record.OriginStoryRewards.Claimed.DarkUrgePowerWordKill == true
            and record.OriginStoryRewards.Consumed.DarkUrgePowerWordKill ~= true then
            record.OriginStoryRewards.Consumed.DarkUrgePowerWordKill = true
            State.MarkDirty()
            if record.OriginStoryGranted.Spells[POWER_WORD_KILL] ~= nil then
                GrantLedger.RemoveSpell(character, record, POWER_WORD_KILL,
                    record.OriginStoryGranted.Spells)
            end
            return true
        end
        return false
    end
    return false
end

function M.ResetRuntime()
    -- 当前模块没有跨会话延时表；保留统一生命周期入口供服务器明确重置。
end

return M
```

- [ ] **Step 5: Run verification**

Run:

```powershell
.\verify.ps1
```

Expected: catalog/module/package checks pass. If a verified identifier is absent from local game Stats, runtime validation must later raise the explicit `missing story ...` error; do not substitute another stat.

- [ ] **Step 6: Commit the story reward engine**

```powershell
git add source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/OriginStoryRewards.lua
git commit -m "feat: add official origin story rewards"
```

### Task 6: Add failing server/MCM wiring contracts

**Files:**
- Modify: `verify.ps1:628-649`
- Test: `verify.ps1`

- [ ] **Step 1: Require protocol v4, the XP action, and story events**

Update the MCM token from `Version = 3` to `Version = 4`, then add these exact checks:

```powershell
foreach ($token in @('OriginStoryRewards.Sync', 'OriginStoryRewards.ResetRuntime',
    'OriginStoryRewards.IsTrackedFlag', 'OriginStoryRewards.HandleCastedSpell',
    'RegisterListener("FlagSet", 3', 'RegisterListener("FlagCleared", 3',
    'RegisterListener("CastedSpell", 5', 'SetTestExperience',
    'TestLevel12Experience', 'scheduleLevel12TestExperience')) {
    Require ($bootstrap.Contains($token)) "Story reward server wiring is missing: $token"
}
foreach ($token in @('Version = 4', 'TestLevel12Experience', 'SetTestExperience')) {
    Require (($mcmProtocol + $mcmClient).Contains($token)) "MCM test-experience wiring is missing: $token"
}
```

- [ ] **Step 2: Run the contracts and verify the intended failure**

Run:

```powershell
.\verify.ps1
```

Expected: failure containing `Story reward server wiring is missing: OriginStoryRewards.Sync`.

- [ ] **Step 3: Commit only the failing wiring contract**

```powershell
git add verify.ps1
git commit -m "test: require story reward event wiring"
```

### Task 7: Wire story events and make test XP default-off

**Files:**
- Modify: `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/BootstrapServer.lua:3-398`
- Modify: `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/McmProtocol.lua:1-90`
- Modify: `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/BootstrapClient.lua:13-210`
- Test: `verify.ps1`

- [ ] **Step 1: Synchronize the new module in the central pipeline**

Require `OriginStoryRewards.lua`, then add it immediately after identity synchronization:

```lua
OriginFeatures.Sync(character, record)
OriginStoryRewards.Sync(character, record)
ChaosMechanics.Sync(character, record)
```

Call `OriginStoryRewards.ResetRuntime()` in `SessionLoaded` beside the existing runtime resets.

- [ ] **Step 2: Gate XP grants on the saved per-character switch**

Change the helper to accept the selected character and saved record:

```lua
local function grantLevel12TestExperience(character, record)
    if not record.TestLevel12Experience then return false end
    character = ChaosCharacter.CanonicalGuid(character, "level-12 test character")
    if not ChaosCharacter.IsEligible(character) then return false end
    local entity = assert(Ext.Entity.Get(character),
        "ChaosOriginsRemastered: host entity is unavailable for test experience " .. character)
    local experience = assert(entity.Experience,
        "ChaosOriginsRemastered: experience component is unavailable " .. character)
    local total = assert(experience.TotalExperience,
        "ChaosOriginsRemastered: total experience is unavailable " .. character)
    assert(type(total) == "number" and total >= 0,
        "ChaosOriginsRemastered: invalid total experience " .. tostring(total)
            .. " for " .. character)
    if total >= LEVEL_12_TOTAL_EXPERIENCE then return false end
    Osi.AddExplorationExperience(character, LEVEL_12_TOTAL_EXPERIENCE - total)
    return true
end
```

Replace the scheduled helper with this exact host lookup. `LevelGameplayStarted` continues scheduling the check, but the default `false` record makes it a no-op:

```lua
local function scheduleLevel12TestExperience(delay)
    local generation = sessionGeneration
    Ext.Timer.WaitFor(delay, function()
        if generation ~= sessionGeneration then return end
        local character = Osi.GetHostCharacter()
        assert(character ~= nil and character ~= "",
            "ChaosOriginsRemastered: host character is unavailable for test experience")
        character = ChaosCharacter.CanonicalGuid(character, "test experience character")
        if not ChaosCharacter.IsEligible(character) then return end
        grantLevel12TestExperience(character, State.GetCharacter(character))
    end)
end
```

- [ ] **Step 3: Add host-authoritative MCM snapshot/action behavior**

Add to the ready snapshot:

```lua
TestLevel12Experience = saved.TestLevel12Experience,
```

Add a request branch before mechanic handling:

```lua
elseif request.Action == "SetTestExperience" then
    assert(type(request.Value) == "boolean",
        "ChaosOriginsRemastered: test experience value must be boolean")
    changed = saved.TestLevel12Experience ~= request.Value
    if changed then
        saved.TestLevel12Experience = request.Value
        State.MarkDirty()
        if request.Value then grantLevel12TestExperience(snapshot.CharacterId, saved) end
    end
```

Keep combat rejection consistent with other gameplay switches. Turning the checkbox off must never call a negative experience operation.

- [ ] **Step 4: Register exact story events**

Add these listeners after `LevelGameplayStarted`:

```lua
Ext.Osiris.RegisterListener("FlagSet", 3, "after", function(flag)
    if OriginStoryRewards.IsTrackedFlag(flag) then scheduleAllPlayers(200) end
end)

Ext.Osiris.RegisterListener("FlagCleared", 3, "after", function(flag)
    if OriginStoryRewards.IsTrackedFlag(flag) then scheduleAllPlayers(200) end
end)

Ext.Osiris.RegisterListener("CastedSpell", 5, "after", function(caster, spell)
    if not ChaosCharacter.IsEligible(caster) then return end
    local record = State.GetCharacter(caster)
    if OriginStoryRewards.HandleCastedSpell(caster, spell, record) then
        scheduleCharacter(caster, 200)
    end
end)
```

The 200 ms delay lets the official Story finish the same flag chain before the MOD reads the final state.

- [ ] **Step 5: Upgrade MCM protocol and render the checkbox**

In `McmProtocol.lua`, set `Version = 4` and add:

```lua
TestLevel12Experience = "h68000001g0001g4001g8001g000000000001",
```

In `BootstrapClient.lua`, extend controls and snapshot application:

```lua
local controls = {
    Origins = {}, OriginAll = nil, Mechanics = {}, WoundEffects = {}, TestExperience = nil
}

if controls.TestExperience ~= nil then
    controls.TestExperience.Checked = snapshot ~= nil
        and snapshot.TestLevel12Experience == true
    controls.TestExperience.Disabled = disabled
end
```

At the end of `renderGeneral`, before `finishRender()`:

```lua
controls.TestExperience = checkbox(parent, loc(Protocol.Text.TestLevel12Experience), false,
    function(value) request("SetTestExperience", "", value) end)
```

- [ ] **Step 6: Run verification**

Run:

```powershell
.\verify.ps1
```

Expected: `ChaosOriginsRemastered source verification: ok`.

- [ ] **Step 7: Commit the runtime wiring**

```powershell
git add source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/BootstrapServer.lua source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/McmProtocol.lua source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/BootstrapClient.lua
git commit -m "feat: wire story rewards and test experience"
```

### Task 8: Update all player-facing descriptions

**Files:**
- Modify: `localization-src/Chinese/ChaosOriginsRemastered.xml`
- Modify: `localization-src/English/ChaosOriginsRemastered.xml`
- Modify: `localization-src/Japanese/ChaosOriginsRemastered.xml`
- Modify: `localization-src/Korean/ChaosOriginsRemastered.xml`
- Modify: `README.md:15-35`
- Modify: `source/Mods/ChaosOriginsRemastered/meta.lsx`
- Test: `verify.ps1`

- [ ] **Step 1: Add the same new handle to all four localization files**

Use handle `h68000001g0001g4001g8001g000000000001` with these exact labels:

```xml
<!-- Chinese -->
<content contentuid="h68000001g0001g4001g8001g000000000001" version="1">12级测试经验（补足至100000，默认关闭）</content>
<!-- English -->
<content contentuid="h68000001g0001g4001g8001g000000000001" version="1">Level 12 Test XP (fill to 100000; off by default)</content>
<!-- Japanese -->
<content contentuid="h68000001g0001g4001g8001g000000000001" version="1">レベル12テスト経験値（100000まで補充・初期OFF）</content>
<!-- Korean -->
<content contentuid="h68000001g0001g4001g8001g000000000001" version="1">12레벨 테스트 경험치 (100000까지 보충, 기본 꺼짐)</content>
```

- [ ] **Step 2: Replace obsolete level-growth descriptions in all languages**

Update these existing handles in every language:

- `h049bbad7g2b78g5bedg831dga2a983c40cda`: identity passive description; explain that it controls the official tag and immediate ability only.
- `h903c567eg472ag5c11g8a75g1b8a2e298137`: feature overview; list official story-result rewards rather than level thresholds.
- `ha4779903g3937g5f9bg9576g88cdb2406df1`: MCM origin help; explain backfill, permanent claims, and no manual story unlock.
- `h9bc9d749g7b27g5828g8eb4g37f198ae10b5`: general MCM help; explain that enabling test XP only adds the missing difference and disabling cannot remove XP.

For Chinese, use this exact origin-help meaning:

```xml
<content contentuid="ha4779903g3937g5f9bg9576g88cdb2406df1" version="1">七个起源身份默认全部开启。开启身份会同步官方标签、基础能力，并补发存档中已经完成的对应剧情奖励；关闭身份会移除标签与基础能力，但不会收回已经认领的永久剧情奖励。剧情奖励只能由官方剧情结果触发，不能在此手动解锁；战斗中不可修改。</content>
```

- [ ] **Step 3: Update README and module metadata**

Replace README's level-based origin wording with the exact model:

```markdown
起源身份只直接提供官方标签与基础能力；阿斯代伦飞升、盖尔幽影/自爆/成神、威尔契约奖励、卡菈克引擎升级和邪念奖励均由对应官方剧情结果触发。真实起源队友完成结果也可让混沌角色认领，已认领的永久奖励不会因关闭身份被收回。

“12级测试经验”保留在 MCM 中但默认关闭。开启后只把当前混沌角色累计经验补足至 `100000`，不直接升级；关闭不会扣除已经获得的经验。
```

Update `meta.lsx` Description to mention story-driven origin rewards without changing UUID, dependencies, folder, author, or Version64.

- [ ] **Step 4: Run localization and source verification**

Run:

```powershell
.\verify.ps1
```

Expected: `ChaosOriginsRemastered source verification: ok`; all four localization handle sets are identical.

- [ ] **Step 5: Scan for obsolete player-facing claims**

Run:

```powershell
rg -n "每级|等级解锁|level-based|level based|100000.*进入|自动.*100000" README.md localization-src source/Mods/ChaosOriginsRemastered/meta.lsx
```

Expected: no obsolete claim that origin rewards are level-based or that 100000 XP is automatic by default.

- [ ] **Step 6: Commit descriptions separately**

```powershell
git add localization-src README.md source/Mods/ChaosOriginsRemastered/meta.lsx
git commit -m "docs: explain story-driven origin rewards"
```

### Task 9: Strengthen final static regression gates

**Files:**
- Modify: `verify.ps1`
- Test: `verify.ps1`

- [ ] **Step 1: Require each semantic branch, not only identifiers**

Add exact checks for ownership and consequences:

```powershell
foreach ($token in @('Mode = "Permanent"', 'Mode = "Revocable"', 'Mode = "Stage"',
    'Mode = "OneShot"', 'math.max(karlachStage, rule.Stage)',
    'OriginStoryRewards.Claimed', 'OriginStoryRewards.Consumed',
    'GrantLedger.EnsureStatus', 'GrantLedger.RemoveStatus',
    'Osi.SetImmortal(character, 1)', 'Osi.PROC_SetInvulnerable(character, 1)',
    'Osi.ShowGameOverMenu("GameOver_Default")')) {
    Require ($storyRewardsLua.Contains($token)) "Story reward behavior is missing: $token"
}
Require (-not $storyRewardsLua.Contains('PROC_ORI_Gale_Explosion'))
    'Chaos Gale orb must not call the real-Gale explosion procedure'
Require (-not $storyRewardsLua.Contains('SetLevel'))
    'Gale godhood must not change the Chaos character level'
```

Add an exact base-ability whitelist check:

```powershell
foreach ($token in @('Target_VampireBite_Astarion', 'BladeOfFrontiers',
    'ORI_Karlach_SweatImmune', 'ORI_Karlach_Rage_Flames')) {
    Require ($originFeaturesLua.Contains($token)) "Immediate origin ability is missing: $token"
}
foreach ($token in @('LOW_Astarion_VampireAscendant', 'ORI_Gale_ShadowSpellSlots',
    'Shout_ORI_Wyll_FireShield_Warm', 'ORI_KARLACH_FIRSTUPGRADE',
    'Shout_DarkUrge_Slayer')) {
    Require (-not $originFeaturesLua.Contains($token)) "Story reward leaked into OriginFeatures: $token"
}
```

- [ ] **Step 2: Run the complete verifier twice**

Run:

```powershell
.\verify.ps1
.\verify.ps1
```

Expected: two consecutive `ChaosOriginsRemastered source verification: ok` results, demonstrating that atlas rebuilding and static checks are repeatable.

- [ ] **Step 3: Inspect the complete rollback chain**

Run:

```powershell
git log --oneline -12
git status --short
```

Expected: separate test/implementation/refactor/docs commits and only `verify.ps1` modified for this task.

- [ ] **Step 4: Commit the final regression gate**

```powershell
git add verify.ps1
git commit -m "test: cover origin story reward semantics"
```

### Task 10: Build and commit v1.0.21

**Files:**
- Modify through build: `version.json`
- Modify through build: `source/Mods/ChaosOriginsRemastered/meta.lsx`
- Create/replace through build: `dist/ChaosOriginsRemastered.pak`
- Create/replace through build: `dist/build-manifest.json`
- Test: `build.ps1`, reverse-unpacked files and hashes

- [ ] **Step 1: Verify the pre-build version and clean tracked tree**

Run:

```powershell
Get-Content -Raw version.json
git status --short
```

Expected: `lastBuild` is 20 and no tracked changes remain.

- [ ] **Step 2: Build exactly once**

Run:

```powershell
.\build.ps1 -LslibPath 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll'
```

Expected final line:

```text
ChaosOriginsRemastered built and reverse-verified: 1.0.21 (36028797018963989)
```

The build itself must verify the 34-path staging list, reverse-unpack the PAK, and compare SHA-256 for every file.

- [ ] **Step 3: Inspect build outputs and version-only tracked changes**

Run:

```powershell
Get-Content -Raw dist\build-manifest.json
git diff -- version.json source/Mods/ChaosOriginsRemastered/meta.lsx
git status --short
```

Expected: manifest `displayVersion` is `1.0.21`, `version64` is `36028797018963989`, file count is 34; tracked changes are only `version.json` and `meta.lsx`.

- [ ] **Step 4: Commit and push the release state**

```powershell
git add version.json source/Mods/ChaosOriginsRemastered/meta.lsx
git commit -m "chore: release version 1.0.21"
git push origin main
```

Expected: `main` pushes successfully; PAK/build manifest remain build artifacts unless already tracked by repository policy.

### Task 11: Install only after the game-closed gate

**Files:**
- Read: `dist/ChaosOriginsRemastered.pak`
- Backup/replace: `%LOCALAPPDATA%/Larian Studios/Baldur's Gate 3/Mods/ChaosOriginsRemastered.pak`
- Test: source/install SHA-256 equality

- [ ] **Step 1: Prove both game executables are absent**

Run:

```powershell
$running = @(Get-Process -Name bg3,bg3_dx11 -ErrorAction SilentlyContinue)
if ($running.Count -ne 0) { throw 'Baldur\'s Gate 3 is still running; installation stopped.' }
```

Expected: no exception. If either process exists, stop this task without modifying the installed PAK and ask the user to close the game.

- [ ] **Step 2: Resolve and validate exact install paths**

Run:

```powershell
$builtPak = (Resolve-Path -LiteralPath 'dist\ChaosOriginsRemastered.pak').Path
$modsDir = Join-Path $env:LOCALAPPDATA "Larian Studios\Baldur's Gate 3\Mods"
$installedPak = Join-Path $modsDir 'ChaosOriginsRemastered.pak'
$builtPak
$installedPak
```

Expected: source is inside this repository's `dist`; destination is the named BG3 Mods directory.

- [ ] **Step 3: Back up the installed PAK without overwriting an older backup**

Run:

```powershell
if (Test-Path -LiteralPath $installedPak) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPak = Join-Path $modsDir "ChaosOriginsRemastered.pak.backup-$stamp"
    if (Test-Path -LiteralPath $backupPak) { throw "Backup already exists: $backupPak" }
    Copy-Item -LiteralPath $installedPak -Destination $backupPak
}
```

Expected: the v1.0.20 installed PAK remains recoverable at the timestamped backup path.

- [ ] **Step 4: Install and compare hashes**

Run:

```powershell
Copy-Item -LiteralPath $builtPak -Destination $installedPak -Force
$builtHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $builtPak).Hash
$installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedPak).Hash
if ($builtHash -ne $installedHash) { throw 'Installed PAK hash differs from built PAK.' }
$builtHash
```

Expected: one SHA-256 value and exact equality. Report the backup path and installed hash; installation is not game-runtime acceptance.

### Task 12: Hand off the in-game acceptance matrix

**Files:**
- No source changes
- Test: Baldur's Gate 3 runtime with Script Extender and BG3MCM

- [ ] **Step 1: Verify default and existing regressions**

In a new Chaos Origin game, confirm:

1. Character creation and male half-elf default remain correct.
2. Guardian creation remains correct.
3. Seven origin identities default to enabled, with no prominent identity BUFF icons.
4. Level 1 does not receive 100000 XP until the MCM switch is enabled.
5. Enabling the switch fills only to 100000; disabling does not subtract XP.
6. The seven starter spells, three one-time starter rewards, shapeshifter mask behavior, 18 skill expertise, Chaos Power, attack wheel, hit wheel, All-In, and existing console test commands remain functional.

- [ ] **Step 2: Verify story claims and revocation**

Use saves/official debug Flag tooling to confirm:

1. Astarion ascension grants ascendant passive plus bat form.
2. Gale's four independent results grant orb, shadow slots, shadow summon, and godhood independently.
3. Wyll's two character Flags work when set on Chaos or real Wyll.
4. Karlach stage 2 removes/replaces stage 1.
5. Dark Urge Slayer disappears when its Flag clears.
6. Power Word Kill disappears after one cast and does not return after reload, respec, identity off/on, or session reload.
7. A result completed while its identity is disabled backfills when the identity is re-enabled.
8. Permanent claimed rewards remain after the identity is disabled.

- [ ] **Step 3: Verify Gale's destructive and god forms separately**

1. Cast `Target_END_Gale_ActivateNethereseOrb` with the eligible Chaos character and confirm the default game-over screen appears.
2. Confirm the MOD does not route through real Gale's explosion/dialog procedure.
3. For a normal Chaos character, confirm `EPI_GALEGOD`, three god spells, +10 aura, immortality, invulnerability, and unchanged level.
4. For a full-ceremorph Chaos character, confirm `EPI_GALEGOD_MINDFLAYER` replaces the normal god status, with the same power set and unchanged level.

- [ ] **Step 4: Record the acceptance boundary**

Report three states separately:

- Static/source verification: passed only if `verify.ps1` passed.
- Build/install verification: passed only if reverse-unpack and installed hashes matched.
- Game-runtime verification: pending until every applicable check above is tested in game; do not label the release fully accepted before that report.
