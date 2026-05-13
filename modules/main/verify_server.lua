-- On-start item existence verification.
-- Warns server operators (and connected clients) when required inventory items
-- referenced by pickle_moneywash are missing from the active inventory system.

PMW_MissingItems = PMW_MissingItems or {}

CreateThread(function()
    -- Wait for the inventory bridge to be ready (poll up to ~10s).
    local waited = 0
    while not (Inventory and Inventory.Ready) and waited < 10000 do
        Wait(100)
        waited = waited + 100
    end

    if not Inventory then
        print("^1[pickle_moneywash] WARNING: Inventory bridge not initialized; skipping item verification.^0")
        return
    end

    if Inventory.ItemExists == nil then
        print("^3[pickle_moneywash] INFO: standalone bridge in use (ItemExists unavailable); skipping item verification.^0")
        return
    end

    -- Resolve required items.
    local required = {}

    local dirtySetting = Config and Config.FrameworkSettings and Config.FrameworkSettings.dirtyMoney or "DEFAULT"
    local dirtyItem
    if dirtySetting == "DEFAULT" then
        if GetResourceState("es_extended") == "started" then
            dirtyItem = "black_money"
        else
            dirtyItem = "dirty_money"
        end
    else
        dirtyItem = dirtySetting
    end

    if dirtyItem and dirtyItem ~= "" then
        required[#required + 1] = dirtyItem
    end

    -- Build the missing list.
    local missing = {}
    for i = 1, #required do
        local name = required[i]
        if not Inventory.ItemExists(name) then
            missing[#missing + 1] = name
        end
    end

    if #missing > 0 then
        print("^1[pickle_moneywash] WARNING: missing items: " .. table.concat(missing, ", ") .. "^0")
        PMW_MissingItems = missing
        Wait(2000)
        TriggerClientEvent("pickle_moneywash:warnMissingItems", -1, missing)
    else
        PMW_MissingItems = {}
    end
end)
