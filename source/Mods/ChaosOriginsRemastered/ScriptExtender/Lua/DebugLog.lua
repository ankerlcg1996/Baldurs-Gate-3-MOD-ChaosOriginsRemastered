local M = {}
local enabled = false

-- 调试日志默认关闭，只能由 MCM 显式开启。
function M.SetEnabled(value)
    assert(type(value) == "boolean", "ChaosOriginsRemastered: debug flag must be boolean")
    enabled = value
end

function M.Print(message)
    if enabled then Ext.Utils.Print(tostring(message)) end
end

return M
