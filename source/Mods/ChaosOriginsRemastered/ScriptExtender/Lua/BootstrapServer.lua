local MODULE_UUID = "9112dfde-d843-408f-b59b-9c893f5f7d92"
local ORIGIN_UUID = "37914c47-d2f2-433d-9635-3e3040a4663f"
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local State = Ext.Require("ChaosState.lua")
local GrantLedger = Ext.Require("GrantLedger.lua")
local BaseFeatures = Ext.Require("BaseFeatures.lua")
local StarterRewards = Ext.Require("StarterRewards.lua")
local LEVEL_12_TOTAL_EXPERIENCE = 100000

State.Register()

local syncing = {}
local scheduled = {}

local function syncCharacter(character)
    character = ChaosCharacter.CanonicalGuid(character, "sync character")
    if not ChaosCharacter.IsEligible(character) then return end
    if syncing[character] then
        Ext.Utils.PrintWarning("ChaosOriginsRemastered: skipped re-entrant sync for " .. character)
        return
    end

    syncing[character] = true
    local ok, failure = xpcall(function()
        local record = State.GetCharacter(character)
        local failures = {}
        local function runIndependent(label, callback)
            local succeeded, reason = xpcall(callback, debug.traceback)
            if not succeeded then failures[#failures + 1] = label .. ": " .. reason end
        end

        -- 基础能力与奖励互不阻断，任一模块失败时另一模块仍能完成自己的同步。
        runIndependent("base features", function() BaseFeatures.Sync(character, record) end)
        runIndependent("starter rewards", function() StarterRewards.Sync(character, record) end)
        if #failures > 0 then
            error("ChaosOriginsRemastered: character sync failed " .. character
                .. "\n" .. table.concat(failures, "\n"))
        end
    end, debug.traceback)
    syncing[character] = nil
    if not ok then error(failure) end
end

local function scheduleCharacter(character, delay)
    character = ChaosCharacter.CanonicalGuid(character, "scheduled character")
    if scheduled[character] then return end
    scheduled[character] = true
    Ext.Timer.WaitFor(delay, function()
        scheduled[character] = nil
        syncCharacter(character)
    end)
end

local function scheduleAllPlayers(delay)
    Ext.Timer.WaitFor(delay, function()
        -- 玩家数据库是唯一枚举入口，避免扫描并误处理同伴、NPC 或召唤物。
        for _, character in ipairs(ChaosCharacter.Players()) do
            syncCharacter(character)
        end
    end)
end

local function grantLevel12TestExperience()
    local character = Osi.GetHostCharacter()
    assert(character ~= nil and character ~= "",
        "ChaosOriginsRemastered: host character is unavailable for test experience")
    character = ChaosCharacter.CanonicalGuid(character, "test experience character")
    if not ChaosCharacter.IsEligible(character) then return end

    local entity = assert(Ext.Entity.Get(character),
        "ChaosOriginsRemastered: host entity is unavailable for test experience " .. character)
    local experience = assert(entity.Experience,
        "ChaosOriginsRemastered: experience component is unavailable " .. character)
    local total = assert(experience.TotalExperience,
        "ChaosOriginsRemastered: total experience is unavailable " .. character)
    assert(type(total) == "number" and total >= 0,
        "ChaosOriginsRemastered: invalid total experience " .. tostring(total)
            .. " for " .. character)

    local missing = LEVEL_12_TOTAL_EXPERIENCE - total
    if missing > 0 then
        -- 测试版本只补足经验，不直接调用升级，仍由玩家逐级确认成长界面。
        Osi.AddExplorationExperience(character, missing)
        Ext.Utils.Print("ChaosOriginsRemastered: granted " .. tostring(missing)
            .. " test experience to " .. character)
    end
end

Ext.Events.SessionLoaded:Subscribe(function()
    syncing = {}
    scheduled = {}
    GrantLedger.ResetRuntime()
    StarterRewards.ResetRuntime()
end)

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function()
    scheduleAllPlayers(500)
    Ext.Timer.WaitFor(750, grantLevel12TestExperience)
end)

Ext.Osiris.RegisterListener("CharacterCreationFinished", 0, "after", function()
    scheduleAllPlayers(500)
end)

Ext.Osiris.RegisterListener("CharacterMadePlayer", 1, "after", function(character)
    scheduleCharacter(character, 200)
end)

Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", function(character)
    scheduleCharacter(character, 200)
end)

Ext.Osiris.RegisterListener("ObjectAvailableLevelChanged", 3, "after",
    function(character, _, _)
        scheduleCharacter(character, 200)
    end)

Ext.Osiris.RegisterListener("LeveledUp", 1, "after", function(character)
    scheduleCharacter(character, 500)
end)

return {
    ModuleUUID = MODULE_UUID,
    OriginUUID = ORIGIN_UUID,
    Level12TotalExperience = LEVEL_12_TOTAL_EXPERIENCE,
    SyncCharacter = syncCharacter
}
