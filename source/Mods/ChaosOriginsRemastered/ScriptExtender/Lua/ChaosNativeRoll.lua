local M = {}

-- Osi.Random 返回从零开始的整数；统一转换为一开始的闭区间。

local function roll(maximum)
    assert(type(maximum) == "number" and maximum >= 1 and maximum % 1 == 0,
        "ChaosOriginsRemastered: random maximum must be a positive integer")
    return Osi.Random(maximum) + 1
end

function M.Index(maximum)
    return roll(maximum)
end

function M.Chance(percent)
    assert(type(percent) == "number" and percent >= 0 and percent <= 100,
        "ChaosOriginsRemastered: chance must be between zero and one hundred")
    if percent == 0 then return false end
    if percent == 100 then return true end
    return roll(100) <= percent
end

return M
