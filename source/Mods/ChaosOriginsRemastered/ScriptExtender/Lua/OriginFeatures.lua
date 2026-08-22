local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local GrantLedger = Ext.Require("GrantLedger.lua")
local State = Ext.Require("ChaosState.lua")
local M = {}

local VERIFY_INTERVAL_MS = 100
local VERIFY_TIMEOUT_MS = 2000
local alignment = {}
local guardedStatus = {}

M.Definitions = {
    { Name = "Astarion", Passive = "COR_Origin_Astarion", Status = "COR_ORIGIN_TAG_ASTARION",
        Tag = "ffd08582-7396-4cac-bcd4-8f9cd0fd8ef3",
        Passives = { { "LOW_Astarion_VampireAscendant", 10 } },
        Spells = { { "Target_VampireBite_Astarion", 1 }, { "Shout_EPI_Astarion_TurnIntoBat", 12 } } },
    { Name = "Gale", Passive = "COR_Origin_Gale", Status = "COR_ORIGIN_TAG_GALE",
        Tag = "9b0354c0-56d9-4723-8034-918ac9abab19",
        Passives = { { "ORI_Gale_ShadowSpellSlots", 5 } },
        Spells = { { "Target_ORI_Gale_ShadowSummon", 5 } } },
    { Name = "Laezel", Passive = "COR_Origin_Laezel", Status = "COR_ORIGIN_TAG_LAEZEL",
        Tag = "b5682d1d-c395-489c-9675-1f9b0c328ea5", Passives = {}, Spells = {} },
    { Name = "Shadowheart", Passive = "COR_Origin_Shadowheart", Status = "COR_ORIGIN_TAG_SHADOWHEART",
        Tag = "642d2aee-e3df-47e3-9f47-bbcd441bb9e0", Passives = {}, Spells = {} },
    { Name = "Wyll", Passive = "COR_Origin_Wyll", Status = "COR_ORIGIN_TAG_WYLL",
        Tag = "5f40def5-d3ec-4698-a367-01a339888956",
        Passives = { { "BladeOfFrontiers", 1 } },
        Spells = { { "Shout_ORI_Wyll_FireShield_Warm", 7 }, { "Target_ORI_Wyll_SummonCambion", 11 } } },
    { Name = "Karlach", Passive = "COR_Origin_Karlach", Status = "COR_ORIGIN_TAG_KARLACH",
        Tag = "1a2f70d6-8ead-4eb5-a824-79ee1971764a",
        Passives = { { "ORI_Karlach_SweatImmune", 1 }, { "ORI_Karlach_Rage_Flames", 1 },
            { "ORI_Karlach_FirstUpgrade", 3 }, { "Karlach_Infernal_Fury", 5 },
            { "ORI_Karlach_SecondUpgrade", 7 } }, Spells = {} },
    { Name = "DarkUrge", Passive = "COR_Origin_DarkUrge", Status = "COR_ORIGIN_TAG_DARKURGE",
        Tag = "cd611d7d-b67d-42b4-a75c-a0c6091ef8a2",
        Passives = { { "UNI_DarkUrge_Stealth_Expertise_Passive", 3 },
            { "UNI_DarkUrge_Bleeding_Dagger_Passive", 5 } },
        Spells = { { "Shout_DarkUrge_Slayer", 9 } } }
}

local byStatus = {}
local byName = {}
for _, definition in ipairs(M.Definitions) do
    assert(byStatus[definition.Status] == nil and byName[definition.Name] == nil,
        "ChaosOriginsRemastered: duplicate origin identity definition " .. definition.Name)
    byStatus[definition.Status] = definition
    byName[definition.Name] = definition
end

local validated = false
local function validateStats()
    if validated then return end
    for _, definition in ipairs(M.Definitions) do
        assert(Ext.Stats.Get(definition.Passive) ~= nil,
            "ChaosOriginsRemastered: missing origin toggle passive " .. definition.Passive)
        assert(Ext.Stats.Get(definition.Status) ~= nil,
            "ChaosOriginsRemastered: missing origin identity status " .. definition.Status)
        for _, feature in ipairs(definition.Passives) do
            assert(Ext.Stats.Get(feature[1]) ~= nil,
                "ChaosOriginsRemastered: missing origin passive " .. feature[1])
        end
        for _, feature in ipairs(definition.Spells) do
            assert(Ext.Stats.Get(feature[1]) ~= nil,
                "ChaosOriginsRemastered: missing origin spell " .. feature[1])
        end
    end
    validated = true
end

local function guarded(character)
    local result = guardedStatus[character]
    if result == nil then
        result = {}
        guardedStatus[character] = result
    end
    return result
end

local function statusesMatch(character, record)
    for _, definition in ipairs(M.Definitions) do
        local expected = record.ActiveOriginIdentity == definition.Name and 1 or 0
        if Osi.HasActiveStatus(character, definition.Status) ~= expected then return false end
    end
    return true
end

local function scheduleAlignment(character, record)
    if alignment[character] ~= nil then return end
    local operation = { Elapsed = 0, Record = record }
    alignment[character] = operation
    local function verify()
        Ext.Timer.WaitFor(VERIFY_INTERVAL_MS, function()
            if alignment[character] ~= operation then return end
            if not ChaosCharacter.IsEligible(character) then
                alignment[character] = nil
                return
            end
            local allPassivesReady = true
            for _, definition in ipairs(M.Definitions) do
                if Osi.HasPassive(character, definition.Passive) == 0 then allPassivesReady = false end
            end
            if allPassivesReady and statusesMatch(character, operation.Record) then
                alignment[character] = nil
                return
            end
            if allPassivesReady then
                local guard = guarded(character)
                for _, definition in ipairs(M.Definitions) do
                    local expected = operation.Record.ActiveOriginIdentity == definition.Name and 1 or 0
                    if Osi.HasActiveStatus(character, definition.Status) ~= expected
                        and guard[definition.Status] == nil then
                        -- TogglePassive 没有显式目标参数，因此先比对状态，再记录预期事件并翻转一次。
                        guard[definition.Status] = expected == 1
                        Osi.TogglePassive(character, definition.Passive)
                    end
                end
            end
            operation.Elapsed = operation.Elapsed + VERIFY_INTERVAL_MS
            assert(operation.Elapsed < VERIFY_TIMEOUT_MS,
                "ChaosOriginsRemastered: origin identity toggles did not align after "
                    .. tostring(VERIFY_TIMEOUT_MS) .. " ms for " .. character)
            verify()
        end)
    end
    verify()
end

local function desiredFeatures(record, level)
    local passives, spells, tags = {}, {}, {}
    local definition = byName[record.ActiveOriginIdentity]
    if definition ~= nil then
        tags[definition.Tag] = true
        for _, feature in ipairs(definition.Passives) do
            if feature[2] <= level then passives[feature[1]] = true end
        end
        for _, feature in ipairs(definition.Spells) do
            if feature[2] <= level then spells[feature[1]] = true end
        end
    end
    return passives, spells, tags
end

function M.Sync(character, record)
    validateStats()
    character = ChaosCharacter.CanonicalGuid(character, "origin identity character")
    for _, definition in ipairs(M.Definitions) do
        GrantLedger.EnsurePassive(character, record, definition.Passive)
    end
    local desiredPassives, desiredSpells, desiredTags = desiredFeatures(record, Osi.GetLevel(character))
    for passive in pairs(record.OriginGranted.Passives) do
        if not desiredPassives[passive] then
            GrantLedger.RemovePassive(character, record, passive, record.OriginGranted.Passives)
        end
    end
    for spell in pairs(record.OriginGranted.Spells) do
        if not desiredSpells[spell] then
            GrantLedger.RemoveSpell(character, record, spell, record.OriginGranted.Spells)
        end
    end
    for tag in pairs(record.OriginGranted.Tags) do
        if not desiredTags[tag] then
            GrantLedger.RemoveTag(character, record, tag, record.OriginGranted.Tags)
        end
    end
    for passive in pairs(desiredPassives) do
        GrantLedger.EnsurePassive(character, record, passive, record.OriginGranted.Passives)
    end
    for spell in pairs(desiredSpells) do
        GrantLedger.EnsureSpell(character, record, spell, record.OriginGranted.Spells)
    end
    for tag in pairs(desiredTags) do
        -- 永久标签参与官方剧情与 Osiris 判定；账本只认领本 MOD 实际设置的标签。
        GrantLedger.EnsureTag(character, record, tag, record.OriginGranted.Tags)
    end
    scheduleAlignment(character, record)
end

function M.IsStatus(status)
    return byStatus[status] ~= nil
end

function M.HandleStatus(character, status, enabled, record)
    local definition = byStatus[status]
    assert(definition ~= nil, "ChaosOriginsRemastered: unknown origin status " .. tostring(status))
    character = ChaosCharacter.CanonicalGuid(character, "origin toggle character")
    local guard = guarded(character)
    if guard[status] ~= nil then
        assert(guard[status] == enabled,
            "ChaosOriginsRemastered: origin toggle produced an unexpected state " .. status)
        guard[status] = nil
        return false
    end
    if Osi.IsInCombat(character) ~= 0 then
        -- 战斗中立即恢复原状态，避免战斗与剧情条件在同一帧发生变化。
        guard[status] = not enabled
        Osi.TogglePassive(character, definition.Passive)
        return false
    end
    if enabled then record.ActiveOriginIdentity = definition.Name
    elseif record.ActiveOriginIdentity == definition.Name then record.ActiveOriginIdentity = "" end
    State.MarkDirty()
    return true
end

function M.SetActive(character, record, identity)
    assert(identity == "" or byName[identity] ~= nil,
        "ChaosOriginsRemastered: invalid requested origin identity " .. tostring(identity))
    if record.ActiveOriginIdentity == identity then return false end
    assert(Osi.IsInCombat(character) == 0,
        "ChaosOriginsRemastered: origin identity cannot change in combat")
    record.ActiveOriginIdentity = identity
    State.MarkDirty()
    return true
end

function M.ResetRuntime()
    alignment = {}
    guardedStatus = {}
end

return M
