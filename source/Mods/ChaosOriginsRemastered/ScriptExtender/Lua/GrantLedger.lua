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
        if operation.Matches(operation.Character, operation.StatId, operation.Applied) then
            if operation.Desired == operation.Applied then
                -- 只有引擎确认最新目标已生效，才更新 MOD 归属账本。
                operation.Ledger[operation.StatId] = operation.Desired == 1 and true or nil
                pending[operation.Key] = nil
                State.MarkDirty()
                return
            end

            -- 等待前一次异步写入落地后，再执行期间到达的相反目标。
            operation.Applied = operation.Desired
            operation.SetState(operation.Character, operation.StatId, operation.Applied)
            scheduleVerification(operation, 0)
            return
        end

        local nextElapsed = elapsed + VERIFY_INTERVAL_MS
        if nextElapsed >= VERIFY_TIMEOUT_MS then
            pending[operation.Key] = nil
            error("ChaosOriginsRemastered: timed out waiting for " .. operation.Kind .. " "
                .. operation.StatId .. " on " .. operation.Character
                .. " (applied=" .. tostring(operation.Applied)
                .. ", desired=" .. tostring(operation.Desired) .. ")")
        end
        scheduleVerification(operation, nextElapsed)
    end)
end

local function start(character, statId, kind, expected, matches, setState, ledger, validateStat)
    character = ChaosCharacter.CanonicalGuid(character, kind .. " character")
    if validateStat then requireStat(statId, kind) end
    local key = verificationKey(character, kind, statId)
    local operation = pending[key]
    if operation ~= nil then
        if operation.Desired ~= expected then
            assert(operation.Ledger == ledger,
                "ChaosOriginsRemastered: conflicting ledgers for pending " .. kind .. " " .. statId)
            operation.Desired = expected
            operation.Ledger[statId] = expected == 1 and "adding" or "removing"
            State.MarkDirty()
        end
        return false
    end

    if matches(character, statId, expected) then
        if expected == 1 and ledger[statId] ~= nil and ledger[statId] ~= true then
            ledger[statId] = true
            State.MarkDirty()
        elseif expected == 0 and ledger[statId] ~= nil then
            ledger[statId] = nil
            State.MarkDirty()
        end
        return false
    end

    -- 先持久化意图；切换会话后可根据实际状态确认或重试，不会留下无主授予。
    ledger[statId] = expected == 1 and "adding" or "removing"
    State.MarkDirty()
    setState(character, statId, expected)
    operation = {
        Key = key,
        Character = character,
        StatId = statId,
        Kind = kind,
        Applied = expected,
        Desired = expected,
        Matches = matches,
        SetState = setState,
        Ledger = ledger
    }
    pending[key] = operation
    scheduleVerification(operation, 0)
    return true
end

function M.EnsurePassive(character, record, passive, ledger)
    ledger = ledger or record.Granted.Passives
    return start(character, passive, "passive", 1,
        function(target, statId, expected) return Osi.HasPassive(target, statId) == expected end,
        function(target, statId, desired)
            if desired == 1 then Osi.AddPassive(target, statId)
            else Osi.RemovePassive(target, statId) end
        end,
        ledger, true)
end

local function includeContainerSpells(spell)
    local stat = assert(Ext.Stats.Get(spell),
        "ChaosOriginsRemastered: missing spell stat " .. spell)
    return type(stat.ContainerSpells) == "string" and stat.ContainerSpells ~= "" and 1 or 0
end

local function spellFamily(spell)
    local stat = assert(Ext.Stats.Get(spell),
        "ChaosOriginsRemastered: missing spell stat " .. spell)
    local family = { spell }
    if type(stat.ContainerSpells) == "string" and stat.ContainerSpells ~= "" then
        for child in string.gmatch(stat.ContainerSpells, "[^;]+") do
            family[#family + 1] = child
        end
    end
    return family
end

local function spellFamilyMatches(target, spell, expected)
    -- 容器法术必须让父项和全部子项同时达到目标状态，不能只确认父项。
    for _, member in ipairs(spellFamily(spell)) do
        if Osi.HasSpell(target, member) ~= expected then return false end
    end
    return true
end

function M.EnsureSpell(character, record, spell, ledger)
    ledger = ledger or record.Granted.Spells
    return start(character, spell, "spell", 1,
        spellFamilyMatches,
        function(target, statId, desired)
            if desired == 1 then
                Osi.AddSpell(target, statId, 0, includeContainerSpells(statId))
            else
                Osi.RemoveSpell(target, statId, includeContainerSpells(statId))
            end
        end,
        ledger, true)
end

function M.EnsureTag(character, record, tag, ledger)
    assert(type(ledger) == "table", "ChaosOriginsRemastered: tag ledger is unavailable")
    return start(character, tag, "tag", 1,
        function(target, tagId, expected) return Osi.IsTagged(target, tagId) == expected end,
        function(target, tagId, desired)
            if desired == 1 then Osi.SetTag(target, tagId)
            else Osi.ClearTag(target, tagId) end
        end,
        ledger, false)
end

function M.RemoveTag(character, record, tag, ledger)
    assert(ledger[tag] == true or ledger[tag] == "adding" or ledger[tag] == "removing",
        "ChaosOriginsRemastered: cannot remove unowned tag " .. tag)
    return start(character, tag, "tag", 0,
        function(target, tagId, expected) return Osi.IsTagged(target, tagId) == expected end,
        function(target, tagId, desired)
            if desired == 1 then Osi.SetTag(target, tagId)
            else Osi.ClearTag(target, tagId) end
        end,
        ledger, false)
end

function M.RemovePassive(character, record, passive, ledger)
    assert(ledger[passive] == true or ledger[passive] == "adding"
        or ledger[passive] == "removing",
        "ChaosOriginsRemastered: cannot remove unowned passive " .. passive)
    return start(character, passive, "passive", 0,
        function(target, statId, expected) return Osi.HasPassive(target, statId) == expected end,
        function(target, statId, desired)
            if desired == 1 then Osi.AddPassive(target, statId)
            else Osi.RemovePassive(target, statId) end
        end,
        ledger, true)
end

function M.RemoveSpell(character, record, spell, ledger)
    assert(ledger[spell] == true or ledger[spell] == "adding"
        or ledger[spell] == "removing",
        "ChaosOriginsRemastered: cannot remove unowned spell " .. spell)
    return start(character, spell, "spell", 0,
        spellFamilyMatches,
        function(target, statId, desired)
            if desired == 1 then
                Osi.AddSpell(target, statId, 0, includeContainerSpells(statId))
            else
                Osi.RemoveSpell(target, statId, includeContainerSpells(statId))
            end
        end,
        ledger, true)
end

function M.ResetRuntime()
    -- 切换存档后旧会话的延时确认失效，新会话会重新检查实际能力状态。
    pending = {}
end

return M
