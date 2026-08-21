local State = Ext.Require("ChaosState.lua")
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local GrantLedger = Ext.Require("GrantLedger.lua")
local Catalog = Ext.Require("RaceCatalog.lua")
local M = {}

local NULL_UUID = "00000000-0000-0000-0000-000000000000"
local validated = false

local function optionalRaceGuid(value, label)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" or string.sub(text, -36) == NULL_UUID then return nil end
    return ChaosCharacter.CanonicalGuid(value, label)
end

function M.IsReady(character)
    local entity = Ext.Entity.Get(character)
    return entity ~= nil and entity.CharacterCreationStats ~= nil
end

local function nativeRaceTags(character)
    local entity = assert(Ext.Entity.Get(character),
        "ChaosOriginsRemastered: race character entity is unavailable " .. character)
    local creation = assert(entity.CharacterCreationStats,
        "ChaosOriginsRemastered: character creation stats are unavailable " .. character)
    local tags = {}
    local order = {}
    local visitedRaces = {}

    local function addAncestry(value, label)
        local raceUuid = optionalRaceGuid(value, label)
        while raceUuid ~= nil and raceUuid ~= Catalog.PlayableParentRoot do
            if visitedRaces[raceUuid] then return end
            local race = assert(Catalog.Races[raceUuid],
                "ChaosOriginsRemastered: selected race is absent from the audited catalog "
                    .. raceUuid .. " for " .. character)
            visitedRaces[raceUuid] = true
            for _, tag in ipairs(race.Tags) do
                if not tags[tag] then
                    tags[tag] = true
                    order[#order + 1] = tag
                end
            end
            raceUuid = race.Parent
        end
    end

    -- 子种族标签必须先于父种族，这就是角色的原生种族身份顺序。
    addAncestry(creation.SubRace, "selected subrace")
    addAncestry(creation.Race, "selected race")
    assert(#order > 0,
        "ChaosOriginsRemastered: selected race has no identity tags for " .. character)
    return tags, order
end

local function validateCatalog()
    if validated then return end
    assert(Catalog.Schema == 1 and Catalog.CandidateSpellPolicy == "grant_all",
        "ChaosOriginsRemastered: unsupported race catalog policy")
    assert(Catalog.RaceCount == 39 and Catalog.TagCount == 32
        and Catalog.PassiveCount == 20 and Catalog.SpellCount == 29,
        "ChaosOriginsRemastered: audited race catalog counts changed")
    for _, level in ipairs(Catalog.FeatureLevels) do
        local features = assert(Catalog.FeaturesByLevel[level],
            "ChaosOriginsRemastered: missing racial feature level " .. tostring(level))
        for _, passive in ipairs(features.Passives) do
            assert(Ext.Stats.Get(passive) ~= nil,
                "ChaosOriginsRemastered: missing racial passive stat " .. passive)
        end
        for _, spell in ipairs(features.Spells) do
            assert(Ext.Stats.Get(spell) ~= nil,
                "ChaosOriginsRemastered: missing racial spell stat " .. spell)
        end
        assert(Ext.Stats.Get(Catalog.RacialSpellPassives[level]) ~= nil,
            "ChaosOriginsRemastered: missing racial spell grant passive "
                .. tostring(Catalog.RacialSpellPassives[level]))
    end
    validated = true
end

local function persistNativeOrder(record, actualOrder)
    if #record.NativeRaceTags == 0 then
        for index, tag in ipairs(actualOrder) do record.NativeRaceTags[index] = tag end
        State.MarkDirty()
        return
    end
    assert(#record.NativeRaceTags == #actualOrder,
        "ChaosOriginsRemastered: saved native race-tag count changed")
    for index, tag in ipairs(actualOrder) do
        assert(record.NativeRaceTags[index] == tag,
            "ChaosOriginsRemastered: saved native race-tag order changed at "
                .. tostring(index))
    end
end

function M.Sync(character, record)
    character = ChaosCharacter.CanonicalGuid(character, "racial feature character")
    validateCatalog()
    local nativeTags, nativeOrder = nativeRaceTags(character)
    persistNativeOrder(record, nativeOrder)

    -- 原生标签只做存档记录；账本只记录 MOD 实际新增的其他种族标签。
    for _, tag in ipairs(nativeOrder) do
        assert(Osi.IsTagged(character, tag) == 1,
            "ChaosOriginsRemastered: native race tag is missing " .. tag
                .. " for " .. character)
    end
    for _, tag in ipairs(Catalog.AllTags) do
        if not nativeTags[tag] then
            GrantLedger.EnsureTag(character, record, tag, record.RaceGranted.Tags)
        end
    end

    local level = Osi.GetLevel(character)
    assert(type(level) == "number" and level >= 1,
        "ChaosOriginsRemastered: invalid character level " .. tostring(level)
            .. " for racial features " .. character)
    local desiredPassives = {}
    for _, unlockLevel in ipairs(Catalog.FeatureLevels) do
        if unlockLevel <= level then
            local features = Catalog.FeaturesByLevel[unlockLevel]
            for _, passive in ipairs(features.Passives) do desiredPassives[passive] = true end
            -- 隐藏被动用官方 UnlockSpell 语义保留种族施法属性与长休次数。
            desiredPassives[Catalog.RacialSpellPassives[unlockLevel]] = true
        end
    end

    for passive in pairs(record.RaceGranted.Passives) do
        if not desiredPassives[passive] then
            GrantLedger.RemovePassive(character, record, passive, record.RaceGranted.Passives)
        end
    end
    for passive in pairs(desiredPassives) do
        GrantLedger.EnsurePassive(character, record, passive, record.RaceGranted.Passives)
    end
end

return M
