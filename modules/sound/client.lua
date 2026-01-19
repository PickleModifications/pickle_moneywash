-- Generic 3D sound playback (via NUI) with distance attenuation + stereo panning.

PMW_Sound3D = PMW_Sound3D or {}

local Active = {}
-- Active[id] = { coords=vector3, range=number, volume=number, rate=number, loop=bool, startedAt=ms }

local function clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
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

local function newId()
    return ("%d-%d"):format(GetGameTimer(), math.random(100000, 999999))
end

local function nuiPlay(id, path, volume, pan, opts)
    SendNUIMessage({
        type = "pmw_sound_play",
        id = id,
        path = path,
        volume = volume,
        pan = pan,
        loop = opts.loop == true,
        rate = opts.rate or 1.0,
    })
end

local function nuiUpdate(id, volume, pan, opts)
    SendNUIMessage({
        type = "pmw_sound_update",
        id = id,
        volume = volume,
        pan = pan,
        rate = opts.rate or 1.0,
    })
end

local function nuiStop(id)
    SendNUIMessage({
        type = "pmw_sound_stop",
        id = id,
    })
end

local function computeVolume(baseVolume, dist, range)
    -- Simple linear rolloff with a slight curve
    local t = 1.0 - (dist / range)
    if t <= 0.0 then return 0.0 end
    local curved = t * t
    return clamp((baseVolume or 1.0) * curved, 0.0, 1.0)
end

local function computePan(distVec, dist, range)
    if dist <= 0.0001 then return 0.0 end
    local ped = PlayerPedId()
    local _, right = GetEntityMatrix(ped)
    local dir = distVec / dist
    local pan = (right.x * dir.x) + (right.y * dir.y) + (right.z * dir.z)
    -- Reduce pan as distance increases (more natural)
    local panScale = 1.0 - (dist / range)
    return clamp(pan * panScale, -1.0, 1.0)
end

PMW_Sound3D.PlayLocal = function(coords, soundPath, opts)
    coords = toVector3(coords)
    soundPath = safeSoundPath(soundPath)
    if not coords or not soundPath then return nil end
    opts = opts or {}

    -- Allow passing bare filenames; default to nui/audio/
    if not string.find(soundPath, "/") then
        soundPath = ("audio/%s"):format(soundPath)
    end

    local id = newId()
    local range = tonumber(opts.range) or tonumber(opts.distance) or 25.0
    if range <= 0.0 then return nil end
    local volume = tonumber(opts.volume) or 0.8
    local rate = tonumber(opts.rate) or 1.0

    Active[id] = {
        coords = coords,
        range = range,
        volume = volume,
        loop = opts.loop == true,
        rate = rate,
        startedAt = GetGameTimer(),
    }

    -- Start at 0 to avoid a loud pop before first update
    nuiPlay(id, soundPath, 0.0, 0.0, Active[id])
    return id
end

PMW_Sound3D.Stop = function(id)
    if not id then return end
    id = tostring(id)
    if not Active[id] then return end
    nuiStop(id)
    Active[id] = nil
end

PMW_Sound3D.PlayNet = function(coords, soundPath, opts)
    opts = opts or {}
    -- local playback for immediacy
    local localId = nil
    if opts.playLocal ~= false then
        localId = PMW_Sound3D.PlayLocal(coords, soundPath, opts)
    end
    opts.excludeSource = true
    TriggerServerEvent("pickle_moneywash:sound3d:play", coords, soundPath, opts)
    return localId
end

RegisterNetEvent("pickle_moneywash:sound3d:play", function(soundPath, payload)
    payload = payload or {}
    PMW_Sound3D.PlayLocal(payload.coords, soundPath, payload)
end)

CreateThread(function()
    while true do
        if next(Active) == nil then
            Wait(300)
        else
            Wait(80)
        end

        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)

        for id, s in pairs(Active) do
            local distVec = s.coords - pcoords
            local dist = #(distVec)
            if dist > (s.range + 5.0) and not s.loop then
                nuiStop(id)
                Active[id] = nil
            else
                local vol = computeVolume(s.volume, dist, s.range)
                local pan = computePan(distVec, dist, s.range)
                nuiUpdate(id, vol, pan, s)
            end
        end
    end
end)

exports("PlaySound3D", function(coords, soundPath, opts)
    return PMW_Sound3D.PlayLocal(coords, soundPath, opts)
end)

exports("PlaySound3DNet", function(coords, soundPath, opts)
    return PMW_Sound3D.PlayNet(coords, soundPath, opts)
end)

