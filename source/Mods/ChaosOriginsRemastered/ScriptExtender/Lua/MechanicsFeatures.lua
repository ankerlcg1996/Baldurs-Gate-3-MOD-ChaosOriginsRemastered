local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
local GrantLedger = Ext.Require("GrantLedger.lua")
local M = {}

-- 机制授予与显示完全从持久状态重建，读档和洗点不会重复叠加能力。

local LOST_STATUSES = {}
for count = 0, 10 do LOST_STATUSES[#LOST_STATUSES + 1] = "COR_CHAOS_LOST_COUNT_" .. count end

local function desired(record, level)
    local passives, spells = {}, {}
    if record.Mechanics.Wound then passives.COR_ChaosWound = true end
    if record.Mechanics.Duality then passives.COR_ChaosDuality = true end
    if record.Mechanics.Power then
        passives.COR_ChaosLost = true
        passives.COR_ChaosPower = true
        spells.Shout_COR_ChaosGenesis = true
        if record.ChaosPower >= 3 then passives.COR_ChaosGenesisCharge = true end
    end
    if record.Mechanics.AllIn then
        passives.COR_ChaosAllIn = true
        if level >= 5 then passives.COR_ChaosAllInUseL5 = true end
        if level >= 9 then passives.COR_ChaosAllInUseL9 = true end
    end
    if record.Mechanics.Echo then passives.COR_ChaosEcho = true end
    if record.Mechanics.Strike and level >= 12 then passives.COR_ChaosStrike = true end
    return passives, spells
end

local function removeStatus(character, status)
    if Osi.HasActiveStatus(character, status) == 1 then Osi.RemoveStatus(character, status) end
end

local function syncPowerDisplay(character, record)
    removeStatus(character, "COR_CHAOS_POWER_STACK")
    removeStatus(character, "COR_CHAOS_GENESIS_READY")
    if not record.Mechanics.Power then return end
    -- Osiris 时长使用秒；每层写入6秒，0层则用永久状态保留可见图标。
    local displayDuration = record.ChaosPower == 0 and -1 or record.ChaosPower * 6
    Osi.ApplyStatus(character, "COR_CHAOS_POWER_STACK", displayDuration, 100, character)
    if record.ChaosPower >= 3 then
        Osi.ApplyStatus(character, "COR_CHAOS_GENESIS_READY", -1, 100, character)
    end
end

local function syncLostDisplay(character, record)
    for _, status in ipairs(LOST_STATUSES) do removeStatus(character, status) end
    if record.Mechanics.Power then
        Osi.ApplyStatus(character, "COR_CHAOS_LOST_COUNT_" .. record.LostCount, -1, 100, character)
    end
end

local function syncAllIn(character, record)
    if not record.Mechanics.AllIn then
        record.AllInEnabled = false
        removeStatus(character, "COR_CHAOS_ALLIN_TOGGLE")
        removeStatus(character, "COR_CHAOS_ALLIN_L1")
        removeStatus(character, "COR_CHAOS_ALLIN_L3")
        removeStatus(character, "COR_CHAOS_ALLIN_L7")
    end
end

function M.Sync(character, record)
    character = ChaosCharacter.CanonicalGuid(character, "mechanic character")
    local wantedPassives, wantedSpells = desired(record, Osi.GetLevel(character))
    for passive in pairs(record.MechanicGranted.Passives) do
        if not wantedPassives[passive] then
            GrantLedger.RemovePassive(character, record, passive, record.MechanicGranted.Passives)
        end
    end
    for spell in pairs(record.MechanicGranted.Spells) do
        if not wantedSpells[spell] then
            GrantLedger.RemoveSpell(character, record, spell, record.MechanicGranted.Spells)
        end
    end
    for passive in pairs(wantedPassives) do
        GrantLedger.EnsurePassive(character, record, passive, record.MechanicGranted.Passives)
    end
    for spell in pairs(wantedSpells) do
        GrantLedger.EnsureSpell(character, record, spell, record.MechanicGranted.Spells)
    end
    syncPowerDisplay(character, record)
    syncLostDisplay(character, record)
    syncAllIn(character, record)
end

function M.SyncDisplays(character, record)
    syncPowerDisplay(character, record)
    syncLostDisplay(character, record)
end

return M
