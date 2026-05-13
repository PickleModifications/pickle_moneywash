RegisteredEntityTypes = {}
EntityPlayers = {}

AddEventHandler("playerDropped", function()
    local src = source
    for k,v in pairs(EntityPlayers) do
        for entityId, players in pairs(v) do
            for i=1, #players do
                local player = players[i]
                if player == src then
                    table.remove(players, i)
                    break
                end
            end
        end
    end
end)

RegisterNetEvent("pickle_moneywash:initializePlayer", function()
    local src = source
    local moneyCounters = {}
    if PMW_Entities and PMW_Entities.GetByType then
        moneyCounters = PMW_Entities.GetByType("moneycounter")
    end
    TriggerClientEvent("pickle_moneywash:initializePlayer", src, {
        moneyCounters = moneyCounters,
        moneyProcessors = MoneyProcessors,
    })
    if PMW_Entities and PMW_Entities.SyncPlayer then
        PMW_Entities.SyncPlayer(src)
    end
    TriggerClientEvent("pickle_moneywash:warnMissingItems", src, PMW_MissingItems or {})
end)