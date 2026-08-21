local State = Ext.Require("ChaosState.lua")
local ChaosCharacter = Ext.Require("ChaosCharacter.lua")
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

local function guarded(character, operation, callback)
    local ok, failure = xpcall(callback, debug.traceback)
    if not ok then
        if active[character] == operation then active[character] = nil end
        error(failure)
    end
end

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
    Ext.Timer.WaitFor(2000, function()
        if active[character] ~= operation then return end
        active[character] = nil
        error("ChaosOriginsRemastered: timed out equipping starter mask " .. maskObject
            .. " for " .. character)
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
        local holderKey = string.sub(tostring(inventoryHolder), -36)
        local templateKey = string.sub(tostring(template), -36)
        local operation = active[holderKey]
        if operation == nil or operation.PendingTemplate ~= templateKey then return end

        local holderGuid = ChaosCharacter.CanonicalGuid(inventoryHolder, "reward holder")
        local templateGuid = ChaosCharacter.CanonicalGuid(template, "reward template")
        local objectGuid = ChaosCharacter.CanonicalGuid(object, "reward object")
        guarded(holderGuid, operation, function()
            -- 创建事件本身就是对象来源证据，先持久化可避免后续验证失败时重复创建。
            operation.Record.RewardItems[templateGuid] = objectGuid
            operation.PendingTemplate = nil
            State.MarkDirty()
            Ext.Timer.WaitFor(100, function()
                if active[holderGuid] ~= operation then return end
                guarded(holderGuid, operation, function()
                    local actualTemplate = ChaosCharacter.CanonicalGuid(Osi.GetTemplate(objectGuid),
                        "created reward template")
                    local actualHolder = ChaosCharacter.CanonicalGuid(Osi.GetInventoryOwner(objectGuid),
                        "created reward holder")
                    assert(actualTemplate == templateGuid and actualHolder == holderGuid,
                        "ChaosOriginsRemastered: created reward identity mismatch " .. objectGuid
                            .. " for " .. holderGuid .. " template " .. templateGuid)
                    continueRewards(holderGuid)
                end)
            end)
        end)
    end)

Ext.Osiris.RegisterListener("Equipped", 2, "after", function(item, character)
    local characterKey = string.sub(tostring(character), -36)
    local operation = active[characterKey]
    if operation == nil or not operation.Equipping then return end

    local characterGuid = ChaosCharacter.CanonicalGuid(character, "equipped character")
    local itemGuid = ChaosCharacter.CanonicalGuid(item, "equipped item")
    if operation.Record.RewardItems[MASK_TEMPLATE] ~= itemGuid then return end

    guarded(characterGuid, operation, function()
        assert(Osi.IsEquipped(itemGuid) == 1,
            "ChaosOriginsRemastered: starter mask equip event was not applied " .. itemGuid
                .. " for " .. characterGuid)
        -- 三件奖励和自动装备全部成功后，才允许写入完成版本。
        operation.Record.StarterRewardsVersion = 1
        State.MarkDirty()
        active[characterGuid] = nil
    end)
end)

function M.Sync(character, record)
    character = ChaosCharacter.CanonicalGuid(character, "reward character")
    if record.StarterRewardsVersion == 1 or active[character] ~= nil then return end
    validateTemplates()
    local operation = { Record = record, PendingTemplate = nil, Equipping = false }
    active[character] = operation
    guarded(character, operation, function() continueRewards(character) end)
end

function M.ResetRuntime()
    -- 切换存档时丢弃旧会话中的异步句柄；持久化账本会在新会话重新驱动流程。
    active = {}
end

M.MaskTemplate = MASK_TEMPLATE
M.Templates = REWARD_TEMPLATES

return M
