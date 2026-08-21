local GrantLedger = Ext.Require("GrantLedger.lua")
local M = {}

M.Passives = {
    "COR_BaseProficiencies",
    "COR_AllSkillMastery"
}

M.StarterSpellPassive = "COR_BaseStarterSpells"

M.Spells = {
    "Target_BoomingBlade_ClassSpell",
    "Target_Guidance",
    "Target_MageHand",
    "Target_MinorIllusion",
    "Shout_FeatherFall",
    "Target_Jump",
    "Shout_DisguiseSelf"
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
    assert(Ext.Stats.Get(M.StarterSpellPassive) ~= nil,
        "ChaosOriginsRemastered: missing starter-spell passive " .. M.StarterSpellPassive)
    validated = true
end

function M.Sync(character, record)
    validateStats()
    GrantLedger.EnsurePassive(character, record, "COR_BaseProficiencies")
    if record.Mechanics.Skills then
        GrantLedger.EnsurePassive(character, record, "COR_AllSkillMastery")
    elseif record.Granted.Passives.COR_AllSkillMastery ~= nil then
        GrantLedger.RemovePassive(character, record, "COR_AllSkillMastery", record.Granted.Passives)
    end
    if next(record.Granted.Spells) ~= nil then
        -- 旧存档继续沿用已经记账的直接法术来源，只补齐新增的自我伪装。
        for _, spell in ipairs(M.Spells) do
            GrantLedger.EnsureSpell(character, record, spell)
        end
    else
        -- 新角色只使用一个 UnlockSpell 被动，避免与种族法术产生第二来源。
        GrantLedger.EnsurePassive(character, record, M.StarterSpellPassive)
    end
end

return M
