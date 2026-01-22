lib.callback.register("pickle_moneywash:getMoneyCounterData", function(source, moneyCounterId)
    return {
        totalDirtyMoney = GetMoney(source, "dirty") or 0,
    }
end)

-- Server-side exclusive-use lock for each money counter entity id.
-- Prevents multiple players from using the same counter at once and cleans up on disconnect/timeout.
local MoneyCounterLocks = {} -- [id] = { src = number, lastPing = ms, coords = vector3 }
local LOCK_TIMEOUT_MS = 20 * 1000

local function normalizeId(id)
    if id == nil then return nil end
    return tostring(id)
end

local function isPlayerConnected(src)
    src = tonumber(src)
    if not src then return false end
    return GetPlayerName(src) ~= nil
end

local function clearLock(id)
    if not id then return end
    MoneyCounterLocks[id] = nil
end

local function getCounterCoords(id)
    if not PMW_Entities or not PMW_Entities.GetOne then return nil end
    local rec = PMW_Entities.GetOne("moneycounter", id)
    return rec and rec.coords or nil
end

local function isLockValid(lock)
    if not lock or not lock.src then return false end
    if not isPlayerConnected(lock.src) then return false end
    local lastPing = tonumber(lock.lastPing) or 0
    if lastPing <= 0 then return false end
    return (GetGameTimer() - lastPing) <= LOCK_TIMEOUT_MS
end

local function validateAndGetLock(id)
    local lock = MoneyCounterLocks[id]
    if not lock then return nil end
    if not isLockValid(lock) then
        clearLock(id)
        return nil
    end
    return lock
end

-- Acquire exclusive use of this money counter id.
-- Returns { ok = true } or { ok = false, reason = "in_use", holder = <serverId> }.
lib.callback.register("pickle_moneywash:moneycounter:tryUse", function(source, moneyCounterId)
    local src = source
    local id = normalizeId(moneyCounterId)
    if not id then return { ok = false, reason = "invalid" } end

    local existing = validateAndGetLock(id)
    if existing and existing.src ~= src then
        return { ok = false, reason = "in_use", holder = existing.src }
    end

    local coords = getCounterCoords(id)
    MoneyCounterLocks[id] = {
        src = src,
        lastPing = GetGameTimer(),
        coords = coords,
    }
    return { ok = true }
end)

-- Keepalive while a player is actively using the counter.
RegisterNetEvent("pickle_moneywash:moneycounter:keepalive", function(moneyCounterId)
    local src = source
    local id = normalizeId(moneyCounterId)
    if not id then return end
    local lock = validateAndGetLock(id)
    if not lock then return end
    if lock.src ~= src then return end
    lock.lastPing = GetGameTimer()
    -- Refresh coords in case it was edited/moved.
    lock.coords = getCounterCoords(id) or lock.coords
end)

-- Release the lock when client ends interaction normally.
RegisterNetEvent("pickle_moneywash:moneycounter:releaseUse", function(moneyCounterId)
    local src = source
    local id = normalizeId(moneyCounterId)
    if not id then return end
    local lock = MoneyCounterLocks[id]
    if lock and lock.src == src then
        clearLock(id)
        -- Broadcast to nearby clients that the session ended so they can clear bills
        local record = PMW_Entities.GetOne("moneycounter", id)
        if record and record.coords then
            local coords = record.coords
            for _, player in ipairs(GetPlayers()) do
                local pid = tonumber(player)
                if pid and pid ~= src then
                    local ped = GetPlayerPed(pid)
                    if ped and ped ~= 0 then
                        local pcoords = GetEntityCoords(ped)
                        if #(pcoords - coords) <= (Config.RenderDistance or 100.0) then
                            TriggerClientEvent("pickle_moneywash:moneycounter:sessionEnded", pid, tostring(id))
                        end
                    end
                end
            end
        end
    end
end)

-- Cleanup on disconnect so locks never get stuck.
AddEventHandler("playerDropped", function()
    local src = source
    for id, lock in pairs(MoneyCounterLocks) do
        if lock and lock.src == src then
            -- Broadcast to nearby clients that the session ended (player disconnected)
            local record = PMW_Entities.GetOne("moneycounter", id)
            if record and record.coords then
                local coords = record.coords
                for _, player in ipairs(GetPlayers()) do
                    local pid = tonumber(player)
                    if pid and pid ~= src then
                        local ped = GetPlayerPed(pid)
                        if ped and ped ~= 0 then
                            local pcoords = GetEntityCoords(ped)
                            if #(pcoords - coords) <= (Config.RenderDistance or 100.0) then
                                TriggerClientEvent("pickle_moneywash:moneycounter:sessionEnded", pid, tostring(id))
                            end
                        end
                    end
                end
            end
            MoneyCounterLocks[id] = nil
        end
    end
end)

-- Periodic cleanup for timeouts / stale players.
CreateThread(function()
    while true do
        local now = GetGameTimer()
        for id, lock in pairs(MoneyCounterLocks) do
            local lastPing = tonumber(lock and lock.lastPing) or 0
            if (not lock) or (not lock.src) or (not isPlayerConnected(lock.src)) or lastPing <= 0 or (now - lastPing) > LOCK_TIMEOUT_MS then
                -- Broadcast to nearby clients that the session ended (timeout)
                local record = PMW_Entities.GetOne("moneycounter", id)
                if record and record.coords then
                    local coords = record.coords
                    for _, player in ipairs(GetPlayers()) do
                        local pid = tonumber(player)
                        if pid and pid ~= lock.src then
                            local ped = GetPlayerPed(pid)
                            if ped and ped ~= 0 then
                                local pcoords = GetEntityCoords(ped)
                                if #(pcoords - coords) <= (Config.RenderDistance or 100.0) then
                                    TriggerClientEvent("pickle_moneywash:moneycounter:sessionEnded", pid, tostring(id))
                                end
                            end
                        end
                    end
                end
                MoneyCounterLocks[id] = nil
            end
        end
        Wait(5000)
    end
end)

local function doCountMoney(source, moneyCounterId)
    local src = source
    local id = normalizeId(moneyCounterId)
    -- Enforce lock on the server too (prevents bypass via direct callback calls).
    local lock = id and validateAndGetLock(id) or nil
    if not lock or lock.src ~= src then return end

    local pcoords = GetEntityCoords(GetPlayerPed(src))
    local dirtyMoney = GetMoney(src, "dirty") or 0
    if dirtyMoney <= 0 then return end
    if not PMW_Entities or not PMW_Entities.GetOne then return end
    local moneycounter = PMW_Entities.GetOne("moneycounter", id)
    if not moneycounter or not moneycounter.coords then return end
    local moneycounterCoords = moneycounter.coords
    local distance = #(pcoords - moneycounterCoords)
    if distance > 5.0 then return end
    local maxWash = Config.MoneyCounter.maxCountAmount
    local amountToWash = math.min(dirtyMoney, maxWash)
    if amountToWash <= 0 then return end

    local itemName = "unprocessed_money"
    if not Inventory or not Inventory.CanCarryItem or not Inventory.AddItem then return end
    if not Inventory.CanCarryItem(src, itemName, amountToWash) then
        ShowNotification(src, _L("moneycounter_cant_carry_unprocessed"))
        return
    end

    RemoveMoney(src, amountToWash, "dirty")
    Inventory.AddItem(src, itemName, amountToWash)

    ShowNotification(src, _L("moneycounter_unprocessed_money", GetCurrencyString(amountToWash)))
    
    -- Discord log
    if ConfigSV and ConfigSV.LogToDiscord then
        pcall(function()
            ConfigSV.LogToDiscord("money_counter_counted", src, {
                amount = amountToWash,
                counterId = id,
                coords = moneycounterCoords,
            })
        end)
    end
    
    return {
        totalDirtyMoney = dirtyMoney - amountToWash,
    }
end

-- New behavior: count dirty money into unprocessed money item.
lib.callback.register("pickle_moneywash:countMoney", function(source, moneyCounterId)
    return doCountMoney(source, moneyCounterId)
end)

-- Backwards-compat alias (kept for safety; behavior is the same as countMoney).
lib.callback.register("pickle_moneywash:washMoney", function(source, moneyCounterId)
    return doCountMoney(source, moneyCounterId)
end)

-- Broadcast inserted-bill animation to nearby clients
RegisterNetEvent("pickle_moneywash:moneycounter:billInserted", function(moneyCounterId, count)
    local src = source
    if not PMW_Entities or not PMW_Entities.GetOne then return end
    if not moneyCounterId then return end

    -- Only the lock owner can broadcast bill inserts for this counter.
    local id = normalizeId(moneyCounterId)
    local lock = id and validateAndGetLock(id) or nil
    if not lock or lock.src ~= src then return end

    local record = PMW_Entities.GetOne("moneycounter", id)
    if not record or not record.coords then return end

    local coords = record.coords
    local heading = record.heading or 0.0
    local billCount = tonumber(count) or 1

    for _, player in ipairs(GetPlayers()) do
        local pid = tonumber(player)
        if pid and pid ~= src then
            local ped = GetPlayerPed(pid)
            if ped and ped ~= 0 then
                local pcoords = GetEntityCoords(ped)
                if #(pcoords - coords) <= (Config.RenderDistance or 100.0) then
                    TriggerClientEvent("pickle_moneywash:moneycounter:billInserted", pid, tostring(id), { coords = coords, heading = heading }, billCount)
                end
            end
        end
    end
end)