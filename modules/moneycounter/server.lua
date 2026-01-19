lib.callback.register("pickle_moneywash:getMoneyCounterData", function(source, moneyCounterId)
    return {
        totalDirtyMoney = GetMoney(source, "dirty") or 0,
    }
end)

local function doCountMoney(source, moneyCounterId)
    local src = source
    local pcoords = GetEntityCoords(GetPlayerPed(src))
    local dirtyMoney = GetMoney(src, "dirty") or 0
    if dirtyMoney <= 0 then return end
    if not PMW_Entities or not PMW_Entities.GetOne then return end
    local moneycounter = PMW_Entities.GetOne("moneycounter", moneyCounterId)
    if not moneycounter or not moneycounter.coords then return end
    local moneycounterCoords = moneycounter.coords
    local distance = #(pcoords - moneycounterCoords)
    if distance > 5.0 then return end
    local maxWash = Config.MoneyCounter.maxCountAmount
    local amountToWash = math.min(dirtyMoney, maxWash)
    if amountToWash <= 0 then return end
    RemoveMoney(src, amountToWash, "dirty")

    local identifier = GetIdentifier and GetIdentifier(src) or nil
    if not identifier then return end

    -- Wait briefly for the processor module to load (load order can vary).
    if not PMW_MoneyWash or not PMW_MoneyWash.AddCountedBalance then
        for _ = 1, 50 do
            Wait(0)
            if PMW_MoneyWash and PMW_MoneyWash.AddCountedBalance then break end
        end
    end
    if not PMW_MoneyWash or not PMW_MoneyWash.AddCountedBalance then return end

    PMW_MoneyWash.AddCountedBalance(identifier, amountToWash)
    ShowNotification(src, _L("moneycounter_counted_money", GetCurrencyString(amountToWash)))
    return {
        totalDirtyMoney = dirtyMoney - amountToWash,
    }
end

-- New behavior: count dirty money into counted balance.
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

    local record = PMW_Entities.GetOne("moneycounter", moneyCounterId)
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
                    TriggerClientEvent("pickle_moneywash:moneycounter:billInserted", pid, tostring(moneyCounterId), { coords = coords, heading = heading }, billCount)
                end
            end
        end
    end
end)