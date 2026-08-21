local State = Ext.Require("ChaosState.lua")
local M = {}

local MASK_TEMPLATE = "5d66776d-0650-4512-b300-b2ac38e2be3a"
local REWARD_TEMPLATES = {
    MASK_TEMPLATE,
    "8a1f5dc0-3f13-47ed-b238-50fdcaa2f680",
    "0ae83daa-1096-4b38-9b8c-fc610a9306aa"
}
local NULL_UUID = "00000000-0000-0000-0000-000000000000"
local active = {}
local templatesValidated = false
local continueRewards

local function validateTemplates()
    if templatesValidated then return end
    for _, template in ipairs(REWARD_TEMPLATES) do
        assert(Ext.Template.GetRootTemplate(template) ~= nil,
            "ChaosOriginsRemastered: missing starter reward template " .. template)
    end
    templatesValidated = true
end

local function finishByEquippingMask(character, operation)
    local maskObject = operation.Record.RewardItems[MASK_TEMPLATE]
    assert(type(maskObject) == "string" and maskObject ~= "" and maskObject ~= NULL_UUID,
        "ChaosOriginsRemastered: missing recorded mask object for " .. character)
    assert(Ext.Entity.Get(maskObject) ~= nil,
        "ChaosOriginsRemastered: recorded mask object is unavailable " .. maskObject
            .. " for " .. character)

    if Osi.IsEquipped(maskObject) == 1 then
        operation.Record.StarterRewardsVersion = 1
        State.MarkDirty()
        active[character] = nil
        return
    end

    operation.Equipping = true
    Osi.Equip(character, maskObject, 1, 1, 0)
    Ext.Timer.WaitFor(200, function()
        if active[character] ~= operation then return end
        active[character] = nil
        assert(Osi.IsEquipped(maskObject) == 1,
            "ChaosOriginsRemastered: failed to equip starter mask " .. maskObject
                .. " for " .. character)
        -- 三件奖励和自动装备全部成功后，才允许写入完成版本。
        operation.Record.StarterRewardsVersion = 1
        State.MarkDirty()
    end)
end

continueRewards = function(character)
    local operation = assert(active[character],
        "ChaosOriginsRemastered: starter reward operation is missing for " .. character)
    for _, template in ipairs(REWARD_TEMPLATES) do
        if operation.Record.RewardItems[template] == nil then
            operation.PendingTemplate = template
            Osi.TemplateAddTo(template, character, 1, 1)
            Ext.Timer.WaitFor(2000, function()
                if active[character] == operation and operation.PendingTemplate == template then
                    active[character] = nil
                    error("ChaosOriginsRemastered: failed to create starter reward "
                        .. template .. " for " .. character)
                end
            end)
            return
        end
    end
    finishByEquippingMask(character, operation)
end

Ext.Osiris.RegisterListener("TemplateAddedTo", 4, "after",
    function(template, object, inventoryHolder, _)
        local operation = active[inventoryHolder]
        if operation == nil or operation.PendingTemplate ~= template then return end
        assert(type(object) == "string" and object ~= "" and object ~= NULL_UUID,
            "ChaosOriginsRemastered: invalid created reward object " .. tostring(object)
                .. " for " .. inventoryHolder .. " template " .. template)

        -- 记录事件返回的真实对象，而不是按模板查询背包，避免误认玩家原有物品。
        operation.Record.RewardItems[template] = object
        operation.PendingTemplate = nil
        State.MarkDirty()
        Ext.Timer.WaitFor(100, function()
            if active[inventoryHolder] == operation then continueRewards(inventoryHolder) end
        end)
    end)

function M.Sync(character, record)
    if record.StarterRewardsVersion == 1 or active[character] ~= nil then return end
    validateTemplates()
    active[character] = { Record = record, PendingTemplate = nil, Equipping = false }
    continueRewards(character)
end

function M.ResetRuntime()
    -- 切换存档时丢弃旧会话中的异步句柄；持久化账本会在新会话重新驱动流程。
    active = {}
end

M.MaskTemplate = MASK_TEMPLATE
M.Templates = REWARD_TEMPLATES

return M
