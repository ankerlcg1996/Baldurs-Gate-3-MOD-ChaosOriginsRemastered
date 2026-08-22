local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local GrantLedger = Ext.Require("GrantLedger.lua")
local State = Ext.Require("ChaosState.lua")
local M = {}

local NULL_GUID = "00000000-0000-0000-0000-000000000000"
local WYLL_UUID = "c774d764-4a17-48dc-b470-32ace9ce447d"
local FULL_CEREMORPH = "3797bfc4-8004-4a19-9578-61ce0714cc0b"
local ORB_SPELL = "Target_END_Gale_ActivateNethereseOrb"
local POWER_WORD_KILL = "Target_LOW_DarkUrge_PowerWordKill"
local GALE_GOD = "EPI_GALEGOD"
local GALE_GOD_MINDFLAYER = "EPI_GALEGOD_MINDFLAYER"

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
local claimableKeys = {}
local oneShotKeys = {}
local supportedIdentities = {
    Astarion = true, Gale = true, Laezel = true, Shadowheart = true,
    Wyll = true, Karlach = true, DarkUrge = true
}
local supportedScopes = { Global = true, CharacterEither = true }
local supportedModes = { Permanent = true, Revocable = true, Stage = true, OneShot = true }
local allowedRuleFields = {
    Key = true, Identity = true, Scope = true, Flag = true, Mode = true,
    Passives = true, Spells = true, Statuses = true, Stage = true, God = true
}

local function validateStringArray(value, label)
    if value == nil then return end
    assert(type(value) == "table", "ChaosOriginsRemastered: " .. label .. " must be an array")
    local count, maximum = 0, 0
    for index, entry in pairs(value) do
        assert(type(index) == "number" and index >= 1 and index % 1 == 0,
            "ChaosOriginsRemastered: invalid " .. label .. " index " .. tostring(index))
        assert(type(entry) == "string" and entry ~= "",
            "ChaosOriginsRemastered: invalid " .. label .. " entry " .. tostring(entry))
        count = count + 1
        if index > maximum then maximum = index end
    end
    assert(count == maximum,
        "ChaosOriginsRemastered: " .. label .. " must be a dense array")
end

local ruleKeys = {}
local ruleCount, maximumRuleIndex = 0, 0
for index, rule in pairs(M.Rules) do
    assert(type(index) == "number" and index >= 1 and index % 1 == 0 and type(rule) == "table",
        "ChaosOriginsRemastered: invalid origin story rule index " .. tostring(index))
    ruleCount = ruleCount + 1
    if index > maximumRuleIndex then maximumRuleIndex = index end
    for field in pairs(rule) do
        assert(allowedRuleFields[field] == true,
            "ChaosOriginsRemastered: unknown origin story rule field " .. tostring(field))
    end
    for _, field in ipairs({ "Key", "Identity", "Scope", "Flag", "Mode" }) do
        assert(type(rule[field]) == "string" and rule[field] ~= "",
            "ChaosOriginsRemastered: invalid origin story rule " .. field .. " at " .. tostring(index))
    end
    assert(ruleKeys[rule.Key] == nil,
        "ChaosOriginsRemastered: duplicate origin story rule key " .. rule.Key)
    assert(trackedFlags[rule.Flag] == nil,
        "ChaosOriginsRemastered: duplicate origin story flag " .. rule.Flag)
    assert(supportedIdentities[rule.Identity] == true,
        "ChaosOriginsRemastered: unsupported origin story identity " .. rule.Identity)
    assert(supportedScopes[rule.Scope] == true,
        "ChaosOriginsRemastered: unsupported origin story scope " .. rule.Scope)
    assert(supportedModes[rule.Mode] == true,
        "ChaosOriginsRemastered: unsupported origin story mode " .. rule.Mode)
    validateStringArray(rule.Passives, rule.Key .. " passives")
    validateStringArray(rule.Spells, rule.Key .. " spells")
    validateStringArray(rule.Statuses, rule.Key .. " statuses")
    if rule.Mode == "Stage" then
        assert(rule.Stage == 1 or rule.Stage == 2,
            "ChaosOriginsRemastered: invalid origin story stage " .. tostring(rule.Stage))
    else
        assert(rule.Stage == nil,
            "ChaosOriginsRemastered: non-stage rule has a stage " .. rule.Key)
    end
    if rule.Key == "GaleGod" then
        assert(rule.God == true, "ChaosOriginsRemastered: GaleGod rule must set God")
    else
        assert(rule.God == nil,
            "ChaosOriginsRemastered: only GaleGod may set God")
    end
    ruleKeys[rule.Key] = true
    trackedFlags[rule.Flag] = true
    if rule.Mode == "Permanent" or rule.Mode == "OneShot" then
        claimableKeys[rule.Key] = true
    end
    if rule.Mode == "OneShot" then oneShotKeys[rule.Key] = true end
end
assert(ruleCount == maximumRuleIndex and ruleCount == 11,
    "ChaosOriginsRemastered: origin story rules must be a dense eleven-rule catalog")

local validated = false
local function validateCatalog()
    if validated then return end
    for _, rule in ipairs(M.Rules) do
        for _, field in ipairs({ "Passives", "Spells", "Statuses" }) do
            for _, stat in ipairs(rule[field] or {}) do
                assert(Ext.Stats.Get(stat) ~= nil,
                    "ChaosOriginsRemastered: missing origin story stat " .. stat)
            end
        end
    end
    for _, status in ipairs({ GALE_GOD, GALE_GOD_MINDFLAYER }) do
        assert(Ext.Stats.Get(status) ~= nil,
            "ChaosOriginsRemastered: missing origin story stat " .. status)
    end
    validated = true
end

local function flagIsSet(rule, character)
    if rule.Scope == "Global" then return Osi.GetFlag(rule.Flag, NULL_GUID) == 1 end
    if rule.Scope == "CharacterEither" then
        return Osi.GetFlag(rule.Flag, character) == 1 or Osi.GetFlag(rule.Flag, WYLL_UUID) == 1
    end
    error("ChaosOriginsRemastered: unknown origin story scope " .. tostring(rule.Scope))
end

local function shouldOwn(rule, character, record)
    local rewards = record.OriginStoryRewards
    local enabled = record.OriginIdentities[rule.Identity] == true
    if rule.Mode == "Permanent" then
        if rewards.Claimed[rule.Key] ~= true and enabled and flagIsSet(rule, character) then
            rewards.Claimed[rule.Key] = true
            State.MarkDirty()
        end
        return rewards.Claimed[rule.Key] == true
    end
    if rule.Mode == "Revocable" or rule.Mode == "Stage" then
        return enabled and flagIsSet(rule, character)
    end
    if rule.Mode == "OneShot" then
        if rewards.Claimed[rule.Key] ~= true and enabled and flagIsSet(rule, character) then
            rewards.Claimed[rule.Key] = true
            State.MarkDirty()
        end
        return rewards.Claimed[rule.Key] == true and rewards.Consumed[rule.Key] ~= true
    end
    error("ChaosOriginsRemastered: unknown origin story mode " .. tostring(rule.Mode))
end

local function validateSavedRewards(record)
    local rewards = assert(record.OriginStoryRewards,
        "ChaosOriginsRemastered: origin story rewards are unavailable")
    assert(type(rewards.Claimed) == "table" and type(rewards.Consumed) == "table",
        "ChaosOriginsRemastered: origin story reward maps are invalid")
    for key, claimed in pairs(rewards.Claimed) do
        assert(claimed == true and claimableKeys[key] == true,
            "ChaosOriginsRemastered: invalid claimed origin story reward " .. tostring(key))
    end
    for key, consumed in pairs(rewards.Consumed) do
        assert(consumed == true and oneShotKeys[key] == true and rewards.Claimed[key] == true,
            "ChaosOriginsRemastered: invalid consumed origin story reward " .. tostring(key))
    end
end

local function collect(target, values)
    for _, value in ipairs(values or {}) do target[value] = true end
end

function M.Sync(character, record)
    validateCatalog()
    character = ChaosCharacter.CanonicalGuid(character, "origin story character")
    validateSavedRewards(record)
    local passives, spells, statuses = {}, {}, {}
    local selectedStageRule = nil
    for _, rule in ipairs(M.Rules) do
        if shouldOwn(rule, character, record) then
            if rule.Mode == "Stage" then
                if selectedStageRule == nil or rule.Stage > selectedStageRule.Stage then
                    selectedStageRule = rule
                end
            else
                collect(passives, rule.Passives)
                collect(spells, rule.Spells)
                collect(statuses, rule.Statuses)
            end
            if rule.God then
                local godStatus = Osi.IsTagged(character, FULL_CEREMORPH) == 1
                    and GALE_GOD_MINDFLAYER or GALE_GOD
                statuses[godStatus] = true
                Osi.SetImmortal(character, 1)
                Osi.PROC_SetInvulnerable(character, 1)
            end
        end
    end
    if selectedStageRule ~= nil then
        collect(statuses, selectedStageRule.Statuses)
    end

    local ledger = record.OriginStoryGranted
    for passive in pairs(ledger.Passives) do
        if not passives[passive] then
            GrantLedger.RemovePassive(character, record, passive, ledger.Passives)
        end
    end
    for spell in pairs(ledger.Spells) do
        if not spells[spell] then
            GrantLedger.RemoveSpell(character, record, spell, ledger.Spells)
        end
    end
    for status in pairs(ledger.Statuses) do
        if not statuses[status] then
            GrantLedger.RemoveStatus(character, record, status, ledger.Statuses)
        end
    end
    for passive in pairs(passives) do
        GrantLedger.EnsurePassive(character, record, passive, ledger.Passives)
    end
    for spell in pairs(spells) do
        GrantLedger.EnsureSpell(character, record, spell, ledger.Spells)
    end
    for status in pairs(statuses) do
        GrantLedger.EnsureStatus(character, record, status, ledger.Statuses)
    end
end

function M.IsTrackedFlag(flag)
    return trackedFlags[flag] == true
end

function M.HandleCastedSpell(character, spell, record)
    character = ChaosCharacter.CanonicalGuid(character, "origin story caster")
    validateSavedRewards(record)
    local rewards = record.OriginStoryRewards
    local ledger = record.OriginStoryGranted.Spells
    if spell == ORB_SPELL then
        if rewards.Claimed.GaleOrb == true and ledger[ORB_SPELL] ~= nil then
            Osi.ShowGameOverMenu("GameOver_Default")
            return true
        end
        return false
    end
    if spell == POWER_WORD_KILL then
        if rewards.Claimed.DarkUrgePowerWordKill == true
            and rewards.Consumed.DarkUrgePowerWordKill ~= true then
            rewards.Consumed.DarkUrgePowerWordKill = true
            State.MarkDirty()
            if ledger[POWER_WORD_KILL] ~= nil then
                GrantLedger.RemoveSpell(character, record, POWER_WORD_KILL, ledger)
            end
            return true
        end
        return false
    end
    return false
end

function M.ResetRuntime()
    -- 本模块没有跨会话计时器表，运行时无需清空额外状态。
end

return M
