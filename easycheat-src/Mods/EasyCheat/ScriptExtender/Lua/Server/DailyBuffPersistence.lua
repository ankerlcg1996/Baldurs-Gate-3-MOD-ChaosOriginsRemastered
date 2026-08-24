local SETTINGS_PATH = "EasyCheat/DailyBuffSettings.json"

local function SaveDailyBuffSettings(settings)
    local contents = Ext.DumpExport(settings)
    if contents == nil then
        error("EasyCheat could not serialize the daily buff settings.")
    end

    Ext.IO.SaveFile(SETTINGS_PATH, contents)
end

local function LoadDailyBuffSettings()
    local contents = Ext.IO.LoadFile(SETTINGS_PATH)
    if contents == nil then
        return nil
    end

    local success, settings = pcall(Ext.Json.Parse, contents)
    if not success then
        error("EasyCheat daily buff settings are invalid: " .. tostring(settings))
    end
    if type(settings) ~= "table" then
        error("EasyCheat daily buff settings must contain a JSON object.")
    end

    return settings
end

local function RestoreDailyBuffSettings()
    local settings = LoadDailyBuffSettings()
    if settings ~= nil then
        Helpers.ModVars:Get(ModuleUUID)[ModVarIDs.DailyBuffs] = settings
    end
end

local originalOnLevelGameplayStarted = EHandlers.OnLevelGameplayStarted
EHandlers.OnLevelGameplayStarted = function(...)
    RestoreDailyBuffSettings()
    return originalOnLevelGameplayStarted(...)
end

local originalOnResetCompleted = EHandlers.OnResetCompleted
EHandlers.OnResetCompleted = function(...)
    RestoreDailyBuffSettings()
    return originalOnResetCompleted(...)
end

local originalOnRequestChangeDailyBuffs = EHandlers.OnRequestChangeDailyBuffs
EHandlers.OnRequestChangeDailyBuffs = function(...)
    originalOnRequestChangeDailyBuffs(...)
    local settings = Helpers.ModVars:Get(ModuleUUID)[ModVarIDs.DailyBuffs]
    SaveDailyBuffSettings(settings)
end
