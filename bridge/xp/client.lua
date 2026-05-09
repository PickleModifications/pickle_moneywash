-- By default, this will use Pickle's XP, but you can change it to your system here.
if not Config.XPEnabled then return end

local function xpAvailable()
    return GetResourceState("pickle_xp") == "started"
end

function GetLevel(name)
    if not xpAvailable() then return 1 end
    local ok, lvl = pcall(function() return exports.pickle_xp:GetLevel(name) end)
    if not ok then return 1 end
    return tonumber(lvl) or 1
end

function GetXPData()
    local data = {}
    if not xpAvailable() then return data end
    for k,v in pairs(Config.XPCategories) do
        local level = GetLevel(k)
        local xp = 0
        pcall(function() xp = exports.pickle_xp:GetXP(k) end)
        data[k] = {
            label = v.label,
            level = level,
        }
    end
    return data
end
