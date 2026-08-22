local MODULE_UUID = "9112dfde-d843-408f-b59b-9c893f5f7d92"
local ORIGIN_UUID = "37914c47-d2f2-433d-9635-3e3040a4663f"
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local State = Ext.Require("ChaosState.lua")
local GrantLedger = Ext.Require("GrantLedger.lua")
local BaseFeatures = Ext.Require("BaseFeatures.lua")
local RaceFeatures = Ext.Require("RaceFeatures.lua")
local OriginFeatures = Ext.Require("OriginFeatures.lua")
local ChaosMechanics = Ext.Require("ChaosMechanics.lua")
local McmProtocol = Ext.Require("McmProtocol.lua")
local LEVEL_12_TOTAL_EXPERIENCE = 100000

State.Register()

local syncing = {}
local scheduled = {}
local sessionGeneration = 0
local READY_RETRY_MS = 100
local READY_TIMEOUT_MS = 2000
local mcmRevision = 0
local osirisReady = false
local mcmChannel = Ext.Net.CreateChannel(MODULE_UUID, McmProtocol.Channel)

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
        -- 豪华版物品属于官方 DLC，混沌起源只同步自身与官方种族能力。
        BaseFeatures.Sync(character, record)
        RaceFeatures.Sync(character, record)
        OriginFeatures.Sync(character, record)
        ChaosMechanics.Sync(character, record)
    end, debug.traceback)
    syncing[character] = nil
    if not ok then error(failure) end
end

local function queueCharacter(character, notBefore, readyElapsed)
    local request = {
        NotBefore = notBefore,
        ReadyElapsed = readyElapsed
    }
    local generation = sessionGeneration
    scheduled[character] = request
    local remaining = notBefore - Ext.Timer.MonotonicTime()
    if remaining < 0 then remaining = 0 end
    Ext.Timer.WaitFor(remaining, function()
        if generation ~= sessionGeneration or scheduled[character] ~= request then return end
        -- 单调时钟截止点避免后到事件只等待旧计时器的剩余时间。
        local now = Ext.Timer.MonotonicTime()
        if now < request.NotBefore then
            queueCharacter(character, request.NotBefore, request.ReadyElapsed)
            return
        end
        if not ChaosCharacter.IsEligible(character) then
            scheduled[character] = nil
            return
        end
        if not RaceFeatures.IsReady(character) then
            local nextElapsed = readyElapsed + READY_RETRY_MS
            assert(nextElapsed <= READY_TIMEOUT_MS,
                "ChaosOriginsRemastered: character creation stats were not ready after "
                    .. tostring(READY_TIMEOUT_MS) .. " ms for " .. character)
            queueCharacter(character, now + READY_RETRY_MS, nextElapsed)
            return
        end
        scheduled[character] = nil
        syncCharacter(character)
    end)
end

local function scheduleCharacter(character, delay)
    character = ChaosCharacter.CanonicalGuid(character, "scheduled character")
    assert(type(delay) == "number" and delay >= 0,
        "ChaosOriginsRemastered: invalid sync delay " .. tostring(delay))
    local notBefore = Ext.Timer.MonotonicTime() + delay
    local previous = scheduled[character]
    if previous ~= nil and previous.NotBefore > notBefore then
        notBefore = previous.NotBefore
    end
    local readyElapsed = previous ~= nil and previous.ReadyElapsed or 0
    -- 新事件重新满足完整延迟；一旦开始就绪轮询，则保留首次失败后的硬超时预算。
    queueCharacter(character, notBefore, readyElapsed)
end

local function scheduleAllPlayers(delay)
    local generation = sessionGeneration
    Ext.Timer.WaitFor(delay, function()
        if generation ~= sessionGeneration then return end
        -- 玩家数据库是唯一枚举入口，避免扫描并误处理同伴、NPC 或召唤物。
        for _, character in ipairs(ChaosCharacter.Players()) do
            scheduleCharacter(character, 0)
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

local function scheduleLevel12TestExperience(delay)
    local generation = sessionGeneration
    Ext.Timer.WaitFor(delay, function()
        if generation ~= sessionGeneration then return end
        grantLevel12TestExperience()
    end)
end

local function copyBooleanMap(source, definitions)
    local result = {}
    for _, definition in ipairs(definitions) do
        local key = definition[1]
        assert(type(source[key]) == "boolean",
            "ChaosOriginsRemastered: MCM snapshot field is not boolean " .. key)
        result[key] = source[key]
    end
    return result
end

local function hostSnapshot()
    if not osirisReady then
        -- 会话加载早期尚未建立 Osiris 查询适配器，MCM 只能报告等待状态。
        return { Ready = false, CharacterId = "", IsChaos = false, InCombat = false }
    end
    local host = Osi.GetHostCharacter()
    if host == nil or host == "" then
        return { Ready = false, CharacterId = "", IsChaos = false, InCombat = false }
    end
    host = ChaosCharacter.CanonicalGuid(host, "MCM host character")
    if not ChaosCharacter.IsEligible(host) then
        return { Ready = true, CharacterId = host, IsChaos = false,
            InCombat = Osi.IsInCombat(host) ~= 0 }
    end
    local saved = State.GetCharacter(host)
    return {
        Ready = true,
        CharacterId = host,
        IsChaos = true,
        InCombat = Osi.IsInCombat(host) ~= 0,
        OriginIdentities = copyBooleanMap(saved.OriginIdentities, McmProtocol.Origins),
        Mechanics = copyBooleanMap(saved.Mechanics, McmProtocol.Mechanics),
        WoundEffects = copyBooleanMap(saved.WoundEffects, McmProtocol.WoundEffects),
        ChaosPower = saved.ChaosPower,
        KillCount = saved.KillCount,
        LostCount = saved.LostCount,
        LastWoundOutcome = saved.LastWoundOutcome
    }
end

local function mcmReply(requestId, ok, code)
    return {
        Version = McmProtocol.Version,
        RequestId = requestId,
        Revision = mcmRevision,
        Ok = ok,
        Code = code or "",
        Snapshot = hostSnapshot()
    }
end

local function protocolContains(definitions, key)
    for _, definition in ipairs(definitions) do
        if definition[1] == key then return true end
    end
    return false
end

local function isHostPeer(peerId)
    assert(type(peerId) == "number" and peerId >= 0 and peerId % 1 == 0,
        "ChaosOriginsRemastered: invalid MCM peer id")
    local userId = (peerId & 0xffff0000) | 0x0001
    if userId == 65537 then return true end
    if not osirisReady then return false end
    local host = Osi.GetHostCharacter()
    for _, entity in pairs(Ext.Entity.GetAllEntitiesWithComponent("ClientControl")) do
        if entity.UserReservedFor.UserID == userId then
            return ChaosCharacter.CanonicalGuid(entity.Uuid.EntityUuid, "MCM peer character")
                == ChaosCharacter.CanonicalGuid(host, "MCM host character")
        end
    end
    return false
end

local function invalidateMcm()
    mcmRevision = mcmRevision + 1
    mcmChannel:Broadcast({
        Version = McmProtocol.Version,
        Type = "Invalidated",
        Revision = mcmRevision
    })
end

local function invalidateMcmIfHost(character)
    local host = Osi.GetHostCharacter()
    if host == nil or host == "" then return end
    if ChaosCharacter.CanonicalGuid(character, "MCM combat character")
        == ChaosCharacter.CanonicalGuid(host, "MCM combat host") then
        invalidateMcm()
    end
end

mcmChannel:SetRequestHandler(function(request, peerId)
    assert(type(request) == "table" and request.Version == McmProtocol.Version,
        "ChaosOriginsRemastered: invalid MCM protocol version")
    assert(type(request.RequestId) == "number" and request.RequestId >= 1
        and request.RequestId % 1 == 0, "ChaosOriginsRemastered: invalid MCM request id")
    assert(type(request.Action) == "string", "ChaosOriginsRemastered: invalid MCM action")
    if not isHostPeer(peerId) then return mcmReply(request.RequestId, false, "NOT_HOST") end
    if request.Action == "GetSnapshot" then return mcmReply(request.RequestId, true) end

    local snapshot = hostSnapshot()
    if not snapshot.Ready then return mcmReply(request.RequestId, false, "HOST_NOT_READY") end
    if not snapshot.IsChaos then return mcmReply(request.RequestId, false, "NOT_CHAOS") end
    if request.CharacterId ~= snapshot.CharacterId then
        return mcmReply(request.RequestId, false, "CHARACTER_CHANGED")
    end
    if snapshot.InCombat then return mcmReply(request.RequestId, false, "IN_COMBAT") end
    local saved = State.GetCharacter(snapshot.CharacterId)
    local changed = false
    if request.Action == "SetOrigin" then
        assert(type(request.Key) == "string"
            and protocolContains(McmProtocol.Origins, request.Key),
            "ChaosOriginsRemastered: invalid MCM origin")
        assert(type(request.Value) == "boolean",
            "ChaosOriginsRemastered: MCM origin value must be boolean")
        changed = OriginFeatures.SetEnabled(snapshot.CharacterId, saved, request.Key, request.Value)
    elseif request.Action == "SetMechanic" then
        assert(protocolContains(McmProtocol.Mechanics, request.Key),
            "ChaosOriginsRemastered: invalid MCM mechanic")
        assert(type(request.Value) == "boolean",
            "ChaosOriginsRemastered: MCM mechanic value must be boolean")
        changed = ChaosMechanics.SetMechanic(snapshot.CharacterId, saved, request.Key, request.Value)
    elseif request.Action == "SetWoundEffect" then
        assert(protocolContains(McmProtocol.WoundEffects, request.Key),
            "ChaosOriginsRemastered: invalid MCM wound effect")
        assert(type(request.Value) == "boolean",
            "ChaosOriginsRemastered: MCM wound value must be boolean")
        changed = ChaosMechanics.SetWoundEffect(saved, request.Key, request.Value)
    else
        error("ChaosOriginsRemastered: unsupported MCM action " .. request.Action)
    end
    if changed then
        scheduleCharacter(snapshot.CharacterId, 0)
        invalidateMcm()
    end
    return mcmReply(request.RequestId, true)
end)

Ext.Events.SessionLoaded:Subscribe(function()
    -- 会话代数让上一存档已排队的同步和测试经验闭包全部失效。
    osirisReady = false
    sessionGeneration = sessionGeneration + 1
    syncing = {}
    scheduled = {}
    GrantLedger.ResetRuntime()
    OriginFeatures.ResetRuntime()
    ChaosMechanics.ResetRuntime()
    mcmRevision = mcmRevision + 1
end)

local function handleOriginStatus(character, status, enabled)
    if not OriginFeatures.IsStatus(status) or not ChaosCharacter.IsEligible(character) then return end
    local record = State.GetCharacter(character)
    if OriginFeatures.HandleStatus(character, status, enabled, record) then
        scheduleCharacter(character, 200)
    end
end

Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(character, status, _, _)
    handleOriginStatus(character, status, true)
end)

Ext.Osiris.RegisterListener("StatusRemoved", 4, "after", function(character, status, _, _)
    handleOriginStatus(character, status, false)
end)

Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", function(character)
    invalidateMcmIfHost(character)
end)

Ext.Osiris.RegisterListener("LeftCombat", 2, "after", function(character)
    invalidateMcmIfHost(character)
end)

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function()
    osirisReady = true
    invalidateMcm()
    scheduleAllPlayers(500)
    scheduleLevel12TestExperience(750)
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

Ext.Osiris.RegisterListener("RespecCompleted", 1, "after", function(character)
    -- 洗点完成后以引擎的实际等级重新计算种族能力。
    scheduleCharacter(character, 500)
end)

Ext.Osiris.RegisterListener("RespecCancelled", 1, "after", function(character)
    scheduleCharacter(character, 500)
end)

return {
    ModuleUUID = MODULE_UUID,
    OriginUUID = ORIGIN_UUID,
    Level12TotalExperience = LEVEL_12_TOTAL_EXPERIENCE,
    SyncCharacter = syncCharacter
}
