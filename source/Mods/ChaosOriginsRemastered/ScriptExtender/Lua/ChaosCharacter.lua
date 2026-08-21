local M = {}

local ORIGIN_TAG = "7bb4d001-3c7e-445d-b52b-db0507db38d4"
local ORIGIN_MARKER = "COR_OriginMarker"
local NULL_UUID = "00000000-0000-0000-0000-000000000000"
local GUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

function M.CanonicalGuid(value, label)
    local text = tostring(value)
    local guid = string.sub(text, -36)
    assert(string.match(guid, GUID_PATTERN) ~= nil and guid ~= NULL_UUID,
        "ChaosOriginsRemastered: invalid " .. label .. " GUID " .. text)
    return guid
end

function M.IsEligible(character)
    if character == nil or character == "" or Osi.IsPlayer(character) ~= 1 then return false end
    character = M.CanonicalGuid(character, "character")
    -- 只接受新混沌起源自己的标签或标记，职业、种族和名字都不能作为替代条件。
    return Osi.HasPassive(character, ORIGIN_MARKER) == 1
        or Osi.IsTagged(character, ORIGIN_TAG) == 1
end

function M.Players()
    local players = {}
    for _, row in ipairs(Osi.DB_Players:Get(nil)) do
        players[#players + 1] = M.CanonicalGuid(row[1], "player")
    end
    return players
end

return M
