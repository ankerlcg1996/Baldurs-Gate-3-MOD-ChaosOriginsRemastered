local GrantLedger = Ext.Require("GrantLedger.lua")
local M = {}

M.Passives = {
    "COR_BaseProficiencies",
    "COR_AllSkillMastery"
}

M.Spells = {
    "Target_BoomingBlade_ClassSpell",
    "Target_Guidance",
    "Target_MageHand",
    "Target_MinorIllusion",
    "Shout_FeatherFall",
    "Target_Jump"
}

local validated = false

local function validateStats()
    if validated then return end
    -- 先完整校验清单，再授予任何能力，避免角色停留在无法解释的半完成状态。
    for _, passive in ipairs(M.Passives) do
        assert(Ext.Stats.Get(passive) ~= nil,
            "ChaosOriginsRemastered: missing base passive stat " .. passive)
    end
    for _, spell in ipairs(M.Spells) do
        assert(Ext.Stats.Get(spell) ~= nil,
            "ChaosOriginsRemastered: missing starter spell stat " .. spell)
    end
    validated = true
end

function M.Sync(character, record)
    validateStats()
    for _, passive in ipairs(M.Passives) do
        GrantLedger.EnsurePassive(character, record, passive)
    end
    for _, spell in ipairs(M.Spells) do
        GrantLedger.EnsureSpell(character, record, spell)
    end
end

return M
