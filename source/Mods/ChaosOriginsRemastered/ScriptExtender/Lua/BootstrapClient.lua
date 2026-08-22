local MODULE_UUID = "9112dfde-d843-408f-b59b-9c893f5f7d92"
local Protocol = Ext.Require("McmProtocol.lua")
local channel = Ext.Net.CreateChannel(MODULE_UUID, Protocol.Channel)

-- MCM 控件随窗口重建；代数阻止旧控件回调修改当前角色。
local uiGeneration = 0
local requestId = 0
local lastReplyId = 0
local lastRevision = -1
local snapshot = nil
local applying = false
local mcmOpen = false
local controls = {
    Origins = {}, OriginAll = nil, Mechanics = {}, WoundEffects = {}, TestExperience = nil
}
local rendered = { General = false, Origins = false, Wounds = false }
local statusTexts = {}
local pollSnapshot

local function loc(handle)
    local value = Ext.Loca.GetTranslatedString(handle)
    assert(value ~= nil and value ~= "", "ChaosOriginsRemastered: missing localization " .. handle)
    return value
end

local function updateStatus(code)
    if #statusTexts == 0 then return end
    local line
    if not Ext.Net.IsHost() then
        line = loc(Protocol.Text.HostOnly)
    elseif snapshot == nil or not snapshot.Ready then
        line = loc(Protocol.Text.Waiting)
    elseif not snapshot.IsChaos then
        line = loc(Protocol.Text.NotChaos)
    else
        local wound = loc(Protocol.Text.NoWound)
        if snapshot.LastWoundOutcome ~= "" then
            wound = loc(assert(Protocol.WoundOutcomes[snapshot.LastWoundOutcome],
                "ChaosOriginsRemastered: unknown wound outcome " .. snapshot.LastWoundOutcome))
        end
        line = loc(Protocol.Text.CurrentLost) .. ": " .. snapshot.LostCount .. "/10  |  "
            .. loc(Protocol.Text.CurrentPower) .. ": " .. snapshot.ChaosPower .. "  |  "
            .. loc(Protocol.Text.KillCount) .. ": " .. snapshot.KillCount .. "  |  "
            .. loc(Protocol.Text.LastWound) .. ": " .. wound
    end
    if code ~= nil and code ~= "" then
        line = line .. "  |  " .. loc(assert(Protocol.Errors[code],
            "ChaosOriginsRemastered: unknown MCM error " .. code))
    end
    for _, control in ipairs(statusTexts) do control.Label = line end
end

local function applySnapshot(code)
    applying = true
    local disabled = not Ext.Net.IsHost() or snapshot == nil or not snapshot.Ready
        or not snapshot.IsChaos or snapshot.InCombat
    local allOriginsEnabled = snapshot ~= nil and snapshot.OriginIdentities ~= nil
    for _, definition in ipairs(Protocol.Origins) do
        allOriginsEnabled = allOriginsEnabled
            and snapshot.OriginIdentities[definition[1]] == true
        local control = controls.Origins[definition[1]]
        if control ~= nil then
            control.Checked = snapshot ~= nil and snapshot.OriginIdentities ~= nil
                and snapshot.OriginIdentities[definition[1]] == true
            control.Disabled = disabled
        end
    end
    if controls.OriginAll ~= nil then
        controls.OriginAll.Checked = allOriginsEnabled
        controls.OriginAll.Disabled = disabled
    end
    for _, definition in ipairs(Protocol.Mechanics) do
        local control = controls.Mechanics[definition[1]]
        if control ~= nil then
            control.Checked = snapshot ~= nil and snapshot.Mechanics ~= nil
                and snapshot.Mechanics[definition[1]] == true
            control.Disabled = disabled
        end
    end
    if controls.TestExperience ~= nil then
        controls.TestExperience.Checked = snapshot ~= nil and snapshot.TestLevel12Experience == true
        controls.TestExperience.Disabled = disabled
    end
    for _, definition in ipairs(Protocol.WoundEffects) do
        local control = controls.WoundEffects[definition[1]]
        if control ~= nil then
            control.Checked = snapshot ~= nil and snapshot.WoundEffects ~= nil
                and snapshot.WoundEffects[definition[1]] == true
            control.Disabled = disabled
        end
    end
    applying = false
    updateStatus(code)
end

local function receive(reply)
    assert(type(reply) == "table" and reply.Version == Protocol.Version
        and type(reply.RequestId) == "number" and type(reply.Revision) == "number"
        and type(reply.Ok) == "boolean" and type(reply.Snapshot) == "table",
        "ChaosOriginsRemastered: invalid MCM reply")
    if reply.Revision < lastRevision then return end
    if reply.Revision == lastRevision and reply.RequestId < lastReplyId then return end
    lastRevision = reply.Revision
    lastReplyId = reply.RequestId
    snapshot = reply.Snapshot
    applySnapshot(reply.Ok and "" or reply.Code)
end

local function request(action, key, value)
    if not Ext.Net.IsHost() then return end
    requestId = requestId + 1
    channel:RequestToServer({
        Version = Protocol.Version,
        RequestId = requestId,
        Action = action,
        CharacterId = snapshot ~= nil and snapshot.CharacterId or "",
        Key = key,
        Value = value
    }, receive)
end

channel:SetHandler(function(message)
    if not Ext.Net.IsHost() then return end
    assert(type(message) == "table" and message.Version == Protocol.Version
        and message.Type == "Invalidated" and type(message.Revision) == "number",
        "ChaosOriginsRemastered: invalid MCM invalidation")
    if message.Revision >= lastRevision then request("GetSnapshot") end
end)

local function checkbox(parent, label, initial, onChange)
    local generation = uiGeneration
    local control = parent:AddCheckbox(label, initial)
    control.OnChange = function(changed)
        if not applying and generation == uiGeneration then onChange(changed.Checked) end
    end
    return control
end

local function addStatus(parent)
    statusTexts[#statusTexts + 1] = parent:AddText(loc(Protocol.Text.Waiting))
end

local function finishRender()
    applySnapshot("")
    request("GetSnapshot")
end

local function renderGeneral(parent)
    if rendered.General then return end
    rendered.General = true
    addStatus(parent)
    parent:AddText(loc(Protocol.Text.Help))
    for _, definition in ipairs(Protocol.Mechanics) do
        local key, handle = definition[1], definition[2]
        controls.Mechanics[key] = checkbox(parent, loc(handle), true,
            function(value) request("SetMechanic", key, value) end)
    end
    controls.TestExperience = checkbox(parent, loc(Protocol.Text.TestLevel12Experience), false,
        function(value) request("SetTestExperience", "", value) end)
    finishRender()
end

local function renderOrigins(parent)
    if rendered.Origins then return end
    rendered.Origins = true
    addStatus(parent)
    parent:AddText(loc(Protocol.Text.OriginHelp))
    controls.OriginAll = checkbox(parent, loc(Protocol.Text.AllOrigins), true,
        function(value) request("SetAllOrigins", "", value) end)
    for _, definition in ipairs(Protocol.Origins) do
        local key, handle = definition[1], definition[2]
        controls.Origins[key] = checkbox(parent, loc(handle), true,
            function(value) request("SetOrigin", key, value) end)
    end
    finishRender()
end

local function renderWounds(parent)
    if rendered.Wounds then return end
    rendered.Wounds = true
    addStatus(parent)
    for _, definition in ipairs(Protocol.WoundEffects) do
        local key, handle = definition[1], definition[2]
        controls.WoundEffects[key] = checkbox(parent, loc(handle), true,
            function(value) request("SetWoundEffect", key, value) end)
    end
    finishRender()
end

pollSnapshot = function(generation)
    Ext.Timer.WaitFor(500, function()
        if not mcmOpen or generation ~= uiGeneration then return end
        request("GetSnapshot")
        pollSnapshot(generation)
    end)
end

Ext.Events.SessionLoaded:Subscribe(function()
    snapshot = nil
    lastRevision = -1
    lastReplyId = 0
end)

Ext.ModEvents.BG3MCM.MCM_Window_Opened:Subscribe(function()
    if mcmOpen then return end
    mcmOpen = true
    request("GetSnapshot")
    pollSnapshot(uiGeneration)
end)

Ext.ModEvents.BG3MCM.MCM_Window_Closed:Subscribe(function()
    mcmOpen = false
end)

-- 分页避免 MCM 自定义页过长时截断起源开关与受创结果。
MCM.InsertModMenuTab(loc(Protocol.Text.Tab), renderGeneral, MODULE_UUID, true)
MCM.InsertModMenuTab(loc(Protocol.Text.OriginTab), renderOrigins, MODULE_UUID, true)
MCM.InsertModMenuTab(loc(Protocol.Text.WoundTab), renderWounds, MODULE_UUID, true)
