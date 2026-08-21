local State = Ext.Require("ChaosState.lua")
local M = {}

local function requireStat(statId, kind)
    assert(Ext.Stats.Get(statId) ~= nil,
        "ChaosOriginsRemastered: missing " .. kind .. " stat " .. statId)
end

function M.EnsurePassive(character, record, passive)
    requireStat(passive, "passive")
    if Osi.HasPassive(character, passive) == 1 then return false end

    Osi.AddPassive(character, passive)
    assert(Osi.HasPassive(character, passive) == 1,
        "ChaosOriginsRemastered: failed to grant passive " .. passive .. " to " .. character)
    -- 仅记录本 MOD 真正新增的被动，原有能力永远不被本 MOD 认领。
    record.Granted.Passives[passive] = true
    State.MarkDirty()
    return true
end

function M.EnsureSpell(character, record, spell)
    requireStat(spell, "spell")
    if Osi.HasSpell(character, spell) == 1 then return false end

    Osi.AddSpell(character, spell, 0, 1)
    assert(Osi.HasSpell(character, spell) == 1,
        "ChaosOriginsRemastered: failed to grant spell " .. spell .. " to " .. character)
    -- 原本已有的法术不写入账本，未来关闭机制时不会误删官方或其他 MOD 的能力。
    record.Granted.Spells[spell] = true
    State.MarkDirty()
    return true
end

return M
