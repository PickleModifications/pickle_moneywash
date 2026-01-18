MoneyCounters = {}

lib.callback.register("pickle_moneywash:getMoneyCounterData", function(source, index)
    return {
        totalDirtyMoney = GetMoney(source, "dirty") or 0,
    }
end)

lib.callback.register("pickle_moneywash:washMoney", function(source, index)
    local src = source
    local pcoords = GetEntityCoords(GetPlayerPed(src))
    local dirtyMoney = GetMoney(src, "dirty") or 0
    if dirtyMoney <= 0 then return end
    local moneycounter = MoneyCounters[index]
    if not moneycounter then return end
    local moneycounterCoords = moneycounter.coords
    local moneycounterHeading = moneycounter.heading
    local distance = #(pcoords - moneycounterCoords)
    if distance > 5.0 then return end
    local maxWash = Config.MoneyCounter.maxCountAmount
    local amountToWash = math.min(dirtyMoney, maxWash)
    if amountToWash <= 0 then return end
    RemoveMoney(src, amountToWash, "dirty")
    AddMoney(src, amountToWash, "money")
    ShowNotification(src, _L("moneycounter_washed_money", GetCurrencyString(amountToWash)))
    return {
        totalDirtyMoney = dirtyMoney - amountToWash,
    }
end)

CreateThread(function()
    for i=1, #Config.MoneyCounter.locations do
        local location = Config.MoneyCounter.locations[i]
        MoneyCounters[#MoneyCounters + 1] = {
            coords = location.coords,
            heading = location.heading,
        }
    end
end)