local State = Ext.Require("ChaosState.lua")
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local M = {}
local pending = {}
local VERIFY_INTERVAL_MS = 100
local VERIFY_TIMEOUT_MS = 2000

local function requireStat(statId, kind)
    assert(Ext.Stats.Get(statId) ~= nil,
        "ChaosOriginsRemastered: missing " .. kind .. " stat " .. statId)
end

local function verificationKey(character, kind, statId)
    return character .. ":" .. kind .. ":" .. statId
end

local function scheduleVerification(operation, elapsed)
    Ext.Timer.WaitFor(VERIFY_INTERVAL_MS, function()
        if pending[operation.Key] ~= operation then return end
        if operation.Has(operation.Character, operation.StatId) == 1 then
            -- 只有引擎确认能力已经存在，才把它登记为本 MOD 所有。
            operation.Ledger[operation.StatId] = true
            pending[operation.Key] = nil
            State.MarkDirty()
            return
        end

        local nextElapsed = elapsed + VERIFY_INTERVAL_MS
        if nextElapsed >= VERIFY_TIMEOUT_MS then
            pending[operation.Key] = nil
            error("ChaosOriginsRemastered: timed out granting " .. operation.Kind .. " "
                .. operation.StatId .. " to " .. operation.Character)
        end
        scheduleVerification(operation, nextElapsed)
    end)
end

local function ensure(character, record, statId, kind, has, add, ledger)
    character = ChaosCharacter.CanonicalGuid(character, kind .. " character")
    requireStat(statId, kind)
    if has(character, statId) == 1 then return false end

    local key = verificationKey(character, kind, statId)
    if pending[key] ~= nil then return false end
    add(character, statId)
    local operation = {
        Key = key,
        Character = character,
        StatId = statId,
        Kind = kind,
        Has = has,
        Ledger = ledger
    }
    pending[key] = operation
    scheduleVerification(operation, 0)
    return true
end

function M.EnsurePassive(character, record, passive)
    return ensure(character, record, passive, "passive",
        function(target, statId) return Osi.HasPassive(target, statId) end,
        function(target, statId) Osi.AddPassive(target, statId) end,
        record.Granted.Passives)
end

function M.EnsureSpell(character, record, spell)
    return ensure(character, record, spell, "spell",
        function(target, statId) return Osi.HasSpell(target, statId) end,
        function(target, statId) Osi.AddSpell(target, statId, 0, 0) end,
        record.Granted.Spells)
end

function M.ResetRuntime()
    -- 切换存档后旧会话的延时确认失效，新会话会重新检查实际能力状态。
    pending = {}
end

return M
