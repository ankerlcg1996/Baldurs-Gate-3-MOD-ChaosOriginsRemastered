local M = {}
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")

local MODULE_UUID = "9112dfde-d843-408f-b59b-9c893f5f7d92"
local STATE_NAME = "State"
local SCHEMA_VERSION = 6
local registered = false
local ORIGIN_IDENTITY_KEYS = {
    "Astarion", "Gale", "Laezel", "Shadowheart", "Wyll", "Karlach", "DarkUrge"
}
local WOUND_EFFECT_KEYS = {
    "Madness", "Frightened", "Stunned", "Silenced", "Prone", "Blinded", "Slowed",
    "Poisoned", "Bleeding", "Burning", "MeleeDisadvantage", "RangedDisadvantage",
    "SpellDisadvantage", "Vulnerability", "ExtraDamage"
}

local function defaultWoundEffects()
    local result = {}
    for _, key in ipairs(WOUND_EFFECT_KEYS) do result[key] = true end
    return result
end

local function defaultOriginIdentities()
    local result = {}
    for _, key in ipairs(ORIGIN_IDENTITY_KEYS) do result[key] = false end
    return result
end

local function assertOnlyKeys(value, allowed, label)
    for key in pairs(value) do
        assert(allowed[key] == true,
            "ChaosOriginsRemastered: unknown " .. label .. " field " .. tostring(key))
    end
end

local function validateGrantMap(value, label)
    assert(type(value) == "table", "ChaosOriginsRemastered: " .. label .. " must be a table")
    for key, owned in pairs(value) do
        assert(type(key) == "string"
            and (owned == true or owned == "adding" or owned == "removing"),
            "ChaosOriginsRemastered: invalid " .. label .. " entry " .. tostring(key))
    end
end

local function validateLegacyFields(record, characterId)
    assert(type(record.Granted) == "table",
        "ChaosOriginsRemastered: grant ledger must be a table " .. characterId)
    assertOnlyKeys(record.Granted, { Passives = true, Spells = true }, "grant ledger")
    validateGrantMap(record.Granted.Passives, "passive grant ledger")
    validateGrantMap(record.Granted.Spells, "spell grant ledger")

    assert(type(record.RewardItems) == "table",
        "ChaosOriginsRemastered: reward ledger must be a table " .. characterId)
    for template, object in pairs(record.RewardItems) do
        assert(type(template) == "string" and type(object) == "string" and object ~= "",
            "ChaosOriginsRemastered: invalid reward ledger entry " .. tostring(template))
    end
    assert(record.StarterRewardsVersion == 0 or record.StarterRewardsVersion == 1,
        "ChaosOriginsRemastered: invalid starter reward version " .. characterId)
end

local function validateLegacyCharacter(record, characterId)
    assert(type(record) == "table",
        "ChaosOriginsRemastered: character state must be a table " .. characterId)
    assertOnlyKeys(record, {
        Granted = true,
        RewardItems = true,
        StarterRewardsVersion = true
    }, "character state")
    validateLegacyFields(record, characterId)
end

local function validateCharacter(record, characterId)
    assert(type(record) == "table",
        "ChaosOriginsRemastered: character state must be a table " .. characterId)
    assertOnlyKeys(record, {
        Granted = true,
        RaceGranted = true,
        OriginGranted = true,
        OriginIdentities = true,
        MechanicGranted = true,
        Mechanics = true,
        WoundEffects = true,
        ChaosPower = true,
        KillCount = true,
        LostCount = true,
        WoundConsumedThisRound = true,
        LastWoundOutcome = true,
        AllInEnabled = true,
        NativeRaceTags = true,
        RewardItems = true,
        StarterRewardsVersion = true
    }, "character state")
    validateLegacyFields(record, characterId)

    assert(type(record.RaceGranted) == "table",
        "ChaosOriginsRemastered: racial grant ledger must be a table " .. characterId)
    assertOnlyKeys(record.RaceGranted,
        { Passives = true, Spells = true, Tags = true }, "racial grant ledger")
    validateGrantMap(record.RaceGranted.Passives, "racial passive grant ledger")
    validateGrantMap(record.RaceGranted.Spells, "racial spell grant ledger")
    validateGrantMap(record.RaceGranted.Tags, "racial tag grant ledger")

    assert(type(record.OriginGranted) == "table",
        "ChaosOriginsRemastered: origin grant ledger must be a table " .. characterId)
    assertOnlyKeys(record.OriginGranted,
        { Passives = true, Spells = true, Tags = true }, "origin grant ledger")
    validateGrantMap(record.OriginGranted.Passives, "origin passive grant ledger")
    validateGrantMap(record.OriginGranted.Spells, "origin spell grant ledger")
    validateGrantMap(record.OriginGranted.Tags, "origin tag grant ledger")
    assert(type(record.OriginIdentities) == "table",
        "ChaosOriginsRemastered: origin identities must be a table " .. characterId)
    local expectedIdentities = defaultOriginIdentities()
    assertOnlyKeys(record.OriginIdentities, expectedIdentities, "origin identities")
    local identityCount = 0
    for key, enabled in pairs(record.OriginIdentities) do
        assert(type(enabled) == "boolean",
            "ChaosOriginsRemastered: invalid origin identity toggle " .. tostring(key))
        identityCount = identityCount + 1
    end
    assert(identityCount == #ORIGIN_IDENTITY_KEYS,
        "ChaosOriginsRemastered: origin identity toggle set is incomplete " .. characterId)

    assert(type(record.MechanicGranted) == "table",
        "ChaosOriginsRemastered: mechanic grant ledger must be a table " .. characterId)
    assertOnlyKeys(record.MechanicGranted,
        { Passives = true, Spells = true }, "mechanic grant ledger")
    validateGrantMap(record.MechanicGranted.Passives, "mechanic passive grant ledger")
    validateGrantMap(record.MechanicGranted.Spells, "mechanic spell grant ledger")
    local mechanicKeys = {
        Skills = true, Power = true, Wound = true, KillPower = true,
        Duality = true, AllIn = true, Echo = true, Strike = true, DebugLogging = true
    }
    assert(type(record.Mechanics) == "table", "ChaosOriginsRemastered: mechanics must be a table")
    assertOnlyKeys(record.Mechanics, mechanicKeys, "mechanics")
    for key in pairs(mechanicKeys) do
        assert(type(record.Mechanics[key]) == "boolean",
            "ChaosOriginsRemastered: mechanic toggle must be boolean " .. key)
    end
    assert(type(record.WoundEffects) == "table",
        "ChaosOriginsRemastered: wound-effect toggles must be a table")
    local expectedWoundEffects = defaultWoundEffects()
    assertOnlyKeys(record.WoundEffects, expectedWoundEffects, "wound-effect toggles")
    local woundEffectCount = 0
    for key, enabled in pairs(record.WoundEffects) do
        assert(type(enabled) == "boolean",
            "ChaosOriginsRemastered: invalid wound-effect toggle " .. tostring(key))
        woundEffectCount = woundEffectCount + 1
    end
    assert(woundEffectCount == #WOUND_EFFECT_KEYS,
        "ChaosOriginsRemastered: wound-effect toggle set is incomplete")
    for _, field in ipairs({ "ChaosPower", "KillCount", "LostCount" }) do
        local value = record[field]
        assert(type(value) == "number" and value >= 0 and value % 1 == 0,
            "ChaosOriginsRemastered: invalid mechanic counter " .. field)
    end
    assert(record.LostCount <= 10, "ChaosOriginsRemastered: LostCount exceeds ten")
    assert(type(record.WoundConsumedThisRound) == "boolean",
        "ChaosOriginsRemastered: WoundConsumedThisRound must be boolean")
    assert(type(record.LastWoundOutcome) == "string",
        "ChaosOriginsRemastered: LastWoundOutcome must be a string")
    assert(type(record.AllInEnabled) == "boolean",
        "ChaosOriginsRemastered: AllInEnabled must be boolean")

    assert(type(record.NativeRaceTags) == "table",
        "ChaosOriginsRemastered: native race-tag order must be a table " .. characterId)
    local seenTags = {}
    local tagCount = 0
    for index, tag in pairs(record.NativeRaceTags) do
        assert(type(index) == "number" and index >= 1 and index % 1 == 0
            and type(tag) == "string" and not seenTags[tag],
            "ChaosOriginsRemastered: invalid native race-tag order entry " .. tostring(tag))
        ChaosCharacter.CanonicalGuid(tag, "native race tag")
        seenTags[tag] = true
        tagCount = tagCount + 1
    end
    assert(tagCount == #record.NativeRaceTags,
        "ChaosOriginsRemastered: native race-tag order must be a dense array " .. characterId)
end

local function newCharacter()
    return {
        Granted = { Passives = {}, Spells = {} },
        RaceGranted = { Passives = {}, Spells = {}, Tags = {} },
        OriginGranted = { Passives = {}, Spells = {}, Tags = {} },
        OriginIdentities = defaultOriginIdentities(),
        MechanicGranted = { Passives = {}, Spells = {} },
        Mechanics = {
            Skills = true, Power = true, Wound = true, KillPower = true,
            Duality = true, AllIn = true, Echo = true, Strike = true, DebugLogging = false
        },
        WoundEffects = defaultWoundEffects(),
        ChaosPower = 0,
        KillCount = 0,
        LostCount = 0,
        WoundConsumedThisRound = false,
        LastWoundOutcome = "",
        AllInEnabled = false,
        NativeRaceTags = {},
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
        variables[STATE_NAME] = { SchemaVersion = SCHEMA_VERSION, Characters = {}, PendingDuality = {} }
        M.MarkDirty()
    end

    local state = variables[STATE_NAME]
    assert(type(state) == "table", "ChaosOriginsRemastered: saved state must be a table")
    assertOnlyKeys(state,
        { SchemaVersion = true, Characters = true, PendingDuality = true }, "saved state")
    assert(type(state.Characters) == "table",
        "ChaosOriginsRemastered: saved character map must be a table")
    if state.SchemaVersion == 1 then
        -- 1.0.08 存档只新增独立种族账本，旧能力与已有物品记录原样保留。
        for characterId, record in pairs(state.Characters) do
            validateLegacyCharacter(record, characterId)
            record.RaceGranted = { Passives = {}, Spells = {}, Tags = {} }
            record.NativeRaceTags = {}
            record.OriginGranted = { Passives = {}, Spells = {}, Tags = {} }
            record.ActiveOriginIdentity = ""
        end
        state.SchemaVersion = 3
        M.MarkDirty()
    end
    if state.SchemaVersion == 2 then
        -- 1.0.09 及以前没有起源身份开关；迁移后保持全部关闭，避免读档时自动触发剧情。
        for characterId, record in pairs(state.Characters) do
            record.OriginGranted = { Passives = {}, Spells = {}, Tags = {} }
            record.ActiveOriginIdentity = ""
        end
        state.SchemaVersion = 3
        M.MarkDirty()
    end
    if state.SchemaVersion == 3 then
        -- 1.0.09 的存档没有正式混沌机制字段；全部机制按设计默认开启。
        for _, record in pairs(state.Characters) do
            local defaults = newCharacter()
            record.MechanicGranted = defaults.MechanicGranted
            record.Mechanics = defaults.Mechanics
            record.WoundEffects = defaults.WoundEffects
            record.ChaosPower = 0
            record.KillCount = 0
            record.LostCount = 0
            record.WoundConsumedThisRound = false
            record.LastWoundOutcome = ""
            record.AllInEnabled = false
        end
        state.PendingDuality = {}
        state.SchemaVersion = 4
        M.MarkDirty()
    end
    if state.SchemaVersion == 4 then
        -- 1.0.13 以前只用临时状态模拟起源身份，没有实际官方标签归属账本。
        for _, record in pairs(state.Characters) do
            record.OriginGranted.Tags = {}
        end
        state.SchemaVersion = 5
        M.MarkDirty()
    end
    if state.SchemaVersion == 5 then
        -- 旧版起源身份是单选字符串；迁移后保留原选项并改为七个独立开关。
        local validIdentity = { [""] = true }
        for _, key in ipairs(ORIGIN_IDENTITY_KEYS) do validIdentity[key] = true end
        for characterId, record in pairs(state.Characters) do
            assert(type(record.ActiveOriginIdentity) == "string"
                and validIdentity[record.ActiveOriginIdentity] == true,
                "ChaosOriginsRemastered: invalid legacy origin identity "
                    .. tostring(record.ActiveOriginIdentity) .. " for " .. characterId)
            record.OriginIdentities = defaultOriginIdentities()
            if record.ActiveOriginIdentity ~= "" then
                record.OriginIdentities[record.ActiveOriginIdentity] = true
            end
            record.ActiveOriginIdentity = nil
        end
        state.SchemaVersion = SCHEMA_VERSION
        M.MarkDirty()
    end
    assert(state.SchemaVersion == SCHEMA_VERSION,
        "ChaosOriginsRemastered: unsupported saved-state schema " .. tostring(state.SchemaVersion))
    assert(type(state.PendingDuality) == "table",
        "ChaosOriginsRemastered: PendingDuality must be a table")
    local pendingDualityCount = 0
    for index, entry in pairs(state.PendingDuality) do
        assert(type(index) == "number" and index >= 1 and index % 1 == 0
            and type(entry) == "table",
            "ChaosOriginsRemastered: invalid delayed Duality entry")
        pendingDualityCount = pendingDualityCount + 1
        assertOnlyKeys(entry,
            { Trigger = true, Source = true, Target = true, Damages = true }, "delayed Duality")
        ChaosCharacter.CanonicalGuid(entry.Trigger, "delayed Duality trigger")
        ChaosCharacter.CanonicalGuid(entry.Source, "delayed Duality source")
        ChaosCharacter.CanonicalGuid(entry.Target, "delayed Duality target")
        assert(type(entry.Damages) == "table", "ChaosOriginsRemastered: delayed damage map is invalid")
        for damageType, amount in pairs(entry.Damages) do
            assert(type(damageType) == "string" and type(amount) == "number"
                and amount >= 0 and amount % 1 == 0,
                "ChaosOriginsRemastered: invalid delayed damage entry " .. tostring(damageType))
        end
    end
    assert(pendingDualityCount == #state.PendingDuality,
        "ChaosOriginsRemastered: PendingDuality must be a dense array")
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

function M.GetRoot()
    return root()
end

return M
