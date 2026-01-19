-- Generic networked 3D sound broadcaster (NUI playback handled client-side).

local function toVector3(coords)
    if type(coords) == "vector3" then return coords end
    if type(coords) == "table" and coords.x and coords.y and coords.z then
        return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    end
    if type(coords) == "table" and coords[1] and coords[2] and coords[3] then
        return vector3((coords[1] + 0.0), (coords[2] + 0.0), (coords[3] + 0.0))
    end
    return nil
end

local function safeSoundPath(path)
    if type(path) ~= "string" then return nil end
    if path == "" then return nil end
    if string.find(path, "%.%.") then return nil end
    if string.find(path, ":") then return nil end
    if string.find(path, "\\") then return nil end
    if string.sub(path, 1, 1) == "/" then return nil end
    return path
end

local function broadcast3D(coords, soundPath, opts, excludeSource)
    coords = toVector3(coords)
    soundPath = safeSoundPath(soundPath)
    if not coords or not soundPath then return end
    opts = opts or {}

    local range = tonumber(opts.range) or tonumber(opts.distance) or 25.0
    if range <= 0.0 then return end
    if range > 250.0 then range = 250.0 end -- safety cap

    local payload = {
        coords = coords,
        range = range,
        volume = tonumber(opts.volume) or 0.8,
        loop = opts.loop == true,
        rate = tonumber(opts.rate) or 1.0,
    }

    local src = excludeSource and tonumber(excludeSource) or nil
    for _, player in ipairs(GetPlayers()) do
        local pid = tonumber(player)
        if pid and (not src or pid ~= src) then
            local ped = GetPlayerPed(pid)
            if ped and ped ~= 0 then
                local pcoords = GetEntityCoords(ped)
                if #(pcoords - coords) <= range then
                    TriggerClientEvent("pickle_moneywash:sound3d:play", pid, soundPath, payload)
                end
            end
        end
    end
end

RegisterNetEvent("pickle_moneywash:sound3d:play", function(coords, soundPath, opts)
    local src = source
    opts = opts or {}
    local exclude = (opts.excludeSource ~= false) and src or nil
    broadcast3D(coords, soundPath, opts, exclude)
end)

PMW_Sound3D = PMW_Sound3D or {}
PMW_Sound3D.Broadcast = function(coords, soundPath, opts)
    broadcast3D(coords, soundPath, opts, nil)
end

