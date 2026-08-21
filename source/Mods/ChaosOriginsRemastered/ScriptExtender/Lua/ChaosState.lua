local M = {}
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")

local MODULE_UUID = "9112dfde-d843-408f-b59b-9c893f5f7d92"
local STATE_NAME = "State"
local SCHEMA_VERSION = 1
local registered = false

local function assertOnlyKeys(value, allowed, label)
    for key in pairs(value) do
        assert(allowed[key] == true,
            "ChaosOriginsRemastered: unknown " .. label .. " field " .. tostring(key))
    end
end

local function validateBooleanMap(value, label)
    assert(type(value) == "table", "ChaosOriginsRemastered: " .. label .. " must be a table")
    for key, owned in pairs(value) do
        assert(type(key) == "string" and owned == true,
            "ChaosOriginsRemastered: invalid " .. label .. " entry " .. tostring(key))
    end
end

local function validateCharacter(record, characterId)
    assert(type(record) == "table",
        "ChaosOriginsRemastered: character state must be a table " .. characterId)
    assertOnlyKeys(record, {
        Granted = true,
        RewardItems = true,
        StarterRewardsVersion = true
    }, "character state")

    assert(type(record.Granted) == "table",
        "ChaosOriginsRemastered: grant ledger must be a table " .. characterId)
    assertOnlyKeys(record.Granted, { Passives = true, Spells = true }, "grant ledger")
    validateBooleanMap(record.Granted.Passives, "passive grant ledger")
    validateBooleanMap(record.Granted.Spells, "spell grant ledger")

    -- 保留 1.0.07 的奖励字段只为兼容旧存档；新版本不再读写或补发这些物品。
    assert(type(record.RewardItems) == "table",
        "ChaosOriginsRemastered: reward ledger must be a table " .. characterId)
    for template, object in pairs(record.RewardItems) do
        assert(type(template) == "string" and type(object) == "string" and object ~= "",
            "ChaosOriginsRemastered: invalid reward ledger entry " .. tostring(template))
    end
    assert(record.StarterRewardsVersion == 0 or record.StarterRewardsVersion == 1,
        "ChaosOriginsRemastered: invalid starter reward version " .. characterId)
end

local function newCharacter()
    return {
        Granted = { Passives = {}, Spells = {} },
        RewardItems = {},
        StarterRewardsVersion = 0
    }
end

function M.Register()
    assert(not registered, "ChaosOriginsRemastered: state variable was registered twice")
    Ext.Vars.RegisterModVariable(MODULE_UUID, STATE_NAME, {
        Server = true,
        Client = false,
        Persistent = true,
        WriteableOnServer = true,
        SyncToClient = false
    })
    registered = true
end

local function root()
    assert(registered, "ChaosOriginsRemastered: state variable is not registered")
    local variables = assert(Ext.Vars.GetModVariables(MODULE_UUID),
        "ChaosOriginsRemastered: mod variables are unavailable")
    if variables[STATE_NAME] == nil then
        -- 只有整个状态不存在时才初始化；已有但损坏的状态必须明确报错。
        variables[STATE_NAME] = { SchemaVersion = SCHEMA_VERSION, Characters = {} }
        M.MarkDirty()
    end

    local state = variables[STATE_NAME]
    assert(type(state) == "table", "ChaosOriginsRemastered: saved state must be a table")
    assertOnlyKeys(state, { SchemaVersion = true, Characters = true }, "saved state")
    assert(state.SchemaVersion == SCHEMA_VERSION,
        "ChaosOriginsRemastered: unsupported saved-state schema " .. tostring(state.SchemaVersion))
    assert(type(state.Characters) == "table",
        "ChaosOriginsRemastered: saved character map must be a table")
    return state
end

function M.MarkDirty()
    assert(registered, "ChaosOriginsRemastered: cannot persist unregistered state")
    Ext.Vars.DirtyModVariables(MODULE_UUID, STATE_NAME)
end

function M.CharacterId(character)
    local canonical = ChaosCharacter.CanonicalGuid(character, "character")
    local entity = assert(Ext.Entity.Get(canonical),
        "ChaosOriginsRemastered: character entity is unavailable " .. canonical)
    local uuid = assert(entity.Uuid,
        "ChaosOriginsRemastered: character UUID component is unavailable " .. canonical)
    assert(uuid.EntityUuid ~= nil,
        "ChaosOriginsRemastered: character UUID value is unavailable " .. canonical)
    return ChaosCharacter.CanonicalGuid(uuid.EntityUuid, "character entity")
end

function M.GetCharacter(character)
    local state = root()
    local characterId = M.CharacterId(character)
    local record = state.Characters[characterId]
    if record == nil then
        -- 每个存档、每个角色独立建账，避免跨角色认领或移除能力。
        record = newCharacter()
        state.Characters[characterId] = record
        M.MarkDirty()
    end
    validateCharacter(record, characterId)
    return record
end

return M
