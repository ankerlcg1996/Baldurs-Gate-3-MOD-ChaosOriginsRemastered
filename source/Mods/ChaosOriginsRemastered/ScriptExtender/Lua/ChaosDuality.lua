local M = {}
local DebugLog = Ext.Require("DebugLog.lua")

M.Events = {
    { Id = "Return", Weight = 21.25 },
    { Id = "Elemental", Weight = 17.25 },
    { Id = "TargetEcho", Weight = 7 },
    { Id = "CasterEcho", Weight = 6 },
    { Id = "TwinRift", Weight = 6 },
    { Id = "Chain", Weight = 5 },
    { Id = "Mistaken", Weight = 5 },
    { Id = "TwinPulse", Weight = 4 },
    { Id = "RandomPrey", Weight = 3 },
    { Id = "Rewrite", Weight = 5 },
    { Id = "TwinRewrite", Weight = 4 },
    { Id = "Burst", Weight = 3 },
    { Id = "TwinTime", Weight = 2 },
    { Id = "Verdict", Weight = 1 },
    { Id = "Devour", Weight = 8 },
    { Id = "Genesis", Weight = 2.5 }
}
M.EventNames = {
    Return = "混沌归还",
    Elemental = "元素错位",
    TargetEcho = "延迟回响",
    CasterEcho = "逆时残响",
    TwinRift = "双生裂痕",
    Chain = "连锁裂变",
    Mistaken = "目标错认",
    TwinPulse = "二重脉冲",
    RandomPrey = "随机猎物",
    Rewrite = "伤害复写",
    TwinRewrite = "双目标复写",
    Burst = "敌群爆裂",
    TwinTime = "双时回响",
    Verdict = "混沌裁决",
    Devour = "虚无吞噬",
    Genesis = "开天裂击"
}

local damageTypes = {
    "Acid", "Bludgeoning", "Cold", "Fire", "Force", "Lightning", "Necrotic",
    "Piercing", "Poison", "Psychic", "Radiant", "Slashing", "Thunder"
}
local pending = {}
local captured = {}
local applying = {}
local applyingSources = {}
local applyingTargets = {}
local generation = 0
local options = nil

local function uuid(entityHandle)
    local entity = Ext.Entity.Get(entityHandle)
    if entity == nil or entity.Uuid == nil then return nil end
    return tostring(entity.Uuid.EntityUuid)
end

local function total(damages)
    local result = 0
    for _, amount in pairs(damages) do result = result + amount end
    return result
end

local function addDamage(destination, damageType, amount)
    if amount <= 0 then return end
    destination[damageType] = (destination[damageType] or 0) + amount
end

local function scaleDamages(damages, numerator, denominator)
    local sourceTotal = total(damages)
    local targetTotal = math.floor(sourceTotal * numerator / denominator)
    local result = {}
    local remainders = {}
    local assigned = 0
    for damageType, amount in pairs(damages) do
        local exact = amount * targetTotal / sourceTotal
        local base = math.floor(exact)
        result[damageType] = base
        assigned = assigned + base
        remainders[#remainders + 1] = { Type = damageType, Value = exact - base }
    end
    table.sort(remainders, function(a, b)
        if a.Value == b.Value then return a.Type < b.Type end
        return a.Value > b.Value
    end)
    for index = 1, targetTotal - assigned do
        local damageType = remainders[index].Type
        result[damageType] = result[damageType] + 1
    end
    return result
end

local function splitDamages(damages, fixedAmount)
    local sourceTotal = total(damages)
    assert(sourceTotal > 0 and fixedAmount >= 0 and fixedAmount <= sourceTotal,
        "ChaosOriginsRemastered: invalid Chaos Duality damage split")
    local fixed = scaleDamages(damages, fixedAmount, sourceTotal)
    local random = {}
    for damageType, amount in pairs(damages) do
        random[damageType] = amount - (fixed[damageType] or 0)
    end
    return fixed, random
end

local function rollEvent(roll)
    assert(type(roll) == "number" and roll % 1 == 0 and roll >= 1 and roll <= 400,
        "ChaosOriginsRemastered: Chaos Duality native roll must be an integer from 1 to 400")
    local cursor = 0
    for _, definition in ipairs(M.Events) do
        cursor = cursor + definition.Weight * 4
        if roll <= cursor then return definition.Id end
    end
    error("ChaosOriginsRemastered: Chaos Duality weights do not cover 400 native outcomes")
end

local function validTarget(target, source)
    local entity = Ext.Entity.Get(target)
    local sourceEntity = Ext.Entity.Get(source)
    if entity == nil or entity.Uuid == nil or sourceEntity == nil or sourceEntity.Uuid == nil then return false end
    if entity.ServerCharacter ~= nil and Osi.IsDead(target) ~= 0 then return false end
    return (entity.ServerCharacter ~= nil or entity.ServerItem ~= nil)
        and Osi.GetRegion(target) == Osi.GetRegion(source)
end

local function candidates(source, original, maximumDistance)
    local result = {}
    local sourceCombat = Osi.CombatGetGuidFor(source)
    for _, entity in ipairs(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter")) do
        if entity.Uuid ~= nil then
            local candidate = tostring(entity.Uuid.EntityUuid)
            if candidate ~= original and candidate ~= source and Osi.IsDead(candidate) == 0
                and Osi.IsEnemy(candidate, source) == 1 and Osi.GetRegion(candidate) == Osi.GetRegion(source)
                and (sourceCombat == nil or sourceCombat == "" or Osi.CombatGetGuidFor(candidate) == sourceCombat) then
                local distance = Osi.GetDistanceTo(original, candidate)
                if distance ~= nil and (maximumDistance == nil or distance <= maximumDistance) then
                    result[#result + 1] = { Target = candidate, Distance = distance }
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.Distance == b.Distance then return a.Target < b.Target end
        return a.Distance < b.Distance
    end)
    return result
end

local function markAndApply(source, target, damages)
    if not validTarget(target, source) then return end
    local key = source .. ":" .. target
    applying[key] = (applying[key] or 0) + 1
    applyingSources[source] = (applyingSources[source] or 0) + 1
    applyingTargets[target] = (applyingTargets[target] or 0) + 1
    local applyGeneration = generation
    for damageType, amount in pairs(damages) do
        if amount > 0 then Osi.ApplyDamage(target, amount, damageType, source) end
    end
    Ext.Timer.WaitFor(1, function()
        if applyGeneration ~= generation then return end
        applying[key] = applying[key] - 1
        if applying[key] == 0 then applying[key] = nil end
        applyingSources[source] = applyingSources[source] - 1
        if applyingSources[source] == 0 then applyingSources[source] = nil end
        applyingTargets[target] = applyingTargets[target] - 1
        if applyingTargets[target] == 0 then applyingTargets[target] = nil end
    end)
end

local function distribute(source, targets, damages)
    if #targets == 0 then return end
    for damageType, amount in pairs(damages) do
        local quotient = math.floor(amount / #targets)
        local remainder = amount % #targets
        for index, target in ipairs(targets) do
            local share = quotient + (index <= remainder and 1 or 0)
            if share > 0 then markAndApply(source, target, { [damageType] = share }) end
        end
    end
end

local function queueDelayed(trigger, source, target, damages)
    local triggerEntity = Ext.Entity.Get(trigger)
    if triggerEntity == nil or triggerEntity.ServerCharacter == nil then trigger = source end
    local delayed = options.Delayed()
    delayed[#delayed + 1] = { Trigger = trigger, Source = source, Target = target, Damages = damages }
    options.Dirty()
end

local function converted(damages, index)
    return { [damageTypes[index]] = total(damages) }
end

local function applyEvent(envelope, eventId)
    local source, target, damages = envelope.Source, envelope.Target, envelope.Random
    local nearest = candidates(source, target, nil)
    local withinSix = candidates(source, target, 6)
    local withinTwelve = candidates(source, target, 12)
    local nearestTarget = nearest[1] and nearest[1].Target or nil

    local function finished()
        options.Log(eventId, source, target, total(damages))
    end

    if eventId == "Return" then markAndApply(source, target, damages); finished()
    elseif eventId == "Elemental" then
        options.RollIndex(source, target, #damageTypes, "DualityDamageType", function(index)
            markAndApply(source, target, converted(damages, index))
            finished()
        end)
    elseif eventId == "TargetEcho" then queueDelayed(target, source, target, damages)
    elseif eventId == "CasterEcho" then queueDelayed(source, source, target, damages)
    elseif eventId == "TwinRift" then
        local targets = { target }
        if nearestTarget ~= nil then targets[#targets + 1] = nearestTarget end
        distribute(source, targets, damages)
    elseif eventId == "Chain" then
        local targets = { target }
        for index = 1, math.min(2, #nearest) do targets[#targets + 1] = nearest[index].Target end
        distribute(source, targets, damages)
    elseif eventId == "Mistaken" then markAndApply(source, nearestTarget or target, damages)
    elseif eventId == "TwinPulse" then
        local now, later = splitDamages(damages, math.floor(total(damages) / 2))
        markAndApply(source, target, now)
        queueDelayed(target, source, target, later)
    elseif eventId == "RandomPrey" then
        if #withinTwelve == 0 then
            markAndApply(source, target, damages)
            finished()
        else
            options.RollIndex(source, target, #withinTwelve, "DualityRandomPrey", function(index)
                markAndApply(source, withinTwelve[index].Target, damages)
                finished()
            end)
        end
    elseif eventId == "Rewrite" then markAndApply(source, target, scaleDamages(damages, 2, 1))
    elseif eventId == "TwinRewrite" then
        markAndApply(source, target, damages)
        if nearestTarget ~= nil then markAndApply(source, nearestTarget, damages) end
    elseif eventId == "Burst" then
        local targets = { target }
        for _, candidate in ipairs(withinSix) do targets[#targets + 1] = candidate.Target end
        distribute(source, targets, scaleDamages(damages, 2, 1))
    elseif eventId == "TwinTime" then
        markAndApply(source, target, damages)
        queueDelayed(target, source, target, damages)
    elseif eventId == "Verdict" then
        local eligible = { target }
        for _, candidate in ipairs(withinTwelve) do eligible[#eligible + 1] = candidate.Target end
        if #eligible == 1 then
            markAndApply(source, target, scaleDamages(damages, 2, 1))
            finished()
        else
            options.RollIndex(source, target, #eligible, "DualityVerdict", function(index)
                markAndApply(source, eligible[index], scaleDamages(damages, 2, 1))
                finished()
            end)
        end
    elseif eventId == "Devour" then
        -- Intentionally disappears.
        finished()
    elseif eventId == "Genesis" then markAndApply(source, target, scaleDamages(damages, 4, 1)); finished()
    else error("ChaosOriginsRemastered: unknown Chaos Duality event " .. tostring(eventId)) end
    if eventId == "TargetEcho" or eventId == "CasterEcho" or eventId == "TwinRift"
        or eventId == "Chain" or eventId == "Mistaken" or eventId == "TwinPulse"
        or eventId == "Rewrite" or eventId == "TwinRewrite" or eventId == "Burst"
        or eventId == "TwinTime" then
        finished()
    end
end

local function resolve(key)
    local envelope = pending[key]
    pending[key] = nil
    if envelope == nil or total(envelope.Random) == 0 then return end
    options.RollIndex(envelope.Source, envelope.Target, 400, "DualityEvent", function(index)
        applyEvent(envelope, rollEvent(index))
    end)
end

function M.Configure(configuration)
    assert(options == nil, "ChaosOriginsRemastered: Chaos Duality was configured twice")
    for _, key in ipairs({ "Enabled", "IsChaos", "Delayed", "Dirty", "RollIndex", "Log" }) do
        assert(type(configuration[key]) == "function", "ChaosOriginsRemastered: missing Chaos Duality option " .. key)
    end
    options = configuration
end

local function writeDamageList(damageList, damages)
    local written = {}
    for index = 1, #damageList do
        local damage = damageList[index]
        local damageType = tostring(damage.DamageType)
        if written[damageType] then
            damage.Amount = 0
        else
            damage.Amount = damages[damageType] or 0
            written[damageType] = true
        end
    end
end

local function eventKey(source, target, actionId, hit)
    return source .. ":" .. target .. ":" .. tostring(actionId) .. ":" .. tostring(hit)
end

function M.CaptureDealDamage(event, multiplier)
    assert(options ~= nil, "ChaosOriginsRemastered: Chaos Duality is not configured")
    assert(type(multiplier) == "number" and multiplier % 1 == 0 and multiplier >= 1,
        "ChaosOriginsRemastered: invalid pre-damage multiplier")
    if event.Hit == nil or event.Hit.DamageList == nil then return end
    local source, target = uuid(event.Caster), uuid(event.Target)
    if source == nil or target == nil then return end
    if source == nil or not options.IsChaos(source) or applyingSources[source] then return end
    local actionId = tonumber(event.StoryActionId or 0) or 0
    local damages, eventTotal = {}, 0
    local damageList = event.Hit.DamageList
    for index = 1, #damageList do
        local damage = damageList[index]
        if damage.Amount > 0 then
            addDamage(damages, tostring(damage.DamageType), damage.Amount)
            eventTotal = eventTotal + damage.Amount
        end
    end
    if eventTotal == 0 then return end
    local expanded = scaleDamages(damages, multiplier, 1)
    if not options.Enabled(source) then
        if multiplier > 1 then writeDamageList(damageList, expanded) end
        return
    end
    local expandedTotal = total(expanded)
    local fixed, random = splitDamages(expanded, math.ceil(expandedTotal / 2))
    writeDamageList(damageList, fixed)
    DebugLog.Print(string.format(
        "[混沌起源][攻击轮盘] 已捕获伤害：施法者=%s，动作=%d，原始=%d，倍率后=%d，固定部分=%d，随机部分=%d",
        source, actionId, eventTotal, expandedTotal, total(fixed), total(random)))
    local captureKey = eventKey(source, target, actionId, event.Hit)
    assert(captured[captureKey] == nil,
        "ChaosOriginsRemastered: duplicate Duality deal-damage capture " .. captureKey)
    local entry = { Source = source, Target = target, Action = actionId, Random = random }
    captured[captureKey] = entry
    local capturedGeneration = generation
    Ext.Timer.WaitFor(2000, function()
        if capturedGeneration ~= generation then return end
        if captured[captureKey] == entry then
            captured[captureKey] = nil
            DebugLog.Print(string.format(
                "[混沌起源][攻击轮盘] 已取消未结算捕获：施法者=%s，目标=%s，动作=%d，随机伤害=%d",
                source, target, actionId, total(random)))
        end
    end)
end

function M.HandleDealtDamage(event)
    assert(options ~= nil, "ChaosOriginsRemastered: Chaos Duality is not configured")
    local target = uuid(event.Target)
    local source = uuid(event.Caster)
    if target == nil or source == nil then return end
    if applyingTargets[target] then return end
    local actionId = tonumber(event.StoryActionId or 0) or 0
    local captureKey = eventKey(source, target, actionId, event.Hit)
    local entry = captured[captureKey]
    if entry == nil then return end
    captured[captureKey] = nil
    assert(entry.Source == source and entry.Target == target,
        "ChaosOriginsRemastered: Duality capture identity changed during settlement")
    local random = entry.Random
    DebugLog.Print(string.format(
        "[混沌起源][攻击轮盘] 已锁定结算目标：施法者=%s，目标=%s，动作=%d，随机伤害=%d",
        source, target, actionId, total(random)))
    local key = source .. ":" .. tostring(actionId) .. ":" .. target
    local envelope = pending[key]
    if envelope == nil then
        envelope = { Source = source, Target = target, Random = {} }
        pending[key] = envelope
        local resolveGeneration = generation
        Ext.Timer.WaitFor(500, function()
            if resolveGeneration == generation then resolve(key) end
        end)
    end
    for damageType, amount in pairs(random) do addDamage(envelope.Random, damageType, amount) end
end

function M.ResetRuntime()
    -- 会话代数使上一存档尚未执行的超时回调失效。
    generation = generation + 1
    pending = {}
    captured = {}
    applying = {}
    applyingSources = {}
    applyingTargets = {}
end

function M.ApplyDamage(source, target, amount, damageType)
    assert(type(amount) == "number" and amount >= 0 and amount % 1 == 0,
        "ChaosOriginsRemastered: additional damage must be a non-negative integer")
    markAndApply(source, target, { [damageType] = amount })
end

function M.IsApplying(source, target)
    if source == nil or target == nil then return false end
    local sourceId, targetId = uuid(source), uuid(target)
    if sourceId == nil or targetId == nil then return false end
    return applying[sourceId .. ":" .. targetId] ~= nil
end

function M.ClearForSource(source)
    source = assert(uuid(source),
        "ChaosOriginsRemastered: Duality source is unavailable while clearing")
    for key, entry in pairs(captured) do
        if entry.Source == source then captured[key] = nil end
    end
    for key, envelope in pairs(pending) do
        if envelope.Source == source then pending[key] = nil end
    end
    local delayed = options.Delayed()
    for index = #delayed, 1, -1 do
        if delayed[index].Source == source then table.remove(delayed, index) end
    end
    options.Dirty()
end

function M.OnTurnStarted(character)
    assert(options ~= nil, "ChaosOriginsRemastered: Chaos Duality is not configured")
    character = assert(uuid(character),
        "ChaosOriginsRemastered: Duality turn character is unavailable")
    local delayed = options.Delayed()
    local changed = false
    for index = #delayed, 1, -1 do
        local entry = delayed[index]
        if not validTarget(entry.Target, entry.Source) then
            table.remove(delayed, index)
            changed = true
        elseif entry.Trigger == character then
            table.remove(delayed, index)
            changed = true
            if options.Enabled(entry.Source) then markAndApply(entry.Source, entry.Target, entry.Damages) end
        end
    end
    if changed then options.Dirty() end
end

return M
