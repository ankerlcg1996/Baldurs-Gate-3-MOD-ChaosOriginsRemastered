local MODULE_UUID = "9112dfde-d843-408f-b59b-9c893f5f7d92"
local ORIGIN_UUID = "37914c47-d2f2-433d-9635-3e3040a4663f"
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local State = Ext.Require("ChaosState.lua")
local BaseFeatures = Ext.Require("BaseFeatures.lua")
local StarterRewards = Ext.Require("StarterRewards.lua")

State.Register()

local syncing = {}

local function syncCharacter(character)
    if not ChaosCharacter.IsEligible(character) then return end
    if syncing[character] then
        Ext.Utils.PrintWarning("ChaosOriginsRemastered: skipped re-entrant sync for " .. character)
        return
    end

    syncing[character] = true
    local ok, failure = pcall(function()
        local record = State.GetCharacter(character)
        BaseFeatures.Sync(character, record)
        StarterRewards.Sync(character, record)
    end)
    syncing[character] = nil
    if not ok then error(failure) end
end

local function scheduleCharacter(character, delay)
    Ext.Timer.WaitFor(delay, function() syncCharacter(character) end)
end

local function scheduleAllPlayers(delay)
    Ext.Timer.WaitFor(delay, function()
        -- 玩家数据库是唯一枚举入口，避免扫描并误处理同伴、NPC 或召唤物。
        for _, character in ipairs(ChaosCharacter.Players()) do
            syncCharacter(character)
        end
    end)
end

Ext.Events.SessionLoaded:Subscribe(function()
    syncing = {}
    StarterRewards.ResetRuntime()
end)

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function()
    scheduleAllPlayers(500)
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
    SyncCharacter = syncCharacter
}
