-- By default, this will use Pickle's XP, but you can change it to your system here.
if not Config.XPEnabled then return end

local function xpAvailable()
    return GetResourceState("pickle_xp") == "started"
end

function AddPlayerXP(source, name, xp)
    if not xpAvailable() then return end
    pcall(function() exports.pickle_xp:AddPlayerXP(source, name, xp) end)
end

function RemovePlayerXP(source, name, xp)
    if not xpAvailable() then return end
    pcall(function() exports.pickle_xp:RemovePlayerXP(source, name, xp) end)
end

function GetPlayerLevel(source, name)
    if not xpAvailable() then return 1 end
    local ok, lvl = pcall(function() return exports.pickle_xp:GetPlayerLevel(source, name) end)
    if not ok then return 1 end
    return tonumber(lvl) or 1
end

function GetPlayerXPData(source, name)
    local data = {}
    if not xpAvailable() then return data end
    for k,v in pairs(Config.XPCategories) do
        local level = GetPlayerLevel(source, name)
        data[name] = {
            label = v.label,
            level = level,
        }
    end
    return data
end
