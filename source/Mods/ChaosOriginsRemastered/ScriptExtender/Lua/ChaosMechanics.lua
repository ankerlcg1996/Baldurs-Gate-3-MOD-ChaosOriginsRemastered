local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local State = Ext.Require("ChaosState.lua")
local Roll = Ext.Require("ChaosNativeRoll.lua")
local Duality = Ext.Require("ChaosDuality.lua")
local Features = Ext.Require("MechanicsFeatures.lua")
local DebugLog = Ext.Require("DebugLog.lua")
local GrantLedger = Ext.Require("GrantLedger.lua")
local M = {}

-- 所有运行时队列都按会话代数隔离，切换存档后旧计时器不能写入新存档。
local generation = 0
local echoPending = {}
local echoApplying = {}
local consumedActions = {}
local processedKills = {}
local woundInitialized = {}

local DAMAGE_TYPES = {
    "Acid", "Cold", "Fire", "Force", "Lightning",
    "Necrotic", "Poison", "Psychic", "Radiant", "Thunder"
}
local LOST_CHANCES = { 5, 10, 15, 25, 35, 50, 65, 80, 90, 100 }
local NEGATIVE_OUTCOMES = {
    "Madness", "Frightened", "Stunned", "Silenced", "Prone", "Blinded", "Slowed",
    "Poisoned", "Bleeding", "Burning", "MeleeDisadvantage", "RangedDisadvantage",
    "SpellDisadvantage", "Vulnerability", "ExtraDamage"
}
local POSITIVE_OUTCOMES = {
    "Bless", "Haste", "Blur", "Heroism", "Invisibility", "MeleeAdvantage",
    "RangedAdvantage", "SpellAdvantage", "RestoreDamage", "Bloodlust", "Wet"
}
local NEGATIVE_STATUSES = {
    Madness = "MADNESS", Frightened = "FRIGHTENED", Stunned = "STUNNED",
    Silenced = "SILENCED", Prone = "PRONE", Blinded = "BLINDED", Slowed = "SLOW",
    Poisoned = "POISONED", Bleeding = "BLEEDING", Burning = "BURNING",
    MeleeDisadvantage = "COR_CHAOS_WOUND_MELEE_DISADVANTAGE",
    RangedDisadvantage = "COR_CHAOS_WOUND_RANGED_DISADVANTAGE",
    SpellDisadvantage = "COR_CHAOS_WOUND_SPELL_DISADVANTAGE"
}
local POSITIVE_STATUSES = {
    Bless = "BLESS", Haste = "COR_CHAOS_WOUND_HASTE", Blur = "BLUR",
    Heroism = "COR_CHAOS_WOUND_HEROISM", Invisibility = "INVISIBILITY",
    MeleeAdvantage = "COR_CHAOS_WOUND_MELEE_ADVANTAGE",
    RangedAdvantage = "COR_CHAOS_WOUND_RANGED_ADVANTAGE",
    SpellAdvantage = "COR_CHAOS_WOUND_SPELL_ADVANTAGE",
    Bloodlust = "COR_CHAOS_WOUND_BLOODLUST"
}

M.NegativeOutcomes = NEGATIVE_OUTCOMES

local function eligible(character)
    return character ~= nil and character ~= "" and ChaosCharacter.IsEligible(character)
end

local function record(character)
    return State.GetCharacter(character)
end

local function eventCharacter(handle)
    local entity = Ext.Entity.Get(handle)
    if entity == nil or entity.Uuid == nil then return nil end
    return tostring(entity.Uuid.EntityUuid)
end

local function hitDamageTotal(hit)
    if hit == nil or hit.DamageList == nil then return 0 end
    local amount = 0
    for index = 1, #hit.DamageList do
        local damage = hit.DamageList[index]
        if damage.Amount > 0 then amount = amount + damage.Amount end
    end
    return amount
end

local function dirtyAndDisplay(character, saved)
    State.MarkDirty()
    Features.Sync(character, saved)
end

local function powerReward()
    local value = Roll.Index(100)
    if value <= 90 then return 1 end
    if value <= 98 then return 2 end
    return 3
end

local function registerNegative(character, saved)
    if not saved.Mechanics.Power then return end
    saved.LostCount = math.min(10, saved.LostCount + 1)
    if Roll.Chance(LOST_CHANCES[saved.LostCount]) then
        saved.LostCount = 0
        saved.ChaosPower = saved.ChaosPower + powerReward()
    end
    dirtyAndDisplay(character, saved)
end

local function woundPool(saved)
    local pool = {}
    for _, outcome in ipairs(NEGATIVE_OUTCOMES) do
        if saved.WoundEffects[outcome] ~= false then pool[#pool + 1] = outcome end
    end
    for _, outcome in ipairs(POSITIVE_OUTCOMES) do pool[#pool + 1] = outcome end
    assert(#pool > 0, "ChaosOriginsRemastered: wound pool is empty")
    return pool
end

local function logWound(character, outcome, damageType)
    local suffix = string.upper(outcome)
    if damageType ~= nil then suffix = suffix .. "_" .. string.upper(damageType) end
    Osi.ApplyStatus(character, "COR_CHAOS_WOUND_LOG_" .. suffix, 0.1, 100, character)
    DebugLog.Print("[混沌起源][受创] " .. character .. " -> " .. suffix)
end

local function applyWound(character, damageAmount, powerEligible)
    local saved = record(character)
    local pool = woundPool(saved)
    local outcome = pool[Roll.Index(#pool)]
    saved.LastWoundOutcome = outcome
    if NEGATIVE_STATUSES[outcome] ~= nil then
        Osi.ApplyStatus(character, NEGATIVE_STATUSES[outcome], 1, 100, character)
        logWound(character, outcome)
        if powerEligible then registerNegative(character, saved) else State.MarkDirty() end
    elseif outcome == "Vulnerability" or outcome == "ExtraDamage" then
        local damageType = DAMAGE_TYPES[Roll.Index(#DAMAGE_TYPES)]
        local prefix = outcome == "Vulnerability" and
            "COR_CHAOS_WOUND_VULNERABILITY_" or "COR_CHAOS_WOUND_EXTRA_DAMAGE_"
        Osi.ApplyStatus(character, prefix .. string.upper(damageType),
            outcome == "Vulnerability" and 1 or 0.1, 100, character)
        if outcome == "ExtraDamage" then
            Duality.ApplyDamage(character, character, Roll.Index(6) + Roll.Index(6), damageType)
        end
        logWound(character, outcome, damageType)
        if powerEligible then registerNegative(character, saved) else State.MarkDirty() end
    elseif POSITIVE_STATUSES[outcome] ~= nil then
        Osi.ApplyStatus(character, POSITIVE_STATUSES[outcome], 1, 100, character)
        logWound(character, outcome)
        State.MarkDirty()
    elseif outcome == "RestoreDamage" then
        if Osi.IsDead(character) == 0 then
            Osi.SetHitpoints(character, math.min(Osi.GetMaxHitpoints(character),
                Osi.GetHitpoints(character) + damageAmount), "Guaranteed")
        end
        logWound(character, outcome)
        State.MarkDirty()
    elseif outcome == "Wet" then
        Osi.ApplyStatus(character, "WET", 1, 100, character)
        logWound(character, outcome)
        State.MarkDirty()
    else
        error("ChaosOriginsRemastered: unknown wound outcome " .. tostring(outcome))
    end
end

local function killChance(count)
    if count <= 20 then return 1 end
    if count <= 30 then return 2 end
    if count <= 40 then return 4 end
    if count <= 49 then return 10 end
    return 100
end

local function processKill(defender, attackOwner, attacker)
    if attackOwner ~= attacker or not eligible(attacker) or Osi.IsEnemy(defender, attacker) == 0 then return end
    local key = tostring(defender) .. ":" .. tostring(attacker)
    if processedKills[key] then return end
    processedKills[key] = true
    local currentGeneration = generation
    Ext.Timer.WaitFor(1000, function()
        if currentGeneration == generation then processedKills[key] = nil end
    end)
    local saved = record(attacker)
    if saved.Mechanics.Power and saved.Mechanics.KillPower then
        saved.KillCount = saved.KillCount + 1
        if Roll.Chance(killChance(saved.KillCount)) then
            local amountRoll = Roll.Index(100)
            saved.ChaosPower = saved.ChaosPower + (amountRoll <= 70 and 1 or (amountRoll <= 90 and 2 or 3))
            saved.KillCount = 0
        end
        dirtyAndDisplay(attacker, saved)
    end
    if Osi.HasActiveStatus(attacker, "COR_CHAOS_WOUND_BLOODLUST") == 1 then
        Osi.RemoveStatus(attacker, "COR_CHAOS_WOUND_BLOODLUST")
        Osi.ApplyStatus(attacker, "COR_CHAOS_WOUND_BLOODLUST_REWARD", 1, 100, attacker)
    end
end

local function allInEffect(level)
    if level >= 7 then return "COR_CHAOS_ALLIN_L7" end
    if level >= 3 then return "COR_CHAOS_ALLIN_L3" end
    return "COR_CHAOS_ALLIN_L1"
end

local function clearAllIn(character)
    Osi.RemoveStatus(character, "COR_CHAOS_ALLIN_L1")
    Osi.RemoveStatus(character, "COR_CHAOS_ALLIN_L3")
    Osi.RemoveStatus(character, "COR_CHAOS_ALLIN_L7")
end

local function consumeAttackEffects(character, storyActionId)
    if not eligible(character) then return end
    local key = tostring(character) .. ":" .. tostring(storyActionId)
    if consumedActions[key] then return end
    consumedActions[key] = true
    local currentGeneration = generation
    Ext.Timer.WaitFor(500, function()
        if currentGeneration == generation then consumedActions[key] = nil end
    end)
    local saved = record(character)
    if saved.AllInEnabled then
        saved.AllInEnabled = false
        Osi.RemoveStatus(character, "COR_CHAOS_ALLIN_TOGGLE")
        clearAllIn(character)
        State.MarkDirty()
    end
    Osi.RemoveStatus(character, "COR_CHAOS_STRIKE_ACTIVE")
    Osi.RemoveStatus(character, "COR_CHAOS_KILL")
end

local function scheduleAttackConsumption(character, storyActionId)
    local currentGeneration = generation
    Ext.Timer.WaitFor(250, function()
        if currentGeneration == generation then consumeAttackEffects(character, storyActionId) end
    end)
end

local function resolveEcho(key)
    local pending = echoPending[key]
    echoPending[key] = nil
    if pending == nil or not eligible(pending.Source) then return end
    local targetEntity = Ext.Entity.Get(pending.Target)
    if targetEntity == nil or targetEntity.Uuid == nil then return end
    local saved = record(pending.Source)
    if not saved.Mechanics.Echo then return end
    local level = Osi.GetLevel(pending.Source)
    local chance, damageRatio, healRatio = 10, 0.10, 0.05
    if level >= 10 then chance, damageRatio, healRatio = 50, 0.30, 0.20
    elseif level >= 6 then chance, damageRatio, healRatio = 30, 0.20, 0.10 end
    if not Roll.Chance(chance) then return end
    echoApplying[pending.Target] = true
    if Roll.Index(2) == 1 then
        local amount = math.max(1, math.floor(pending.Damage * damageRatio))
        Osi.ApplyStatus(pending.Source, "COR_CHAOS_ECHO_LOG_DAMAGE", 0.1, 100, pending.Source)
        Duality.ApplyDamage(pending.Source, pending.Target, amount, "Force")
    elseif targetEntity.ServerCharacter ~= nil and Osi.IsDead(pending.Target) == 0 then
        local amount = math.max(1, math.floor(pending.Damage * healRatio))
        Osi.ApplyStatus(pending.Source, "COR_CHAOS_ECHO_LOG_HEAL", 0.1, 100, pending.Source)
        Osi.SetHitpoints(pending.Target, math.min(Osi.GetMaxHitpoints(pending.Target),
            Osi.GetHitpoints(pending.Target) + amount), "Guaranteed")
    end
    echoApplying[pending.Target] = nil
end

local function registerEcho(target, attackOwner, attacker, damageAmount, damageCause, storyActionId)
    if echoApplying[target] or Duality.IsApplying(attackOwner, target) or damageAmount <= 0
        or attackOwner ~= attacker or not eligible(attackOwner) then return end
    local saved = record(attackOwner)
    if not saved.Mechanics.Echo then return end
    local key = tostring(attackOwner) .. ":" .. tostring(storyActionId) .. ":" .. tostring(target)
    if echoPending[key] == nil then
        echoPending[key] = { Source = attackOwner, Target = target, Damage = 0 }
        local currentGeneration = generation
        Ext.Timer.WaitFor(500, function()
            if currentGeneration == generation then resolveEcho(key) end
        end)
    end
    echoPending[key].Damage = echoPending[key].Damage + damageAmount
end

Duality.Configure({
    Enabled = function(source) return record(source).Mechanics.Duality end,
    IsChaos = eligible,
    Delayed = function() return State.GetRoot().PendingDuality end,
    Dirty = State.MarkDirty,
    RollIndex = function(_, _, maximum, _, callback) callback(Roll.Index(maximum)) end,
    Log = function(eventId, source)
        Osi.ApplyStatus(source, "COR_CHAOS_DUALITY_LOG_" .. string.upper(eventId), 0.1, 100, source)
        DebugLog.Print("[混沌起源][双相] " .. source .. " -> " .. eventId)
    end
})

function M.Sync(character, saved)
    character = ChaosCharacter.CanonicalGuid(character, "mechanic sync character")
    if not woundInitialized[character] then
        -- 本轮锁只属于当前运行会话；读档后必须从未消耗状态重新开始。
        woundInitialized[character] = true
        if saved.WoundConsumedThisRound then
            saved.WoundConsumedThisRound = false
            State.MarkDirty()
        end
    end
    if character == Osi.GetHostCharacter() then DebugLog.SetEnabled(saved.Mechanics.DebugLogging) end
    Features.Sync(character, saved)
end

function M.SetMechanic(character, saved, key, enabled)
    assert(saved.Mechanics[key] ~= nil and type(enabled) == "boolean",
        "ChaosOriginsRemastered: invalid mechanic toggle " .. tostring(key))
    if saved.Mechanics[key] == enabled then return false end
    saved.Mechanics[key] = enabled
    if key == "AllIn" and not enabled then saved.AllInEnabled = false end
    if key == "DebugLogging" then DebugLog.SetEnabled(enabled) end
    if key == "Duality" and not enabled then Duality.ClearForSource(character) end
    if not enabled then
        if key == "AllIn" then
            Osi.RemoveStatus(character, "COR_CHAOS_ALLIN_TOGGLE")
            clearAllIn(character)
        elseif key == "Strike" then Osi.RemoveStatus(character, "COR_CHAOS_STRIKE_ACTIVE")
        elseif key == "Power" then
            Osi.RemoveStatus(character, "COR_CHAOS_KILL")
        end
    end
    State.MarkDirty()
    Features.Sync(character, saved)
    return true
end

function M.SetWoundEffect(saved, outcome, enabled)
    assert(type(enabled) == "boolean", "ChaosOriginsRemastered: wound toggle must be boolean")
    local known = false
    for _, candidate in ipairs(NEGATIVE_OUTCOMES) do if candidate == outcome then known = true end end
    assert(known, "ChaosOriginsRemastered: unknown wound outcome " .. tostring(outcome))
    if saved.WoundEffects[outcome] == enabled then return false end
    saved.WoundEffects[outcome] = enabled
    State.MarkDirty()
    return true
end

function M.ResetRuntime()
    generation = generation + 1
    echoPending = {}
    echoApplying = {}
    consumedActions = {}
    processedKills = {}
    woundInitialized = {}
    Duality.ResetRuntime()
end

Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(character, status)
    if status == "COR_CHAOS_ALLIN_TOGGLE" and eligible(character) then
        local saved = record(character)
        assert(saved.Mechanics.AllIn, "ChaosOriginsRemastered: All-In activated while disabled")
        saved.AllInEnabled = true
        clearAllIn(character)
        Osi.ApplyStatus(character, allInEffect(Osi.GetLevel(character)), -1, 100, character)
        State.MarkDirty()
    end
end)

Ext.Osiris.RegisterListener("StatusRemoved", 4, "after", function(character, status)
    if status == "COR_CHAOS_ALLIN_TOGGLE" and eligible(character) then
        local saved = record(character)
        saved.AllInEnabled = false
        clearAllIn(character)
        State.MarkDirty()
    end
end)

Ext.Osiris.RegisterListener("UsingSpell", 5, "after", function(character, spell)
    if spell ~= "Shout_COR_ChaosGenesis" then return end
    assert(eligible(character), "ChaosOriginsRemastered: non-Chaos character cast Genesis")
    local saved = record(character)
    assert(saved.Mechanics.Power and saved.ChaosPower >= 3,
        "ChaosOriginsRemastered: Genesis requires three Chaos Power")
    saved.ChaosPower = saved.ChaosPower - 3
    GrantLedger.RemovePassive(character, saved, "COR_ChaosGenesisCharge",
        saved.MechanicGranted.Passives)
    GrantLedger.EnsurePassive(character, saved, "COR_ChaosGenesisCharge",
        saved.MechanicGranted.Passives)
    Osi.RemoveHarmfulStatuses(character)
    dirtyAndDisplay(character, saved)
end)

Ext.Osiris.RegisterListener("KilledBy", 4, "after", processKill)

Ext.Osiris.RegisterListener("AttackedBy", 7, "after",
    function(target, attackOwner, attacker, _, damageAmount, damageCause, storyActionId)
        registerEcho(target, attackOwner, attacker, damageAmount, damageCause, storyActionId)
        scheduleAttackConsumption(attackOwner, storyActionId)
    end)

Ext.Osiris.RegisterListener("MissedBy", 4, "after", function(_, attackOwner, _, storyActionId)
    scheduleAttackConsumption(attackOwner, storyActionId)
end)

Ext.Osiris.RegisterListener("TurnStarted", 1, "after", function(character)
    Duality.OnTurnStarted(character)
    if eligible(character) then
        local saved = record(character)
        if saved.WoundConsumedThisRound then
            saved.WoundConsumedThisRound = false
            State.MarkDirty()
        end
    end
end)

Ext.Osiris.RegisterListener("TurnEnded", 1, "after", function(character)
    Osi.RemoveStatus(character, "COR_CHAOS_GENESIS")
end)

local function handleWoundDamage(event)
    if event.Hit == nil then return end
    local target = eventCharacter(event.Target)
    local source = eventCharacter(event.Hit.InflicterOwner)
    if target == nil or source == nil or target == source or not eligible(target)
        or Osi.IsInCombat(target) == 0 or Duality.IsApplying(source, target) then return end
    local damageAmount = hitDamageTotal(event.Hit)
    if damageAmount <= 0 then return end
    local saved = record(target)
    if not saved.Mechanics.Wound or saved.WoundConsumedThisRound then return end
    saved.WoundConsumedThisRound = true
    State.MarkDirty()
    DebugLog.Print(string.format(
        "[混沌起源][受击轮盘] 已捕获伤害：受击者=%s，攻击者=%s，伤害=%d",
        target, source, damageAmount))
    applyWound(target, damageAmount, Osi.IsEnemy(target, source) == 1)
end

Ext.Events.DealtDamage:Subscribe(function(event)
    Duality.HandleDealtDamage(event)
    handleWoundDamage(event)
end)
Ext.Events.BeforeDealDamage:Subscribe(function(event)
    if event.Hit == nil or event.Hit.InflicterOwner == nil then return end
    local entity = Ext.Entity.Get(event.Hit.InflicterOwner)
    if entity == nil or entity.Uuid == nil then return end
    local source = tostring(entity.Uuid.EntityUuid)
    local allIn = (Osi.HasActiveStatus(source, "COR_CHAOS_ALLIN_L1") == 1
        or Osi.HasActiveStatus(source, "COR_CHAOS_ALLIN_L3") == 1
        or Osi.HasActiveStatus(source, "COR_CHAOS_ALLIN_L7") == 1)
        and tostring(event.Hit.AttackRollAbility) ~= "None"
    local strike = Osi.HasActiveStatus(source, "COR_CHAOS_STRIKE_ACTIVE") == 1
    local finisher = Osi.HasActiveStatus(source, "COR_CHAOS_KILL") == 1
    Duality.CaptureBeforeDamage(event,
        (allIn and 2 or 1) * (strike and 2 or 1) * (finisher and 2 or 1))
end)

Ext.Osiris.RegisterListener("LeftCombat", 2, "after", function(character)
    if not eligible(character) then return end
    local saved = record(character)
    if saved.WoundConsumedThisRound then
        saved.WoundConsumedThisRound = false
        State.MarkDirty()
    end
    Duality.ClearForSource(character)
end)

Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", function(character)
    if not eligible(character) then return end
    local saved = record(character)
    if saved.WoundConsumedThisRound then
        saved.WoundConsumedThisRound = false
        State.MarkDirty()
    end
end)

return M
